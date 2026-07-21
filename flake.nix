{
  description = "agency — near-autonomous workflow for coding agents";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # The systems list and the nixpkgs.url input are duplicated in
      # website/flake.nix — intentional: two flakes track different
      # subsystem release cadences (Astro/pnpm vs bats/jj/nickel). If the
      # nixpkgs pin drifts between the two, tool versions diverge across
      # sibling devShells (e.g. bats at one rev, just at another). Bump
      # both flakes' nixpkgs together when updating.
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            # Binaries consumed by recipes: bats, jq, jj (from jujutsu),
            # nickel, shellcheck, just, uv + uvx (uvx is a uv subcommand).
            # Kept in sync with the check-env recipe in justfile.
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