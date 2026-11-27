#!/usr/bin/env bash
# Pin headroom to the latest headroomlabs-ai/headroom vX.Y.Z tag: rev, version, source hash, cargo vendor hash.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
repo=headroomlabs-ai/headroom
tag=$(git ls-remote --tags --refs "https://github.com/$repo" | awk '{sub("refs/tags/","",$2); print $2}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)
new=${tag#v}
old=$(grep -oE '^          version = "[^"]+"' flake.nix | sed -E 's/.*"([^"]+)"/\1/')
[ "$new" != "$old" ] || { echo "up to date: $old"; exit 0; }
rev=$(git ls-remote "https://github.com/$repo" "refs/tags/$tag^{}" | awk '{print $1}')
[ -n "$rev" ] || rev=$(git ls-remote "https://github.com/$repo" "refs/tags/$tag" | awk '{print $1}')
oldrev=$(grep -oE 'headroomRevision = "[0-9a-f]{40}"' flake.nix | sed -E 's/.*"([^"]+)"/\1/')
src=$(nix flake prefetch "github:$repo/$rev" --json | jq -r .hash)
fake=sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
sed -i -E \
  -e "s/$oldrev/$rev/g" \
  -e "s|^(          version = )\"$old\"|\1\"$new\"|" \
  -e "s|\"org.opencontainers.image.version\" = \"[^\"]+\"|\"org.opencontainers.image.version\" = \"$new\"|" \
  -e "s|(headroomSrc = pkgs.fetchFromGitHub \{)|\1|" flake.nix
python3 - "$src" "$fake" <<'PY'
import re, sys
src, fake = sys.argv[1:]
s = open('flake.nix').read()
s = re.sub(r'(rev = headroomRevision;\n\s+hash = )"sha256-[^"]+"', lambda m: m.group(1) + f'"{src}"', s)
s = re.sub(r'(fetchCargoVendor \{[^}]*?hash = )"sha256-[^"]+"', lambda m: m.group(1) + f'"{fake}"', s, flags=re.S)
open('flake.nix', 'w').write(s)
PY
cargo=$(nix build .#default --accept-flake-config --no-link 2>&1 | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | awk '{print $2}' | head -n1 || true)
[ -n "$cargo" ] || { echo "could not derive cargo hash" >&2; exit 1; }
sed -i "s|$fake|$cargo|" flake.nix
echo "bumped $old -> $new ($rev)"
