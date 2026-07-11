#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--reboot]\n' "$0"
  printf 'Set Windows Boot Manager as the UEFI one-shot next boot.\n'
}

case "${1:-}" in
  "")
    reboot_after=false
    ;;
  --reboot)
    reboot_after=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

windows_bootnum="$({
  sudo efibootmgr | awk '
    $1 ~ /^Boot/ && /Windows Boot Manager/ {
      entry = $1
      sub(/^Boot/, "", entry)
      sub(/\*$/, "", entry)
      print entry
      exit
    }
  '
})"

if [[ -z "$windows_bootnum" ]]; then
  printf 'Could not find a UEFI entry named Windows Boot Manager.\n' >&2
  exit 1
fi

sudo efibootmgr -n "$windows_bootnum"
printf 'Windows Boot Manager (Boot%s) is set for the next boot only.\n' "$windows_bootnum"

if [[ "$reboot_after" == true ]]; then
  sudo systemctl reboot
fi
