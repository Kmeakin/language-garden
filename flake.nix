{
  description = "Programming language garden";

  # Flake dependency specification
  #
  # To update all flake inputs:
  #
  #     $ nix flake update --commit-lockfile
  #
  # To update individual flake inputs:
  #
  #     $ nix flake lock --update-input <input> ... --commit-lockfile
  #
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils }:
    # Construct an output set that supports a number of default systems
    flake-utils.lib.eachDefaultSystem (system:
      let
        legacyPackages = nixpkgs.legacyPackages.${system};
        ocamlPackages = legacyPackages.ocamlPackages;
        lib = legacyPackages.lib;
      in
      {
        # Exposed packages that can be built or run with `nix build` or
        # `nix run` respectively:
        #
        #     $ nix build .#<name>
        #     $ nix run .#<name> -- <args?>
        #
        packages = {
          # Compilation

          compile-arith = ocamlPackages.buildDunePackage {
            pname = "compile-arith";
            version = "0";
            src = ./.;

            duneVersion = "3";

            nativeBuildInputs = [
              ocamlPackages.menhir
            ];
          };

          # Elaboration

          elab-dependant = ocamlPackages.buildDunePackage {
            pname = "elab-dependant";
            version = "0";
            src = ./.;

            duneVersion = "3";
          };

          elab-record-patching = ocamlPackages.buildDunePackage {
            pname = "elab-record-patching";
            version = "0";
            src = ./.;
            duneVersion = "3";
          };

          # Experiments

          wip-elab-dependant = ocamlPackages.buildDunePackage {
            pname = "wip-elab-dependant";
            version = "0";
            src = ./.;

            duneVersion = "3";

            nativeBuildInputs = [
              ocamlPackages.menhir
              # for `mltt/tests/dune_inc.ml`
              ocamlPackages.ppx_string
            ];

            buildInputs = [
              ocamlPackages.pp
            ];
          };
        };

        # Development shells
        #
        #    $ nix develop .#<name>
        #    $ nix develop .#<name> --command dune build @test
        #
        # [Direnv](https://direnv.net/) is recommended for automatically loading
        # development environments in your shell. For example:
        #
        #    $ echo "use flake" > .envrc && direnv allow
        #    $ dune build @test
        #
        devShells = {
          default = legacyPackages.mkShell {
            nativeBuildInputs = [
              # Language formatters
              legacyPackages.nixpkgs-fmt
              legacyPackages.ocamlformat
              # For `dune build --watch ...`
              legacyPackages.fswatch
              # Editor tools
              ocamlPackages.ocaml-lsp
              ocamlPackages.ocamlformat-rpc-lib
              # Fancy REPL thing
              ocamlPackages.utop
            ];

            inputsFrom =
              lib.attrValues self.packages.${system};
          };
        };

        # Flake checks
        #
        #     $ nix flake check
        #
        checks = {
          # Check Nix formatting
          nixpkgs-fmt = legacyPackages.runCommand "check-nixpkgs-fmt"
            { nativeBuildInputs = [ legacyPackages.nixpkgs-fmt ]; }
            ''
              mkdir $out
              nixpkgs-fmt --check ${./flake.nix}
            '';
        }
        # Dune package tests
        // lib.mapAttrs
          (name: package:
            package.overrideAttrs (oldAttrs: {
              name = "chack-${oldAttrs.name}";
              doCheck = true;
            }))
          self.packages.${system};
      });
}
