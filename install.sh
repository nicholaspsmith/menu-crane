#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nicholas Smith

# Build Menu Crane.app and symlink it into ~/Applications (rebuilds propagate;
# SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

# Menubarn release rule — every push is a release. Arm the pre-push hook in
# every Menubarn repo cloned beside this one (local git config, so a fresh
# clone has none until this runs). StatusItemKit README, "Releases".
RELEASE_KIT="$(cd "$(dirname "$0")/.." && pwd)/StatusItemKit/scripts/release/adopt.sh"
if [ -x "$RELEASE_KIT" ]; then
    "$RELEASE_KIT" --hooks-only || echo "Release hook: adopt.sh failed" >&2
else
    echo "Release hook: StatusItemKit not found beside this repo — clone it and re-run" >&2
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Menu Crane.app"

"$SRC_DIR/scripts/build-app.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# Register Start at Login. Without this the app only runs until the next reboot,
# and a menu-bar app that quietly fails to come back is easy to miss for weeks.
# SMAppService can only register the calling process's own bundle, so this has
# to run the installed binary rather than call launchctl.
if "$HOME/Applications/$APP_NAME/Contents/MacOS/MenuCrane" --login on >/dev/null; then
    echo "Start at Login: on"
else
    echo "Start at Login: could not register (turn it on from the menu)" >&2
fi

open "$HOME/Applications/$APP_NAME"

cat <<'EOF'

Menu Crane is now running in the menu bar.

Menu Crane is a ⌘Space launcher for apps, math, unit conversions and emoji.
This build is a skeleton: the global hotkey isn't wired up yet, so use the
menu-bar icon for now — it shows Start at Login and the running version.

Optional: menu ▸ Start at Login.
EOF
