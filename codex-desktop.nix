{ config, pkgs, inputs, ... }:
let
  cli = inputs.codex-cli-nix.packages.${pkgs.system}.default;
  desktop = inputs.codex-desktop-linux.packages.${pkgs.system}.codex-desktop-remote-mobile-control;
  socket = "${config.home.homeDirectory}/.codex/app-server-control/app-server-control.sock";
  python = pkgs.python3.withPackages (p: [ p.websockets ]);
  bridge = pkgs.writeShellScriptBin "codex-desktop-bridge" ''
    export CODEX_DESKTOP_REAL_CLI=${cli}/bin/codex
    export CODEX_DESKTOP_SOCKET=${socket}
    exec ${python}/bin/python ${./codex-desktop-bridge.py} "$@"
  '';
  launcher = pkgs.symlinkJoin {
    name = "codex-desktop-shared-server";
    paths = [ desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/codex-desktop"
      makeWrapper ${desktop}/bin/codex-desktop "$out/bin/codex-desktop" \
        --set CODEX_CLI_PATH ${bridge}/bin/codex-desktop-bridge \
        --set CODEX_REMOTE_CONTROL_APP_SERVER_MODE proxy \
        --set CODEX_REMOTE_CONTROL_APP_SERVER_PROXY_SOCKET ${socket} \
        --set CODEX_REMOTE_CONTROL_DAEMON_AUTOSTART_DISABLED 1 \
        --set CODEX_LINUX_DISABLE_USAGE_REPORTING 1 \
        --set CODEX_OZONE_PLATFORM x11 \
        --unset NIXOS_OZONE_WL
      entry="$out/share/applications/codex-desktop.desktop"
      original="$(readlink -f "$entry")"
      rm "$entry"
      substitute "$original" "$entry" \
        --replace-fail '${desktop}/bin/codex-desktop' "$out/bin/codex-desktop"
    '';
  };
in {
  home.packages = [ launcher ];

  # One owner for local Desktop, phone Remote, and SSH app-server proxies.
  # Do not run another `codex app-server --listen unix://` against this socket.
  systemd.user.services.codex-remote-control = {
    Unit.Description = "Shared Codex app-server and remote control";
    Service = {
      ExecStart = "${cli}/bin/codex -c features.code_mode_host=true app-server --remote-control --listen unix://";
      Environment = [
        "CODEX_HOME=${config.home.homeDirectory}/.codex"
        "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      KillMode = "mixed";
      TimeoutStopSec = 30;
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.codex-desktop = {
    Unit = {
      Description = "ChatGPT desktop connected to the shared Codex server";
      After = [ "graphical-session.target" "codex-remote-control.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${launcher}/bin/codex-desktop";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
