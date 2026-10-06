// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
import MenuCraneCore

final class PerformanceTests: XCTestCase {
    func testOneKeystrokeUnderFiveMilliseconds() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "menucrane-perf-\(UUID().uuidString)")
        for i in 0..<150 {
            let contents = dir.appending(path: "App Number \(i).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": "com.perf.app\(i)"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let store = try EmojiStore(data: Data(contentsOf: root.appending(path: "Resources/bundle/emoji.json")))
        let engine = SearchEngine(providers: [
            CalculatorProvider(), ConverterProvider(system: { .usImperial }), EmojiCommandProvider(),
            AppProvider(index: AppIndex(roots: [dir], extras: []), usage: UsageStore(url: dir.appending(path: "u.json"))),
            EmojiInlineProvider(store: store, aliases: { [:] }, recents: { [] }, tone: { .none }),
        ])
        let queries = ["s", "sa", "saf", "safari", "fingers crossed", "72f to c", "2+2*3", "emoji", "xyzzy", "thumbs up", "app num"]
        _ = engine.results(for: "warm")
        // Best of several rounds: a busy machine (parallel builds, a local LLM)
        // slows some rounds, but a real regression slows every one of them.
        let runs = 10
        var perQueryMs = Double.infinity
        for _ in 0..<5 {
            let start = Date()
            for _ in 0..<runs { for q in queries { _ = engine.results(for: q) } }
            perQueryMs = min(perQueryMs, Date().timeIntervalSince(start) * 1000 / Double(runs * queries.count))
        }
        print("per-query (best of 5): \(perQueryMs) ms")
        XCTAssertLessThan(perQueryMs, 5)
    }
}
