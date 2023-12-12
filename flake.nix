{
  description = "cnode workspace";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils, fenix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        toolchain = fenix.packages.${system}.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-S4dA7ne2IpFHG+EnjXfogmqwGyDFSRWFnJ8cy4KZr1k=";
        };

        craneLib = crane.lib.${system}.overrideToolchain toolchain;
        jsonFilter = path: _type:
          builtins.match ".*json$" path != null;
        srcFilter = path: type:
          (jsonFilter path type) || (craneLib.filterCargoSources path type);

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          pname = "cnode-workspace";
          version = "0.0.0";
          src = nixpkgs.lib.cleanSourceWith {
            src = craneLib.path ./.;
          };

          buildInputs = with pkgs; [
            openssl
            pkg-config
            cmake

            sqlite
          ];

          nativeBuildInputs = [ ];

          LD_LIBRARY_PATH = (pkgs.lib.makeLibraryPath (commonArgs.buildInputs ++ commonArgs.nativeBuildInputs));

        };
        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
          # Additional arguments specific to this derivation can be added here.
          # Be warned that using `//` will not do a deep copy of nested structures

          cargoTestProfile = "release";
          cargoBuildProfile = "release";
        });

        cnode = craneLib.buildPackage (commonArgs //
          craneLib.crateNameFromCargoToml { cargoToml = ./Cargo.toml; } // {
          inherit cargoArtifacts;
          doCheck = false;
        });
      in
      {
        # packages.default = ext1-server;
        # packages.ext1-server = ext1-server;
        # packages.ext1-client = ext1-client;
        packages.casper-node = cnode;

        # checks = {
        #   inherit
        #     ext1-server
        #     ext1-client
        #     ext1-clippy;
        # };

        devShells = {
          default = craneLib.devShell {};
          nctl = pkgs.mkShell {
            packages = [
              (pkgs.python3.withPackages (pp: with pp; [ supervisor toml tomlkit ]))
            ];
            shellHook = ''
              . utils/nctl/activate
            '';
          };
        };

        apps = let
          writePythonScriptBin = name: text: pkgs.writeTextFile {
            inherit name;
            executable = true;
            destination = "/bin/${name}";
            text = ''
              #!${pkgs.python3}/bin/python
              ${text}
            '';

            # checkPhase = ''
            #   ${pkgs.python37Packages.black}/bin/black --check --diff --quiet $out/bin/${name}
            # '';
          };
          d = x: builtins.trace x x;
          casperNodeMaybe = if d (builtins.pathExists ./result/bin/casper-node) then "./result/bin/casper-node" else "${self.packages.x86_64-linux.casper-node}/bin/casper-node";
          # casperNodeMaybe = "./result/bin/casper-node";
        in {
          # TODO: clean this up
          casper-node-cluster = let
            # output rundir
            # input run
            run-dir = ''${pkgs.mktemp}/bin/mktemp -d /tmp/casper-node-cluster.XXXXXXXXXX'';
            # generate config as subdir of run-dir
            # generate data as subdir of run-dir
            gen-test-config = pkgs.writeShellScript "gen-test-config" ''
              #${casperNodeMaybe}
              tdir="$(${pkgs.coreutils}/bin/mktemp -d "/tmp/casper-node-config.XXXXXXXXXX")"
              ${pkgs.coreutils}/bin/cp -r resources/local/* "$tdir"
              export TIMESTAMP="$(${writePythonScriptBin "timestamp.py" ''
                from datetime import datetime, timedelta
                print((datetime.utcnow() + timedelta(seconds=40)).isoformat('T') + 'Z')
              ''}/bin/timestamp.py)"
              ${pkgs.envsubst}/bin/envsubst -i resources/local/chainspec.toml.in -o "$tdir"/chainspec.toml
              echo $tdir
            '';
            run-single-node = ''
              function run-single-node {
                # run gen-test-config
                # run node
                # ${casperNodeMaybe} $config/config.toml -C consensus.secret_key_path=$config/secret_keys/node-1 -C storage.path="$(mktemp -d)" -C rpc_server.address='0.0.0.0:50101'
                # casper-node <$ID <$CONFIG <$DATA_DIR (follow run-dev-tmux)
                # config="$(${pkgs.nixFlakes}/bin/nix run .#gen-test-config)"
                # before spawning other nodes, check bootstrap if ID ! 1
                ID=''${1}
                CONFIG_DIR=''${2}
                DATA_DIR=''${3}
                CONFIG_TOML_PATH="''${CONFIG_DIR}/config.toml"
                SECRET_KEY_PATH="''${CONFIG_DIR}/secret_keys/node-''${ID}.pem"
                STORAGE_DIR="''${DATA_DIR}/node-''${ID}-storage"

                CMD=(
                  "${casperNodeMaybe}"
                  "validator"
                  "''${CONFIG_TOML_PATH}"
                  "-C consensus.secret_key_path=''${SECRET_KEY_PATH}"
                  "-C storage.path=''${STORAGE_DIR}"
                  "-C rpc_server.address='0.0.0.0:50101'"
                )

                if [[ ''${ID} != 1 ]]; then
                  # Wait for node-1 to wake up
                  while ! (: </dev/tcp/0.0.0.0/34553) &>/dev/null; do
                      sleep 1
                  done
                  CMD+=("-C network.bind_address='0.0.0.0:0'")
                  CMD+=("-C rpc_server.address='0.0.0.0:0'")
                  CMD+=("-C rest_server.address='0.0.0.0:0'")
                  CMD+=("-C event_stream_server.address='0.0.0.0:0'")
                  CMD+=("-C speculative_exec_server.address='0.0.0.0:0'")
                fi

                CMD+=("> $DATA_DIR/node-$ID.log 2> $DATA_DIR/node-$ID.log.stderr")

                mkdir -p "''${STORAGE_DIR}"

                eval ''${CMD[*]}
              }
            '';
          in {
            program = (pkgs.writeShellScript "run-casper-node" ''
              ${run-single-node}
              config="$(${gen-test-config})"
              run_dir="$(${run-dir})"
              echo $run_dir
              for i in $@; do
                run-single-node $i "$config" "$run_dir" &
              done
            '').outPath;
            type = "app";
          };
          # gen-test-config = {
          #   program = ().outPath;
          #   type = "app";
          # };
        };
      }
    );

}
