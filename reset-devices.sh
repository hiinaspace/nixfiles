#!/usr/bin/env bash
set -euo pipefail

for i in \
  7-1.1.1.1:1.0 \
  7-1.1.1.1:1.1 \
  7-1.1.1.1:1.2 \
  7-1.1.3.2:1.0 \
  7-1.1.3.3:1.0 \
  7-1.1.3.3:1.1 \
  7-1.1.3.3:1.2
do
  echo "$i" | sudo tee /sys/bus/usb/drivers/usbhid/bind >/dev/null || true
  echo "$i" | sudo tee /sys/bus/usb/drivers/cdc_acm/bind >/dev/null || true
done
