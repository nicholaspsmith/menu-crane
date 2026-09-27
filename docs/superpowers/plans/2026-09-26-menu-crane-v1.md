# Menu Crane v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Menu Crane v1.0.0 — a ⌘Space keyboard launcher (apps, arithmetic, unit conversions, emoji with user aliases) that replaces Raycast, shipped as a Menubarn app.

**Architecture:** SwiftPM package with a UI-free, unit-tested `MenuCraneCore` library (matcher, calculator, converter, emoji store, stores, app index, providers, search engine, panel state) and a `MenuCrane` executable (AppKit `NSPanel` hosting SwiftUI views, Carbon hotkey, StatusItemKit menu-bar item). Every provider answers a `Query` with scored `ResultItem`s; the panel shows the merged list.

**Tech Stack:** Swift 5.9, macOS 13+, AppKit + SwiftUI, Carbon `RegisterEventHotKey`, Foundation `Measurement`, FSEvents, XCTest; StatusItemKit and HotkeyKit (local path packages); Python 3 stdlib for the emoji data script.

**Spec:** `docs/superpowers/specs/2026-09-26-menu-crane-design.md`

## Global Constraints

- Repo `~/Code/menu-crane`; product `MenuCrane`; display name `Menu Crane`; bundle id `com.nicholaspsmith.MenuCrane`; log subsystem `com.nicholaspsmith.MenuCrane`.
- `platforms: [.macOS(.v13)]`, `// swift-tools-version:5.9`.
- **License: MIT** (`LICENSE` already in the repo). Every source file starts with:
  ```
  // SPDX-License-Identifier: MIT
  // Copyright (c) 2026 Nicholas Smith
  ```
  (`#` comment form for shell/Python.) Wherever a step below says "MPL header", use this header.
- The public repo `github.com/nicholaspsmith/menu-crane` already exists with a stub `README.md`; Task 18 fills the README out rather than creating it.
- v1 needs **no Accessibility permission** and makes **no network calls at runtime**.
- One keystroke's query across all providers: **< 5 ms** (release build).
- Stored data lives in `~/Library/Application Support/MenuCrane/` (`aliases.json`, `usage.json`); settings in `UserDefaults`; all file writes atomic.
- UI copy, verbatim: `⌘, for settings`, `Copied`, `Couldn't open <name>`, `⚠ Hotkey unavailable — <reason>`, unit setting names `US Imperial` / `Metric`.
- **Menubarn release rule: every push is a release.** Commit locally throughout; nothing is pushed until Task 18, and only after Nick confirms.
- **Do not disturb Raycast during development.** It holds ⌘Space. Use the development hotkey ⌥Space (set in Task 13) until the cutover in Task 19.
- Use `fd` rather than `find` for file searches.

## Review Focus

1. **Queries typed carelessly** — `"  SAFARI "`, `cafe` for "Café", mixed case: must still match. Pinned in Task 1 (`testCaseDiacriticsAndWhitespaceAreIgnored`).
2. **Conversions typed the way people type them** — `-40f to c`, `72F`, `5 KG TO LB`, `12 fl. oz in pt`: must convert. Pinned in Task 3 (`testLooseTyping`).
3. **Numbers as people type them** — `.5*2`, `3.*2`, `1,000 * 2` work; `5+`, `2(3)`, `1,00*2` give no answer rather than a wrong one or a crash. Pinned in Task 2 (`testNumberShapes`, `testIncompleteInputGivesNothing`).
4. **Skin-tone and ZWJ emoji** — copying 👍 at medium tone yields exactly U+1F44D U+1F3FD; aliases and recents stay keyed to the base emoji so changing tone loses nothing. Pinned in Task 5 (`testToneGlyphIsExactScalarSequence`, `testAliasesAndRecentsUseBaseEmoji`).
5. **An app deleted or moved after indexing** — Return must say `Couldn't open <name>` and re-index, not silently do nothing; after re-index the app is gone from results. Pinned in Task 8 (`testRemovedAppDisappearsAfterRebuild`) and Task 14 (`ActionPerformer.open` returns false → footer + `index.rebuild()`; manual check 10).

---

## File Structure

```
menu-crane/
  Package.swift
  .gitignore  LICENSE  README.md  CHANGELOG.md  install.sh
  .github/workflows/release.yml
  Resources/Info.plist
  Resources/bundle/AppIcon.icns            # Task 18
  Resources/bundle/emoji.json              # generated, Task 4
  scripts/build-app.sh  scripts/update-emoji-data.sh  scripts/make-icon.sh
  Sources/MenuCraneCore/
    Query.swift            # Query + folding
    ResultItem.swift       # ResultItem, ResultAction, ResultIcon, ResultKind, Provider
    Matcher.swift          # MatchTarget, Matcher
    NumberText.swift       # parsing "1,000.5" and formatting answers
    Calculator.swift
    UnitCatalog.swift      # UnitSystem, UnitDef table
    Converter.swift        # Conversion, Converter
    Emoji.swift            # Emoji, SkinTone, EmojiHit
    EmojiStore.swift
    Log.swift              # coreLog
    AtomicFile.swift       # AtomicFile, DirectoryWatcher
    AliasStore.swift
    UsageStore.swift
    AppIndex.swift         # AppEntry, AppIndex
    FSEventsWatcher.swift
    Providers.swift        # App/Calculator/Converter/EmojiCommand/EmojiInline providers
    SearchEngine.swift
    PanelState.swift
    HotkeySettings.swift   # HotkeySettings, TriggerText
    AliasTable.swift       # AliasRow + filtering for the Aliases window
  Sources/MenuCrane/
    main.swift  App.swift  Preferences.swift
    HotkeyService.swift
    CranePanel.swift  PanelController.swift  ActionPerformer.swift  IconCache.swift  EditMenu.swift
    PanelViews.swift  EmojiViews.swift
    SettingsWindow.swift  AliasesWindow.swift
  Tests/MenuCraneCoreTests/
    Fixtures.swift  MatcherTests.swift  CalculatorTests.swift  ConverterTests.swift
    EmojiStoreTests.swift  StoresTests.swift  AppIndexTests.swift  ProvidersTests.swift
    PerformanceTests.swift  PanelStateTests.swift  HotkeySettingsTests.swift  AliasTableTests.swift
```

StatusItemKit (`~/Code/StatusItemKit`) gains `CharacterIcon.menuCrane(state:)` (Task 11).

---

### Task 1: Package scaffold, core types, Matcher

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/MenuCraneCore/Query.swift`, `Sources/MenuCraneCore/ResultItem.swift`, `Sources/MenuCraneCore/Matcher.swift`
- Test: `Tests/MenuCraneCoreTests/MatcherTests.swift`

**Interfaces:**
- Produces: `Query(_:)` with `.raw`, `.folded`, `.words`, `.isEmpty`, `Query.fold(_:)`; `MatchTarget(_ fields: [String])`; `Matcher.score(_ query: Query, _ target: MatchTarget) -> Double?` and constants `Matcher.prefixScore` (3), `acronymScore` (2), `subsequenceScore` (1); `ResultItem`, `ResultAction`, `ResultIcon`, `ResultKind`, `ResultItem.pinnedScore` (1000); `protocol Provider { func results(for query: Query) -> [ResultItem] }`.

- [ ] **Step 1: Create the package skeleton**

`Package.swift` (header comment first, as in Global Constraints, then):
```swift
import PackageDescription

