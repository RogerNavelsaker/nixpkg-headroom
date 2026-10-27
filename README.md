# nixpkg-headroom

Nix packaging and a rootless OCI image for Headroom. The standalone package includes the upstream CLI dependencies. The service image uses the same pinned source but omits Magika; Kompress ML stays enabled and runs locally. Magika is omitted because it is eagerly preloaded by the proxy CLI and can create substantial memory pressure.

## Outputs

- `packages.default` / `packages.headroom`: Headroom 0.40.0 CLI, pinned to `3c418f6f0b190ad1060413c0eadd77f20ab3cf46`, which contains the Caveman retrieval safeguard.
- `packages.headroom-service`: service-specific Headroom package with Magika removed; it selects the tested fallback detector and retains the local Kompress ML dependencies.
- `packages.headroom-image`: rootless OCI image locally tagged `agent-services-headroom`, published to `ghcr.io/rogernavelsaker/headroom`, running as UID/GID 10001 on port 8787.

The Nix check runs tests for the Caveman retrieval exclusions and byte-exact OpenAI/Anthropic recovery payloads. It also verifies that the service variant works without Magika and leaves unrelated retrieval tools eligible for compression.

Runtime state is mounted at `/data` and `/config`. The anonymous beacon is disabled; persistent memory and learning are not enabled. Structural transforms remain enabled, and Kompress ML handles general text locally. With a cold cache, Headroom starts a background warm-up after proxy startup and may download the public model weights from Hugging Face; with `HOME=/data`, the cache persists under `/data`. This does not call a hosted LLM API. CCR originals are unencrypted and use Headroom's documented 30-minute default retention, so protect the mounted state.

## Build and verify

```sh
nix flake check --accept-flake-config
nix build .#headroom .#headroom-image --no-link
```

## Image publishing

The `ci.yml` workflow builds the `headroom` package and image and uploads the Nix outputs to Cachix on pushes to `main`. The `publish.yml` workflow is manual-only; it publishes `latest` and a commit-SHA tag to `ghcr.io/rogernavelsaker/headroom`.
