if [ "$#" -ne 1 ] || [[ "$1" != "on" && "$1" != "off" ]]; then
  echo "usage: vr-lighthouses on|off" >&2
  exit 2
fi

# Base-station IDs, one per line, in ~/.config/vr-lighthouses. lighthouse
# 2.0.0 requires lowercase, colon-separated IDs. Omit the unstable hciN
# prefix so Bluetooth adapter renumbering does not skip the stations.
conf="${XDG_CONFIG_HOME:-$HOME/.config}/vr-lighthouses"
args=()
while read -r id; do
  [ -n "$id" ] && args+=(--bsid "$id")
done < "$conf"

exec lighthouse -vv \
  --state "$1" \
  "${args[@]}" \
  --retries 5 \
  --retry-delay 2
