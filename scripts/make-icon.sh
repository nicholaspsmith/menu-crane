#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nicholas Smith

# Rebuild Resources/bundle/AppIcon.icns and docs/mascot.png: Mendoza, drawn by
# the same code as in the menu bar (StatusItemKit), large on a dark macOS tile.
# The renderer lives in the Menumon site repo, which draws every app's icon the
# same way; this runs it for this app only. Needs widgets.nicksmith.software and
# StatusItemKit checked out beside this repo.
set -euo pipefail
cd "$(dirname "$0")/.."
renderer=../widgets.nicksmith.software/art/glyphs/app-icons.sh
[ -x "$renderer" ] || { echo "Missing $renderer (clone widgets.nicksmith.software beside this repo)" >&2; exit 1; }
CODE="$(cd .. && pwd)" "$renderer" menu-crane
