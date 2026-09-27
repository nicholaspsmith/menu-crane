// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation

/// Where the panel remembers being dragged to, and the rule for using it again.
public enum PanelPlacement {
    public static let xKey = "PanelX"
    public static let topKey = "PanelTop"

    /// The remembered top-left, if a drag ever saved one.
    public static func load(from defaults: UserDefaults) -> CGPoint? {
        guard defaults.object(forKey: xKey) != nil, defaults.object(forKey: topKey) != nil else { return nil }
        return CGPoint(x: defaults.double(forKey: xKey), y: defaults.double(forKey: topKey))
    }

    public static func save(_ point: CGPoint, to defaults: UserDefaults) {
        defaults.set(Double(point.x), forKey: xKey)
        defaults.set(Double(point.y), forKey: topKey)
    }

    /// A remembered top-left is used only while it's still on a currently connected screen's
    /// visible frame; otherwise (or if nothing was ever saved) the caller falls back to its own
    /// default placement. Pure — no AppKit, so this is unit-testable without a real screen.
    public static func decide(saved: CGPoint?, screens: [CGRect]) -> CGPoint? {
        guard let saved, screens.contains(where: { $0.contains(saved) }) else { return nil }
        return saved
    }
}
