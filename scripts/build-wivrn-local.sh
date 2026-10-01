#!/usr/bin/env bash
# Build local server edits through the same derivation used by the NixOS service.
set -euo pipefail
config=$(cd -- "$(dirname -- "$0")/.." && pwd)
checkout=${WIVRN_CHECKOUT:-/home/s/code/wivrn}
if [[ ! -f "$checkout/monado-rev" ]]; then
  echo "Missing WiVRn checkout: $checkout" >&2
  exit 1
fi
exec nix build "$config#wivrn-frame" \
  --override-input wivrn-src "path:$checkout" --no-write-lock-file \
  --out-link "$checkout/result-server" --print-build-logs "$@"
