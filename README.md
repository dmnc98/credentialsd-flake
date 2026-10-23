# credentialsd-flake

Unofficial Nix flake for [credentialsd](https://github.com/linux-credentials/credentialsd),
a D-Bus service that lets browsers use passkeys and security keys (USB FIDO keys,
NFC, phone-as-authenticator) on Linux.

It provides a NixOS module for the services, a home-manager module for the
browser side, and the patched xdg-desktop-portal that credentialsd needs.

Tested on NixOS unstable (26.11) with Hyprland and Zen Browser.

## Usage

Add the input:

```nix
# flake.nix
inputs.credentialsd = {
  url = "github:dmnc98/credentialsd-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### NixOS

```nix
imports = [ inputs.credentialsd.nixosModules.default ];

services.credentialsd.enable = true;
# services.credentialsd.smartcard.enable = true; # pcscd, for NFC readers / smart cards
# services.credentialsd.firefox.enable = true;   # defaults to programs.firefox.enable
```

This installs the daemon and UI with their D-Bus and systemd user services, and
swaps in the patched xdg-desktop-portal (see [How it works](#how-it-works)).
Requires `xdg.portal.enable = true`, which most desktop modules already set.
USB security keys work without extra udev rules, because systemd's
`60-fido-id.rules` already grant access.

With `firefox.enable`, the NixOS-managed Firefox (`programs.firefox`) gets the
native messaging host and the helper add-on installed through policy.

### home-manager

For browsers configured through home-manager (`programs.firefox`,
`programs.zen-browser`):

```nix
imports = [ inputs.credentialsd.homeModules.default ];

programs.credentialsd.enable = true;
# programs.credentialsd.firefox = true;       # default: programs.firefox.enable
# programs.credentialsd.zen-browser = true;   # default: programs.zen-browser.enable
```

This force-installs the helper add-on and registers its native messaging host.
Only Firefox-based browsers are supported for now.

### After switching

```sh
systemctl --user restart xdg-desktop-portal
systemctl --user stop xyz.iinuwa.credentialsd.Credentials   # D-Bus restarts it on demand
```

Logging out and back in also works. Then restart the browser and try
<https://webauthn.io>.

## How it works

```
browser add-on -> native messaging helper -> xdg-desktop-portal (Credential portal) -> credentialsd -> credentialsd-ui
```

- **Patched portal.** credentialsd >= 0.3 only takes requests from
  xdg-desktop-portal's experimental Credential portal, which isn't upstream
  yet. `xdg-desktop-portal.nix` builds
  [linux-credentials' fork](https://github.com/linux-credentials/xdg-desktop-portal)
  on top of the nixpkgs package. The module runs it in the existing
  `xdg-desktop-portal` user service through a drop-in, with
  `XDG_DESKTOP_PORTAL_ENABLE_EXPERIMENTAL=credential` set. Only the main portal
  binary is replaced; portal backends (GTK, Hyprland, ...), the document portal
  and the permission store are unchanged.
- **Portal routing.** The fork only exports the interface when `portals.conf`
  names a backend for it, so the module adds
  `org.freedesktop.impl.portal.experimental.Credential=credentialsd` to
  `/etc/xdg/xdg-desktop-portal/portals.conf`. Other interfaces keep using your
  existing portal configuration.
- **Trusted caller.** credentialsd only accepts requests from portal binaries
  at hard-coded FHS paths. `package.nix` adds the patched portal's store path at
  build time, so `services.credentialsd.package` and
  `services.credentialsd.portal.package` must match. An assertion checks this.
- **Browser add-on.** The add-on built from source is unsigned, so release
  Firefox would only load it temporarily. The package ships upstream's
  Mozilla-signed XPI from the GitHub release as `passthru.firefoxExtension`.
- **Public suffix list.** libwebauthn looks for it under `/usr/share`; it is
  patched to use the nixpkgs `publicsuffix-list`.

## Flake outputs

| Output | Description |
|---|---|
| `packages.<system>.credentialsd` (default) | credentialsd, built to trust the portal below |
| `packages.<system>.xdg-desktop-portal-credentials` | xdg-desktop-portal with the Credential portal |
| `overlays.default` | Both packages |
| `nixosModules.default` | `services.credentialsd` |
| `homeModules.default` | `programs.credentialsd` |

## Troubleshooting

Check that the portal exports the interface:

```sh
busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep experimental.Credential
```

If it's missing, the portal is still the stock one or wasn't restarted. Follow
the logs while trying a request:

```sh
journalctl --user -f -u xdg-desktop-portal \
  -u xyz.iinuwa.credentialsd.Credentials -u xyz.iinuwa.credentialsd.UiControl
```

"Request received from untrusted caller" means credentialsd and the running
portal don't match.

## Updating

- **credentialsd:** bump `version` in `package.nix`, then refresh the `src` and
  `cargoDeps` hashes (set them to `lib.fakeHash`, build, and copy the hash from
  the error).
- **Helper add-on:** its version is separate from credentialsd (currently
  0.2.0). Update the file name in the `firefoxExtension` URL to match the
  release asset, and refresh its hash.
- **Portal fork:** update `rev` and `hash` in `xdg-desktop-portal.nix` to the
  head of the fork's `credentials-portal` branch.

Upstream is pre-1.0 and its portal integration is experimental, so expect
updates to need more than hash bumps.
