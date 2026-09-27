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

    /// A panel dropped flush under the menu bar saves a top edge exactly at the screen's
    /// visible-frame maxY — `CGRect.contains` is half-open there, so this must still count as on
    /// screen.
    func testSavedPointExactlyAtScreenMaxYIsUsed() {
        let saved = CGPoint(x: 100, y: 900)
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertEqual(PanelPlacement.decide(saved: saved, screens: screens), saved)
    }

    /// A point on a second, negatively-offset screen (e.g. one placed to the left of the main
    /// display) is still on screen.
    func testSavedPointOnAnOffsetSecondScreenIsUsed() {
        let saved = CGPoint(x: -1440, y: 200)
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1440, y: 0, width: 1440, height: 900)]
        XCTAssertEqual(PanelPlacement.decide(saved: saved, screens: screens), saved)
    }

    func testRoundTripThroughUserDefaults() {
        XCTAssertNil(PanelPlacement.load(from: defaults))
        let point = CGPoint(x: 42, y: 88)
        PanelPlacement.save(point, to: defaults)
        XCTAssertEqual(PanelPlacement.load(from: defaults), point)
    }
}
