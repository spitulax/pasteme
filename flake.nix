{
  description = "A very simple program to quickly copy frequently used file to the current directory.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mypkgs.url = "github:spitulax/mypkgs";
  };

  outputs = { self, nixpkgs, mypkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      eachSystem = f: lib.genAttrs systems f;
      pkgsFor = eachSystem (system:
        import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              odin = mypkgs.packages.${final.system}.odin;
            })
            self.overlays.default
          ];
        });
    in
    {
      overlays = import ./nix/overlays.nix { inherit self lib inputs; };

      packages = eachSystem (system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          default = self.packages.${system}.pasteme;
          inherit (pkgs) pasteme pasteme-debug;
        });

      devShells = eachSystem (system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          default = pkgs.callPackage ./nix/shell.nix { inherit self; };
        }
      );
    };

  nixConfig = {
    extra-substituters = [
      "spitulax.cachix.org"
    ];
    extra-trusted-public-keys = [
      "spitulax.cachix.org-1:GQRdtUgc9vwHTkfukneFHFXLPOo0G/2lj2nRw66ENmU="
    ];
  };
}
