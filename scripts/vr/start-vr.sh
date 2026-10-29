controller_count() {
  local invocation
  invocation=$(systemctl --user show monado.service --property=InvocationID --value)
  if [ -z "$invocation" ]; then
    echo 0
    return
  fi
  journalctl --user "_SYSTEMD_INVOCATION_ID=$invocation" --output=cat \
    | grep -c 'Found lighthouse controller' || true
}

wait_for_controllers() {
  local count=0
  for _ in $(seq 1 15); do
    count=$(controller_count)
    if [ "$count" -ge 2 ]; then
      echo "Monado detected both Index controllers."
      return 0
    fi
    sleep 1
  done
  return 1
}

remind_about_controllers() {
  notify-send --app-name=start-vr \
    "VR startup" "Turn on both Index controllers; Monado will start automatically." || true
  echo "Turn on both Index controllers; starting Monado automatically..."
}

if [ "$#" -ne 0 ]; then
  echo "usage: start-vr" >&2
  exit 2
fi

cleanup_incomplete_start() {
  status=$?
  if [ "$status" -ne 0 ] && ! systemctl --user is-active --quiet vr-session.target; then
    systemctl --user stop vr-lighthouses.service || true
  fi
  exit "$status"
}
trap cleanup_incomplete_start EXIT

systemctl --user start vr-lighthouses.service

if ! systemctl --user is-active --quiet vr-session.target; then
  # Clear a socket-activated instance before the user powers on the
  # controllers. Startup retries leave standby disabled so this does not
  # turn off a controller the old instance already knew about.
  systemctl --user stop wayvr-debug.service || true
  systemctl --user stop monado.service monado.socket || true
  remind_about_controllers

  systemctl --user start vr-session.target
fi

# Standby is disabled for ordinary Monado exits, so retries do not turn
# off a controller that an earlier attempt already discovered.
for attempt in 1 2 3; do
  if wait_for_controllers; then
    exit 0
  fi

  count=$(controller_count)
  if [ "$attempt" -eq 3 ]; then
    echo "Monado detected only $count of 2 Index controllers after $attempt attempts; check its journal." >&2
    systemctl --user stop vr-session.target || true
    exit 1
  fi

  echo "Monado detected only $count of 2 Index controllers; restarting the VR clients (attempt $((attempt + 1))/3)."
  notify-send --app-name=start-vr \
    "VR controller retry" "Only $count of 2 controllers detected. Make sure both are powered on." || true
  systemctl --user stop wayvr-debug.service || true
  systemctl --user stop monado.service || true
  systemctl --user start monado.socket monado.service wayvr-debug.service
done
