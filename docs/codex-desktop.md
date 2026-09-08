# Codex desktop and shared app-server on sayu

`codex-desktop.nix` installs the pinned ilysenko remote-mobile desktop variant.
`codex-remote-control.service` is a systemd user service enabled at boot;
`users.users.s.linger = true` keeps the user manager running without login.
`codex-desktop.service` starts the UI with the graphical session and stops it
when that session ends. The server remains independent of the UI.

The server uses the existing declarative codex-cli-nix CLI and ~/.codex state.
The desktop's private CLI adapter translates newline JSON RPC into WebSocket
messages on ~/.codex/app-server-control/app-server-control.sock. Codex 0.153.4's
`app-server proxy` only forwards bytes, so it cannot directly bridge Electron's
stdio JSON to this WebSocket listener. WebSocket compression must be disabled.
The adapter uses Nix-packaged Python/websockets, not uv or a /tmp script.

Remote host: phone or Natto Desktop -> Sayu's single server.
Local UI: Sayu Desktop -> adapter -> the same server.
Do not start a second app-server on the same socket. Prefer Remote's
"Control other devices" on Natto. An SSH client must reuse the existing socket;
an SSH bootstrap which launches another server may report address-in-use.

Useful commands:

    systemctl --user status codex-remote-control codex-desktop
    journalctl --user -u codex-remote-control -u codex-desktop
    systemctl --user restart codex-desktop

Restarting codex-remote-control interrupts active sessions. GUI/browser tools
may still require a graphical login and desktop helpers even while the server
itself is reachable headlessly.

Updates: edit the pinned codex-desktop-linux revision in flake.nix, update the
lock, build, and retest the adapter and phone/desktop access. Keep the CLI and
server transport compatible. App updates are managed through Nix.
