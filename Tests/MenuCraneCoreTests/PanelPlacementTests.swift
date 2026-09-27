// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MenuCraneCore

final class PanelPlacementTests: XCTestCase {
    var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "menucrane-tests-\(UUID().uuidString)")
    }

    func testSavedPointOnAScreenIsUsed() {
        let saved = CGPoint(x: 100, y: 200)
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertEqual(PanelPlacement.decide(saved: saved, screens: screens), saved)
    }

    func testSavedPointOffEveryScreenFallsBackToDefault() {
        let saved = CGPoint(x: 5000, y: 5000)
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertNil(PanelPlacement.decide(saved: saved, screens: screens))
    }

    func testNoSavedPointFallsBackToDefault() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertNil(PanelPlacement.decide(saved: nil, screens: screens))
    }

    func testRoundTripThroughUserDefaults() {
        XCTAssertNil(PanelPlacement.load(from: defaults))
        let point = CGPoint(x: 42, y: 88)
        PanelPlacement.save(point, to: defaults)
        XCTAssertEqual(PanelPlacement.load(from: defaults), point)
    }
}
