self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.credentialsd;
  flakePackages = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "services" "credentialsd" "portal" "enable" ] ''
      The patched xdg-desktop-portal is now always used; see services.credentialsd.portal.package.
    '')
  ];

  options.services.credentialsd = {
    enable = lib.mkEnableOption "credentialsd, a D-Bus service for WebAuthn/passkey credentials";

    package = lib.mkOption {
      type = lib.types.package;
      default = flakePackages.credentialsd;
      defaultText = lib.literalExpression "credentialsd.packages.\${system}.credentialsd";
      description = ''
        The credentialsd package to use. It must be built to trust
        {option}`services.credentialsd.portal.package`.
      '';
    };

    portal.package = lib.mkOption {
      type = lib.types.package;
      default = flakePackages.xdg-desktop-portal-credentials;
      defaultText = lib.literalExpression "credentialsd.packages.\${system}.xdg-desktop-portal-credentials";
      description = ''
        xdg-desktop-portal build with the experimental Credential portal. Browsers
        send WebAuthn requests to it, and it forwards them to credentialsd. It
        replaces the stock portal in the `xdg-desktop-portal` user service.
      '';
    };

    smartcard.enable = lib.mkEnableOption ''
      pcscd, so credentialsd can talk to NFC readers and smart-card authenticators.
      USB security keys work without it'';

    firefox.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.firefox.enable;
      defaultText = lib.literalExpression "config.programs.firefox.enable";
      description = ''
        Register the native messaging host with the NixOS-managed Firefox
        (`programs.firefox`) and force-install the signed credentialsd helper
        extension through policy.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.xdg.portal.enable;
            message = "services.credentialsd requires xdg.portal.enable = true.";
          }
          {
            assertion = cfg.package.xdg-desktop-portal or null == cfg.portal.package;
            message = ''
              services.credentialsd.package only trusts the portal it was built with.
              Build it with `.override { xdg-desktop-portal = <services.credentialsd.portal.package>; }`.
            '';
          }
        ];

        # Puts the UI's GSettings schema and icons on the profile.
        environment.systemPackages = [ cfg.package ];

        # D-Bus activation files for xyz.iinuwa.credentialsd.{Credentials,UiControl};
        # they hand off to the systemd user units below.
        services.dbus.packages = [ cfg.package ];
        systemd.packages = [ cfg.package ];

        # Run the patched portal in place of the stock one and switch on its
        # Credential interface. Only the main portal binary is swapped; the
        # document portal and permission store stay stock. Written as a raw
        # drop-in because systemd.user.services would also pin PATH, hiding the
        # session PATH the portal needs to launch apps.
        # The portal only exports the Credential interface when portals.conf
        # names a backend for it (credentialsd.portal has no UseIn fallback).
        # portals.conf files from all config dirs are consulted in turn, so
        # this one entry in /etc/xdg doesn't affect other interfaces.
        xdg.portal = {
          extraPortals = [ cfg.package ];
          config.common."org.freedesktop.impl.portal.experimental.Credential" = [ "credentialsd" ];
        };

        systemd.user.units."xdg-desktop-portal.service" = {
          overrideStrategy = "asDropin";
          text = ''
            [Service]
            ExecStart=
            ExecStart=${cfg.portal.package}/libexec/xdg-desktop-portal
            Environment=XDG_DESKTOP_PORTAL_ENABLE_EXPERIMENTAL=credential
          '';
        };
      }

      (lib.mkIf cfg.smartcard.enable {
        services.pcscd.enable = true;
      })

      (lib.mkIf cfg.firefox.enable {
        programs.firefox = {
          nativeMessagingHosts.packages = [ cfg.package ];
          policies.ExtensionSettings.${cfg.package.firefoxExtension.addonId} = {
            installation_mode = "force_installed";
            install_url = "file://${cfg.package.firefoxExtension}";
          };
        };
      })
    ]
  );
}
