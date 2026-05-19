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
      # `nix run .#png-to-pcx` — convert a directory of PNGs to 8-bit PCX
      # via assets/png-to-pcx.py. Run from the repo root. All arguments are
      # forwarded to the script:
      #   nix run .#png-to-pcx -- [SRC_DIR] [DST_DIR] [--size N]
      # With no arguments the script's own defaults apply (assets/XboxSeries
      # -> assets/XboxSeries-pcx).
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          png-to-pcx = pkgs.writeShellApplication {
            name = "png-to-pcx";
            runtimeInputs = [ (pythonFor system) ];
            text = ''
              exec python3 ${./assets/png-to-pcx.py} "$@"
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

      # `nix develop` — a shell with python3 + Pillow and dos2unix on
      # PATH. dos2unix provides unix2dos, which sync-and-build.sh uses to
      # convert the LF-stored .uc sources to the CRLF that UCC.exe wants.
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ (pythonFor system) pkgs.dos2unix ];
          };
        });
    };
}