let package = Package(
    name: "MenuCrane",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MenuCraneCore", targets: ["MenuCraneCore"]),
    ],
    targets: [
        .target(name: "MenuCraneCore"),
        .testTarget(name: "MenuCraneCoreTests", dependencies: ["MenuCraneCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
.swiftpm/
.superpowers/
.DS_Store
```

`Sources/MenuCraneCore/Query.swift`:
```swift
import Foundation

/// A search string as typed, plus the folded words every matcher compares.
public struct Query: Equatable, Sendable {
    public let raw: String
    /// Lowercased, diacritics and width folded, trimmed.
    public let folded: String
    public let words: [String]

    public init(_ raw: String) {
        self.raw = raw
        folded = Query.fold(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        words = folded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public var isEmpty: Bool { words.isEmpty }

    /// The case-, diacritic- and width-insensitive form used on both sides of every match.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
```

`Sources/MenuCraneCore/ResultItem.swift`:
```swift
import Foundation

public enum ResultAction: Equatable, Sendable {
    case open(URL)
    case reveal(URL)
    case copy(String)
    case enterEmojiMode

    /// Footer wording for this action.
    public var label: String {
        switch self {
        case .open, .enterEmojiMode: return "Open"
        case .reveal: return "Show in Finder"
        case .copy: return "Copy"
        }
    }
}

public enum ResultIcon: Equatable, Sendable {
    case app(URL)
    case emoji(String)
    case symbol(String)   // SF Symbol name
}

public enum ResultKind: Equatable, Sendable { case answer, command, app, emoji }

public struct ResultItem: Equatable, Identifiable, Sendable {
    /// Math and conversion answers sit above everything else.
    public static let pinnedScore = 1000.0

    public let id: String
    public let kind: ResultKind
    public let title: String
    public let subtitle: String
    public let icon: ResultIcon
    public let score: Double
    public let action: ResultAction
    public let alternate: ResultAction?
    /// Footer wording for the ⌘↩ action when `alternate.label` is not specific enough.
    public let alternateLabel: String?
    /// App key or base emoji to record in UsageStore when this item is used.
    public let usageKey: String?

    public init(id: String, kind: ResultKind, title: String, subtitle: String, icon: ResultIcon,
                score: Double, action: ResultAction, alternate: ResultAction? = nil,
                alternateLabel: String? = nil, usageKey: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle; self.icon = icon
        self.score = score; self.action = action; self.alternate = alternate
        self.alternateLabel = alternateLabel; self.usageKey = usageKey
    }

    /// "↩ Open  ⌘↩ Show in Finder"
    public var footerHint: String {
        var s = "↩ \(action.label)"
        if let alternate { s += "   ⌘↩ \(alternateLabel ?? alternate.label)" }
        return s
    }
}

public protocol Provider {
    func results(for query: Query) -> [ResultItem]
}
```

- [ ] **Step 2: Write the failing Matcher tests**

`Tests/MenuCraneCoreTests/MatcherTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class MatcherTests: XCTestCase {
    func s(_ q: String, _ fields: String...) -> Double? { Matcher.score(Query(q), MatchTarget(fields)) }

    func testPrefixBeatsAcronymBeatsSubsequence() {
        let prefix = s("vis", "Visual Studio Code")!
        let acronym = s("vsc", "Visual Studio Code")!
        let subsequence = s("vsd", "Visual Studio Code")!
        XCTAssertGreaterThan(prefix, acronym)
        XCTAssertGreaterThan(acronym, subsequence)
        XCTAssertEqual(acronym, Matcher.acronymScore)
        XCTAssertEqual(subsequence, Matcher.subsequenceScore)
    }

    func testWordOrderDoesNotMatter() {
        XCTAssertNotNil(s("crossed fingers", "crossed fingers"))
        XCTAssertNotNil(s("fingers crossed", "crossed fingers"))
        XCTAssertNotNil(s("cross fing", "crossed fingers"))
    }

    func testEveryWordMustMatch() {
        XCTAssertNil(s("crossed banana", "crossed fingers"))
        XCTAssertNil(s("zzz", "Safari"))
    }

    func testCaseDiacriticsAndWhitespaceAreIgnored() {
        XCTAssertNotNil(s("  SAFARI ", "Safari"))
        XCTAssertNotNil(s("cafe", "Café Menu"))
        XCTAssertNotNil(s("CAFÉ", "cafe menu"))
    }

    func testFirstWordStartMatchRanksHigher() {
        XCTAssertGreaterThan(s("saf", "Safari")!, s("saf", "Open Safari")!)
    }

    func testExactWordBeatsLongerWord() {
        XCTAssertGreaterThan(s("mail", "Mail")!, s("mail", "Mailplane")!)
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertNil(s("", "Safari"))
        XCTAssertNil(s("   ", "Safari"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ~/Code/menu-crane && swift test --filter MatcherTests`
Expected: compile error — `cannot find 'Matcher' in scope`.

- [ ] **Step 4: Implement Matcher**

`Sources/MenuCraneCore/Matcher.swift`:
```swift
import Foundation

/// The folded words of one searchable thing, built once so a keystroke only compares strings.
public struct MatchTarget: Sendable {
    public let words: [String]
    public let initials: String
    public let joined: String

    public init(_ fields: [String]) {
        let ws = fields.flatMap { MatchTarget.split(Query.fold($0)) }
        words = ws
        initials = String(ws.compactMap(\.first))
        joined = ws.joined()
    }

    static func split(_ s: String) -> [String] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

public enum Matcher {
    public static let prefixScore = 3.0
    public static let acronymScore = 2.0
    public static let subsequenceScore = 1.0

    /// nil unless every query word matches the target; otherwise the mean of each word's best match.
    /// A word that starts a target word scores 3–4 (4 for the whole word), plus 0.5 when the query's
    /// first word starts the target's first word. Initials score 2, letters in order score 1.
    public static func score(_ query: Query, _ target: MatchTarget) -> Double? {
        guard !query.words.isEmpty, !target.words.isEmpty else { return nil }
        var total = 0.0
        for (i, qword) in query.words.enumerated() {
            let q = MatchTarget.split(qword).joined()
            if q.isEmpty { continue }   // a word of pure punctuation constrains nothing
            guard let best = best(q, target, isFirst: i == 0) else { return nil }
            total += best
        }
        return total / Double(query.words.count)
    }

    static func best(_ q: String, _ t: MatchTarget, isFirst: Bool) -> Double? {
        var best: Double?
        for (i, w) in t.words.enumerated() where w.hasPrefix(q) {
            var s = prefixScore + Double(q.count) / Double(w.count)
            if isFirst && i == 0 { s += 0.5 }
            best = max(best ?? 0, s)
        }
        if best == nil, q.count >= 2, t.initials.hasPrefix(q) { best = acronymScore }
        if best == nil, isSubsequence(q, of: t.joined) { best = subsequenceScore }
        return best
    }

    static func isSubsequence(_ q: String, of s: String) -> Bool {
        var it = s.makeIterator()
        outer: for c in q {
            while let d = it.next() { if d == c { continue outer } }
            return false
        }
        return true
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter MatcherTests`
Expected: all 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: core query, result types and fuzzy matcher"
```

---

### Task 2: Number text and Calculator

**Files:**
- Create: `Sources/MenuCraneCore/NumberText.swift`, `Sources/MenuCraneCore/Calculator.swift`
- Test: `Tests/MenuCraneCoreTests/CalculatorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NumberText.value(of: String) -> Double?` (accepts `12`, `.5`, `3.`, `1,000.25`; rejects `1,00`), `NumberText.answer(_ v: Double) -> String` (≤10 decimals, no grouping, no trailing zeros, never `-0`), `NumberText.significant(_ v: Double, digits: Int = 6) -> String`; `Calculator.evaluate(_ input: String) -> Double?`.

- [ ] **Step 1: Write the failing tests**

`Tests/MenuCraneCoreTests/CalculatorTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class CalculatorTests: XCTestCase {
    func e(_ s: String) -> Double? { Calculator.evaluate(s) }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(e("2+2"), 4)
        XCTAssertEqual(e("2 + 3 * 4"), 14)
        XCTAssertEqual(e("(2+3)*4"), 20)
        XCTAssertEqual(e("10/4"), 2.5)
        XCTAssertEqual(e("10 - 2 - 3"), 5)
        XCTAssertEqual(e("-5+2"), -3)
        XCTAssertEqual(e("3 x 4"), 12)
        XCTAssertEqual(e("3X4"), 12)
        XCTAssertEqual(e("2*-3"), -6)
    }

    func testNumberShapes() {
        XCTAssertEqual(e(".5*2"), 1)
        XCTAssertEqual(e("3.*2"), 6)
        XCTAssertEqual(e("1,000 * 2"), 2000)
        XCTAssertEqual(e("1,234.5 + 0.5"), 1235)
        XCTAssertNil(e("1,00*2"))
    }

    func testIncompleteInputGivesNothing() {
        XCTAssertNil(e("5+"))
        XCTAssertNil(e("2(3)"))
        XCTAssertNil(e("(2+3"))
        XCTAssertNil(e("*2"))
    }

    func testNotMathGivesNothing() {
        XCTAssertNil(e("42"))            // a lone number is not a calculation
        XCTAssertNil(e("-42"))
        XCTAssertNil(e("xcode"))
        XCTAssertNil(e("safari"))
        XCTAssertNil(e(""))
        XCTAssertNil(e("2 × 3"))         // only + - * / x are operators
    }

    func testDivisionByZeroAndOverflowGiveNothing() {
        XCTAssertNil(e("5/0"))
        XCTAssertNil(e("5/(2-2)"))
        let big = String(repeating: "9", count: 200)
        XCTAssertNil(e("\(big)*\(big)"))
    }

    func testFormatting() {
        XCTAssertEqual(NumberText.answer(0.1 + 0.2), "0.3")
        XCTAssertEqual(NumberText.answer(2.5), "2.5")
        XCTAssertEqual(NumberText.answer(-0.0), "0")
        XCTAssertEqual(NumberText.answer(1234567), "1234567")
        XCTAssertEqual(NumberText.significant(22.2222222), "22.2222")
        XCTAssertEqual(NumberText.significant(0.453592374), "0.453592")
        XCTAssertEqual(NumberText.significant(-40), "-40")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CalculatorTests`
Expected: compile error — `cannot find 'Calculator' in scope`.

- [ ] **Step 3: Implement NumberText**

`Sources/MenuCraneCore/NumberText.swift`:
```swift
import Foundation

public enum NumberText {
    private static let shape = try! NSRegularExpression(pattern: #"^(\d{1,3}(,\d{3})+|\d*)(\.\d*)?$"#)

    /// "12", ".5", "3.", "1,000.25" → value. Commas only as thousands separators.
    public static func value(of text: String) -> Double? {
        guard !text.isEmpty, text != ".",
              shape.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: ""))
    }

    /// Calculator answers: exact to 10 decimal places, no grouping, no trailing zeros.
    public static func answer(_ v: Double) -> String {
        format(v) { $0.maximumFractionDigits = 10 }
    }

    /// Conversion results: at most `digits` significant figures.
    public static func significant(_ v: Double, digits: Int = 6) -> String {
        format(v) { $0.usesSignificantDigits = true; $0.maximumSignificantDigits = digits }
    }

    private static func format(_ v: Double, _ configure: (NumberFormatter) -> Void) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        configure(f)
        let s = f.string(from: NSNumber(value: v)) ?? String(v)
        return s == "-0" ? "0" : s
    }
}
```

- [ ] **Step 4: Implement Calculator**

`Sources/MenuCraneCore/Calculator.swift`:
```swift
import Foundation

public enum Calculator {
    /// The value of `input` when it is arithmetic with at least one binary operator; otherwise nil.
    /// Operators: + - * / and x (multiply). Parentheses, decimals, leading minus.
    public static func evaluate(_ input: String) -> Double? {
        guard let tokens = tokenize(input) else { return nil }
        var p = Parser(tokens: tokens)
        guard p.hasBinaryOperator, let v = p.parseExpression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    enum Token: Equatable { case number(Double), op(Character), lparen, rparen }

    static func tokenize(_ s: String) -> [Token]? {
        var out: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace { i = s.index(after: i); continue }
            if (c.isASCII && c.isNumber) || c == "." {
                var j = i
                while j < s.endIndex, (s[j].isASCII && s[j].isNumber) || s[j] == "." || s[j] == "," {
                    j = s.index(after: j)
                }
                guard let v = NumberText.value(of: String(s[i..<j])) else { return nil }
                out.append(.number(v)); i = j; continue
            }
            switch c {
            case "+", "-", "*", "/": out.append(.op(c))
            case "x", "X": out.append(.op("*"))
            case "(": out.append(.lparen)
            case ")": out.append(.rparen)
            default: return nil
            }
            i = s.index(after: i)
        }
        return out
    }

    struct Parser {
        let tokens: [Token]
        var pos = 0

        var atEnd: Bool { pos == tokens.count }

        /// An operator that follows a number or ")" — so "-42" alone is not a calculation.
        var hasBinaryOperator: Bool {
            tokens.indices.dropFirst().contains { i in
                guard case .op = tokens[i] else { return false }
                switch tokens[i - 1] { case .number, .rparen: return true; default: return false }
            }
        }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peekOp("+-") {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = op == "+" ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while let op = peekOp("*/") {
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    lhs /= rhs
                } else {
                    lhs *= rhs
                }
            }
            return lhs
        }

        mutating func parseFactor() -> Double? {
            guard pos < tokens.count else { return nil }
            switch tokens[pos] {
            case .op("-"): pos += 1; return parseFactor().map { -$0 }
            case .op("+"): pos += 1; return parseFactor()
            case .number(let v): pos += 1; return v
            case .lparen:
                pos += 1
                guard let v = parseExpression(), pos < tokens.count, tokens[pos] == .rparen else { return nil }
                pos += 1
                return v
            default: return nil
            }
        }

        func peekOp(_ set: String) -> Character? {
            guard pos < tokens.count, case .op(let c) = tokens[pos], set.contains(c) else { return nil }
            return c
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CalculatorTests`
Expected: all 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuCraneCore/NumberText.swift Sources/MenuCraneCore/Calculator.swift Tests/MenuCraneCoreTests/CalculatorTests.swift
git commit -m "feat: calculator with + - * / x, parentheses and number formatting"
```

---

### Task 3: Unit catalog and Converter

**Files:**
- Create: `Sources/MenuCraneCore/UnitCatalog.swift`, `Sources/MenuCraneCore/Converter.swift`
- Test: `Tests/MenuCraneCoreTests/ConverterTests.swift`

**Interfaces:**
- Consumes: `NumberText.value(of:)`, `NumberText.significant(_:)`, `Query.fold(_:)`.
- Produces: `enum UnitSystem: String { case usImperial, metric }` with `.title`; `struct Conversion { input: Double; from: String; to: String; result: Double; bare: String; withUnit: String; inputText: String }`; `struct Converter { init(system: UnitSystem); func convert(_ input: String) -> Conversion? }`.

- [ ] **Step 1: Write the failing tests**

`Tests/MenuCraneCoreTests/ConverterTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class ConverterTests: XCTestCase {
    let us = Converter(system: .usImperial)
    let metric = Converter(system: .metric)

    func assertConverts(_ input: String, _ bare: String, _ to: String, using c: Converter? = nil,
                        file: StaticString = #filePath, line: UInt = #line) {
        let r = (c ?? us).convert(input)
        XCTAssertEqual(r?.bare, bare, input, file: file, line: line)
        XCTAssertEqual(r?.to, to, input, file: file, line: line)
    }

    func testExplicitTargets() {
        assertConverts("72f to c", "22.2222", "°C")
        assertConverts("1 lb to kg", "0.453592", "kg")
        assertConverts("12 fl oz in pt", "0.75", "pt")
        assertConverts("2 pt to fl oz", "32", "fl oz")
        assertConverts("1 cup to ml", "236.588", "mL")
        assertConverts("5 in in cm", "12.7", "cm")
        assertConverts("1,000 ft to m", "304.8", "m")
        assertConverts("30 fps to m/s", "9.144", "m/s")
        assertConverts("32 ft/s2 to m/s²", "9.7536", "m/s²")
        assertConverts("9.80665 m/s^2 to g-force", "1", "g-force")
        assertConverts("60 mph as km/h", "96.5606", "km/h")
    }

    func testLooseTyping() {
        assertConverts("-40f to c", "-40", "°C")
        assertConverts("72F", "22.2222", "°C")
        assertConverts("5 KG TO LB", "11.0231", "lb")
        assertConverts("12 fl. oz in pt", "0.75", "pt")
        assertConverts("  72 °F  ", "22.2222", "°C")
        assertConverts("100 degrees f to c", "37.7778", "°C")
    }

    func testBareValuesFollowTheUnitSystem() {
        assertConverts("100 km/h", "62.1371", "mph")               // metric → US in US Imperial
        XCTAssertNil(metric.convert("100 km/h"))                    // metric stays put in Metric
        assertConverts("100 mph", "160.934", "km/h", using: metric) // US → metric in Metric
        assertConverts("72f", "22.2222", "°C", using: metric)
        assertConverts("10 knots", "11.5078", "mph")                // neutral → US in US Imperial
        assertConverts("10 knots", "18.52", "km/h", using: metric)  // neutral → metric in Metric
        assertConverts("5 in", "12.7", "cm")
    }

    func testExplicitTargetWinsOverSystem() {
        assertConverts("100 km/h to m/s", "27.7778", "m/s", using: metric)
    }

    func testNothingForNonsense() {
        XCTAssertNil(us.convert("5 kg to mph"))     // mismatched dimensions
        XCTAssertNil(us.convert("5 bananas"))
        XCTAssertNil(us.convert("5"))
        XCTAssertNil(us.convert("to c"))
        XCTAssertNil(us.convert("5 kg to kg"))
        XCTAssertNil(us.convert("safari"))
        XCTAssertNil(us.convert("5 kg to parsecs"))
    }

    func testDisplayStrings() {
        let r = us.convert("72f to c")!
        XCTAssertEqual(r.withUnit, "22.2222 °C")
        XCTAssertEqual(r.inputText, "72 °F")
        XCTAssertEqual(UnitSystem.usImperial.title, "US Imperial")
        XCTAssertEqual(UnitSystem.metric.title, "Metric")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConverterTests`
Expected: compile error — `cannot find 'Converter' in scope`.

- [ ] **Step 3: Implement the unit catalog**

`Sources/MenuCraneCore/UnitCatalog.swift`:
```swift
import Foundation

public enum UnitSystem: String, CaseIterable, Sendable {
    case usImperial, metric
    public var title: String { self == .usImperial ? "US Imperial" : "Metric" }
}

enum UnitFamily: Sendable { case us, metric, neutral }

struct UnitDef {
    let symbol: String
    let unit: Dimension
    let family: UnitFamily
    let aliases: [String]        // already normalized (see UnitCatalog.normalize)
    let usPartner: String?       // symbol suggested for a bare value
    let metricPartner: String?
}

enum UnitCatalog {
    /// Lowercase, fold, drop spaces and periods, "²"/"^2" → "2".
    static func normalize(_ s: String) -> String {
        Query.fold(s)
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "^", with: "")
            .filter { !$0.isWhitespace && $0 != "." }
    }

    // US customary cup (236.588 mL); Foundation's .cups is the 240 mL metric cup.
    static let usCup = UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.2365882365))
    static let feetPerSecond = UnitSpeed(symbol: "ft/s", converter: UnitConverterLinear(coefficient: 0.3048))
    static let feetPerSecondSquared = UnitAcceleration(symbol: "ft/s²", converter: UnitConverterLinear(coefficient: 0.3048))

    static let all: [UnitDef] = [
        // Temperature
        UnitDef(symbol: "°F", unit: UnitTemperature.fahrenheit, family: .us,
                aliases: ["f", "°f", "fahrenheit", "degf", "degreesf", "degreesfahrenheit"], usPartner: nil, metricPartner: "°C"),
        UnitDef(symbol: "°C", unit: UnitTemperature.celsius, family: .metric,
                aliases: ["c", "°c", "celsius", "centigrade", "degc", "degreesc", "degreescelsius"], usPartner: "°F", metricPartner: nil),
        UnitDef(symbol: "K", unit: UnitTemperature.kelvin, family: .neutral,
                aliases: ["k", "kelvin", "kelvins"], usPartner: "°F", metricPartner: "°C"),
        // Mass
        UnitDef(symbol: "lb", unit: UnitMass.pounds, family: .us,
                aliases: ["lb", "lbs", "pound", "pounds"], usPartner: nil, metricPartner: "kg"),
        UnitDef(symbol: "oz", unit: UnitMass.ounces, family: .us,
                aliases: ["oz", "ounce", "ounces"], usPartner: nil, metricPartner: "g"),
        UnitDef(symbol: "st", unit: UnitMass.stones, family: .us,
                aliases: ["st", "stone", "stones"], usPartner: nil, metricPartner: "kg"),
        UnitDef(symbol: "kg", unit: UnitMass.kilograms, family: .metric,
                aliases: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"], usPartner: "lb", metricPartner: nil),
        UnitDef(symbol: "g", unit: UnitMass.grams, family: .metric,
                aliases: ["g", "gram", "grams"], usPartner: "oz", metricPartner: nil),
        // Volume
        UnitDef(symbol: "fl oz", unit: UnitVolume.fluidOunces, family: .us,
                aliases: ["floz", "fluidounce", "fluidounces"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "cup", unit: usCup, family: .us,
                aliases: ["cup", "cups"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "pt", unit: UnitVolume.pints, family: .us,
                aliases: ["pt", "pint", "pints"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "qt", unit: UnitVolume.quarts, family: .us,
                aliases: ["qt", "quart", "quarts"], usPartner: nil, metricPartner: "L"),
        UnitDef(symbol: "gal", unit: UnitVolume.gallons, family: .us,
                aliases: ["gal", "gals", "gallon", "gallons"], usPartner: nil, metricPartner: "L"),
        UnitDef(symbol: "tsp", unit: UnitVolume.teaspoons, family: .us,
                aliases: ["tsp", "teaspoon", "teaspoons"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "tbsp", unit: UnitVolume.tablespoons, family: .us,
                aliases: ["tbsp", "tbs", "tablespoon", "tablespoons"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "mL", unit: UnitVolume.milliliters, family: .metric,
                aliases: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"], usPartner: "fl oz", metricPartner: nil),
        UnitDef(symbol: "L", unit: UnitVolume.liters, family: .metric,
                aliases: ["l", "liter", "liters", "litre", "litres"], usPartner: "qt", metricPartner: nil),
        // Length
        UnitDef(symbol: "in", unit: UnitLength.inches, family: .us,
                aliases: ["in", "inch", "inches"], usPartner: nil, metricPartner: "cm"),
        UnitDef(symbol: "ft", unit: UnitLength.feet, family: .us,
                aliases: ["ft", "foot", "feet"], usPartner: nil, metricPartner: "m"),
        UnitDef(symbol: "yd", unit: UnitLength.yards, family: .us,
                aliases: ["yd", "yds", "yard", "yards"], usPartner: nil, metricPartner: "m"),
        UnitDef(symbol: "mi", unit: UnitLength.miles, family: .us,
                aliases: ["mi", "mile", "miles"], usPartner: nil, metricPartner: "km"),
        UnitDef(symbol: "mm", unit: UnitLength.millimeters, family: .metric,
                aliases: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"], usPartner: "in", metricPartner: nil),
        UnitDef(symbol: "cm", unit: UnitLength.centimeters, family: .metric,
                aliases: ["cm", "centimeter", "centimeters", "centimetre", "centimetres"], usPartner: "in", metricPartner: nil),
        UnitDef(symbol: "m", unit: UnitLength.meters, family: .metric,
                aliases: ["m", "meter", "meters", "metre", "metres"], usPartner: "ft", metricPartner: nil),
        UnitDef(symbol: "km", unit: UnitLength.kilometers, family: .metric,
                aliases: ["km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"], usPartner: "mi", metricPartner: nil),
        // Speed
        UnitDef(symbol: "mph", unit: UnitSpeed.milesPerHour, family: .us,
                aliases: ["mph", "mi/h", "milesperhour"], usPartner: nil, metricPartner: "km/h"),
        UnitDef(symbol: "ft/s", unit: feetPerSecond, family: .us,
                aliases: ["ft/s", "fps", "feetpersecond", "footpersecond"], usPartner: nil, metricPartner: "m/s"),
        UnitDef(symbol: "km/h", unit: UnitSpeed.kilometersPerHour, family: .metric,
                aliases: ["km/h", "kmh", "kph", "kmph", "kilometersperhour", "kilometresperhour"], usPartner: "mph", metricPartner: nil),
        UnitDef(symbol: "m/s", unit: UnitSpeed.metersPerSecond, family: .metric,
                aliases: ["m/s", "mps", "meterspersecond", "metrespersecond"], usPartner: "mph", metricPartner: nil),
        UnitDef(symbol: "kn", unit: UnitSpeed.knots, family: .neutral,
                aliases: ["kn", "kt", "kts", "knot", "knots"], usPartner: "mph", metricPartner: "km/h"),
        // Acceleration
        UnitDef(symbol: "m/s²", unit: UnitAcceleration.metersPerSecondSquared, family: .metric,
                aliases: ["m/s2", "mps2", "meterspersecondsquared", "metrespersecondsquared"], usPartner: "ft/s²", metricPartner: nil),
        UnitDef(symbol: "ft/s²", unit: feetPerSecondSquared, family: .us,
                aliases: ["ft/s2", "fps2", "feetpersecondsquared"], usPartner: nil, metricPartner: "m/s²"),
        UnitDef(symbol: "g-force", unit: UnitAcceleration.gravity, family: .neutral,
                aliases: ["g-force", "gforce", "gs", "gee", "gees", "standardgravity"], usPartner: "ft/s²", metricPartner: "m/s²"),
    ]

    static let byAlias: [String: UnitDef] = {
        var map: [String: UnitDef] = [:]
        for def in all { for a in def.aliases { map[a] = def } }
        return map
    }()

    static let bySymbol: [String: UnitDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.symbol, $0) })

    static func lookup(_ text: String) -> UnitDef? {
        let n = normalize(text)
        return byAlias[n] ?? bySymbol.values.first { normalize($0.symbol) == n }
    }
}
```

- [ ] **Step 4: Implement the Converter**

`Sources/MenuCraneCore/Converter.swift`:
```swift
import Foundation

public struct Conversion: Equatable, Sendable {
    public let input: Double
    public let from: String
    public let to: String
    public let result: Double

    public var bare: String { NumberText.significant(result) }
    public var withUnit: String { "\(bare) \(to)" }
    public var inputText: String { "\(NumberText.significant(input)) \(from)" }
}

public struct Converter: Sendable {
    public let system: UnitSystem
    public init(system: UnitSystem) { self.system = system }

    private static let leadingNumber = try! NSRegularExpression(pattern: #"^([+-]?[\d.,]+)\s*(.+)$"#)
    private static let withTarget = try! NSRegularExpression(
        pattern: #"^(.+?)\s+(?:to|in|into|as|->|→)\s+(.+)$"#)

    public func convert(_ input: String) -> Conversion? {
        let s = Query.fold(input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = Self.leadingNumber.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numRange = Range(m.range(at: 1), in: s), let restRange = Range(m.range(at: 2), in: s)
        else { return nil }
        var numText = String(s[numRange])
        let negative = numText.hasPrefix("-")
        if numText.hasPrefix("-") || numText.hasPrefix("+") { numText.removeFirst() }
        guard var value = NumberText.value(of: numText) else { return nil }
        if negative { value = -value }

        let rest = String(s[restRange])
        let fromDef: UnitDef, toDef: UnitDef
        if let t = Self.withTarget.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
           let a = Range(t.range(at: 1), in: rest), let b = Range(t.range(at: 2), in: rest),
           let f = UnitCatalog.lookup(String(rest[a])) {
            guard let target = UnitCatalog.lookup(String(rest[b])) else { return nil }
            fromDef = f; toDef = target
        } else {
            guard let f = UnitCatalog.lookup(rest), let p = partner(for: f) else { return nil }
            fromDef = f; toDef = p
        }
        guard fromDef.symbol != toDef.symbol,
              type(of: fromDef.unit) == type(of: toDef.unit) else { return nil }
        let base = fromDef.unit.converter.baseUnitValue(fromValue: value)
        let result = toDef.unit.converter.value(fromBaseUnitValue: base)
        guard result.isFinite else { return nil }
        return Conversion(input: value, from: fromDef.symbol, to: toDef.symbol, result: result)
    }

    /// Where a bare value goes: US units convert to metric; metric units to US in US Imperial
    /// and nowhere in Metric; neutral units (K, knots, g-force) to the chosen system.
    func partner(for d: UnitDef) -> UnitDef? {
        let symbol: String?
        switch (d.family, system) {
        case (.us, _): symbol = d.metricPartner
        case (.metric, .usImperial): symbol = d.usPartner
        case (.metric, .metric): symbol = nil
        case (.neutral, .usImperial): symbol = d.usPartner
        case (.neutral, .metric): symbol = d.metricPartner
        }
        return symbol.flatMap { UnitCatalog.bySymbol[$0] }
    }
}
```

Note: the `withTarget` branch only applies when its left side is itself a known unit, so `5 in` (bare inches) still works while `5 in in cm` and `12 fl oz in pt` split correctly.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ConverterTests`
Expected: all 6 tests PASS. If a numeric expectation differs only in the 6th significant figure, recompute it by hand (e.g. `100 km/h ÷ 1.609344`) and fix the expectation, not the rounding.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuCraneCore/UnitCatalog.swift Sources/MenuCraneCore/Converter.swift Tests/MenuCraneCoreTests/ConverterTests.swift
git commit -m "feat: unit converter with US Imperial / Metric bare-value suggestions"
```

---

### Task 4: Emoji data script and generated emoji.json

**Files:**
- Create: `scripts/update-emoji-data.sh`, `Resources/bundle/emoji.json` (generated)

**Interfaces:**
- Produces: `Resources/bundle/emoji.json` — JSON array of `{"c": char, "n": name, "k": [keywords], "g": group, "t": [5 tone variants light→dark]?}` in Unicode order, fully-qualified only, no `Component` group. Keys match `Emoji.CodingKeys` in Task 5.

- [ ] **Step 1: Write the script**

`scripts/update-emoji-data.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nicholas Smith
# Regenerate Resources/bundle/emoji.json from Unicode's emoji-test.txt and CLDR's
# English annotations. Re-run (bumping the pins) when Unicode ships a new version.
set -euo pipefail
cd "$(dirname "$0")/.."
EMOJI_VERSION="${EMOJI_VERSION:-16.0}"
CLDR_TAG="${CLDR_TAG:-release-46}"
python3 - "$EMOJI_VERSION" "$CLDR_TAG" <<'PY'
import json, re, sys, urllib.request, xml.etree.ElementTree as ET
emoji_version, cldr = sys.argv[1], sys.argv[2]
TEST = f"https://unicode.org/Public/emoji/{emoji_version}/emoji-test.txt"
CLDR = f"https://raw.githubusercontent.com/unicode-org/cldr/{cldr}/common"
TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]

def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()

names, keywords = {}, {}
for path in ("annotations/en.xml", "annotationsDerived/en.xml"):
    for a in ET.fromstring(fetch(f"{CLDR}/{path}")).iter("annotation"):
        cp = a.get("cp").replace("️", "")
        text = (a.text or "").strip()
        if a.get("type") == "tts":
            names[cp] = text
        else:
            keywords[cp] = [k.strip() for k in text.split("|") if k.strip()]

line_re = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E[\d.]+\s+(.+)$")
emoji, index, group = [], {}, None
for line in fetch(TEST).decode("utf-8").splitlines():
    if line.startswith("# group:"):
        group = line.split(":", 1)[1].strip()
        continue
    m = line_re.match(line)
    if not m or group == "Component":
        continue
    cps = [int(x, 16) for x in m.group(1).split()]
    char = "".join(map(chr, cps))
    tones = [c for c in cps if c in TONES]
    if tones:
        base = "".join(chr(c) for c in cps if c not in TONES)
        i = index.get(base, index.get(base.replace("️", "")))
        if i is not None and len(set(tones)) == 1:
            emoji[i].setdefault("t", [None] * 5)[TONES.index(tones[0])] = char
        continue
    key = char.replace("️", "")
    index[char] = index[key] = len(emoji)
    emoji.append({"c": char, "n": names.get(key, m.group(2)), "k": keywords.get(key, []), "g": group})

for e in emoji:
    if "t" in e and None in e["t"]:
        del e["t"]

with open("Resources/bundle/emoji.json", "w", encoding="utf-8") as f:
    json.dump(emoji, f, ensure_ascii=False, separators=(",", ":"))
print(f"wrote {len(emoji)} emoji ({sum('t' in e for e in emoji)} with skin tones)")
PY
```

- [ ] **Step 2: Run it**

Run: `chmod +x scripts/update-emoji-data.sh && mkdir -p Resources/bundle && scripts/update-emoji-data.sh`
Expected: `wrote 1900+ emoji (300+ with skin tones)` (exact counts depend on the pinned version).

- [ ] **Step 3: Spot-check the output**

Run:
```bash
python3 -c "
import json; d=json.load(open('Resources/bundle/emoji.json'))
by={e['c']:e for e in d}
print(by['🤞']); print(by['👍'].get('t')); print(any(e['g']=='Component' for e in d))"
```
Expected: 🤞's entry has name `crossed fingers` and keywords including `luck`; 👍 has five tone variants; `False`.

- [ ] **Step 4: Commit**

```bash
git add scripts/update-emoji-data.sh Resources/bundle/emoji.json
git commit -m "feat: emoji data generated from Unicode 16.0 and CLDR 46"
```

---

### Task 5: Emoji model and EmojiStore

**Files:**
- Create: `Sources/MenuCraneCore/Emoji.swift`, `Sources/MenuCraneCore/EmojiStore.swift`, `Tests/MenuCraneCoreTests/Fixtures.swift`
- Test: `Tests/MenuCraneCoreTests/EmojiStoreTests.swift`

**Interfaces:**
- Consumes: `Query`, `MatchTarget`, `Matcher.score`, `Resources/bundle/emoji.json`.
- Produces: `enum SkinTone: Int { none, light, mediumLight, medium, mediumDark, dark }` with `.title`, `.swatch`, `.next`; `struct Emoji { char, name, keywords, group, tones: [String]?; func glyph(_ tone: SkinTone) -> String }`; `struct EmojiHit { emoji, score; id }`; `final class EmojiStore { init(data: Data) throws; let all: [Emoji]; let groups: [String]; func emoji(for char: String) -> Emoji?; func search(_ q: Query, aliases: [String: [String]], recents: [String]) -> [EmojiHit] }`. Aliases and recents are keyed by **base** emoji (`Emoji.char`). Test helper `Fixtures.emojiStore()`.

- [ ] **Step 1: Write the fixtures helper and failing tests**

`Tests/MenuCraneCoreTests/Fixtures.swift`:
```swift
import Foundation
@testable import MenuCraneCore

enum Fixtures {
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static var emojiJSON: URL { packageRoot.appending(path: "Resources/bundle/emoji.json") }
    static func emojiStore() throws -> EmojiStore { try EmojiStore(data: Data(contentsOf: emojiJSON)) }

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "menucrane-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

`Tests/MenuCraneCoreTests/EmojiStoreTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class EmojiStoreTests: XCTestCase {
    var store: EmojiStore!
    override func setUpWithError() throws { store = try Fixtures.emojiStore() }

    func top(_ q: String, aliases: [String: [String]] = [:], recents: [String] = []) -> [String] {
        store.search(Query(q), aliases: aliases, recents: recents).map(\.emoji.char)
    }

    func testDataLoaded() {
        XCTAssertGreaterThan(store.all.count, 1800)
        XCTAssertFalse(store.groups.contains("Component"))
        XCTAssertEqual(store.groups.first, "Smileys & Emotion")
    }

    func testCrossedFingersAnyWordOrder() {
        XCTAssertEqual(top("fingers crossed").first, "🤞")
        XCTAssertEqual(top("crossed fingers").first, "🤞")
        XCTAssertEqual(top("cross fing").first, "🤞")
        XCTAssertTrue(top("luck").prefix(10).contains("🤞"))
    }

    func testUserAliasOutranksBuiltInNames() {
        XCTAssertEqual(top("nerd", aliases: ["👓": ["nerd"]]).first, "👓")
    }

    func testEmptyQueryShowsRecentsThenEverything() {
        let r = top("", recents: ["🎉", "👍"])
        XCTAssertEqual(Array(r.prefix(2)), ["🎉", "👍"])
        XCTAssertEqual(r.count, store.all.count)
        XCTAssertEqual(r.filter { $0 == "🎉" }.count, 1)
    }

    func testRecentsBreakTies() {
        let plain = top("heart")
        let second = plain[1]
        XCTAssertEqual(top("heart", recents: [second]).first, second)
    }

    func testToneGlyphIsExactScalarSequence() throws {
        let thumbs = try XCTUnwrap(store.emoji(for: "👍"))
        XCTAssertEqual(thumbs.glyph(.medium).unicodeScalars.map(\.value), [0x1F44D, 0x1F3FD])
        XCTAssertEqual(thumbs.glyph(.none), "👍")
        let couple = try XCTUnwrap(store.emoji(for: "🧑‍🤝‍🧑"))
        XCTAssertEqual(couple.glyph(.dark), "🧑🏿‍🤝‍🧑🏿")
        let rocket = try XCTUnwrap(store.emoji(for: "🚀"))
        XCTAssertEqual(rocket.glyph(.dark), "🚀")   // no tones: unchanged
    }

    func testAliasesAndRecentsUseBaseEmoji() {
        // Aliases/recents are stored against the base emoji, so they find it whatever tone is chosen.
        let hits = store.search(Query("yes"), aliases: ["👍": ["yes"]], recents: ["👍"])
        XCTAssertEqual(hits.first?.emoji.char, "👍")
        XCTAssertEqual(hits.first?.emoji.glyph(.dark), "👍🏿")
    }

    func testSkinToneCycle() {
        XCTAssertEqual(SkinTone.none.next, .light)
        XCTAssertEqual(SkinTone.dark.next, SkinTone.none)
        XCTAssertEqual(SkinTone.medium.swatch, "✋🏽")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EmojiStoreTests`
Expected: compile error — `cannot find 'EmojiStore' in scope`.

- [ ] **Step 3: Implement the model**

`Sources/MenuCraneCore/Emoji.swift`:
```swift
import Foundation

public enum SkinTone: Int, CaseIterable, Codable, Sendable {
    case none = 0, light, mediumLight, medium, mediumDark, dark

    public var title: String {
        ["Default", "Light", "Medium-Light", "Medium", "Medium-Dark", "Dark"][rawValue]
    }
    public var swatch: String { ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][rawValue] }
    public var next: SkinTone { SkinTone(rawValue: (rawValue + 1) % SkinTone.allCases.count)! }
}

public struct Emoji: Codable, Equatable, Sendable {
    public let char: String
    public let name: String
    public let keywords: [String]
    public let group: String
    /// Light → dark variants, for emoji that take a skin tone.
    public let tones: [String]?

    enum CodingKeys: String, CodingKey {
        case char = "c", name = "n", keywords = "k", group = "g", tones = "t"
    }

    public func glyph(_ tone: SkinTone) -> String {
        guard tone != .none, let tones, tones.count == 5 else { return char }
        return tones[tone.rawValue - 1]
    }
}

public struct EmojiHit: Equatable, Identifiable, Sendable {
    public let emoji: Emoji
    public let score: Double
    public var id: String { emoji.char }
}
```

- [ ] **Step 4: Implement the store**

`Sources/MenuCraneCore/EmojiStore.swift`:
```swift
import Foundation

public final class EmojiStore {
    static let aliasBonus = 2.0
    static let recentBonus = 0.5

    public let all: [Emoji]
    public let groups: [String]
    private let targets: [MatchTarget]
    private let indexByChar: [String: Int]

    public init(data: Data) throws {
        all = try JSONDecoder().decode([Emoji].self, from: data)
        targets = all.map { MatchTarget([$0.name] + $0.keywords) }
        indexByChar = Dictionary(all.enumerated().map { ($1.char, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        groups = all.map(\.group).filter { seen.insert($0).inserted }
    }

    public func emoji(for char: String) -> Emoji? { indexByChar[char].map { all[$0] } }

    /// Ranked emoji for `query`, matching name, CLDR keywords and the user's aliases in any
    /// word order. An empty query lists recents first, then every emoji in Unicode order.
    public func search(_ query: Query, aliases: [String: [String]], recents: [String]) -> [EmojiHit] {
        let recentRank = Dictionary(recents.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        if query.isEmpty {
            let recent = recents.compactMap(emoji(for:)).map { EmojiHit(emoji: $0, score: 0) }
            let rest = all.filter { recentRank[$0.char] == nil }.map { EmojiHit(emoji: $0, score: 0) }
            return recent + rest
        }
        var hits: [(hit: EmojiHit, order: Int)] = []
        for (i, e) in all.enumerated() {
            var s = Matcher.score(query, targets[i])
            if let names = aliases[e.char], !names.isEmpty, let a = Matcher.score(query, MatchTarget(names)) {
                s = max(s ?? 0, a + Self.aliasBonus)
            }
            guard var score = s else { continue }
            if let r = recentRank[e.char] {
                score += Self.recentBonus * (1 - Double(r) / Double(max(recents.count, 1)))
            }
            hits.append((EmojiHit(emoji: e, score: score), i))
        }
        return hits.sorted { $0.hit.score != $1.hit.score ? $0.hit.score > $1.hit.score : $0.order < $1.order }
            .map(\.hit)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter EmojiStoreTests`
Expected: all 8 tests PASS. If `testRecentsBreakTies` fails because `plain[0]` and `plain[1]` differ in score by more than 0.5, choose a query whose top two tie (e.g. `"cat"`) — the point is that recency breaks a tie, not that it overrides a better match.

- [ ] **Step 6: Commit**

```bash
git add Sources/MenuCraneCore/Emoji.swift Sources/MenuCraneCore/EmojiStore.swift Tests/MenuCraneCoreTests/Fixtures.swift Tests/MenuCraneCoreTests/EmojiStoreTests.swift
git commit -m "feat: emoji store with any-order search, aliases, recents and skin tones"
```

---

### Task 6: AliasStore, UsageStore and file helpers

**Files:**
- Create: `Sources/MenuCraneCore/Log.swift`, `Sources/MenuCraneCore/AtomicFile.swift`, `Sources/MenuCraneCore/AliasStore.swift`, `Sources/MenuCraneCore/UsageStore.swift`
- Test: `Tests/MenuCraneCoreTests/StoresTests.swift`

**Interfaces:**
- Consumes: `Fixtures.tempDir()`.
- Produces: `coreLog: Logger`; `AtomicFile.write(_ data: Data, to url: URL) throws`; `DirectoryWatcher(directory: URL, onChange: @escaping () -> Void)` (failable); `AliasStore(url:)` with `aliases: [String: [String]]`, `loadError: String?`, `onChange: (() -> Void)?`, `reload()`, `setAliases(_ names: [String], for emoji: String) throws`, `startWatching()`; `AliasStoreError.fileUnreadable`; `UsageStore(url:now:)` with `recordLaunch(_ key: String)`, `boost(for key: String) -> Double`, `recordEmoji(_ base: String)`, `recentEmoji: [String]`, `UsageStore.maxRecentEmoji` (24); `AppSupport.directory: URL` (`~/Library/Application Support/MenuCrane`).

- [ ] **Step 1: Write the failing tests**

`Tests/MenuCraneCoreTests/StoresTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StoresTests`
Expected: compile error — `cannot find 'AliasStore' in scope`.

- [ ] **Step 3: Implement the helpers**

`Sources/MenuCraneCore/Log.swift`:
```swift
import os

let coreLog = Logger(subsystem: "com.nicholaspsmith.MenuCrane", category: "core")
```

`Sources/MenuCraneCore/AtomicFile.swift`:
```swift
import Foundation

public enum AppSupport {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MenuCrane")
    }
}

public enum AtomicFile {
    /// Write to a temporary file and rename over `url`, so a crash can't leave half a file.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Calls `onChange` (debounced 0.2 s, on main) when entries in `directory` are added, renamed or
/// removed — which is what an atomic save of a file inside it looks like.
public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init?(directory: URL, onChange: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
```

- [ ] **Step 4: Implement AliasStore**

`Sources/MenuCraneCore/AliasStore.swift`:
```swift
import Foundation

public enum AliasStoreError: Error { case fileUnreadable }

/// The user's emoji aliases, `{ "👓": ["nerd"] }`, keyed by base emoji. Hand-editable JSON.
public final class AliasStore {
    public let url: URL
    public private(set) var aliases: [String: [String]] = [:]
    /// Why the file on disk is not in use; the last good copy stays loaded meanwhile.
    public private(set) var loadError: String?
    public var onChange: (() -> Void)?
    private var watcher: DirectoryWatcher?

    public init(url: URL) {
        self.url = url
        reload()
    }

    public func reload() {
        defer { onChange?() }
        guard FileManager.default.fileExists(atPath: url.path) else {
            aliases = [:]; loadError = nil; return
        }
        do {
            let decoded = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
            aliases = decoded.mapValues(Self.clean).filter { !$0.value.isEmpty }
            loadError = nil
        } catch {
            loadError = "aliases.json could not be read (\(error.localizedDescription)). Using the last good copy; fix or delete the file to edit aliases."
            coreLog.error("aliases.json unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Replace `emoji`'s aliases (empty removes them). Refuses while the file on disk is unreadable,
    /// so a hand edit with a typo is never overwritten.
    public func setAliases(_ names: [String], for emoji: String) throws {
        guard loadError == nil else { throw AliasStoreError.fileUnreadable }
        var next = aliases
        let cleaned = Self.clean(names)
        next[emoji] = cleaned.isEmpty ? nil : cleaned
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(enc.encode(next), to: url)
        aliases = next
        onChange?()
    }

    public func startWatching() {
        watcher = DirectoryWatcher(directory: url.deletingLastPathComponent()) { [weak self] in self?.reload() }
    }

    static func clean(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
```

- [ ] **Step 5: Implement UsageStore**

`Sources/MenuCraneCore/UsageStore.swift`:
```swift
import Foundation

/// App launch counts for frecency, and recently used emoji (base emoji, newest first).
public final class UsageStore {
    public static let maxRecentEmoji = 24

    struct AppUse: Codable { var count: Int; var last: Date }
    struct Snapshot: Codable { var apps: [String: AppUse] = [:]; var recentEmoji: [String] = [] }

    private let url: URL
    private let now: () -> Date
    private var snap: Snapshot

    public init(url: URL, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        snap = (try? Data(contentsOf: url)).flatMap { try? dec.decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    public var recentEmoji: [String] { snap.recentEmoji }

    public func recordLaunch(_ key: String) {
        var use = snap.apps[key] ?? AppUse(count: 0, last: now())
        use.count += 1
        use.last = now()
        snap.apps[key] = use
        save()
    }

    public func recordEmoji(_ base: String) {
        snap.recentEmoji.removeAll { $0 == base }
        snap.recentEmoji.insert(base, at: 0)
        snap.recentEmoji = Array(snap.recentEmoji.prefix(Self.maxRecentEmoji))
        save()
    }

    /// 0…1.5: grows with log2 of launches, halves roughly every three weeks of disuse.
    public func boost(for key: String) -> Double {
        guard let use = snap.apps[key] else { return 0 }
        let days = max(0, now().timeIntervalSince(use.last) / 86_400)
        return min(1.5, log2(1 + Double(use.count)) * 0.3) * exp(-days / 30)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try AtomicFile.write(enc.encode(snap), to: url) }
        catch { coreLog.error("usage.json not saved: \(error.localizedDescription, privacy: .public)") }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter StoresTests`
Expected: all 7 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MenuCraneCore/Log.swift Sources/MenuCraneCore/AtomicFile.swift Sources/MenuCraneCore/AliasStore.swift Sources/MenuCraneCore/UsageStore.swift Tests/MenuCraneCoreTests/StoresTests.swift
git commit -m "feat: alias and usage stores with atomic writes"
```

---

### Task 7: AppIndex and FSEvents watcher

**Files:**
- Create: `Sources/MenuCraneCore/AppIndex.swift`, `Sources/MenuCraneCore/FSEventsWatcher.swift`
- Modify: `Tests/MenuCraneCoreTests/Fixtures.swift` (add `makeApp`)
- Test: `Tests/MenuCraneCoreTests/AppIndexTests.swift`

**Interfaces:**
- Consumes: `coreLog`, `Fixtures.tempDir()`.
- Produces: `struct AppEntry { name: String; url: URL; bundleID: String?; key: String }`; `final class AppIndex { init(roots: [URL] = AppIndex.defaultRoots, extras: [URL] = AppIndex.defaultExtras); apps: [AppEntry]; generation: Int; func rebuild(); var skipped: [String] }`; `FSEventsWatcher(paths: [String], latency: TimeInterval = 1, onChange: @escaping () -> Void)` with `start()`, `stop()`. Test helper `Fixtures.makeApp(_:in:bundleID:) -> URL`.

- [ ] **Step 1: Extend fixtures**

Append inside `enum Fixtures` in `Tests/MenuCraneCoreTests/Fixtures.swift`:
```swift
    /// A minimal `.app` directory; `bundleID` nil leaves out Info.plist entirely.
    @discardableResult
    static func makeApp(_ name: String, in dir: URL, bundleID: String?) throws -> URL {
        let app = dir.appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let bundleID {
            let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        }
        return app
    }
```

- [ ] **Step 2: Write the failing tests**

`Tests/MenuCraneCoreTests/AppIndexTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class AppIndexTests: XCTestCase {
    func testScansRootsOneLevelDeepResolvesLinksAndDedupes() throws {
        let fm = FileManager.default
        let a = try Fixtures.tempDir(), b = try Fixtures.tempDir(), elsewhere = try Fixtures.tempDir()
        try Fixtures.makeApp("Real", in: a, bundleID: "com.test.real")
        let utilities = a.appending(path: "Utilities")
        try fm.createDirectory(at: utilities, withIntermediateDirectories: true)
        try Fixtures.makeApp("Tool", in: utilities, bundleID: "com.test.tool")
        let deep = a.appending(path: "Folder/Deeper")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try Fixtures.makeApp("TooDeep", in: deep, bundleID: "com.test.deep")
        try Fixtures.makeApp("NoID", in: a, bundleID: nil)
        // b: a symlink to an app that lives elsewhere (how ~/Applications holds Menubarn apps),
        // a duplicate of Real by bundle id, and a broken link.
        let linked = try Fixtures.makeApp("Linked", in: elsewhere, bundleID: "com.test.linked")
        try fm.createSymbolicLink(at: b.appending(path: "Linked.app"), withDestinationURL: linked)
        try Fixtures.makeApp("Real Copy", in: b, bundleID: "com.test.real")
        try fm.createSymbolicLink(at: b.appending(path: "Gone.app"), withDestinationURL: elsewhere.appending(path: "Missing.app"))

        let index = AppIndex(roots: [a, b], extras: [])
        let names = index.apps.map(\.name)
        XCTAssertEqual(Set(names), ["Real", "Tool", "NoID", "Linked"])
        XCTAssertEqual(index.apps.first { $0.name == "Linked" }?.url.resolvingSymlinksInPath(), linked.resolvingSymlinksInPath())
        XCTAssertNil(index.apps.first { $0.name == "NoID" }?.bundleID)
        XCTAssertTrue(index.skipped.contains { $0.contains("Gone.app") })
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    func testUnreadableRootIsSkipped() {
        let index = AppIndex(roots: [URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")], extras: [])
        XCTAssertEqual(index.apps, [])
    }

    func testRebuildBumpsGenerationAndSeesChanges() throws {
        let dir = try Fixtures.tempDir()
        let index = AppIndex(roots: [dir], extras: [])
        let g = index.generation
        try Fixtures.makeApp("New", in: dir, bundleID: "com.test.new")
        index.rebuild()
        XCTAssertEqual(index.apps.map(\.name), ["New"])
        XCTAssertEqual(index.generation, g + 1)
    }

    func testExtrasAreIncluded() throws {
        let dir = try Fixtures.tempDir()
        let finder = try Fixtures.makeApp("Finder", in: dir, bundleID: "com.apple.finder")
        XCTAssertEqual(AppIndex(roots: [], extras: [finder]).apps.map(\.name), ["Finder"])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter AppIndexTests`
Expected: compile error — `cannot find 'AppIndex' in scope`.

- [ ] **Step 4: Implement AppIndex**

`Sources/MenuCraneCore/AppIndex.swift`:
```swift
import Foundation

public struct AppEntry: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let bundleID: String?
    /// Identity for de-duplication and usage: bundle id, else path.
    public var key: String { bundleID ?? url.path }
}

public final class AppIndex {
    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    }
    public static var defaultExtras: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    }

    public private(set) var apps: [AppEntry] = []
    /// Bumped on every rebuild so providers know to refresh their match targets.
    public private(set) var generation = 0
    /// Paths skipped during the last rebuild, with the reason.
    public private(set) var skipped: [String] = []
    private let roots: [URL]
    private let extras: [URL]

    public init(roots: [URL] = AppIndex.defaultRoots, extras: [URL] = AppIndex.defaultExtras) {
        self.roots = roots
        self.extras = extras
        rebuild()
    }

    public func rebuild() {
        var found: [AppEntry] = []
        var seen = Set<String>()
        var skipped: [String] = []
        func add(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                skipped.append("\(url.path): broken link"); return
            }
            var name = FileManager.default.displayName(atPath: resolved.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            let entry = AppEntry(name: name, url: resolved, bundleID: Bundle(url: resolved)?.bundleIdentifier)
            if seen.insert(entry.key).inserted { found.append(entry) }
        }
        func walk(_ dir: URL, depth: Int) {
            let items: [URL]
            do {
                items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch {
                skipped.append("\(dir.path): \(error.localizedDescription)"); return
            }
            for item in items.sorted(by: { $0.path < $1.path }) {
                if item.pathExtension == "app" { add(item); continue }
                var isDir: ObjCBool = false
                if depth < 1, FileManager.default.fileExists(atPath: item.resolvingSymlinksInPath().path, isDirectory: &isDir), isDir.boolValue {
                    walk(item, depth: depth + 1)
                }
            }
        }
        for root in roots { walk(root, depth: 0) }
        for extra in extras { add(extra) }
        for s in skipped { coreLog.info("app index skipped \(s, privacy: .public)") }
        apps = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.skipped = skipped
        generation += 1
    }
}
```

Note: `testUnreadableRootIsSkipped` passes because `contentsOfDirectory` throws and the root is recorded in `skipped`.

- [ ] **Step 5: Implement the FSEvents watcher**

`Sources/MenuCraneCore/FSEventsWatcher.swift`:
```swift
import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything under `paths` changes (coalesced by `latency`).
public final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: () -> Void

    public init(paths: [String], latency: TimeInterval = 1, onChange: @escaping () -> Void) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    public func start() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter AppIndexTests`
Expected: all 4 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MenuCraneCore/AppIndex.swift Sources/MenuCraneCore/FSEventsWatcher.swift Tests/MenuCraneCoreTests
git commit -m "feat: app index over the application folders with symlink resolution"
```

---

### Task 8: Providers, SearchEngine and the 5 ms budget

**Files:**
- Create: `Sources/MenuCraneCore/Providers.swift`, `Sources/MenuCraneCore/SearchEngine.swift`
- Test: `Tests/MenuCraneCoreTests/ProvidersTests.swift`, `Tests/MenuCraneCoreTests/PerformanceTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `AppProvider(index:usage:)`, `CalculatorProvider()`, `ConverterProvider(system: @escaping () -> UnitSystem)`, `EmojiCommandProvider()`, `EmojiInlineProvider(store:aliases:recents:tone:)` (closures `() -> [String: [String]]`, `() -> [String]`, `() -> SkinTone`), all `Provider`; `SearchEngine(providers:)` with `results(for raw: String, limit: Int = 50) -> [ResultItem]`. Result ids: `"calc"`, `"convert"`, `"cmd:emoji"`, `"app:<key>"`, `"emoji:<base>"`.

- [ ] **Step 1: Write the failing tests**

`Tests/MenuCraneCoreTests/ProvidersTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class ProvidersTests: XCTestCase {
    var dir: URL!
    var index: AppIndex!
    var usage: UsageStore!
    var engine: SearchEngine!

    override func setUpWithError() throws {
        dir = try Fixtures.tempDir()
        for (name, id) in [("Safari", "com.apple.Safari"), ("Emacs", "org.gnu.Emacs"),
                           ("Visual Studio Code", "com.microsoft.VSCode"), ("Mail", "com.apple.mail")] {
            try Fixtures.makeApp(name, in: dir, bundleID: id)
        }
        index = AppIndex(roots: [dir], extras: [])
        usage = UsageStore(url: dir.appending(path: "usage.json"))
        let store = try Fixtures.emojiStore()
        engine = SearchEngine(providers: [
            CalculatorProvider(),
            ConverterProvider(system: { .usImperial }),
            EmojiCommandProvider(),
            AppProvider(index: index, usage: usage),
            EmojiInlineProvider(store: store, aliases: { [:] }, recents: { [] }, tone: { .none }),
        ])
    }

    func ids(_ q: String) -> [String] { engine.results(for: q).map(\.id) }

    func testAppsByPrefixAndAcronym() {
        XCTAssertEqual(ids("saf").first, "app:com.apple.Safari")
        XCTAssertEqual(ids("vsc").first, "app:com.microsoft.VSCode")
    }

    func testAppResultShape() throws {
        let r = try XCTUnwrap(engine.results(for: "safari").first)
        XCTAssertEqual(r.kind, .app)
        XCTAssertEqual(r.title, "Safari")
        guard case .open(let url) = r.action else { return XCTFail("expected open") }
        XCTAssertEqual(r.alternate, .reveal(url))
        XCTAssertEqual(r.usageKey, "com.apple.Safari")
        XCTAssertEqual(r.footerHint, "↩ Open   ⌘↩ Show in Finder")
    }

    func testMathIsPinnedAndCopiesBareNumber() throws {
        let r = try XCTUnwrap(engine.results(for: "2+2*3").first)
        XCTAssertEqual(r.id, "calc")
        XCTAssertEqual(r.title, "= 8")
        XCTAssertEqual(r.action, .copy("8"))
    }

    func testConversionIsPinnedWithUnitAlternate() throws {
        let r = try XCTUnwrap(engine.results(for: "72f").first)
        XCTAssertEqual(r.id, "convert")
        XCTAssertEqual(r.title, "= 22.2222 °C")
        XCTAssertEqual(r.subtitle, "72 °F → °C")
        XCTAssertEqual(r.action, .copy("22.2222"))
        XCTAssertEqual(r.alternate, .copy("22.2222 °C"))
        XCTAssertEqual(r.footerHint, "↩ Copy   ⌘↩ Copy with unit")
    }

    func testEAndEmojiPinTheEmojiCommand() {
        XCTAssertEqual(ids("e").first, "cmd:emoji")
        XCTAssertEqual(ids("emoji").first, "cmd:emoji")
        XCTAssertEqual(ids("E").first, "cmd:emoji")
        XCTAssertTrue(ids("emo").contains("cmd:emoji"))
        XCTAssertEqual(ids("ema").first, "app:org.gnu.Emacs")
    }

    func testCloseEmojiMatchesAppearInline() {
        let r = ids("fingers crossed")
        XCTAssertTrue(r.contains("emoji:🤞"))
        XCTAssertLessThanOrEqual(r.filter { $0.hasPrefix("emoji:") }.count, 3)
        XCTAssertFalse(ids("s").contains { $0.hasPrefix("emoji:") })   // one letter: no emoji noise
    }

    func testFrecencyReordersTies() {
        let before = ids("ma")
        XCTAssertTrue(before.contains("app:com.apple.mail"))
        for _ in 0..<5 { usage.recordLaunch("com.apple.mail") }
        XCTAssertEqual(ids("ma").first, "app:com.apple.mail")
    }

    func testRemovedAppDisappearsAfterRebuild() throws {
        try FileManager.default.removeItem(at: dir.appending(path: "Safari.app"))
        XCTAssertEqual(ids("safari").first, "app:com.apple.Safari")   // stale until re-indexed
        index.rebuild()
        XCTAssertFalse(ids("safari").contains("app:com.apple.Safari"))
    }

    func testEmptyQueryGivesNothing() {
        XCTAssertEqual(ids(""), [])
        XCTAssertEqual(ids("   "), [])
    }

    func testMergeIsStableForEqualScores() {
        struct Fixed: Provider {
            let items: [ResultItem]
            func results(for query: Query) -> [ResultItem] { items }
        }
        func item(_ id: String, _ score: Double) -> ResultItem {
            ResultItem(id: id, kind: .command, title: id, subtitle: "", icon: .symbol("x"), score: score, action: .copy(id))
        }
        let e = SearchEngine(providers: [Fixed(items: [item("a", 1), item("b", 2)]), Fixed(items: [item("c", 1)])])
        XCTAssertEqual(e.results(for: "q").map(\.id), ["b", "a", "c"])
    }
}
```

`Tests/MenuCraneCoreTests/PerformanceTests.swift` (public API only — no `@testable`, so it runs in release):
```swift
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
        let start = Date()
        let runs = 10
        for _ in 0..<runs { for q in queries { _ = engine.results(for: q) } }
        let perQueryMs = Date().timeIntervalSince(start) * 1000 / Double(runs * queries.count)
        print("per-query: \(perQueryMs) ms")
        XCTAssertLessThan(perQueryMs, 5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProvidersTests`
Expected: compile error — `cannot find 'SearchEngine' in scope`.

- [ ] **Step 3: Implement the providers**

`Sources/MenuCraneCore/Providers.swift`:
```swift
import Foundation

public final class AppProvider: Provider {
    private let index: AppIndex
    private let usage: UsageStore
    private var targets: [(app: AppEntry, target: MatchTarget)] = []
    private var builtGeneration = -1

    public init(index: AppIndex, usage: UsageStore) {
        self.index = index
        self.usage = usage
    }

    public func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        if builtGeneration != index.generation {
            targets = index.apps.map { ($0, MatchTarget([$0.name])) }
            builtGeneration = index.generation
        }
        return targets.compactMap { app, target in
            guard let s = Matcher.score(query, target) else { return nil }
            return ResultItem(id: "app:\(app.key)", kind: .app, title: app.name,
                              subtitle: Self.abbreviate(app.url.path), icon: .app(app.url),
                              score: s + usage.boost(for: app.key), action: .open(app.url),
                              alternate: .reveal(app.url), usageKey: app.key)
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

public struct CalculatorProvider: Provider {
    public init() {}
    public func results(for query: Query) -> [ResultItem] {
        guard let v = Calculator.evaluate(query.raw) else { return [] }
        let text = NumberText.answer(v)
        return [ResultItem(id: "calc", kind: .answer, title: "= \(text)",
                           subtitle: query.raw.trimmingCharacters(in: .whitespaces),
                           icon: .symbol("equal.circle"), score: ResultItem.pinnedScore, action: .copy(text))]
    }
}

public struct ConverterProvider: Provider {
    private let system: () -> UnitSystem
    public init(system: @escaping () -> UnitSystem) { self.system = system }
    public func results(for query: Query) -> [ResultItem] {
        guard let c = Converter(system: system()).convert(query.raw) else { return [] }
        return [ResultItem(id: "convert", kind: .answer, title: "= \(c.withUnit)",
                           subtitle: "\(c.inputText) → \(c.to)", icon: .symbol("arrow.left.arrow.right.circle"),
                           score: ResultItem.pinnedScore, action: .copy(c.bare),
                           alternate: .copy(c.withUnit), alternateLabel: "Copy with unit")]
    }
}

public struct EmojiCommandProvider: Provider {
    static let target = MatchTarget(["Emoji", "Search Emoji"])
    public init() {}
    public func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        let pinned = query.folded == "e" || query.folded == "emoji"
        guard let score = pinned ? ResultItem.pinnedScore - 1 : Matcher.score(query, Self.target) else { return [] }
        return [ResultItem(id: "cmd:emoji", kind: .command, title: "Emoji", subtitle: "Search emoji",
                           icon: .symbol("face.smiling"), score: score, action: .enterEmojiMode)]
    }
}

public struct EmojiInlineProvider: Provider {
    static let maxInline = 3
    private let store: EmojiStore
    private let aliases: () -> [String: [String]]
    private let recents: () -> [String]
    private let tone: () -> SkinTone

    public init(store: EmojiStore, aliases: @escaping () -> [String: [String]],
                recents: @escaping () -> [String], tone: @escaping () -> SkinTone) {
        self.store = store; self.aliases = aliases; self.recents = recents; self.tone = tone
    }

    /// Only close matches (every word starts a word of the name, a keyword or an alias), at most three,
    /// and never for a one-letter query.
    public func results(for query: Query) -> [ResultItem] {
        guard query.folded.count >= 2 else { return [] }
        let t = tone()
        return store.search(query, aliases: aliases(), recents: recents())
            .prefix(while: { $0.score >= Matcher.prefixScore })
            .prefix(Self.maxInline)
            .map { hit in
                let glyph = hit.emoji.glyph(t)
                return ResultItem(id: "emoji:\(hit.emoji.char)", kind: .emoji, title: hit.emoji.name.capitalizedFirstLetter,
                                  subtitle: "Emoji", icon: .emoji(glyph), score: hit.score * 0.9,
                                  action: .copy(glyph), usageKey: hit.emoji.char)
            }
    }
}

extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
```

`Sources/MenuCraneCore/SearchEngine.swift`:
```swift
import Foundation

public final class SearchEngine {
    private let providers: [Provider]
    public init(providers: [Provider]) { self.providers = providers }

    /// Every provider's results for `raw`, best first; equal scores keep provider order.
    public func results(for raw: String, limit: Int = 50) -> [ResultItem] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        return providers.flatMap { $0.results(for: query) }
            .enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(limit)
            .map(\.element)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProvidersTests`
Expected: all 10 tests PASS.

- [ ] **Step 5: Run the performance test in release**

Run: `swift test -c release -Xswiftc -enable-testing --filter PerformanceTests`
Expected: PASS, printing a per-query time well under 5 ms. If it fails, profile before changing anything: the likely cost is `EmojiStore.search` building `MatchTarget` for aliased emoji; cache those per `aliases` dictionary identity.

- [ ] **Step 6: Run the full suite and commit**

Run: `swift test`
Expected: all tests PASS.
```bash
git add Sources/MenuCraneCore/Providers.swift Sources/MenuCraneCore/SearchEngine.swift Tests/MenuCraneCoreTests/ProvidersTests.swift Tests/MenuCraneCoreTests/PerformanceTests.swift
git commit -m "feat: result providers, merged search engine and 5 ms budget test"
```

---

### Task 9: PanelState

**Files:**
- Create: `Sources/MenuCraneCore/PanelState.swift`
- Test: `Tests/MenuCraneCoreTests/PanelStateTests.swift`

**Interfaces:**
- Consumes: `SearchEngine`, `EmojiHit`, `Query`.
- Produces: `enum PanelMode { main, emoji }`; `enum EscapeOutcome { clearedQuery, backToMain, close }`; `final class PanelState: ObservableObject` with published `mode`, `query` (setting it re-searches), `results`, `emoji`, `selection`, `footerMessage`; `gridColumns`; `init(engine:gridColumns: = 9, emojiSearch: @escaping (Query) -> [EmojiHit])`; `itemCount`, `selectedResult`, `selectedEmoji`, `isMiss`; `refresh()`, `move(_:)`, `moveGrid(dx:dy:)`, `select(index:) -> Bool`, `enterEmojiMode()`, `backToMain()`, `escape() -> EscapeOutcome`, `deleteOnEmpty() -> Bool`, `reset()`.

- [ ] **Step 1: Write the failing tests**

`Tests/MenuCraneCoreTests/PanelStateTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class PanelStateTests: XCTestCase {
    struct Words: Provider {
        func results(for query: Query) -> [ResultItem] {
            (0..<12).map { i in
                ResultItem(id: "\(query.folded)-\(i)", kind: .command, title: "\(i)", subtitle: "",
                           icon: .symbol("x"), score: Double(100 - i), action: .copy("\(i)"))
            }.filter { _ in query.folded != "none" }
        }
    }
    static let emoji = (0..<20).map { i in
        EmojiHit(emoji: Emoji(char: "e\(i)", name: "n\(i)", keywords: [], group: "g", tones: nil), score: 1)
    }
    func make() -> PanelState {
        PanelState(engine: SearchEngine(providers: [Words()]), gridColumns: 9) { q in
            q.isEmpty ? Self.emoji : Array(Self.emoji.prefix(3))
        }
    }

    func testTypingSearchesAndResetsSelection() {
        let s = make()
        s.query = "a"
        XCTAssertEqual(s.results.count, 12)
        s.move(3)
        XCTAssertEqual(s.selection, 3)
        s.query = "ab"
        XCTAssertEqual(s.selection, 0)
    }

    func testMoveClamps() {
        let s = make()
        s.query = "a"
        s.move(-1); XCTAssertEqual(s.selection, 0)
        s.move(50); XCTAssertEqual(s.selection, 11)
    }

    func testSelectIndexForCommandDigits() {
        let s = make()
        s.query = "a"
        XCTAssertTrue(s.select(index: 4)); XCTAssertEqual(s.selection, 4)
        XCTAssertFalse(s.select(index: 20)); XCTAssertEqual(s.selection, 4)
    }

    func testEscapeInMainClearsThenCloses() {
        let s = make()
        s.query = "a"
        XCTAssertEqual(s.escape(), .clearedQuery)
        XCTAssertEqual(s.query, "")
        XCTAssertEqual(s.escape(), .close)
    }

    func testEmojiModeEnterEscapeAndBackspace() {
        let s = make()
        s.query = "e"
        s.enterEmojiMode()
        XCTAssertEqual(s.mode, .emoji)
        XCTAssertEqual(s.query, "")
        XCTAssertEqual(s.emoji.count, 20)
        s.query = "fire"
        XCTAssertEqual(s.escape(), .backToMain)          // even with text typed
        XCTAssertEqual(s.mode, .main)
        XCTAssertEqual(s.query, "")
        s.enterEmojiMode()
        XCTAssertTrue(s.deleteOnEmpty())
        XCTAssertEqual(s.mode, .main)
        XCTAssertFalse(s.deleteOnEmpty())                // main mode: backspace is just backspace
    }

    func testGridMovement() {
        let s = make()
        s.enterEmojiMode()
        s.moveGrid(dx: 1, dy: 0); XCTAssertEqual(s.selection, 1)
        s.moveGrid(dx: 0, dy: 1); XCTAssertEqual(s.selection, 10)
        s.moveGrid(dx: 0, dy: 1); XCTAssertEqual(s.selection, 19)   // clamps to last
        s.moveGrid(dx: -1, dy: -5); XCTAssertEqual(s.selection, 0)
    }

    func testMissAndReset() {
        let s = make()
        XCTAssertFalse(s.isMiss)
        s.query = "none"
        XCTAssertTrue(s.isMiss)
        s.footerMessage = "Copied"
        s.enterEmojiMode()
        s.reset()
        XCTAssertEqual(s.mode, .main)
        XCTAssertEqual(s.query, "")
        XCTAssertNil(s.footerMessage)
        XCTAssertEqual(s.results, [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PanelStateTests`
Expected: compile error — `cannot find 'PanelState' in scope`.

- [ ] **Step 3: Implement PanelState**

`Sources/MenuCraneCore/PanelState.swift`:
```swift
import Combine
import Foundation

public enum PanelMode: Equatable, Sendable { case main, emoji }
public enum EscapeOutcome: Equatable, Sendable { case clearedQuery, backToMain, close }

/// Everything the panel shows, and the rules for moving around it. No AppKit here.
public final class PanelState: ObservableObject {
    @Published public private(set) var mode: PanelMode = .main
    @Published public var query: String = "" { didSet { refresh() } }
    @Published public private(set) var results: [ResultItem] = []
    @Published public private(set) var emoji: [EmojiHit] = []
    @Published public private(set) var selection = 0
    @Published public var footerMessage: String?
    public let gridColumns: Int

    private let engine: SearchEngine
    private let emojiSearch: (Query) -> [EmojiHit]

    public init(engine: SearchEngine, gridColumns: Int = 9, emojiSearch: @escaping (Query) -> [EmojiHit]) {
        self.engine = engine
        self.gridColumns = gridColumns
        self.emojiSearch = emojiSearch
    }

    public var itemCount: Int { mode == .main ? results.count : emoji.count }
    public var selectedResult: ResultItem? { mode == .main && selection < results.count ? results[selection] : nil }
    public var selectedEmoji: EmojiHit? { mode == .emoji && selection < emoji.count ? emoji[selection] : nil }
    /// Something typed and nothing found — Mendoza looks puzzled.
    public var isMiss: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty && itemCount == 0 }

    public func refresh() {
        switch mode {
        case .main: results = engine.results(for: query)
        case .emoji: emoji = emojiSearch(Query(query))
        }
        selection = 0
    }

    public func move(_ delta: Int) {
        guard itemCount > 0 else { return }
        selection = min(max(selection + delta, 0), itemCount - 1)
    }

    public func moveGrid(dx: Int, dy: Int) { move(dx + dy * gridColumns) }

    @discardableResult
    public func select(index: Int) -> Bool {
        guard index >= 0, index < itemCount else { return false }
        selection = index
        return true
    }

    public func enterEmojiMode() {
        mode = .emoji
        query = ""
    }

    public func backToMain() {
        mode = .main
        query = ""
    }

    public func escape() -> EscapeOutcome {
        switch mode {
        case .emoji:
            backToMain()
            return .backToMain
        case .main:
            if query.isEmpty { return .close }
            query = ""
            return .clearedQuery
        }
    }

    /// ⌫ on an empty emoji search goes back to the main list.
    public func deleteOnEmpty() -> Bool {
        guard mode == .emoji, query.isEmpty else { return false }
        backToMain()
        return true
    }

    /// Fresh state for each summon.
    public func reset() {
        mode = .main
        footerMessage = nil
        query = ""
        emoji = []
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PanelStateTests`
Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuCraneCore/PanelState.swift Tests/MenuCraneCoreTests/PanelStateTests.swift
git commit -m "feat: panel state machine for list, emoji grid and escape handling"
```

---

### Task 10: Hotkey settings and trigger text

**Files:**
- Modify: `Package.swift` (Core depends on HotkeyKit)
- Create: `Sources/MenuCraneCore/HotkeySettings.swift`
- Test: `Tests/MenuCraneCoreTests/HotkeySettingsTests.swift`

**Interfaces:**
- Consumes: HotkeyKit `Trigger`, `Modifiers`.
- Produces: `HotkeySettings.defaultTrigger` (`.key(49, [.command])`), `HotkeySettings.load(from: UserDefaults) -> Trigger`, `HotkeySettings.save(_: Trigger, to: UserDefaults)`, defaults keys `HotkeyKeyCode` (Int) and `HotkeyModifiers` (Int, HotkeyKit `Modifiers.rawValue`); `TriggerText.describe(_: Trigger) -> String` (e.g. `⌘Space`, `⌃⌥⇧⌘K`).

- [ ] **Step 1: Add the dependency**

Replace `Package.swift`'s `let package = …` with:
```swift
let package = Package(
    name: "MenuCrane",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MenuCraneCore", targets: ["MenuCraneCore"]),
    ],
    dependencies: [
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "MenuCraneCore", dependencies: [.product(name: "HotkeyKit", package: "HotkeyKit")]),
        .testTarget(name: "MenuCraneCoreTests", dependencies: ["MenuCraneCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

`Tests/MenuCraneCoreTests/HotkeySettingsTests.swift`:
```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter HotkeySettingsTests`
Expected: compile error — `cannot find 'HotkeySettings' in scope`.

- [ ] **Step 4: Implement**

`Sources/MenuCraneCore/HotkeySettings.swift`:
```swift
import CoreGraphics
import Foundation
import HotkeyKit

public enum HotkeySettings {
    public static let keyCodeKey = "HotkeyKeyCode"
    public static let modifiersKey = "HotkeyModifiers"
    public static let defaultTrigger = Trigger.key(49, [.command])   // ⌘Space

    /// The saved hotkey; a bare key with no modifier is refused (it would eat normal typing).
    public static func load(from defaults: UserDefaults) -> Trigger {
        guard defaults.object(forKey: keyCodeKey) != nil else { return defaultTrigger }
        let mods = Modifiers(rawValue: defaults.integer(forKey: modifiersKey))
        guard !mods.isEmpty else { return defaultTrigger }
        return .key(CGKeyCode(defaults.integer(forKey: keyCodeKey)), mods)
    }

    public static func save(_ trigger: Trigger, to defaults: UserDefaults) {
        guard case let .key(code, mods) = trigger else { return }
        defaults.set(Int(code), forKey: keyCodeKey)
        defaults.set(mods.rawValue, forKey: modifiersKey)
    }
}

public enum TriggerText {
    public static func describe(_ trigger: Trigger) -> String {
        switch trigger {
        case let .key(code, mods): return symbols(mods) + (names[code] ?? "Key \(code)")
        case let .mediaKey(key, mods): return symbols(mods) + "Media \(key)"
        }
    }

    static func symbols(_ m: Modifiers) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    }

    static let names: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter HotkeySettingsTests`
Expected: all 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/MenuCraneCore/HotkeySettings.swift Tests/MenuCraneCoreTests/HotkeySettingsTests.swift
git commit -m "feat: hotkey settings and trigger display text"
```

---

### Task 11: Mendoza's menu-bar glyph in StatusItemKit

**Repo:** `~/Code/StatusItemKit` (branch first: `git -C ~/Code/StatusItemKit switch -c feature/menu-crane-glyph`).

**Files:**
- Modify: `~/Code/StatusItemKit/Sources/StatusItemKit/CharacterIcon.swift` (append before the final `}` of `enum CharacterIcon`)
- Modify: `~/Code/StatusItemKit/Tests/StatusItemKitTests/CharacterIconTests.swift`
- Modify: `~/Code/StatusItemKit/scripts/release/adopt.sh:32-34` (add `menu-crane` to `APPS`)
- Modify: `~/Code/StatusItemKit/CHANGELOG.md` (new version section)
- Modify: `~/Code/widgets.nicksmith.software/art/glyphs/main.swift`, `…/art/glyphs/render-glyphs.sh` (repo map)

**Interfaces:**
- Produces: `CharacterIcon.CraneState` (`idle`, `searching`, `grabbed`, `miss`) and `CharacterIcon.menuCrane(state:) -> NSImage` (22×22 pt, full colour, non-template).

- [ ] **Step 1: Write the failing test**

Add to `CharacterIconTests`:
```swift
    func testMenuCraneIs22ptFullColourAndEveryStateDiffers() {
        let states: [CharacterIcon.CraneState] = [.idle, .searching, .grabbed, .miss]
        let images = states.map { CharacterIcon.menuCrane(state: $0) }
        for img in images {
            XCTAssertEqual(img.size, NSSize(width: 22, height: 22))
            XCTAssertFalse(img.isTemplate)
        }
        let pngs = images.map { NSBitmapImageRep(data: $0.tiffRepresentation!)!.representation(using: .png, properties: [:])! }
        XCTAssertEqual(Set(pngs).count, states.count)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/Code/StatusItemKit && swift test --filter CharacterIconTests`
Expected: compile error — `type 'CharacterIcon' has no member 'CraneState'`.

- [ ] **Step 3: Draw Mendoza**

Append inside `public enum CharacterIcon { … }`:
```swift
    // MENU CRANE: Mendoza's head side-on — red cap, two big touching eyes, a long beak to the
    // right with a clamshell grab bucket hanging from a ring near its tip. The bucket opens
    // while the panel is up, snaps shut on a copy, and hangs open and empty on no results.
    public enum CraneState: Sendable { case idle, searching, grabbed, miss }

    static let craneRed = NSColor(red: 0.88, green: 0.27, blue: 0.23, alpha: 1)
    static let craneBeak = NSColor(red: 0.89, green: 0.78, blue: 0.56, alpha: 1)
    static let craneBucket = NSColor(red: 0.97, green: 0.78, blue: 0.22, alpha: 1)
    static let craneInk = NSColor(white: 0.12, alpha: 1)

    public static func menuCrane(state: CraneState) -> NSImage {
        canvas(width: 22, height: 22) { _ in
            let line: CGFloat = 0.9
            func inked(_ p: NSBezierPath, _ fill: NSColor) {
                fill.set(); p.fill()
                craneInk.set(); p.lineWidth = line; p.lineJoinStyle = .round; p.stroke()
            }
            func clipped(to p: NSBezierPath, _ fill: NSColor, _ rect: NSRect) {
                NSGraphicsContext.saveGraphicsState()
                p.addClip(); fill.set(); NSBezierPath(rect: rect).fill()
                NSGraphicsContext.restoreGraphicsState()
                craneInk.set(); p.lineWidth = line; p.stroke()
            }

            // Neck, rising from the bottom-left edge, with its white collar.
            let neck = NSBezierPath()
            neck.move(to: NSPoint(x: 1.2, y: -1))
            neck.curve(to: NSPoint(x: 2.6, y: 11), controlPoint1: NSPoint(x: 0.8, y: 4), controlPoint2: NSPoint(x: 1.2, y: 8))
            neck.line(to: NSPoint(x: 8.6, y: 10))
            neck.curve(to: NSPoint(x: 7.4, y: -1), controlPoint1: NSPoint(x: 6.6, y: 7), controlPoint2: NSPoint(x: 6.8, y: 3))
            neck.close()
            inked(neck, body)
            clipped(to: neck, .white, NSRect(x: 0, y: 1.2, width: 10, height: 1.6))

            // Head and red cap.
            let head = NSBezierPath(ovalIn: NSRect(x: 1.2, y: 8.8, width: 11, height: 11))
            inked(head, body)
            clipped(to: head, craneRed, NSRect(x: 0, y: 17.4, width: 14, height: 5))

            // Beak, then the eyes on top of it.
            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: 8.2, y: 12.6))
            beak.line(to: NSPoint(x: 21.4, y: 10.8))
            beak.line(to: NSPoint(x: 8.6, y: 10.0))
            beak.close()
            inked(beak, craneBeak)

            let eyes = [NSPoint(x: 5.6, y: 14.8), NSPoint(x: 9.8, y: 15.2)]
            for c in eyes { inked(NSBezierPath(ovalIn: NSRect(x: c.x - 2.7, y: c.y - 2.7, width: 5.4, height: 5.4)), .white) }
            if state == .grabbed {
                for c in eyes {   // happy closed crescents
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: NSPoint(x: c.x, y: c.y - 0.6), radius: 1.4, startAngle: 20, endAngle: 160)
                    arc.lineWidth = 1; arc.lineCapStyle = .round
                    craneInk.set(); arc.stroke()
                }
            } else {
                let look: [CGSize]
                switch state {
                case .searching: look = [CGSize(width: 0.9, height: -1.1), CGSize(width: 0.9, height: -1.1)]
                case .miss: look = [CGSize(width: -1.0, height: 0.8), CGSize(width: 1.0, height: -0.6)]
                default: look = [CGSize(width: 1.1, height: 0), CGSize(width: 1.1, height: 0)]
                }
                craneInk.set()
                for (c, d) in zip(eyes, look) {
                    NSBezierPath(ovalIn: NSRect(x: c.x + d.width - 0.8, y: c.y + d.height - 0.8, width: 1.6, height: 1.6)).fill()
                }
            }

            // Ring on the beak, cable, bucket.
            let ringC = NSPoint(x: 17.6, y: 10.6)
            let ring = NSBezierPath(ovalIn: NSRect(x: ringC.x - 1.1, y: ringC.y - 1.1, width: 2.2, height: 2.2))
            ring.lineWidth = 0.9; NSColor(white: 0.55, alpha: 1).set(); ring.stroke()
            let open = state == .searching || state == .miss
            let top: CGFloat = open ? 6.8 : 7.8
            let cable = NSBezierPath()
            cable.move(to: NSPoint(x: ringC.x, y: ringC.y - 1.1)); cable.line(to: NSPoint(x: ringC.x, y: top))
            cable.lineWidth = 0.8; craneInk.set(); cable.stroke()
            if open {
                for side: CGFloat in [-1, 1] {
                    let jaw = NSBezierPath()
                    jaw.move(to: NSPoint(x: ringC.x, y: top))
                    jaw.line(to: NSPoint(x: ringC.x + side * 3.8, y: top - 1.4))
                    jaw.line(to: NSPoint(x: ringC.x + side * 2.6, y: top - 5.2))
                    jaw.line(to: NSPoint(x: ringC.x + side * 0.6, y: top - 3.4))
                    jaw.close()
                    inked(jaw, craneBucket)
                }
            } else {
                let bucket = NSBezierPath()
                bucket.move(to: NSPoint(x: ringC.x - 3.4, y: top))
                bucket.line(to: NSPoint(x: ringC.x + 3.4, y: top))
                bucket.line(to: NSPoint(x: ringC.x + 2.2, y: top - 4.6))
                bucket.line(to: NSPoint(x: ringC.x - 2.2, y: top - 4.6))
                bucket.close()
                inked(bucket, craneBucket)
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: ringC.x, y: top)); seam.line(to: NSPoint(x: ringC.x, y: top - 4.6))
                seam.lineWidth = 0.7; craneInk.set(); seam.stroke()
            }
            if state == .miss {   // sweat drop beside the head
                let drop = NSBezierPath()
                drop.move(to: NSPoint(x: 13.6, y: 20.4))
                drop.curve(to: NSPoint(x: 13.6, y: 16.6), controlPoint1: NSPoint(x: 12.2, y: 18.2), controlPoint2: NSPoint(x: 12.4, y: 16.6))
                drop.curve(to: NSPoint(x: 13.6, y: 20.4), controlPoint1: NSPoint(x: 14.8, y: 16.6), controlPoint2: NSPoint(x: 15.0, y: 18.2))
                NSColor.systemBlue.set(); drop.fill()
            }
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CharacterIconTests`
Expected: PASS.

- [ ] **Step 5: Render and look at it**

Add to `~/Code/widgets.nicksmith.software/art/glyphs/main.swift` next to the Homestead lines:
```swift
save(CharacterIcon.menuCrane(state: .idle), "icon-menu-crane.png")
strip([CharacterIcon.menuCrane(state: .idle), CharacterIcon.menuCrane(state: .searching),
       CharacterIcon.menuCrane(state: .grabbed), CharacterIcon.menuCrane(state: .miss)], "states-menu-crane.png")
```
Add `[menu-crane]=menu-crane` to the `repo` map in `render-glyphs.sh`, and `mkdir -p ~/Code/menu-crane/docs`.
Run: `~/Code/widgets.nicksmith.software/art/glyphs/render-glyphs.sh`
Then open `~/Code/widgets.nicksmith.software/art/glyphs/build/states-menu-crane.png` with the Read tool and compare against `~/Code/menu-crane/art/mascot/mendoza-*.png`. Tune coordinates in `menuCrane` until the four states read clearly at menu-bar size (eyes, red cap and yellow bucket distinct; nothing clipped at the 22 pt edges). Re-run the test after any change.

- [ ] **Step 6: Add Menu Crane to the release kit and changelog**

In `scripts/release/adopt.sh`, append `menu-crane` to the `APPS=(…)` list (before `StatusItemKit HotkeyKit`).
At the top of `CHANGELOG.md` (below the header text, above the previous version), add, using the day this task is done:
```markdown
## [0.9.0] - YYYY-MM-DD
### Added
- `CharacterIcon.menuCrane(state:)`: Mendoza, Menu Crane's crane, in four states (idle, searching, grabbed, miss).
- Menu Crane joins the release kit's app list.
```

- [ ] **Step 7: Commit (both repos; do not push)**

```bash
cd ~/Code/StatusItemKit && git add -A && git commit -m "feat: Mendoza menu-crane glyph; menu-crane in release kit"
cd ~/Code/widgets.nicksmith.software && git add art/glyphs site/img/glyphs && git commit -m "glyphs: add Menu Crane"
```

---

### Task 12: App target skeleton

**Files:**
- Modify: `Package.swift`
- Create: `Resources/Info.plist`, `scripts/build-app.sh`, `install.sh`, `Sources/MenuCrane/main.swift`, `Sources/MenuCrane/App.swift`

**Interfaces:**
- Consumes: StatusItemKit `StatusItemController`, `YieldClient`, `LoginItem`, `LoginCLI`, `AppVersion`, `CharacterIcon.menuCrane`.
- Produces: `final class App: NSObject, NSApplicationDelegate` with `status`, `buildMenu(_:)`, `menuItem(_:_:key:)` helper; global `log: Logger` (category `app`).

- [ ] **Step 1: Declare the executable**

Replace `Package.swift`'s `let package = …` with:
```swift
let package = Package(
    name: "MenuCrane",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MenuCrane", targets: ["MenuCrane"]),
        .library(name: "MenuCraneCore", targets: ["MenuCraneCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "MenuCraneCore", dependencies: [.product(name: "HotkeyKit", package: "HotkeyKit")]),
        .executableTarget(
            name: "MenuCrane",
            dependencies: [
                "MenuCraneCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "MenuCraneCoreTests", dependencies: ["MenuCraneCore"]),
    ]
)
```

- [ ] **Step 2: Bundle files**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MenuCrane</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.nicholaspsmith.MenuCrane</string>
	<key>CFBundleName</key>
	<string>Menu Crane</string>
	<key>CFBundleDisplayName</key>
	<string>Menu Crane</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

`scripts/build-app.sh` (MIT SPDX header, then):
```bash
# Build "Menu Crane.app" via the shared StatusItemKit bundler.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh MenuCrane "Menu Crane"
```

`install.sh`: copy `~/Code/keylight-menubar/install.sh`, replace its MPL header with the MIT SPDX header, and change `APP_NAME="KeyLight.app"` → `APP_NAME="Menu Crane.app"`, the comment's app name, and the login line's binary path to `"$HOME/Applications/$APP_NAME/Contents/MacOS/MenuCrane"`.

Run: `chmod +x scripts/build-app.sh install.sh`

- [ ] **Step 3: Entry point and delegate**

`Sources/MenuCrane/main.swift` (MIT SPDX header, then):
```swift
import AppKit
import StatusItemKit

// `--login on|off|status` for install.sh; exits before any UI exists.
LoginCLI.runIfRequested()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
```

`Sources/MenuCrane/App.swift` (MIT SPDX header, then):
```swift
import AppKit
import MenuCraneCore
import StatusItemKit
import os

let log = Logger(subsystem: "com.nicholaspsmith.MenuCrane", category: "app")

/// Menu Crane — a ⌘Space launcher for apps, math, unit conversions and emoji.
final class App: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    private var yieldClient: YieldClient!

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.poll() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) },
            autosaveName: "MenuCrane"
        )
        status.start()
        yieldClient = YieldClient(item: status)
        yieldClient.start()
        status.setIcon(CharacterIcon.menuCrane(state: .idle))
    }

    private func poll() {}

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let login = menuItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(menuItem("Quit Menu Crane", #selector(quit), key: "q"))
    }

    func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: Build, tag a local dev version, install**

`make-app.sh` refuses to build without a reachable `vX.Y.Z` tag. Create a **lightweight, local-only** pre-release tag (never pushed; deleted in Task 18):
```bash
git add -A && git commit -m "feat: app target skeleton with menu-bar item"
git tag v0.0.0-dev
./install.sh
```
Expected: `==> Version 0.0.0-dev…`, `Linked ~/Applications/Menu Crane.app -> …/build/Menu Crane.app`, `Start at Login: on`.

- [ ] **Step 5: Verify it runs**

Run: `open "$HOME/Applications/Menu Crane.app"; sleep 2; pgrep -x MenuCrane && ~/Code/menubar-barn/scripts/verify-menubar.sh | grep -i crane`
Expected: a PID, and the verify script lists Menu Crane's item. Its menu shows Start at Login, the version row and Quit Menu Crane.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "build: bundle, install script and license"
```

---

### Task 13: Global hotkey

**Files:**
- Create: `Sources/MenuCrane/HotkeyService.swift`
- Modify: `Sources/MenuCrane/App.swift`

**Interfaces:**
- Consumes: `HotkeySettings`, `TriggerText`, HotkeyKit `Trigger`/`Modifiers`.
- Produces: `final class HotkeyService { var onPress: (() -> Void)?; var failure: String?; func register(_: Trigger) -> String?; func unregister() }`. App gains `hotkey`, `trigger`, `openPanel()` (logs only until Task 14).

- [ ] **Step 1: Implement the Carbon hotkey**

`Sources/MenuCrane/HotkeyService.swift` (MIT SPDX header, then):
```swift
import AppKit
import Carbon.HIToolbox
import HotkeyKit
import MenuCraneCore

/// A system-wide hotkey through Carbon's RegisterEventHotKey — no Accessibility permission needed.
final class HotkeyService {
    var onPress: (() -> Void)?
    /// Why the hotkey isn't active, for the menu's warning row; nil when it is.
    private(set) var failure: String?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Register `trigger`, replacing any previous one. Returns the failure reason, if any.
    @discardableResult
    func register(_ trigger: Trigger) -> String? {
        unregister()
        let name = TriggerText.describe(trigger)
        guard case let .key(code, mods) = trigger else {
            failure = "media keys can't open Menu Crane"; return failure
        }
        if let other = Self.conflictingApp(for: trigger) {
            failure = "\(name) is in use by \(other)"; return failure
        }
        let id = EventHotKeyID(signature: OSType(0x4D43_5248), id: 1)   // 'MCRH'
        let status = RegisterEventHotKey(UInt32(code), Self.carbonModifiers(mods), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        failure = status == noErr ? nil : "\(name) is in use"
        if let failure { log.error("hotkey: \(failure, privacy: .public) (\(status))") }
        return failure
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    static func carbonModifiers(_ m: Modifiers) -> UInt32 {
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.option) { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        if m.contains(.shift) { r |= UInt32(shiftKey) }
        return r
    }

    /// Carbon doesn't reliably report a combination another app holds, so name the known one.
    static func conflictingApp(for trigger: Trigger) -> String? {
        guard trigger == HotkeySettings.defaultTrigger else { return nil }
        let raycast = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.raycast.macos" }
        return raycast ? "Raycast" : nil
    }
}
```

- [ ] **Step 2: Wire it into the app**

In `App`, add properties:
```swift
    private let hotkey = HotkeyService()
    private var trigger = HotkeySettings.load(from: .standard)
```
At the end of `applicationDidFinishLaunching`:
```swift
        hotkey.onPress = { [weak self] in self?.openPanel() }
        hotkey.register(trigger)
```
Replace `poll()`:
```swift
    /// Retry a hotkey another app was holding (e.g. right after Raycast quits).
    private func poll() {
        if hotkey.failure != nil { hotkey.register(trigger) }
    }
```
Replace `buildMenu(_:)`:
```swift
    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if let failure = hotkey.failure {
            let warn = NSMenuItem(title: "⚠ Hotkey unavailable — \(failure)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(menuItem("Open Menu Crane (\(TriggerText.describe(trigger)))", #selector(openPanel)))
        menu.addItem(.separator())
        let login = menuItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(menuItem("Quit Menu Crane", #selector(quit), key: "q"))
    }
```
Add:
```swift
    @objc func openPanel() { log.info("open panel requested") }
```
Add `import HotkeyKit` at the top of `App.swift`.

- [ ] **Step 3: Set the development hotkey and verify**

Raycast owns ⌘Space during development, so use ⌥Space (key code 49, HotkeyKit `.option` raw value 2):
```bash
defaults write com.nicholaspsmith.MenuCrane HotkeyKeyCode -int 49
defaults write com.nicholaspsmith.MenuCrane HotkeyModifiers -int 2
./install.sh && pkill -x MenuCrane; open "$HOME/Applications/Menu Crane.app"
log stream --predicate 'subsystem == "com.nicholaspsmith.MenuCrane"' --style compact &
```
Press ⌥Space. Expected: `open panel requested` in the log stream (stop it with `kill %1`). The menu reads `Open Menu Crane (⌥Space)` with no warning row.
Then check the conflict path without touching Raycast: `defaults delete com.nicholaspsmith.MenuCrane HotkeyKeyCode; defaults delete com.nicholaspsmith.MenuCrane HotkeyModifiers`, relaunch, and open the menu. Expected: `⚠ Hotkey unavailable — ⌘Space is in use by Raycast`. Restore the ⌥Space defaults and relaunch.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: global hotkey via Carbon with conflict warning"
```

---

### Task 14: The panel, main list and actions

**Files:**
- Create: `Sources/MenuCrane/Preferences.swift`, `Sources/MenuCrane/CranePanel.swift`, `Sources/MenuCrane/PanelController.swift`, `Sources/MenuCrane/PanelViews.swift`, `Sources/MenuCrane/ActionPerformer.swift`, `Sources/MenuCrane/IconCache.swift`, `Sources/MenuCrane/EditMenu.swift`
- Modify: `Sources/MenuCrane/App.swift`

**Interfaces:**
- Consumes: all Core types; `HotkeyService`.
- Produces: `Preferences.unitSystem`, `.skinTone`, `.iconStyle` (`"crane"` / `"dot"`); `CranePanel` (`onResignKey`, `keyEquivalentHandler`); `PanelController(state:performer:index:)` with `show()`, `hide()`, `toggle()`, `isVisible`, callbacks `onVisibilityChange: ((Bool) -> Void)?`, `onGrab: (() -> Void)?`, `onOpenSettings: (() -> Void)?`, `emojiKeyHandler: ((NSEvent) -> Bool)?`, `activateEmoji: ((EmojiHit) -> Void)?`; `ActionPerformer(usage:)` with `open(_:usageKey:) -> Bool`, `reveal(_:)`, `copy(_:)`; `IconCache.icon(for: URL) -> NSImage`; `EditMenu.install()`; SwiftUI `PanelBody`, `ResultListView`, `ResultRow`, `FooterView`. App gains `services` (stores, engine, index, watcher) and `panel`.

- [ ] **Step 1: Preferences, icons, edit menu, actions**

`Sources/MenuCrane/Preferences.swift`:
```swift
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
```

`Sources/MenuCrane/IconCache.swift`:
```swift
import AppKit

final class IconCache {
    private var cache: [URL: NSImage] = [:]
    func icon(for url: URL) -> NSImage {
        if let hit = cache[url] { return hit }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[url] = img
        return img
    }
}
```

`Sources/MenuCrane/EditMenu.swift`:
```swift
import AppKit

/// An LSUIElement app has no menu bar, so text fields get no ⌘C/⌘V/⌘A/⌘Z unless a main menu
/// with these items exists. It is never shown.
enum EditMenu {
    static func install() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
```

`Sources/MenuCrane/ActionPerformer.swift`:
```swift
import AppKit
import MenuCraneCore

final class ActionPerformer {
    private let usage: UsageStore
    init(usage: UsageStore) { self.usage = usage }

    /// false when the app is no longer at `url` (deleted or moved since indexing).
    func open(_ url: URL, usageKey: String?) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { log.error("open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
        if let usageKey { usage.recordLaunch(usageKey) }
        return true
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func recordEmoji(_ base: String) { usage.recordEmoji(base) }
}
```

- [ ] **Step 2: The panel window**

`Sources/MenuCrane/CranePanel.swift`:
```swift
import AppKit

/// A borderless floating panel that takes the keyboard without activating Menu Crane, so the app
/// you were in stays frontmost and gets focus back the moment the panel closes.
final class CranePanel: NSPanel {
    var onResignKey: (() -> Void)?
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    init(width: CGFloat, height: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(b)?.isHidden = true }
        isMovable = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
```

- [ ] **Step 3: SwiftUI views for the list and footer**

`Sources/MenuCrane/PanelViews.swift`:
```swift
import MenuCraneCore
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 680
    static let fieldHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let footerHeight: CGFloat = 28
    static let maxRows = 8
    static let emojiBodyHeight: CGFloat = 360
}

struct PanelBody: View {
    @ObservedObject var state: PanelState
    let icons: IconCache
    let onClick: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !state.results.isEmpty {
                Divider()
                ResultListView(state: state, icons: icons, onClick: onClick)
            }
            FooterView(state: state)
        }
    }
}

struct ResultListView: View {
    @ObservedObject var state: PanelState
    let icons: IconCache
    let onClick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.results.enumerated()), id: \.element.id) { i, item in
                        ResultRow(item: item, index: i, selected: i == state.selection, icons: icons)
                            .id(i)
                            .contentShape(Rectangle())
                            .onTapGesture { onClick(i) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: state.selection) { proxy.scrollTo($0) }
        }
    }
}

struct ResultRow: View {
    let item: ResultItem
    let index: Int
    let selected: Bool
    let icons: IconCache

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(item.kind == .answer ? .system(size: 20, weight: .semibold) : .system(size: 14))
                    .lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if index < 9 { Text("⌘\(index + 1)").font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 12)
        .frame(height: PanelMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .padding(.horizontal, 8)
    }

    @ViewBuilder var icon: some View {
        switch item.icon {
        case .app(let url): Image(nsImage: icons.icon(for: url)).resizable()
        case .emoji(let s): Text(s).font(.system(size: 22))
        case .symbol(let name): Image(systemName: name).font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }
}

struct FooterView: View {
    @ObservedObject var state: PanelState

    var body: some View {
        HStack {
            Text("⌘, for settings")
            Spacer()
            Text(state.footerMessage ?? hint)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: PanelMetrics.footerHeight)
    }

    var hint: String {
        switch state.mode {
        case .main: return state.selectedResult?.footerHint ?? ""
        case .emoji: return state.selectedEmoji == nil ? "" : "↩ Copy   ⌘K Aliases   ⌘⇧S Skin tone"
        }
    }
}
```

- [ ] **Step 4: The controller**

`Sources/MenuCrane/PanelController.swift`:
```swift
import AppKit
import Combine
import MenuCraneCore
import SwiftUI

final class PanelController: NSObject, NSTextFieldDelegate {
    let state: PanelState
    private let panel: CranePanel
    private let field = NSTextField()
    private let performer: ActionPerformer
    private let index: AppIndex
    private let icons = IconCache()
    private var hosting: NSHostingView<AnyView>!
    private var cancellables = Set<AnyCancellable>()
    private var anchorTop: CGFloat = 0
    private var anchorX: CGFloat = 0

    var onVisibilityChange: ((Bool) -> Void)?
    var onGrab: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Emoji-mode key equivalents (⌘K, ⌘⇧S), installed by Task 15.
    var emojiKeyHandler: ((NSEvent) -> Bool)?
    /// Copy an emoji chosen in the grid, installed by Task 15.
    var activateEmoji: ((EmojiHit) -> Void)?

    init(state: PanelState, performer: ActionPerformer, index: AppIndex) {
        self.state = state
        self.performer = performer
        self.index = index
        panel = CranePanel(width: PanelMetrics.width, height: PanelMetrics.fieldHeight + PanelMetrics.footerHeight)
        super.init()

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.placeholderString = Self.mainPlaceholder
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false

        hosting = NSHostingView(rootView: makeBody())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(field)
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            field.heightAnchor.constraint(equalToConstant: 30),
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor, constant: PanelMetrics.fieldHeight),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.onResignKey = { [weak self] in self?.hide() }
        panel.keyEquivalentHandler = { [weak self] e in self?.handleKeyEquivalent(e) ?? false }
        state.$results.combineLatest(state.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)
    }

    static let mainPlaceholder = "Search apps, emoji, math, units…"
    static let emojiPlaceholder = "Search emoji…"

    /// The body view; Task 15 swaps in the emoji grid for emoji mode.
    func makeBody() -> AnyView {
        AnyView(PanelBody(state: state, icons: icons, onClick: { [weak self] i in self?.activate(index: i, alternate: false) }))
    }

    var isVisible: Bool { panel.isVisible }
    func toggle() { isVisible ? hide() : show() }

    func show() {
        state.reset()
        syncField()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        anchorTop = vf.maxY - vf.height / 3 + PanelMetrics.fieldHeight / 2
        anchorX = vf.midX - PanelMetrics.width / 2
        resize()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        onVisibilityChange?(true)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        onVisibilityChange?(false)
    }

    func resize() {
        let body: CGFloat
        if state.mode == .emoji {
            body = PanelMetrics.emojiBodyHeight
        } else {
            let rows = min(state.results.count, PanelMetrics.maxRows)
            body = rows == 0 ? 0 : CGFloat(rows) * PanelMetrics.rowHeight + 9
        }
        let h = PanelMetrics.fieldHeight + body + PanelMetrics.footerHeight
        panel.setFrame(NSRect(x: anchorX, y: anchorTop - h, width: PanelMetrics.width, height: h), display: true)
    }

    /// Put the field's text and placeholder in step with the state (after mode changes).
    func syncField() {
        field.stringValue = state.query
        field.placeholderString = state.mode == .main ? Self.mainPlaceholder : Self.emojiPlaceholder
    }

    // MARK: - Keys

    func controlTextDidChange(_ obj: Notification) {
        state.footerMessage = nil
        state.query = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let grid = state.mode == .emoji
        switch sel {
        case #selector(NSResponder.moveUp(_:)):
            grid ? state.moveGrid(dx: 0, dy: -1) : state.move(-1); return true
        case #selector(NSResponder.moveDown(_:)):
            grid ? state.moveGrid(dx: 0, dy: 1) : state.move(1); return true
        case #selector(NSResponder.moveLeft(_:)) where grid:
            state.moveGrid(dx: -1, dy: 0); return true
        case #selector(NSResponder.moveRight(_:)) where grid:
            state.moveGrid(dx: 1, dy: 0); return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection(alternate: false); return true
        case #selector(NSResponder.cancelOperation(_:)):
            switch state.escape() {
            case .close: hide()
            case .clearedQuery, .backToMain: syncField()
            }
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            if state.deleteOnEmpty() { syncField(); return true }
            return false
        default:
            return false
        }
    }

    func handleKeyEquivalent(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }
        if (e.keyCode == 36 || e.keyCode == 76) && !mods.contains(.shift) {   // ⌘↩
            activateSelection(alternate: true); return true
        }
        if e.keyCode == 43 && !mods.contains(.shift) {                          // ⌘,
            hide(); onOpenSettings?(); return true
        }
        if state.mode == .main, !mods.contains(.shift),
           let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
            activate(index: n - 1, alternate: false); return true
        }
        if state.mode == .emoji, let handler = emojiKeyHandler, handler(e) { return true }
        return false
    }

    // MARK: - Actions

    func activateSelection(alternate: Bool) {
        if state.mode == .emoji {
            if let hit = state.selectedEmoji { activateEmoji?(hit) }
            return
        }
        activate(index: state.selection, alternate: alternate)
    }

    func activate(index i: Int, alternate: Bool) {
        guard state.mode == .main, state.select(index: i), let item = state.selectedResult else { return }
        guard let action = alternate ? item.alternate : item.action else { return }
        switch action {
        case .enterEmojiMode:
            state.enterEmojiMode()
            syncField()
        case .open(let url):
            if performer.open(url, usageKey: item.usageKey) {
                onGrab?()
                hide()
            } else {
                state.footerMessage = "Couldn't open \(item.title)"
                index.rebuild()
            }
        case .reveal(let url):
            performer.reveal(url)
            hide()
        case .copy(let text):
            performer.copy(text)
            if item.kind == .emoji, let base = item.usageKey { performer.recordEmoji(base) }
            flashCopied()
        }
    }

    func flashCopied() {
        state.footerMessage = "Copied"
        onGrab?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.hide() }
    }
}
```

- [ ] **Step 5: Wire services into the app**

In `App.swift` add `import MenuCraneCore` (already present) and these properties:
```swift
    private var usage: UsageStore!
    private var aliases: AliasStore!
    private var emojiStore: EmojiStore?
    private var appIndex: AppIndex!
    private var appWatcher: FSEventsWatcher?
    private var panel: PanelController!
```
Add, and call `makeServices()` at the start of `applicationDidFinishLaunching` (before the status item):
```swift
    private func makeServices() {
        EditMenu.install()
        let dir = AppSupport.directory
        usage = UsageStore(url: dir.appending(path: "usage.json"))
        aliases = AliasStore(url: dir.appending(path: "aliases.json"))
        aliases.startWatching()
        if let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
           let data = try? Data(contentsOf: url), let store = try? EmojiStore(data: data) {
            emojiStore = store
        } else {
            log.fault("emoji.json missing from the bundle; emoji disabled")
        }
        appIndex = AppIndex()
        appWatcher = FSEventsWatcher(paths: (AppIndex.defaultRoots).map(\.path)) { [weak self] in self?.appIndex.rebuild() }
        appWatcher?.start()

        var providers: [Provider] = [
            CalculatorProvider(),
            ConverterProvider(system: { Preferences.unitSystem }),
            AppProvider(index: appIndex, usage: usage),
        ]
        if let store = emojiStore {
            providers.insert(EmojiCommandProvider(), at: 2)
            providers.append(EmojiInlineProvider(store: store, aliases: { [weak self] in self?.aliases.aliases ?? [:] },
                                                 recents: { [weak self] in self?.usage.recentEmoji ?? [] },
                                                 tone: { Preferences.skinTone }))
        }
        let state = PanelState(engine: SearchEngine(providers: providers)) { [weak self] q in
            guard let self, let store = self.emojiStore else { return [] }
            return store.search(q, aliases: self.aliases.aliases, recents: self.usage.recentEmoji)
        }
        panel = PanelController(state: state, performer: ActionPerformer(usage: usage), index: appIndex)
    }
```
Replace `openPanel()`:
```swift
    @objc func openPanel() { panel.toggle() }
```

- [ ] **Step 6: Build and verify by hand**

Run: `swift build && ./install.sh && pkill -x MenuCrane; open "$HOME/Applications/Menu Crane.app"`
With ⌥Space, check each and fix before moving on:
1. Panel appears centred, a third down the screen with the pointer; the app you were in stays frontmost (its menu bar name doesn't change).
2. `saf` → Safari first; ↩ opens it and the panel closes.
3. `2+2*3` → `= 8` top row; ↩ → `pbpaste` prints `8`; footer flashed `Copied`.
4. `72f` → `= 22.2222 °C`; ⌘↩ → `pbpaste` prints `22.2222 °C`.
5. ↑/↓, ⌃N/⌃P move; ⌘3 runs row 3.
6. Esc with text clears it; Esc again closes.
7. ⌘V pastes into the field; ⌘A selects all.
8. Clicking another window closes the panel.
9. Summon over a full-screen app (e.g. full-screen Safari): the panel appears on top. If it doesn't, change `level = .floating` to `level = .statusBar` in `CranePanel` and re-check.
10. Deleted-app path: `cp -R /System/Applications/Chess.app /tmp/Chess.app`, then in Terminal `mkdir -p ~/Applications/tmpcrane && cp -R /tmp/Chess.app ~/Applications/tmpcrane/ChessCopy.app`, wait 2 s, summon, type `chesscopy` (it shows), then `rm -rf ~/Applications/tmpcrane` and **immediately** press ↩ → footer `Couldn't open ChessCopy`; type again → it's gone.
11. The footer always reads `⌘, for settings` on the left.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: launcher panel with results list, actions and footer"
```

---

### Task 15: Emoji mode

**Files:**
- Create: `Sources/MenuCrane/EmojiViews.swift`
- Modify: `Sources/MenuCrane/PanelViews.swift` (`PanelBody`), `Sources/MenuCrane/App.swift`

**Interfaces:**
- Consumes: `PanelState` (emoji mode), `AliasStore`, `Preferences.skinTone`, `ActionPerformer`.
- Produces: `EmojiUI: ObservableObject` (`editing: Emoji?`, `tone: SkinTone`, `aliasError: String?`); SwiftUI `EmojiGridView`, `AliasEditorView`; `PanelBody` switching on `state.mode`.

- [ ] **Step 1: Views**

`Sources/MenuCrane/EmojiViews.swift`:
```swift
import MenuCraneCore
import SwiftUI

/// UI-only emoji state: the alias editor and the current skin tone.
final class EmojiUI: ObservableObject {
    @Published var editing: Emoji?
    @Published var tone: SkinTone = Preferences.skinTone
    @Published var aliasError: String?
}

struct EmojiGridView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var ui: EmojiUI
    let onBack: () -> Void
    let onPick: (EmojiHit) -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(64), spacing: 8), count: state.gridColumns) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onBack) { Text("‹ Back") }.buttonStyle(.borderless)
                Spacer()
                Text(state.selectedEmoji?.emoji.name.capitalized ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(state.emoji.enumerated()), id: \.element.id) { i, hit in
                            Text(hit.emoji.glyph(ui.tone))
                                .font(.system(size: 34))
                                .frame(width: 64, height: 52)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(i == state.selection ? Color.accentColor.opacity(0.3) : .clear))
                                .id(i)
                                .onTapGesture { onPick(hit) }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: state.selection) { proxy.scrollTo($0) }
            }
        }
        .padding(.top, 6)
        .overlay { if let e = ui.editing { AliasEditorView(emoji: e, ui: ui) } }
    }
}

struct AliasEditorView: View {
    let emoji: Emoji
    @ObservedObject var ui: EmojiUI
    @State private var newAlias = ""
    @FocusState private var focused: Bool
    /// Set by the app: current aliases for an emoji, and a saver that throws when the file is unreadable.
    static var aliasesFor: (String) -> [String] = { _ in [] }
    static var save: ([String], String) throws -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(emoji.char).font(.system(size: 40)); Text(emoji.name.capitalized).font(.headline) }
            ForEach(Self.aliasesFor(emoji.char), id: \.self) { alias in
                HStack {
                    Text(alias)
                    Spacer()
                    Button("Remove") { update(Self.aliasesFor(emoji.char).filter { $0 != alias }) }
                        .buttonStyle(.borderless)
                }
            }
            TextField("Add a name, then Return", text: $newAlias)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    update(Self.aliasesFor(emoji.char) + [newAlias])
                    newAlias = ""
                }
            if let err = ui.aliasError { Text(err).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Done") { ui.editing = nil } .keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .shadow(radius: 12)
        .onAppear { focused = true }
    }

    private func update(_ names: [String]) {
        do { try Self.save(names, emoji.char); ui.aliasError = nil }
        catch { ui.aliasError = "aliases.json can't be read, so it isn't being changed. Fix or delete it first." }
        ui.objectWillChange.send()
    }
}
```

Replace `PanelBody` in `PanelViews.swift`:
```swift
struct PanelBody: View {
    @ObservedObject var state: PanelState
    @ObservedObject var ui: EmojiUI
    let icons: IconCache
    let onClick: (Int) -> Void
    let onBack: () -> Void
    let onPick: (EmojiHit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if state.mode == .emoji {
                Divider()
                EmojiGridView(state: state, ui: ui, onBack: onBack, onPick: onPick)
            } else if !state.results.isEmpty {
                Divider()
                ResultListView(state: state, icons: icons, onClick: onClick)
            }
            FooterView(state: state)
        }
    }
}
```

- [ ] **Step 2: Controller changes**

In `PanelController`:
- add `let emojiUI = EmojiUI()`;
- replace `makeBody()`:
```swift
    func makeBody() -> AnyView {
        AnyView(PanelBody(
            state: state, ui: emojiUI, icons: icons,
            onClick: { [weak self] i in self?.activate(index: i, alternate: false) },
            onBack: { [weak self] in self?.state.backToMain(); self?.syncField(); self?.focusField() },
            onPick: { [weak self] hit in self?.activateEmoji?(hit) }))
    }

    func focusField() { panel.makeFirstResponder(field) }
```
- in `show()`, after `state.reset()`, add `emojiUI.editing = nil`.

- [ ] **Step 3: App wiring for emoji copy, ⌘K and ⌘⇧S**

At the end of `makeServices()` in `App.swift`:
```swift
        AliasEditorView.aliasesFor = { [weak self] c in self?.aliases.aliases[c] ?? [] }
        AliasEditorView.save = { [weak self] names, c in try self?.aliases.setAliases(names, for: c) }
        panel.activateEmoji = { [weak self] hit in
            guard let self else { return }
            let glyph = hit.emoji.glyph(self.panel.emojiUI.tone)
            let performer = ActionPerformer(usage: self.usage)
            performer.copy(glyph)
            performer.recordEmoji(hit.emoji.char)
            self.panel.flashCopied()
        }
        panel.emojiKeyHandler = { [weak self] e in
            guard let self else { return false }
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 40 && !mods.contains(.shift), let hit = self.panel.state.selectedEmoji {   // ⌘K
                self.panel.emojiUI.editing = hit.emoji
                return true
            }
            if e.keyCode == 1 && mods.contains(.shift) {                                                // ⌘⇧S
                let next = self.panel.emojiUI.tone.next
                self.panel.emojiUI.tone = next
                Preferences.skinTone = next
                self.panel.state.footerMessage = "Skin tone: \(next.title) \(next.swatch)"
                return true
            }
            return false
        }
        aliases.onChange = { [weak self] in self?.panel.state.refresh() }
```
In `PanelController.control(_:textView:doCommandBy:)`, Esc while the alias editor is open should close the editor, not the mode. At the top of the `cancelOperation` case add:
```swift
            if emojiUI.editing != nil { emojiUI.editing = nil; focusField(); return true }
```
And when the editor closes via Done, focus returns to the field: add to `EmojiUI`:
```swift
    var onClose: (() -> Void)?
    @Published var editing: Emoji? { didSet { if editing == nil { onClose?() } } }
```
(replacing the earlier `editing` declaration) and in `PanelController.init` after `super.init()`: `emojiUI.onClose = { [weak self] in self?.focusField() }`.

- [ ] **Step 4: Build and verify by hand**

Run: `swift build && ./install.sh && pkill -x MenuCrane; open "$HOME/Applications/Menu Crane.app"`
Check with ⌥Space:
1. `e` ↩ and `emoji` ↩ both open the grid; the field placeholder reads `Search emoji…`; recents come first.
2. Arrows move around the grid; ↩ copies (`pbpaste`), panel closes; the emoji is now first in recents.
3. `fingers crossed` and `crossed fingers` both put 🤞 first.
4. Esc with text typed returns to the main list; ⌫ on an empty emoji field also does; `‹ Back` does.
5. ⌘K on 👓 → add `nerd` → Done; `nerd` now puts 👓 first; `~/Library/Application Support/MenuCrane/aliases.json` contains it.
6. Break the file (`echo '{oops' > ~/Library/Application\ Support/MenuCrane/aliases.json`), ⌘K → adding shows the red error; file unchanged; restore it.
7. ⌘⇧S cycles skin tone; 👍 in the grid changes; copying gives the toned glyph; footer shows the tone.
8. Paste a copied emoji into Messages, Slack and Terminal — it arrives intact.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: emoji grid with aliases editor and skin tones"
```

---

### Task 16: Settings and Emoji Aliases windows

**Files:**
- Create: `Sources/MenuCraneCore/AliasTable.swift`, `Sources/MenuCrane/SettingsWindow.swift`, `Sources/MenuCrane/AliasesWindow.swift`
- Modify: `Sources/MenuCrane/App.swift`
- Test: `Tests/MenuCraneCoreTests/AliasTableTests.swift`

**Interfaces:**
- Consumes: `EmojiStore`, `AliasStore`, `UsageStore`, `HotkeySettings`, `TriggerText`, HotkeyKit `TriggerRecorder`, StatusItemKit `LoginItem`.
- Produces: `struct AliasRow: Identifiable, Equatable { id, char, name, group, aliases: [String]; aliasText }`; `enum AliasTable { static func rows(store:aliases:recents:search:group:onlyWithAliases:onlyRecent:) -> [AliasRow] }`; `SettingsWindowController.show()`; `AliasesWindowController.show()`.

- [ ] **Step 1: Write the failing filter tests**

`Tests/MenuCraneCoreTests/AliasTableTests.swift`:
```swift
import XCTest
@testable import MenuCraneCore

final class AliasTableTests: XCTestCase {
    var store: EmojiStore!
    override func setUpWithError() throws { store = try Fixtures.emojiStore() }

    func rows(search: String = "", group: String? = nil, withAliases: Bool = false, recent: Bool = false) -> [AliasRow] {
        AliasTable.rows(store: store, aliases: ["👓": ["nerd", "specs"]], recents: ["🎉"],
                        search: search, group: group, onlyWithAliases: withAliases, onlyRecent: recent)
    }

    func testAllRowsByDefault() {
        XCTAssertEqual(rows().count, store.all.count)
        XCTAssertEqual(rows().first { $0.char == "👓" }?.aliasText, "nerd, specs")
    }

    func testSearchUsesTheEmojiMatcher() {
        XCTAssertEqual(rows(search: "crossed fingers").first?.char, "🤞")
        XCTAssertEqual(rows(search: "specs").first?.char, "👓")
    }

    func testFilters() {
        XCTAssertEqual(rows(withAliases: true).map(\.char), ["👓"])
        XCTAssertEqual(rows(recent: true).map(\.char), ["🎉"])
        XCTAssertTrue(rows(group: "Flags").allSatisfy { $0.group == "Flags" })
        XCTAssertFalse(rows(group: "Flags").isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AliasTableTests`
Expected: compile error — `cannot find 'AliasTable' in scope`.

- [ ] **Step 3: Implement AliasTable**

`Sources/MenuCraneCore/AliasTable.swift`:
```swift
import Foundation

public struct AliasRow: Identifiable, Equatable, Sendable {
    public var id: String { char }
    public let char: String
    public let name: String
    public let group: String
    public let aliases: [String]
    public var aliasText: String { aliases.joined(separator: ", ") }
}

public enum AliasTable {
    /// Rows for the Emoji Aliases window: ranked by `search` when given (same matcher as the
    /// picker), else Unicode order; then narrowed by group and the two toggles.
    public static func rows(store: EmojiStore, aliases: [String: [String]], recents: [String],
                            search: String, group: String?, onlyWithAliases: Bool, onlyRecent: Bool) -> [AliasRow] {
        let q = Query(search)
        let ordered: [Emoji] = q.isEmpty ? store.all : store.search(q, aliases: aliases, recents: []).map(\.emoji)
        let recentSet = Set(recents)
        return ordered
            .filter { group == nil || $0.group == group }
            .filter { !onlyWithAliases || !(aliases[$0.char] ?? []).isEmpty }
            .filter { !onlyRecent || recentSet.contains($0.char) }
            .map { AliasRow(char: $0.char, name: $0.name, group: $0.group, aliases: aliases[$0.char] ?? []) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AliasTableTests`
Expected: all 3 tests PASS.

- [ ] **Step 5: The Emoji Aliases window**

`Sources/MenuCrane/AliasesWindow.swift`:
```swift
import AppKit
import MenuCraneCore
import SwiftUI

final class AliasesModel: ObservableObject {
    let store: EmojiStore
    let aliasStore: AliasStore
    let usage: UsageStore
    @Published var search = ""
    @Published var group: String? = nil
    @Published var onlyWithAliases = false
    @Published var onlyRecent = false
    @Published var sortOrder = [KeyPathComparator(\AliasRow.name)]
    @Published var saveError: String?

    init(store: EmojiStore, aliasStore: AliasStore, usage: UsageStore) {
        self.store = store; self.aliasStore = aliasStore; self.usage = usage
    }

    var rows: [AliasRow] {
        let r = AliasTable.rows(store: store, aliases: aliasStore.aliases, recents: usage.recentEmoji,
                                search: search, group: group, onlyWithAliases: onlyWithAliases, onlyRecent: onlyRecent)
        return search.isEmpty ? r.sorted(using: sortOrder) : r   // a search keeps its ranking
    }

    func setAliases(_ text: String, for char: String) {
        do {
            try aliasStore.setAliases(text.split(separator: ",").map(String.init), for: char)
            saveError = nil
        } catch {
            saveError = "aliases.json can't be read, so it isn't being changed. Fix or delete it first."
        }
        objectWillChange.send()
    }
}

struct AliasesView: View {
    @ObservedObject var model: AliasesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = model.aliasStore.loadError ?? model.saveError {
                Text(err).foregroundStyle(.red).font(.callout)
            }
            HStack {
                TextField("Search emoji", text: $model.search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Category", selection: $model.group) {
                    Text("All").tag(String?.none)
                    ForEach(model.store.groups, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 240)
                Toggle("Has aliases", isOn: $model.onlyWithAliases)
                Toggle("Recently used", isOn: $model.onlyRecent)
            }
            Table(model.rows, sortOrder: $model.sortOrder) {
                TableColumn("Emoji", value: \.char) { Text($0.char).font(.system(size: 20)) }.width(50)
                TableColumn("Name", value: \.name)
                TableColumn("Category", value: \.group).width(150)
                TableColumn("Aliases", value: \.aliasText) { row in
                    AliasCell(text: row.aliasText) { model.setAliases($0, for: row.char) }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 480)
    }
}

/// Edits in place; saves on Return or when focus leaves.
struct AliasCell: View {
    @State var text: String
    let commit: (String) -> Void
    init(text: String, commit: @escaping (String) -> Void) { _text = State(initialValue: text); self.commit = commit }
    var body: some View {
        TextField("add names, comma-separated", text: $text).onSubmit { commit(text) }
    }
}

final class AliasesWindowController {
    private var window: NSWindow?
    private let model: AliasesModel
    init(model: AliasesModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AliasesView(model: model)))
            w.title = "Emoji Aliases"
            w.setContentSize(NSSize(width: 820, height: 560))
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 6: The Settings window**

`Sources/MenuCrane/SettingsWindow.swift`:
```swift
import AppKit
import HotkeyKit
import MenuCraneCore
import StatusItemKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var trigger: Trigger
    @Published var hotkeyError: String?
    @Published var recording = false
    @Published var unitSystem = Preferences.unitSystem { didSet { Preferences.unitSystem = unitSystem } }
    @Published var tone = Preferences.skinTone { didSet { Preferences.skinTone = tone; onTone?(tone) } }
    @Published var loginEnabled = LoginItem.isEnabled
    let onHotkey: (Trigger) -> String?
    let openAliases: () -> Void
    var onTone: ((SkinTone) -> Void)?
    private let recorder = TriggerRecorder()

    init(trigger: Trigger, hotkeyError: String?, onHotkey: @escaping (Trigger) -> String?, openAliases: @escaping () -> Void) {
        self.trigger = trigger; self.hotkeyError = hotkeyError; self.onHotkey = onHotkey; self.openAliases = openAliases
    }

    func record() {
        recording = true
        recorder.start { [weak self] t in
            guard let self else { return }
            self.recording = false
            guard !t.modifiers.isEmpty else { self.hotkeyError = "Add at least one modifier (⌘, ⌥, ⌃ or ⇧)."; return }
            self.trigger = t
            self.hotkeyError = self.onHotkey(t)
        }
    }

    func setLogin(_ on: Bool) {
        do { try LoginItem.setEnabled(on) } catch { log.error("login item: \(error.localizedDescription, privacy: .public)") }
        loginEnabled = LoginItem.isEnabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            LabeledContent("Hotkey") {
                HStack {
                    Text(model.recording ? "Press a shortcut…" : TriggerText.describe(model.trigger)).monospaced()
                    Button("Record…") { model.record() }.disabled(model.recording)
                }
            }
            if let err = model.hotkeyError { Text(err).foregroundStyle(.red).font(.callout) }
            Picker("Units", selection: $model.unitSystem) {
                ForEach(UnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Emoji skin tone", selection: $model.tone) {
                ForEach(SkinTone.allCases, id: \.self) { Text("\($0.swatch)  \($0.title)").tag($0) }
            }
            LabeledContent("Emoji aliases") { Button("Edit Emoji Aliases…") { model.openAliases() } }
            Toggle("Start at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 8)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    let model: SettingsModel
    init(model: SettingsModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Menu Crane Settings"
            w.styleMask.remove(.resizable)
            w.isReleasedWhenClosed = false
            window = w
        }
        model.loginEnabled = LoginItem.isEnabled
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 7: Wire the windows**

In `App.swift` add properties:
```swift
    private var settings: SettingsWindowController!
    private var aliasesWindow: AliasesWindowController?
```
At the end of `makeServices()`:
```swift
        if let store = emojiStore {
            aliasesWindow = AliasesWindowController(model: AliasesModel(store: store, aliasStore: aliases, usage: usage))
        }
        let settingsModel = SettingsModel(
            trigger: trigger, hotkeyError: nil,
            onHotkey: { [weak self] t in
                guard let self else { return nil }
                self.trigger = t
                HotkeySettings.save(t, to: .standard)
                return self.hotkey.register(t)
            },
            openAliases: { [weak self] in self?.aliasesWindow?.show() })
        settingsModel.onTone = { [weak self] t in self?.panel.emojiUI.tone = t }
        settings = SettingsWindowController(model: settingsModel)
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
```
Add:
```swift
    @objc func openSettings() {
        settings.model.hotkeyError = hotkey.failure
        settings.show()
    }
```
In `buildMenu(_:)`, after the `Open Menu Crane` row add:
```swift
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
```

- [ ] **Step 8: Build and verify by hand**

Run: `swift test && swift build && ./install.sh && pkill -x MenuCrane; open "$HOME/Applications/Menu Crane.app"`
1. ⌘, in the panel and `Settings…` in the menu both open Settings.
2. Record ⌃⌥Space → it works immediately; record back ⌥Space. A bare key without modifiers is refused with the message.
3. Units → Metric: `100 km/h` shows nothing, `100 mph` shows km/h. Back to US Imperial.
4. Skin tone picker changes the grid.
5. Edit Emoji Aliases…: search `specs`, category filter, both toggles and column sorting work; editing an Aliases cell and pressing Return saves (visible in the panel's emoji search).
6. Start at Login toggle matches the menu's checkmark.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: settings and emoji aliases windows"
```

---

### Task 17: Mendoza's moods and the Icon menu

**Files:**
- Modify: `Sources/MenuCrane/App.swift`

**Interfaces:**
- Consumes: `CharacterIcon.menuCrane(state:)`, `PanelController.onVisibilityChange` / `onGrab`, `PanelState.isMiss`, `Preferences.iconStyle`.
- Produces: final menu layout (spec §5): [⚠ warning] · Open Menu Crane · Settings… · — · Start at Login · Icon ▸ (Crane / Dot) · — · Version · Quit Menu Crane.

- [ ] **Step 1: Glyph state**

Add to `App`:
```swift
    private var mood = CharacterIcon.CraneState.idle
    private var grabbedUntil = Date.distantPast

    private func setMood(_ m: CharacterIcon.CraneState) {
        mood = m
        refreshIcon()
    }

    private func refreshIcon() {
        if Preferences.iconStyle == "dot" {
            status.setIcon(Self.dot)
        } else {
            status.setIcon(CharacterIcon.menuCrane(state: mood))
        }
    }

    /// A plain grey dot for people who'd rather not have the crane.
    static let dot: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 7, height: 7)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()

    private func wireMoods() {
        panel.onVisibilityChange = { [weak self] visible in
            guard let self, Date() >= self.grabbedUntil else { return }
            self.setMood(visible ? .searching : .idle)
        }
        panel.onGrab = { [weak self] in
            guard let self else { return }
            self.grabbedUntil = Date().addingTimeInterval(0.5)
            self.setMood(.grabbed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.setMood(self.panel.isVisible ? .searching : .idle)
            }
        }
        panel.state.$results.combineLatest(panel.state.$emoji)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible, Date() >= self.grabbedUntil else { return }
                self.setMood(self.panel.state.isMiss ? .miss : .searching)
            }
            .store(in: &cancellables)
    }
```
Add `import Combine` and `private var cancellables = Set<AnyCancellable>()`. In `applicationDidFinishLaunching`, replace `status.setIcon(CharacterIcon.menuCrane(state: .idle))` with `refreshIcon()` and call `wireMoods()` after it.

- [ ] **Step 2: Final menu**

Replace `buildMenu(_:)`:
```swift
    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if let failure = hotkey.failure {
            let warn = NSMenuItem(title: "⚠ Hotkey unavailable — \(failure)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(menuItem("Open Menu Crane (\(TriggerText.describe(trigger)))", #selector(openPanel)))
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let login = menuItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, style) in [("Crane", "crane"), ("Dot", "dot")] {
            let item = menuItem(title, #selector(chooseIcon(_:)))
            item.representedObject = style
            item.state = Preferences.iconStyle == style ? .on : .off
            sub.addItem(item)
        }
        icon.submenu = sub
        menu.addItem(icon)
        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(menuItem("Quit Menu Crane", #selector(quit), key: "q"))
    }

    @objc private func chooseIcon(_ sender: NSMenuItem) {
        Preferences.iconStyle = sender.representedObject as? String ?? "crane"
        refreshIcon()
    }
```

- [ ] **Step 3: Build and verify by hand**

Run: `swift build && ./install.sh && pkill -x MenuCrane; open "$HOME/Applications/Menu Crane.app"`
(If Barn hides the item, reveal it or run `~/Code/menubar-barn/scripts/verify-menubar.sh`.)
1. Idle: bucket closed, eyes forward.
2. Panel open: bucket opens, eyes look down.
3. Type `qqqzzz`: sweat drop, puzzled eyes, empty open bucket.
4. Copy something: happy eyes and closed bucket for half a second, then idle.
5. Icon ▸ Dot shows the dot; Icon ▸ Crane brings Mendoza back; the choice survives a relaunch.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: Mendoza's moods in the menu bar and the Icon menu"
```

---

### Task 18: Artwork, docs, site and release

**Files:**
- Create: `scripts/make-icon.sh`, `Resources/bundle/AppIcon.icns`, `CHANGELOG.md`, `.github/workflows/release.yml`; Modify: `README.md` (stub → full), `docs/menubar-icon.png` (from render-glyphs)
- Modify (site repo): `art/prompts.json`, `site/img/mascots/menu-crane.png`, `site/index.html`, `site/apps/menu-crane/index.html`
- Modify: `~/.claude/CLAUDE.md` (app list)

- [ ] **Step 1: App icon**

`scripts/make-icon.sh` (MIT SPDX header, then):
```bash
# Build Resources/bundle/AppIcon.icns from Mendoza's 1024 px idle image.
set -euo pipefail
cd "$(dirname "$0")/.."
src=art/mascot/mendoza-idle-1024.png
set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
for s in 16 32 128 256 512; do
  sips -z $s $s "$src" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$src" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/bundle/AppIcon.icns
echo "wrote Resources/bundle/AppIcon.icns"
```
Run: `chmod +x scripts/make-icon.sh && scripts/make-icon.sh && ./install.sh`
Expected: Finder shows Mendoza as `Menu Crane.app`'s icon (`qlmanage -t -s 256 "build/Menu Crane.app" -o /tmp` then Read the PNG).

- [ ] **Step 2: README**

`README.md` sections, in this order (follow `~/Code/keylight-menubar/README.md` for tone and layout):
1. `# Menu Crane` · the mascot image (`art/mascot/mendoza-idle.png`, 160 px) · `**Version 1.0.0** · [Changelog](https://github.com/nicholaspsmith/menu-crane/releases)`.
2. One paragraph: a ⌘Space launcher for apps, math, unit conversions and emoji — what Nick used Raycast for, and nothing else.
3. **Using it** — the key table: ⌘Space, ↑/↓ ⌃N/⌃P, ↩, ⌘↩, ⌘1–9, Esc, ⌘,; emoji mode (`e`/`emoji` ↩, ⌘K aliases, ⌘⇧S skin tone, Esc/⌫/‹ Back); math operators `+ - * / x`; conversion examples and the US Imperial / Metric rule.
4. **The menu-bar crane** — `docs/menubar-icon.png` and what each state means.
5. **Why not a Spotlight extension?** — spec §1's paragraph.
6. **Install** — `./install.sh`; needs StatusItemKit and HotkeyKit cloned beside it; no permissions needed.
7. **Files** — `~/Library/Application Support/MenuCrane/aliases.json` (hand-editable) and `usage.json`.
8. **Manual checklist** — spec §8's list.
9. **Updating emoji** — `scripts/update-emoji-data.sh` with `EMOJI_VERSION` / `CLDR_TAG`.
10. License (MIT).

- [ ] **Step 3: Changelog and release workflow**

`CHANGELOG.md`: copy the header paragraph from `~/Code/keylight-menubar/CHANGELOG.md` (the "Every push to `main` is a release…" text), then:
```markdown
## [1.0.0] - YYYY-MM-DD

First release: Menu Crane replaces Raycast for launching apps, arithmetic, unit conversions and emoji.

- ⌘Space opens a search panel over any app, including full-screen ones.
- Apps rank by how well they match and how often you open them.
- Math with `+ - * / x` and parentheses; ↩ copies the answer.
- Conversions for temperature, mass, volume, length, speed and acceleration, with a US Imperial / Metric setting for bare values.
- Emoji search in any word order, your own aliases, recents first, and a default skin tone.
- Mendoza the crane in the menu bar opens his bucket while you search and snaps it shut when you copy.
```
`.github/workflows/release.yml`: `cp ~/Code/keylight-menubar/.github/workflows/release.yml .github/workflows/release.yml`.
Copy the glyph strip: `cp ~/Code/widgets.nicksmith.software/art/glyphs/build/states-menu-crane.png docs/menubar-icon.png`.
Commit: `git add -A && git commit -m "docs: README, changelog, app icon and release workflow"`.

- [ ] **Step 4: Site entry (local commit only)**

In `~/Code/widgets.nicksmith.software`:
1. Add to `art/prompts.json` `mascots`: `{"id": "menu-crane", "subject": "Mendoza Crane, the Menu Crane: a goofy red-crowned crane in the style of Matt Groening, side-on head and neck, huge touching eyes, long tan beak with a small yellow clamshell grab bucket hanging from a ring near its tip"}` and copy the art: `cp ~/Code/menu-crane/art/mascot/raw/mendoza-idle-raw.png art/raw/menu-crane.png`.
2. `sips -z 256 256 ~/Code/menu-crane/art/mascot/mendoza-idle.png --out site/img/mascots/menu-crane.png`.
3. In `site/index.html`, add a card to the `grid` in the same shape as the Homestead card: `href="apps/menu-crane/"`, `data-repo="https://github.com/nicholaspsmith/menu-crane"`, mascot `img/mascots/menu-crane.png`, `<h3>Menu Crane</h3>` with the `StatusItemKit` chip, glyph `img/glyphs/menu-crane.png` with alt text describing the four states, a one-line in-bar caption ("Mendoza opens his bucket while you search, snaps it shut when you copy, and sweats when nothing matches."), and a paragraph summarising the launcher. Omit the `shot` div until a panel capture exists.
4. `cp -R site/apps/homestead site/apps/menu-crane` and rewrite its text, images and repo link for Menu Crane.
5. `git add -A && git commit -m "site: Menu Crane"`. **Do not deploy** — deployment is Step 6.

- [ ] **Step 5: Update Nick's CLAUDE.md app list**

In `~/.claude/CLAUDE.md`, in the StatusItemKit paragraph: change "Eleven run as standalone" → "Twelve run as standalone", add `` `Menu Crane.app` (`~/Code/menu-crane`) `` to the list, and add one sentence: "**Menu Crane** replaced Raycast (⌘Space launcher: apps, math, conversions, emoji with aliases); its glyph is Mendoza the crane (`CharacterIcon.menuCrane`)." Also update "the twelve above + StatusItemKit" in the release rule to "the thirteen above".

- [ ] **Step 6: Publish — ASK NICK FIRST**

Stop and ask Nick to confirm each of these outward-facing steps before running it:
1. Push StatusItemKit (release 0.9.0): `cd ~/Code/StatusItemKit && git switch main && git merge --ff-only feature/menu-crane-glyph && git push`.
2. (The public repo already exists.)
3. Arm the release rule: `~/Code/StatusItemKit/scripts/release/adopt.sh menu-crane` (sets the pre-push hook and branch protection; it creates nothing that isn't already committed).
4. Delete the local dev tag and push (this is release v1.0.0): `git tag -d v0.0.0-dev && git push origin main`.
5. After CI tags it: `git pull --tags && ./install.sh` — the menu's Version row reads `1.0.0`.
6. Push the site repo and deploy: `cd ~/Code/widgets.nicksmith.software && git push && npm run deploy`.

- [ ] **Step 7: Verify**

Run: `gh release view v1.0.0 --repo nicholaspsmith/menu-crane` (notes = the changelog section) and open https://widgets.nicksmith.software to see the card.

---

### Task 19: Cutover from Raycast (with Nick)

- [ ] **Step 1: Hand ⌘Space to Menu Crane**

With Nick: quit Raycast (`osascript -e 'quit app "Raycast"'`) and turn off its launch at login (Raycast Settings ▸ General ▸ Launch Raycast at login, off). Then remove the development hotkey so the default applies:
```bash
defaults delete com.nicholaspsmith.MenuCrane HotkeyKeyCode
defaults delete com.nicholaspsmith.MenuCrane HotkeyModifiers
pkill -x MenuCrane; open "$HOME/Applications/Menu Crane.app"
```
Expected: the menu shows `Open Menu Crane (⌘Space)` with no warning row, and ⌘Space opens the panel.

- [ ] **Step 2: Run the README's manual checklist once more with ⌘Space.**

- [ ] **Step 3: Record the soak**

Save a project memory (`menu-crane-raycast-soak.md`): Raycast quit and kept installed from the cutover date; uninstall it one week later if nothing was missed (`brew uninstall --cask raycast` if it came from Homebrew, else move `/Applications/Raycast.app` to the Trash and remove `com.raycast.macos` prefs), after asking Nick. Add its line to `MEMORY.md`.
