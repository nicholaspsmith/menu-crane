// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation
import MenuCraneCore

enum Preferences {
    static var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: UserDefaults.standard.string(forKey: "UnitSystem") ?? "") ?? .usImperial }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "UnitSystem") }
    }
    static var skinTone: SkinTone {
        get { SkinTone(rawValue: UserDefaults.standard.integer(forKey: "SkinTone")) ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "SkinTone") }
    }
    /// "crane" (default) or "dot".
    static var iconStyle: String {
        get { UserDefaults.standard.string(forKey: "IconStyle") ?? "crane" }
        set { UserDefaults.standard.set(newValue, forKey: "IconStyle") }
    }
}
