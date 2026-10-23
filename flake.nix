{
  description = "credentialsd (Linux passkey / WebAuthn credential service) for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        xdg-desktop-portal-credentials = pkgs.callPackage ./xdg-desktop-portal.nix { };
        credentialsd = pkgs.callPackage ./package.nix {
          xdg-desktop-portal = xdg-desktop-portal-credentials;
        };
        default = credentialsd;
      });

      overlays.default = final: prev: {
        xdg-desktop-portal-credentials = final.callPackage ./xdg-desktop-portal.nix { };
        credentialsd = final.callPackage ./package.nix {
          xdg-desktop-portal = final.xdg-desktop-portal-credentials;
        };
      };

      nixosModules.default = import ./module.nix self;
      nixosModules.credentialsd = self.nixosModules.default;

      homeModules.default = import ./hm-module.nix self;
      homeModules.credentialsd = self.homeModules.default;

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
