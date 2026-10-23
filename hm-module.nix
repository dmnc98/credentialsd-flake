self:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.credentialsd;

  # Firefox-family browsers managed through home-manager's mkFirefoxModule
  # (programs.firefox, programs.zen-browser, programs.librewolf, ...).
  browserConfig = {
    nativeMessagingHosts = [ cfg.package ];
    policies.ExtensionSettings.${cfg.package.firefoxExtension.addonId} = {
      installation_mode = "force_installed";
      install_url = "file://${cfg.package.firefoxExtension}";
    };
  };

  mkBrowserOption =
    name:
    lib.mkOption {
      type = lib.types.bool;
      default = options.programs ? ${name} && config.programs.${name}.enable;
      defaultText = lib.literalExpression "config.programs.${name}.enable";
      description = "Wire the credentialsd helper extension and native messaging host into `programs.${name}`.";
    };

  browsers = [
    "firefox"
    "zen-browser"
  ];
in
{
  options.programs.credentialsd = {
    enable = lib.mkEnableOption "credentialsd browser integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.credentialsd;
      defaultText = lib.literalExpression "credentialsd.packages.\${system}.credentialsd";
      description = "The credentialsd package to use.";
    };
  }
  // lib.genAttrs browsers mkBrowserOption;

  config = lib.mkIf cfg.enable {
    programs = lib.genAttrs (lib.filter (name: options.programs ? ${name}) browsers) (
      name: lib.mkIf cfg.${name} browserConfig
    );
  };
}
