#!/usr/bin/env bash
# Restart the paired Frame experiment using discovered-server autoconnect.
# Authenticate SSH first; this script contains no credentials.
set -euo pipefail
frame=${FRAME_SSH_TARGET:-steamos@192.168.1.16}
control=${FRAME_SSH_CONTROL:-/run/user/1000/frame-ssh}
ssh_cmd=(ssh -S "$control" -o BatchMode=yes "$frame")
systemctl --user stop wayvr-wivrn.service wivrn.service
"${ssh_cmd[@]}" 'if systemctl --user is-active --quiet wivrn-frame-client.service; then systemctl --user stop wivrn-frame-client.service; fi'
systemctl --user start wivrn.service
"${ssh_cmd[@]}" 'systemd-run --user --unit=wivrn-frame-client --collect /home/steamos/Applications/wivrn/start-client'
for ((attempt=0; attempt<45; attempt++)); do
  if [[ $(busctl --user get-property io.github.wivrn.Server /io/github/wivrn/Server io.github.wivrn.Server HeadsetConnected 2>/dev/null) == 'b true' ]]; then
    systemctl --user start wayvr-wivrn.service
    ss -tun | rg ':9757'
    exit 0
  fi
  sleep 1
done
echo 'Frame did not autoconnect within 45 seconds; check wake state and discovery.' >&2
exit 1
