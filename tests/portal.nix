# Boots the NixOS module and sends requests through portal -> credentialsd. Has
# no display or authenticator, so requests stop once the UI fails to start.
{ pkgs, self }:

let
  python = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);
  client = "${python.interpreter} ${./portal-client.py}";

  # Registering an app ID requires a desktop entry with the same name.
  desktopEntry =
    id:
    pkgs.writeTextDir "share/applications/${id}.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=${id}
      Exec=/bin/sh
    '';
in
pkgs.testers.runNixOSTest {
  name = "credentialsd-portal";

  nodes.machine = {
    imports = [ self.nixosModules.default ];

    services.credentialsd.enable = true;
    xdg.portal = {
      enable = true;
      config.common.default = [ "*" ];
    };

    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };

    environment.systemPackages = map desktopEntry [
      "org.mozilla.firefox"
      "zen-beta"
      "scopedapp"
    ];

    # The portal unit has Requisite=graphical-session.target, which can't be
    # started by hand.
    systemd.user.targets.test-session = {
      bindsTo = [ "graphical-session.target" ];
      before = [ "graphical-session.target" ];
    };
  };

  testScript = ''
    RECEIVED = "Received request for creating credential"
    REJECTED = "App ID could not be verified"


    def user(command: str) -> str:
        env = "XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
        return machine.succeed(f"su - alice -c 'export {env}; {command}'")


    def run_client(command: str) -> tuple[str, str]:
        """Runs a client against freshly started services, returns its output and the logs."""
        user("systemctl --user stop xyz.iinuwa.credentialsd.Credentials")
        # Restarting this often would otherwise hit the start limit.
        user("systemctl --user reset-failed xdg-desktop-portal; systemctl --user restart xdg-desktop-portal")
        since = machine.succeed("date +%s").strip()
        output = user(command)
        print(output)
        logs = user(
            f"journalctl --user --no-pager -o cat --since=@{since} "
            "-u xyz.iinuwa.credentialsd.Credentials -u xdg-desktop-portal"
        )
        return output, logs


    machine.wait_for_unit("user@1000.service")
    user(
        "systemctl --user set-environment RUST_LOG=credentialsd=debug "
        "G_MESSAGES_DEBUG=xdg-desktop-portal XDG_DATA_DIRS=/run/current-system/sw/share"
    )
    user("systemctl --user start test-session.target")
    user("systemctl --user start xdg-desktop-portal")

    with subtest("the patched portal runs with the Credential interface"):
        unit = user("systemctl --user show -p ExecStart xdg-desktop-portal")
        assert "${
          self.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-credentials
        }" in unit, unit
        interfaces = user("busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop")
        assert "org.freedesktop.portal.experimental.Credential" in interfaces

    with subtest("requests from a trusted browser reach credentialsd as privileged"):
        output, logs = run_client("${client} org.mozilla.firefox")
        assert "register: ok" in output
        assert RECEIVED in logs and 'AppId("org.mozilla.firefox")' in logs and "request_kind: Privileged" in logs, logs

    with subtest("requests from other browsers reach credentialsd as unprivileged"):
        output, logs = run_client("${client} zen-beta")
        assert "register: ok" in output
        assert RECEIVED in logs and 'AppId("zen-beta")' in logs and "request_kind: Unprivileged" in logs, logs

    with subtest("a failed registration doesn't hang the request"):
        output, logs = run_client("${client} not-installed")
        assert "register: failed" in output and "create: ok" in output
        assert RECEIVED not in logs, logs

    with subtest("a failed registration falls back to the systemd scope's app ID"):
        output, logs = run_client(
            "systemd-run --user --scope --quiet --unit=app-scopedapp-4242.scope ${client} not-installed"
        )
        assert "register: failed" in output and "create: ok" in output
        assert RECEIVED in logs and 'AppId("scopedapp")' in logs, logs

    with subtest("callers outside the portal are rejected"):
        output, logs = run_client("${client} --direct")
        assert "SecurityError" in output, output
        assert REJECTED in logs, logs
  '';
}
