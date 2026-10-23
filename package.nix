{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  rustPlatform,
  cargo,
  rustc,
  meson,
  ninja,
  pkg-config,
  glib,
  gtk4,
  dbus,
  openssl,
  udev,
  pcsclite,
  libnfc,
  gettext,
  desktop-file-utils,
  appstream,
  blueprint-compiler,
  libxml2,
  zip,
  wrapGAppsHook4,
  python3,
  publicsuffix-list,
  # The portal credentialsd accepts requests from. Needs the experimental
  # Credential portal, see ./xdg-desktop-portal.nix.
  xdg-desktop-portal,
}:

let
  pythonEnv = python3.withPackages (ps: [ ps.dbus-next ]);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "credentialsd";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "linux-credentials";
    repo = "credentialsd";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wCkgO/T8UCQLMAY6HyxEL0HlGFlRhqGC+bZc6XhcTwU=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version src;
    hash = "sha256-+YEr2bPkJwl0DEWMjKDCjIgq5SX54T2jsbYRbRPGOwQ=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    cargo
    rustc
    rustPlatform.cargoSetupHook
    rustPlatform.bindgenHook
    glib
    gettext
    desktop-file-utils
    appstream
    blueprint-compiler
    libxml2
    python3
    zip
    wrapGAppsHook4
  ];

  buildInputs = [
    glib
    gtk4
    dbus
    openssl
    udev
    pcsclite
    libnfc
    pythonEnv
  ];

  postPatch = ''
    patchShebangs credentialsd-ui/data/resources/icons/copy-icons.py

    # Only requests forwarded by xdg-desktop-portal are trusted, identified by
    # the caller's executable path. Upstream only knows FHS locations; add the
    # store path of the (wrapped) portal binary.
    substituteInPlace credentialsd/src/gateway/mod.rs \
      --replace-fail 'PathBuf::from("/usr/lib/xdg-desktop-portal"),' \
        'PathBuf::from("${xdg-desktop-portal}/libexec/.xdg-desktop-portal-wrapped"),
        PathBuf::from("${xdg-desktop-portal}/libexec/xdg-desktop-portal"),
        PathBuf::from("/usr/lib/xdg-desktop-portal"),'

    # libwebauthn looks for the public suffix list (used for WebAuthn related
    # origins) under /usr/share, which doesn't exist on NixOS.
    substituteInPlace $cargoDepsCopy/source-git-0/libwebauthn-*/src/ops/webauthn/psl/dat.rs \
      --replace-fail /usr/share/publicsuffix/public_suffix_list.dat \
        ${publicsuffix-list}/share/publicsuffix/public_suffix_list.dat
  '';

  mesonFlags = [
    (lib.mesonBool "cargo_offline" true)
    (lib.mesonBool "cargo_locked" true)
  ];

  # The cargo test suites need a session bus and real authenticators.
  doCheck = false;

  passthru = {
    inherit xdg-desktop-portal;

    # The XPI built from source is unsigned, so release Firefox only accepts it
    # as a temporary add-on. Upstream publishes a Mozilla-signed build with
    # each release; install this one (e.g. via ExtensionSettings policy).
    firefoxExtension = fetchurl {
      name = "credentialsd-helper-0.2.0.xpi";
      url = "https://github.com/linux-credentials/credentialsd/releases/download/v${finalAttrs.version}/credentialsd-helper%40iinuwa.xyz-0.2.0.xpi";
      hash = "sha256-khoKFbCsCg/YO1bCqY9kYTVVQ3O6KKHgXB9g37yhM9I=";
      passthru.addonId = "credentialsd-helper@iinuwa.xyz";
    };
  };

  meta = {
    description = "Linux credential manager service for passkeys and other web credentials";
    homepage = "https://github.com/linux-credentials/credentialsd";
    license = lib.licenses.lgpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "credentialsd";
  };
})
