{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    advisory-db.url = "github:rustsec/advisory-db";
    advisory-db.flake = false;

    crane.url = "github:ipetkov/crane";

    treefmt.url = "github:numtide/treefmt-nix";
    treefmt.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    advisory-db,
    crane,
    treefmt,
  }: let
    forEachSystem = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "x86_64-linux"
    ];

    mkCommonArgs = pkgs: let
      htmlFilter = path: _type: builtins.match ".*html$" path != null;
      htmlOrCargo = path: type:
        (htmlFilter path type) || ((crane.mkLib pkgs).filterCargoSources path type);
    in {
      src = nixpkgs.lib.cleanSourceWith {
        src = self;
        filter = htmlOrCargo;
        name = "source";
      };

      nativeBuildInputs = with pkgs; [
        pkg-config
      ];

      buildInputs = with pkgs; [
        openssl
      ];

      strictDeps = true;

      postInstall = ''
        mkdir -p $out/share/oidc_pages/assets
        cp -r ${./assets}/* $out/share/oidc_pages/assets
      '';

      preCheck = ''
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      '';

      meta = {
        description = "Serve static HTML with OIDC for authorization and authentication";
        repository = "https://github.com/newAM/oidc_pages";
        license = [nixpkgs.lib.licenses.agpl3Plus];
        maintainers = [nixpkgs.lib.maintainers.newam];
        mainProgram = "oidc_pages";
      };
    };

    mkCargoArtifacts = pkgs: (crane.mkLib pkgs).buildDepsOnly (mkCommonArgs pkgs);

    mkPackage = pkgs:
      (crane.mkLib pkgs).buildPackage (
        nixpkgs.lib.recursiveUpdate (mkCommonArgs pkgs) {
          cargoArtifacts = mkCargoArtifacts pkgs;
        }
      );

    treefmtEval = pkgs:
      treefmt.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          alejandra.enable = true;
          prettier.enable = true;
          rustfmt = {
            enable = true;
            edition = (nixpkgs.lib.importTOML ./Cargo.toml).package.edition;
          };
          taplo.enable = true;
        };
      };
  in {
    devShells = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        commonArgs = mkCommonArgs pkgs;
      in {
        default = pkgs.mkShell {
          inherit (commonArgs) nativeBuildInputs buildInputs;

          shellHook = let
            libPath = nixpkgs.lib.makeLibraryPath commonArgs.buildInputs;
          in ''
            export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
            export LD_LIBRARY_PATH="${libPath}";
          '';
        };
      }
    );

    packages = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = mkPackage pkgs;
      }
    );

    formatter = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        (treefmtEval pkgs).config.build.wrapper
    );

    checks = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        commonArgs = mkCommonArgs pkgs;
      in {
        pkg = self.packages.${system}.default;

        formatting = (treefmtEval pkgs).config.build.check self;

        audit = (crane.mkLib pkgs).cargoAudit (
          nixpkgs.lib.recursiveUpdate commonArgs {
            inherit advisory-db;
          }
        );

        clippy = (crane.mkLib pkgs).cargoClippy (
          nixpkgs.lib.recursiveUpdate commonArgs {
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            cargoArtifacts = mkCargoArtifacts pkgs;
          }
        );

        keycloak = pkgs.callPackage ./nixos/tests/keycloak.nix {inherit self;};

        kanidm = pkgs.callPackage ./nixos/tests/kanidm.nix {inherit self;};
      }
    );

    overlays.default = final: prev: {
      oidc_pages = mkPackage prev;
    };

    nixosModules.default = import ./nixos/module.nix;
  };
}
