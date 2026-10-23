# credentialsd-flake

Nix packaging for [credentialsd](https://github.com/linux-credentials/credentialsd),
a D-Bus service that lets browsers use passkeys and security keys (USB FIDO keys,
NFC, phone-as-authenticator) on Linux.

## Usage

```nix
# flake.nix
inputs.credentialsd = {
  url = "path:/home/dominic/git/credentialsd"; # or a git URL once pushed
  inputs.nixpkgs.follows = "nixpkgs";
};
```

NixOS (daemon, UI, D-Bus activation, systemd user units):

```nix
imports = [ inputs.credentialsd.nixosModules.default ];
services.credentialsd.enable = true;
# services.credentialsd.smartcard.enable = true; # pcscd, for NFC / smart cards
# services.credentialsd.firefox.enable = true;   # defaults to programs.firefox.enable
```

home-manager (browser add-on + native messaging host for `programs.firefox`
and `programs.zen-browser`, each enabled automatically when that browser is):

```nix
imports = [ inputs.credentialsd.homeModules.default ];
programs.credentialsd.enable = true;
```

Then open <https://webauthn.io> to try it.

## Notes

- The browser add-on is the Mozilla-signed XPI from upstream's GitHub release
  (`passthru.firefoxExtension`). The XPI built from source is unsigned.
- credentialsd >= 0.3 only takes requests from xdg-desktop-portal's
  experimental Credential portal, which isn't upstream yet. The module builds
  [linux-credentials' fork](https://github.com/linux-credentials/xdg-desktop-portal)
  (`xdg-desktop-portal.nix`), runs it in the `xdg-desktop-portal` user service
  with `XDG_DESKTOP_PORTAL_ENABLE_EXPERIMENTAL=credential`, and compiles its
  store path into credentialsd's trusted-caller list.
- Updating: bump `version` in `package.nix`, then refresh the `src`,
  `cargoDeps` and `firefoxExtension` hashes (set them to `lib.fakeHash` and
  copy the hash from the build error).
