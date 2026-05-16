{
  description = "DXController asset tooling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # python3 with Pillow (PIL) — the only dependency of png-to-pcx.py.
      pythonFor = system:
        nixpkgs.legacyPackages.${system}.python3.withPackages (ps: [ ps.pillow ]);
    in
    {
      # `nix run .#png-to-pcx` — convert assets/xbox-buttons-png/*.png to
      # 8-bit PCX in assets/xbox-buttons-pcx/. Run from the repo root.
      # Optional args override the source/destination directories:
      #   nix run .#png-to-pcx -- SRC_DIR DST_DIR
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          png-to-pcx = pkgs.writeShellApplication {
            name = "png-to-pcx";
            runtimeInputs = [ (pythonFor system) ];
            text = ''
              src="''${1:-assets/xbox-buttons-png}"
              dst="''${2:-assets/xbox-buttons-pcx}"
              exec python3 ${./assets/png-to-pcx.py} "$src" "$dst"
            '';
          };
        in
        {
          png-to-pcx = {
            type = "app";
            program = "${png-to-pcx}/bin/png-to-pcx";
          };
          default = self.apps.${system}.png-to-pcx;
        });

      # `nix develop` — a shell with python3 + Pillow on PATH.
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [ (pythonFor system) ];
        };
      });
    };
}
