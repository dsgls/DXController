{
  description = "DXController asset tooling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # python3 with Pillow (PIL) for png-to-pcx.py and numpy for
      # gen-wheel.py's per-pixel wheel/wedge rendering.
      pythonFor = system:
        nixpkgs.legacyPackages.${system}.python3.withPackages (ps: [ ps.pillow ps.numpy ]);
    in
    {
      # `nix run .#sync-and-build` — run the in-tree sync-and-build.sh with
      # python3 + Pillow + numpy and dos2unix on PATH (the script generates
      # textures and converts the LF .uc sources to the CRLF UCC.exe wants).
      # Run from the repo root. Arguments pass through:
      #   nix run .#sync-and-build           # sync + build
      #   nix run .#sync-and-build -- -n      # dry run
      #   BUILD_DIR=/path nix run .#sync-and-build
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sync-and-build = pkgs.writeShellApplication {
            name = "sync-and-build";
            runtimeInputs = [ (pythonFor system) pkgs.dos2unix ];
            # Exec the working-tree script (not a store copy) so REPO_DIR
            # resolves to the live tree and picks up uncommitted edits.
            text = ''
              exec "$PWD/sync-and-build.sh" "$@"
            '';
          };
        in
        {
          sync-and-build = {
            type = "app";
            program = "${sync-and-build}/bin/sync-and-build";
          };
          default = self.apps.${system}.sync-and-build;
        });

      # `nix develop` — a shell with python3 + Pillow + numpy and dos2unix
      # on PATH. dos2unix provides unix2dos, which sync-and-build.sh uses to
      # convert the LF-stored .uc sources to the CRLF that UCC.exe wants;
      # Pillow + numpy drive the texture generation.
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ (pythonFor system) pkgs.dos2unix ];
          };
        });
    };
}
