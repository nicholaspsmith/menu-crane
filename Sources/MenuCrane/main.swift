// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

// `--login on|off|status` for install.sh; exits before any UI exists.
LoginCLI.runIfRequested()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
