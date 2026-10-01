#!/bin/sh
# Run the native ARM64 WiVRn client on the Frame without replacing SteamOS files.
set -eu
base="$HOME/Applications/wivrn"
export DISPLAY="${DISPLAY:-:0}"
export XR_RUNTIME_JSON=/opt/steamvr/steamxr_linuxarm64.json
export VR_OVERRIDE=/opt/steamvr
export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
export PRESSURE_VESSEL_FILESYSTEMS_RO=/opt/steamvr
exec "$base/runtime/SteamLinuxRuntime_4-arm64/_v2-entry-point" \
  --verb=waitforexitandrun -- "$base/3e73d98/bin/wivrn" "$@"
