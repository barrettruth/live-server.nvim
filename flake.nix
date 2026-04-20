{
  description = "live-server.nvim — live reload for web development in Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      nixpkgs,
      systems,
      ...
    }:
    let
      forEachSystem =
        f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-tree);

      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.just
            (pkgs.luajit.withPackages (
              ps: with ps; [
                busted
                nlua
              ]
            ))
            pkgs.prettier
            pkgs.stylua
            pkgs.neovim
            pkgs.selene
            pkgs.lua-language-server
            pkgs.vimdoc-language-server
          ];
        };

        ci = pkgs.mkShell {
          packages = [
            pkgs.just
            (pkgs.luajit.withPackages (
              ps: with ps; [
                busted
                nlua
              ]
            ))
            pkgs.prettier
            pkgs.stylua
            pkgs.neovim
            pkgs.selene
            pkgs.lua-language-server
            pkgs.vimdoc-language-server
          ];
        };
      });
    };
}
