{
  description = "agency — near-autonomous workflow for coding agents";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # Duplicated in website/flake.nix — intentional: two flakes track
      # different subsystem release cadences (Astro/pnpm vs bats/jj/nickel).
      # If platform support changes, edit both.
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.bats
              pkgs.jq
              pkgs.jujutsu # jj-vcs/jj — nixpkgs#jj is a different tool (JSON Stream Editor)
              pkgs.nickel
              pkgs.shellcheck
              pkgs.just
              pkgs.uv # for apm-sync (uvx is a uv subcommand)
            ];
          };
        });
    };
}