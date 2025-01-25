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
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    craneLib = crane.mkLib pkgs;

    commonArgs = let
      htmlFilter = path: _type: builtins.match ".*html$" path != null;
      htmlOrCargo = path: type:
        (htmlFilter path type) || (craneLib.filterCargoSources path type);
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

      meta = {
        description = "Serve static HTML with OIDC for authorization and authentication";
        repository = "https://github.com/newAM/oidc_pages";
        license = [nixpkgs.lib.licenses.agpl3Plus];
        maintainers = [nixpkgs.lib.maintainers.newam];
        mainProgram = "oidc_pages";
      };
    };

    cargoArtifacts = craneLib.buildDepsOnly commonArgs;

    treefmtEval = treefmt.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs = {
        alejandra.enable = true;
        prettier.enable = true;
        rustfmt.enable = true;
        taplo.enable = true;
      };
    };
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      inherit (commonArgs) nativeBuildInputs buildInputs;

      shellHook = let
        libPath = nixpkgs.lib.makeLibraryPath commonArgs.buildInputs;
      in ''
        export PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig"
        export LD_LIBRARY_PATH="${libPath}";
      '';
    };

    packages.x86_64-linux.default = craneLib.buildPackage (
      nixpkgs.lib.recursiveUpdate
      commonArgs
      {
        inherit cargoArtifacts;
      }
    );

    formatter.x86_64-linux = treefmtEval.config.build.wrapper;

    checks.x86_64-linux = {
      pkgs = self.packages.x86_64-linux.default;

      formatting = treefmtEval.config.build.check self;

      audit = craneLib.cargoAudit (nixpkgs.lib.recursiveUpdate commonArgs {
        inherit advisory-db;
      });

      clippy = craneLib.cargoClippy (nixpkgs.lib.recursiveUpdate
        commonArgs
        {
          cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          inherit cargoArtifacts;
        });

      basic = pkgs.callPackage ./nixos/tests/basic.nix {inherit self;};
    };

    overlays.default = final: prev: {
      oidc_pages = self.packages.${prev.system}.default;
    };

    nixosModules.default = import ./nixos/module.nix;
  };
}
