if [ "$#" -ne 0 ]; then
  echo "usage: stop-vr" >&2
  exit 2
fi

# Ordinary Monado exits keep standby disabled so start-vr can retry
# safely. Do not use monado-cli test for standby here: its libsurvive
# probe leaves this host's Valve radio HID interfaces detached.
systemctl --user stop wayvr-debug.service || true
systemctl --user stop monado.service monado.socket || true
systemctl --user stop vr-lighthouses.service || true
systemctl --user stop vr-session.target || true
