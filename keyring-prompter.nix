{ pkgs, ... }:
let
  launcher = pkgs.writeShellScript "keyring-prompter" ''
    exec ${pkgs.python3}/bin/python ${./keyring-prompter.py} \
      ${pkgs.systemd}/bin/systemctl ${pkgs.gcr_3}/libexec/gcr-prompter
  '';
  activation = name: {
    text = ''
      [D-BUS Service]
      Name=${name}
      Exec=${launcher}
      SystemdService=keyring-prompter.service
    '';
  };
in {
  # Per-user activation files take precedence over the package's direct Exec.
  xdg.dataFile."dbus-1/services/org.gnome.keyring.SystemPrompter.service" =
    activation "org.gnome.keyring.SystemPrompter";
  xdg.dataFile."dbus-1/services/org.gnome.keyring.PrivatePrompter.service" =
    activation "org.gnome.keyring.PrivatePrompter";

  systemd.user.services.keyring-prompter = {
    Unit = {
      Description = "GNOME Keyring prompt with the graphical login environment";
      After = [ "graphical-session-pre.target" ];
      Before = [ "codex-desktop.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "org.gnome.keyring.SystemPrompter";
      ExecStart = launcher;
      # Early activation may precede a human login by an arbitrary interval.
      TimeoutStartSec = "infinity";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
