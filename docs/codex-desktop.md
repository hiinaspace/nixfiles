# Codex desktop and shared app-server on sayu

`codex-desktop.nix` installs the ilysenko remote-mobile desktop variant. The
upstream Nix flake currently lags OpenAI's official Linux repository, so the
module temporarily overrides its package input with the verified official
`chatgpt_26.917.51856_amd64.deb` package. Remove that override once the
upstream flake carries the same or newer package pin.
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

Desktop passes its `codex_app` MCP definition through launch-time `-c` flags.
The adapter merges those MCP defaults into `thread/start`, `thread/resume`, and
`thread/fork` requests, with request settings taking precedence. Without this,
Desktop's per-thread `enabled_tools` override creates an MCP entry without a
command and fails with `invalid transport`. These defaults stay connection-local:
the Desktop pipe path changes on restart and must not be saved in config.toml
or applied globally to the shared server. Server-wide flags still belong in
the `codex-remote-control` service's ExecStart.

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

## Keyring startup

`keyring-prompter.nix` overrides the two per-user GCR D-Bus activation entries
with `keyring-prompter.service`. The service waits for a live display socket and
reads the user manager's current environment before executing GCR. This matters
with linger: a credential lookup can activate prompting before graphical login,
when the activation environment has no display. Starting GCR directly then can
fail with `cannot open display` and leave Secret Service unlock requests stuck.
Niri's `niri-session` imports the display environment before starting graphical
services; Codex Desktop also orders itself after the prompter. The prompter can
exit when idle and is reactivated through the same guarded path when needed.
The shared app-server still starts independently at boot.

Greetd includes the login PAM stack, which already starts GNOME Keyring and
unlocks the Login keyring with the login password. Login should be the default
collection, and its password must match the login password for auto-unlock.
On 2026-09-14, the Chromium safe-storage key, its control entry, the Chromium
application key, and the existing Codex MCP credential were migrated from the
separate Default keyring into Login. Copies were verified before originals were
removed; unrelated entries remain in the old collection. The original encrypted
files are backed up under `~/.local/state/keyring-migration/20260914-215718/`.
This was a one-time Secret Service migration; no secrets are part of Nix or Git.

Validation: the wrapper waited without a display, picked up a later environment,
and removed a stale DISPLAY value. An isolated user D-Bus activation stayed
pending for 30 seconds before the display became available, then completed.
Both real prompt names activated the managed service after switching, and a
Desktop restart completed account/model/thread-list requests without the prior
Statsig timeout. A full reboot remains the final startup-order check.

Reboot check: log in normally, confirm Codex loads without a keyring dialog, and
inspect `journalctl --user -b -u keyring-prompter -u codex-desktop`. If an unrelated
keyring needs unlocking, its prompt should appear in the graphical session.
Check the default alias with:

    busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service ReadAlias s default

Updates: update the pinned codex-desktop-linux revision in flake.nix, update the
lock, and remove or revise the temporary official-package override above when
upstream catches up. Build and retest the adapter and phone/desktop access.
Keep the CLI and server transport compatible. App updates are managed through
Nix.
