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

      checks = forAllSystems (
        pkgs:
        let
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system})
            credentialsd
            xdg-desktop-portal-credentials
            ;
        in
        {
          inherit credentialsd xdg-desktop-portal-credentials;
          firefox-extension = credentialsd.firefoxExtension;
        }
        # GitHub's arm runners don't have KVM, so the VM test only covers x86_64.
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
          portal = import ./tests/portal.nix { inherit pkgs self; };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
