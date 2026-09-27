#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nicholas Smith

# Build Resources/bundle/AppIcon.icns from Mendoza's 1024 px idle image.
set -euo pipefail
cd "$(dirname "$0")/.."
src=art/mascot/mendoza-idle-1024.png
set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
for s in 16 32 128 256 512; do
  sips -z $s $s "$src" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$src" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/bundle/AppIcon.icns
echo "wrote Resources/bundle/AppIcon.icns"
