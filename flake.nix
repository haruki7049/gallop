{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.alsa-lib ];

          env.LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
          ZIG = pkgs.zig_0_16;
          nativeBuildInputs = [
            # Compiler
            ZIG
            pkgs.pkg-config

            # LSP
            pkgs.nil
            pkgs.zls

            # Music Player
            pkgs.sox # Use this command as: `play result.wav`

            # zon2nix
            pkgs.zon2nix
          ];

          gallop = pkgs.stdenv.mkDerivation {
            name = "gallop";
            src = lib.cleanSource ./.;
            doCheck = true;

            nativeBuildInputs = nativeBuildInputs ++ [ ZIG.hook ];
            inherit buildInputs;

            postPatch = ''
              ln -s ${pkgs.callPackage ./.deps.nix { }} zig-pkg

              # Remove NIX_CFLAGS_COMPILE because zig cannot understand it
              unset NIX_CFLAGS_COMPILE
            '';
          };
        in
        {
          treefmt = {
            projectRootFile = ".git/config";

            # Nix
            programs.nixfmt.enable = true;

            # Zig
            programs.zig.enable = true;
            settings.formatter.zig.command = lib.getExe ZIG;

            # GitHub Actions
            programs.actionlint.enable = true;

            # Markdown
            programs.mdformat.enable = true;
            # Keep the YAML front matter of agent skills (SKILL.md) intact
            programs.mdformat.plugins = ps: [ ps.mdformat-frontmatter ];

            # Shell Scripts
            programs.shellcheck.enable = true;
            programs.shfmt.enable = true;
          };

          packages = {
            inherit gallop;
            default = gallop;
          };

          checks = {
            inherit gallop;
          };

          devShells.default = pkgs.mkShell {
            inherit nativeBuildInputs buildInputs env;

            inputsFrom = [
              config.treefmt.build.devShell
            ];

            shellHook = ''
              # Remove NIX_CFLAGS_COMPILE because zig cannot understand it
              unset NIX_CFLAGS_COMPILE
            '';
          };
        };
    };
}
