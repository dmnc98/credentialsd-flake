# xdg-desktop-portal with the experimental Credential portal. credentialsd >= 0.3
# only accepts WebAuthn requests forwarded by this portal. The interface landed
# upstream after 1.22, but isn't in a stable release yet.
#
# This is the stable release plus the backport credentialsd upstream ships in
# its own RPMs. The patches are taken unchanged from
# https://build.opensuse.org/package/show/home:MSirringhaus:webauthn_devel/xdg-desktop-portal
# (rev 15), which built the xdg-desktop-portal-1.22.1 RPM of credentialsd 0.4.0.
{
  lib,
  fetchFromGitHub,
  libdex,
  xdg-desktop-portal,
}:

xdg-desktop-portal.overrideAttrs (old: {
  version = "1.22.1-credentials";

  # Pinned, since the patches only apply to this release.
  src = fetchFromGitHub {
    owner = "flatpak";
    repo = "xdg-desktop-portal";
    tag = "1.22.1";
    hash = "sha256-GYPc5gFw3vMiDbrw5h6xeU7wupfyWeWq/Vl+vVrX8h0=";
  };

  patches = old.patches ++ [
    ./patches/xdg-desktop-portal/pr-1938.patch # libdex preparations
    ./patches/xdg-desktop-portal/pr-2036.patch # libdex portal implementations
    ./patches/xdg-desktop-portal/pr-1889.patch # Credential portal
    # Not in the RPM. Without it, a failed Register blocks the connection forever,
    # and the helper registers an ID without a desktop entry on NixOS.
    ./patches/xdg-desktop-portal/registry-reject-insert-promise.patch
  ];

  buildInputs = old.buildInputs ++ [ libdex ];

  # The test suite doesn't cover the backport.
  doCheck = false;

  meta = old.meta // {
    description = "xdg-desktop-portal with the experimental Credential portal for credentialsd";
  };
})
