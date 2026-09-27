// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
import HotkeyKit
@testable import MenuCraneCore

final class HotkeySettingsTests: XCTestCase {
    var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "menucrane-tests-\(UUID().uuidString)")
    }

    func testDefaultIsCommandSpace() {
        XCTAssertEqual(HotkeySettings.load(from: defaults), .key(49, [.command]))
    }

    func testRoundTrip() {
        HotkeySettings.save(.key(49, [.option]), to: defaults)
        XCTAssertEqual(HotkeySettings.load(from: defaults), .key(49, [.option]))
        XCTAssertEqual(defaults.integer(forKey: HotkeySettings.keyCodeKey), 49)
        XCTAssertEqual(defaults.integer(forKey: HotkeySettings.modifiersKey), Modifiers.option.rawValue)
    }

    func testNoModifiersFallsBackToDefault() {
        defaults.set(49, forKey: HotkeySettings.keyCodeKey)
        defaults.set(0, forKey: HotkeySettings.modifiersKey)
        XCTAssertEqual(HotkeySettings.load(from: defaults), HotkeySettings.defaultTrigger)
    }

    func testDescribe() {
        XCTAssertEqual(TriggerText.describe(.key(49, [.command])), "⌘Space")
        XCTAssertEqual(TriggerText.describe(.key(40, [.command, .shift, .option, .control])), "⌃⌥⇧⌘K")
        XCTAssertEqual(TriggerText.describe(.key(96, [.control])), "⌃F5")
        XCTAssertEqual(TriggerText.describe(.key(200, [.command])), "⌘Key 200")
    }
}
