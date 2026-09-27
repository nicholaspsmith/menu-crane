#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nicholas Smith

# Build "Menu Crane.app" via the shared StatusItemKit bundler.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh MenuCrane "Menu Crane"
