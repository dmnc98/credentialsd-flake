# xdg-desktop-portal with the experimental Credential portal from
# linux-credentials/xdg-desktop-portal. credentialsd >= 0.3 only accepts
# WebAuthn requests forwarded by this portal; stock xdg-desktop-portal does not
# have the interface yet.
{
  lib,
  fetchFromGitHub,
  runCommand,
  dbus,
  libdex,
  wireplumber,
  xdg-desktop-portal,
}:

let
  # Upstream moved src/ to desktop-portal/ after 1.22, which the nixpkgs patches
  # are written against.
  relocatePatch =
    patch:
    runCommand (baseNameOf patch) { } ''
      sed 's|\([ab]\)/src/|\1/desktop-portal/|' ${patch} > $out
    '';
in
xdg-desktop-portal.overrideAttrs (old: {
  version = "1.23.0-unstable-2026-06-26-credentials";

  src = fetchFromGitHub {
    owner = "linux-credentials";
    repo = "xdg-desktop-portal";
    rev = "138c1257cbb92816476f5d040d4a4a359f4e69f6"; # branch credentials-portal
    hash = "sha256-lGzR0JVoaSvwPf5ykNpVPtUzueb6PaLAROcH/7WCJis=";
  };

  # Keep the icon/sound validator sandbox fixes; drop the installed-tests patch,
  # since this build doesn't ship installed tests.
  patches = map relocatePatch (
    lib.filter (p: !(lib.hasSuffix "installed-tests-path.patch" (toString p))) old.patches
  );

  # Newer upstream base than nixpkgs' 1.22 needs a few more libraries.
  buildInputs = old.buildInputs ++ [
    dbus
    libdex
    wireplumber
  ];

  mesonFlags =
    lib.filter (
      flag: !(lib.hasPrefix "-Dinstalled-tests" flag || lib.hasPrefix "-Dinstalled_test_prefix" flag)
    ) old.mesonFlags
    ++ [ "-Dinstalled-tests=false" ];

  postPatch = lib.replaceStrings [ "src/generate-method-info.py" ] [
    "desktop-portal/generate-method-info.py"
  ] old.postPatch;

  # The test suite targets upstream's portal set, not this fork.
  doCheck = false;

  meta = old.meta // {
    description = "xdg-desktop-portal with the experimental Credential portal for credentialsd";
    homepage = "https://github.com/linux-credentials/xdg-desktop-portal";
  };
})
