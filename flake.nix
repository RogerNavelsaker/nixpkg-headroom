{
  description = "Nix packaging and OCI image for Headroom";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://rogernavelsaker.cachix.org"
      "https://nacosolutions.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "rogernavelsaker.cachix.org-1:n1DtzMNhA9Rz4Kg3xlXOi/KceULu8VrMbs9WXyMFQNQ="
      "nacosolutions.cachix.org-1:JzCiW2CLcuLXtwOVAg3SlSK/kpqWbfSFEVenyKVUlug="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        python = pkgs.python313;
        py = python.pkgs;
        headroomRevision = "3c418f6f0b190ad1060413c0eadd77f20ab3cf46";
        headroomSrc = pkgs.fetchFromGitHub {
          owner = "headroomlabs-ai";
          repo = "headroom";
          rev = headroomRevision;
          hash = "sha256-OSfbEyGIXxceIwE0DqKI/ZIKC8M8iJd/vNnfqZ+x9Fc=";
        };

        headroom = py.buildPythonApplication (finalAttrs: {
          pname = "headroom-ai";
          version = "0.40.0";
          pyproject = true;
          src = headroomSrc;

          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) pname src version;
            hash = "sha256-8Y8FyX1LxLO7dHNDaMK8NAiRjZkNU0bsM4P+HbMvReI=";
          };

          nativeBuildInputs = [
            pkgs.rustPlatform.cargoSetupHook
            pkgs.rustPlatform.maturinBuildHook
          ];

          dependencies = with py; [
            tiktoken
            pydantic
            litellm
            click
            rich
            opentelemetry-api
            ast-grep-cli
            pyyaml
            tomli
            tomlkit
            truststore
            fastapi
            uvicorn
            orjson
            httpx
            h2
            openai
            mcp
            magika
            zstandard
            websockets
            onnxruntime
            transformers
            watchdog
            sqlite-vec
          ];

          makeWrapperArgs = [
            "--prefix"
            "PYTHONPATH"
            ":"
            "${placeholder "out"}/${python.sitePackages}:${py.makePythonPath finalAttrs.propagatedBuildInputs}"
          ];

          postInstall = ''
            cat > "$out/bin/headroom-child-python-check" <<'PY'
            #!${python}/bin/python
            import subprocess
            import sys
            subprocess.run([sys.executable, "-c", "import h2; import headroom.cli"], check=True)
            PY
            chmod +x "$out/bin/headroom-child-python-check"
          '';

          postFixup = ''
            env -u PYTHONPATH "$out/bin/headroom-child-python-check"
            rm "$out/bin/headroom-child-python-check"
          '';

          nativeCheckInputs = [ py.pytestCheckHook ];
          pytestFlags = [ "${./tests/test_headroom_caveman_safeguard.py}" ];
          pythonImportsCheck = [
            "headroom.config"
            "headroom.transforms.content_router"
          ];

          meta = {
            description = "Headroom proxy pinned to the Caveman retrieval safeguard";
            homepage = "https://github.com/headroomlabs-ai/headroom";
            license = lib.licenses.asl20;
            mainProgram = "headroom";
            platforms = lib.platforms.linux;
          };
        });

        headroomService = headroom.overridePythonAttrs (old: {
          dependencies = lib.filter (dependency: dependency != py.magika) old.dependencies;
          postPatch = (old.postPatch or "") + ''
            substituteInPlace headroom/cli/proxy.py --replace-fail '        "magika",' '        # Magika omitted; use the fallback detector.'
          '';
          pytestFlags = old.pytestFlags ++ [ "${./tests/test_headroom_no_magika.py}" ];
        });

        serviceImage = pkgs.dockerTools.buildLayeredImage {
          name = "agent-services-headroom";
          tag = "latest";
          maxLayers = 16;
          contents = [
            pkgs.cacert
            pkgs.tzdata
            pkgs.dockerTools.fakeNss
            headroomService
            py.ast-grep-cli
          ];
          fakeRootCommands = ''
            mkdir -p ./tmp ./data ./config
            chown -R 10001:10001 ./data ./config
            chmod 0700 ./data ./config
            chmod 1777 ./tmp
          '';
          config = {
            Labels = {
              "org.opencontainers.image.title" = "Headroom Proxy";
              "org.opencontainers.image.description" =
                "Headroom with Magika omitted and local Kompress ML enabled";
              "org.opencontainers.image.source" = "https://github.com/RogerNavelsaker/nixpkg-headroom";
              "org.opencontainers.image.version" = "0.40.0+pr4014";
              "org.opencontainers.image.revision" = headroomRevision;
            };
            User = "10001:10001";
            Entrypoint = [ "${headroomService}/bin/headroom" ];
            Cmd = [
              "proxy"
              "--host"
              "0.0.0.0"
              "--port"
              "8787"
            ];
            Env = [
              "PATH=${
                lib.makeBinPath [
                  headroomService
                  py.ast-grep-cli
                ]
              }"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "HOME=/data"
              "TMPDIR=/tmp"
              "TZ=UTC"
              "HEADROOM_WORKSPACE_DIR=/data"
              "HEADROOM_CONFIG_DIR=/config"
              "HEADROOM_BEACON=off"
              "HEADROOM_DETECT_BACKEND=python"
            ];
            WorkingDir = "/data";
            Volumes = {
              "/data" = { };
              "/config" = { };
            };
            ExposedPorts = {
              "8787/tcp" = { };
            };
          };
        };
      in
      {
        packages = {
          default = headroom;
          inherit headroom;
          headroom-service = headroomService;
          headroom-image = serviceImage;
        };

        checks = {
          headroom = headroom;
          headroom-image = serviceImage;
        };
      }
    );
}
