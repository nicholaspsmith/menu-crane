// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MenuCraneCore

final class StoresTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = try Fixtures.tempDir() }

    // MARK: AliasStore

    func testMissingAliasFileIsEmptyAndFine() {
        let s = AliasStore(url: dir.appending(path: "aliases.json"))
        XCTAssertEqual(s.aliases, [:])
        XCTAssertNil(s.loadError)
    }

    func testSetAliasesPersistsAndReloads() throws {
        let url = dir.appending(path: "aliases.json")
        let s = AliasStore(url: url)
        try s.setAliases([" nerd ", "Nerd", "", "geek"], for: "👓")
        XCTAssertEqual(s.aliases["👓"], ["nerd", "geek"])     // trimmed, empty dropped, case-insensitive dedupe
        XCTAssertEqual(AliasStore(url: url).aliases["👓"], ["nerd", "geek"])
        try s.setAliases([], for: "👓")
        XCTAssertNil(AliasStore(url: url).aliases["👓"])
    }

    func testMalformedFileKeepsLastGoodCopyAndIsNeverOverwritten() throws {
        let url = dir.appending(path: "aliases.json")
        let s = AliasStore(url: url)
        try s.setAliases(["nerd"], for: "👓")
        try Data("{not json".utf8).write(to: url)
        s.reload()
        XCTAssertEqual(s.aliases["👓"], ["nerd"])
        XCTAssertNotNil(s.loadError)
        XCTAssertThrowsError(try s.setAliases(["x"], for: "🚀"))
        XCTAssertEqual(try String(contentsOf: url), "{not json")
    }

    func testOnChangeFiresOnReloadAndSet() throws {
        let s = AliasStore(url: dir.appending(path: "aliases.json"))
        var calls = 0
        s.onChange = { calls += 1 }
        try s.setAliases(["a"], for: "🚀")
        s.reload()
        XCTAssertEqual(calls, 2)
    }

    // MARK: UsageStore

    func testBoostGrowsWithUseAndFadesWithTime() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let s = UsageStore(url: dir.appending(path: "usage.json"), now: { now })
        XCTAssertEqual(s.boost(for: "com.apple.Safari"), 0)
        s.recordLaunch("com.apple.Safari")
        let once = s.boost(for: "com.apple.Safari")
        for _ in 0..<7 { s.recordLaunch("com.apple.Safari") }
        let often = s.boost(for: "com.apple.Safari")
        XCTAssertGreaterThan(often, once)
        XCTAssertLessThanOrEqual(often, 1.5)
        now = now.addingTimeInterval(60 * 86_400)
        XCTAssertLessThan(s.boost(for: "com.apple.Safari"), often / 4)
    }

    func testRecentEmojiDedupesOrdersAndCaps() {
        let s = UsageStore(url: dir.appending(path: "usage.json"))
        s.recordEmoji("🎉"); s.recordEmoji("👍"); s.recordEmoji("🎉")
        XCTAssertEqual(s.recentEmoji, ["🎉", "👍"])
        for i in 0..<30 { s.recordEmoji(String(UnicodeScalar(0x1F600 + i)!)) }
        XCTAssertEqual(s.recentEmoji.count, UsageStore.maxRecentEmoji)
    }

    func testUsagePersistsAndSurvivesCorruption() throws {
        let url = dir.appending(path: "usage.json")
        UsageStore(url: url).recordEmoji("🎉")
        XCTAssertEqual(UsageStore(url: url).recentEmoji, ["🎉"])
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(UsageStore(url: url).recentEmoji, [])
    }
}
