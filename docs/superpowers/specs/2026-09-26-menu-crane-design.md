# Menu Crane — design

**Date:** 2026-09-26 · **Status:** approved design, awaiting spec review · **Suite:** Menubarn

Menu Crane is a keyboard launcher that replaces Raycast for the handful of things
Nick actually uses it for. Its mascot is **Mendoza Crane, the Menu Crane**: a goofy
red-crowned crane with a clamshell grab bucket hanging from his beak.

## 1. Intent

**Outcome:** uninstall Raycast without missing it.

**What Nick uses Raycast for (in scope):**

1. Launching applications quickly.
2. Finding emoji (Apple's picker is poor; Raycast's is good).
3. Simple arithmetic: `+ - * /`.
4. Unit conversions: °F↔°C, fl oz↔pt, lb↔kg, speed, acceleration, …

**Later phases (not v1):**

- **v1.1 — file search.** Nice to have; Spotlight and Raycast both rank files badly.
- **v2.0 — clipboard manager.** Its own spec. Lives inside Menu Crane (decided),
  reusing the panel, matcher and paste-back.

**Out of scope, deliberately:** window management (a separate app or part of
Monitor Lizard), snippets / text expansion (macOS Text Replacements covers it),
quicklinks, AI, extensions store, everything else Raycast ships.

**Success criteria:**

- ⌘Space → panel visible and focused with no perceptible lag.
- Every keystroke re-ranks all results within 5 ms.
- Emoji search finds 🤞 from `fingers crossed`, `crossed fingers`, `cross fing` or `luck`,
  and finds 🤓/👓 from a user-added alias such as `nerd`.
- Raycast stays quit for a one-week soak, then is uninstalled.

**Why not a Spotlight extension:** macOS has no third-party hook for Spotlight's
result list. `.mdimporter`s only index file metadata; App Intents (Tahoe) can
surface actions but cannot render custom rows like an emoji grid or live math.

## 2. Identity

| Thing | Value |
|---|---|
| App name | Menu Crane (`Menu Crane.app`) |
| Mascot | Mendoza Crane, the Menu Crane |
| Bundle id | `com.nicholaspsmith.MenuCrane` |
| Repo | `~/Code/menu-crane` (public: github.com/nicholaspsmith/menu-crane) |
| Install | built `.app` symlinked into `~/Applications`, like every Menubarn app |
| Log subsystem | `com.nicholaspsmith.MenuCrane` |
| Minimum macOS | 13 (same as the other Menubarn apps) |

## 3. Architecture

Chosen approach: **AppKit `NSPanel` hosting SwiftUI views.** AppKit owns what SwiftUI
can't do reliably (non-activating floating panel above full-screen apps, key-event
routing before the text field consumes it, returning focus to the previous app);
SwiftUI draws the result list and emoji grid. Rejected: pure AppKit (roughly twice the
UI code for no user-visible gain unless SwiftUI stutters, which we check early) and an
`NSMenu` UI (a menu cannot reliably host a focused text field).

SwiftPM package, same shape as KeyLight:

```
menu-crane/
  Package.swift              # deps: ../StatusItemKit, ../HotkeyKit (Trigger types + recorder only in v1)
  Sources/MenuCraneCore/     # no UI; unit-tested
  Sources/MenuCrane/         # app target
  Tests/MenuCraneCoreTests/
  Resources/bundle/AppIcon.icns
  Resources/emoji/           # generated emoji data (see §4.6)
  scripts/                   # make-app.sh, update-emoji-data.sh
  art/                       # mascot images + the scripts that made them
```

### 3.1 `MenuCraneCore`

**`Provider` protocol.** `func results(for query: Query) -> [ResultItem]`. A
`ResultItem` has a title, subtitle, icon, score and a default action (`.open(URL)`,
`.copy(String)`, `.enterMode(Mode)`) plus an optional alternate action (⌘↩). The main
list merges every provider's results by score. Files (v1.1) and Clipboard (v2) are new
providers; the panel does not change for them.

**`AppIndex`.**
- Scans `/Applications`, `/System/Applications` (including `Utilities`),
  `/System/Library/CoreServices/Finder.app` and `~/Applications`.
- Resolves symlinks (the Menubarn apps live in `~/Applications` as symlinks) and
  de-duplicates by bundle id.
- An FSEvents watcher on those folders triggers a re-index when apps are
  installed or removed.
- Records launch count and last-launched date per bundle id (persisted in
  `usage.json`) for frecency ranking.

**`Matcher`.** One scorer shared by every provider. Query words match
independently of order. Per word, best match wins: prefix of a word > acronym
(`vsc` → Visual Studio Code) > in-order subsequence. A candidate matches only if
every query word matches somewhere. Frecency adds a boost for apps; recent use
adds one for emoji.

**`Calculator`.** Hand-written recursive-descent parser. Operators `+ - * /`
and `x` as a synonym for `*` (no `×`/`÷`). Parentheses, decimals, leading minus,
standard precedence. Invalid input, division by zero or overflow → no result (never
an error row, never a crash). Not `NSExpression`.

**`Converter`.** Parses `<number> <unit> [to|in|as] <unit>` and bare `<number><unit>`.
Backed by Foundation `Measurement` / `UnitConverter`. Dimensions:

| Dimension | Units (with aliases) |
|---|---|
| Temperature | °F `f` `°f` `fahrenheit`, °C `c` `°c` `celsius`, K `kelvin` |
| Mass | lb `lb` `lbs` `pound(s)`, oz, kg, g, st |
| Volume | fl oz `floz` `fl oz`, cup, pt `pt` `pint(s)`, qt, gal, tsp, tbsp, mL, L |
| Length | in, ft, yd, mi, mm, cm, m, km |
| Speed | mph, km/h `kph`, m/s, ft/s `fps`, knots `kn` |
| Acceleration | m/s², ft/s², g |

- **Unit system setting: US Imperial (default) / Metric.** Named so "UK Imperial"
  can be added later. US Imperial means US customary (16 fl oz per pint).
- Explicit `to <unit>` always wins.
- Bare values: in US Imperial, a metric value converts to its US counterpart and a
  US value that has a natural metric pairing converts to metric (`72f` → °C,
  `100 km/h` → mph). In Metric, US values convert to metric; bare metric values get
  no suggestion.
- Results rounded to at most 6 significant figures.

**`EmojiStore`.**
- Data: Unicode CLDR English annotations (names + keywords) and `emoji-test.txt`
  (ordering, groups, skin-tone variants), converted to a bundled JSON by
  `scripts/update-emoji-data.sh`. Re-run when Unicode ships a new version.
- Merges user aliases from `aliases.json`; an alias match outranks a CLDR match.
- Tracks recently used emoji (in `usage.json`).
- Default skin tone setting applies to emoji that support it.

### 3.2 App target

- **`CranePanel`** — `NSPanel` subclass: non-activating, floats above full-screen
  apps, hides on resign-key (click elsewhere), restores focus to the previously
  frontmost app on close.
- **`SearchField`** — `NSTextField` subclass that intercepts ↑ ↓ ↩ ⌘↩ ⎋ ⌘1…9 ⌘, ⌘K
  before the field editor sees them.
- **SwiftUI views** — `ResultList`, `EmojiGrid` (`LazyVGrid`), footer.
- **`HotkeyService`** — registers the global hotkey via Carbon
  `RegisterEventHotKey` (no Accessibility permission needed), keyed by a HotkeyKit
  `Trigger`. HotkeyKit's `HotkeyTap` (a `CGEventTap`) is not used in v1 because it
  requires Accessibility; only its `Trigger` model and `TriggerRecorder` (a local
  `NSEvent` monitor, no permission) are.
- **`AliasesWindow`**, **`SettingsWindow`** — separate windows (§5).
- **Status item** — StatusItemKit `StatusItemController`, glyph
  `CharacterIcon.menuCrane(state:)`, runs a `YieldClient` for Barn.

### 3.3 Data flow

Every keystroke queries all providers synchronously on the main thread (everything
is in memory), merges by score and redraws. When the query parses as math or a
conversion, that result is pinned as the top row. `e` or `emoji` pins the **Emoji**
command as the top row.

## 4. Behaviour

### 4.1 Summon and dismiss

- Default hotkey **⌘Space** (Spotlight's ⌘Space is already disabled on this Mac;
  Raycast must be quit). Changeable in Settings.
- The panel is draggable by its background, and opens where it was last dragged
  to (`PanelX`/`PanelTop` in `UserDefaults`) as long as the panel — 680 pt wide,
  at least field + footer tall, hanging from that top-left — still overlaps a
  connected screen's visible frame. Otherwise, or when nothing has been saved,
  it opens horizontally centred, about one third from the top, on the screen
  containing the mouse pointer. **menu ▸ Reset Panel Position** forgets the saved
  position. Empty field, no list until you type.
- ⌘Space again, Esc on an empty query, ⌘W, or clicking elsewhere closes it. Focus
  returns to the app you were in.
- The Settings and Emoji Aliases windows close with ⌘W (a hidden File ▸ Close
  menu item) or Esc.

### 4.2 Look

- One rounded `NSVisualEffectView` panel, ~680 pt wide; search field ~56 pt tall.
- Rows: icon · title · dim subtitle. The list grows to 8 rows, then scrolls.
- Follows light/dark mode.
- **Footer** (thin, small grey text): left — `⌘, for settings`; right — the selected
  row's actions, e.g. `↩ Open`, `↩ Copy`, `⌘↩ Copy with unit`.

### 4.3 Main list

- Results: apps, math, conversions, and emoji whose name, keyword or alias
  matches closely, in one list (files come later behind a prefix).
- Keys: ↑/↓ and ⌃P/⌃N move; ↩ runs the default action; ⌘1…⌘9 run that row;
  ⎋ clears the query, then closes; ⌘↩ on an app reveals it in Finder;
  ⌘, opens Settings.
- **Math/conversion row** shows the answer large (`= 22.22 °C`). ↩ copies the bare
  number (`22.22`); ⌘↩ copies with the unit (`22.22 °C`).
- After any copy the panel flashes "Copied" (~300 ms) and closes.

### 4.4 Emoji mode

- Entered with `emoji` + ↩ or `e` + ↩ (the Emoji command is pinned to the top
  for those queries).
- Grid with its own search field and a "‹ Back" chip. Empty search shows recently
  used first, then all emoji by Unicode group.
- Arrows move through the grid; ↩ or click **copies** the emoji to the clipboard
  and closes the panel (no paste-back in v1, so no Accessibility permission).
- ⎋ returns to the main list (even with text in the emoji search). ⌫ on an empty
  field also returns.
- ⌘K on the selected emoji opens a small inline alias editor (add/remove names).
- ⌘⇧S picks the default skin tone.
- Opens fresh (empty search, recents first) each time it is entered.

### 4.5 Search semantics for emoji

A query matches an emoji when every query word is a prefix of some word in its CLDR
name, CLDR keywords or user aliases, **in any order**. So `fingers crossed`,
`crossed fingers`, `cross fing` and `luck` all find 🤞. Alias hits rank above CLDR
hits; recency breaks ties.

### 4.6 Emoji data build

`scripts/update-emoji-data.sh` downloads the CLDR `annotations/en.xml`,
`annotationsDerived/en.xml` and `emoji-test.txt` for a pinned Unicode version and
writes `Resources/emoji/emoji.json` (`[{char, name, keywords, group, subgroup,
skinTones}]`). The generated file is committed; the app never fetches at runtime.

## 5. Settings, windows and stored data

**Settings window** (⌘, from the panel or the menu):

- Hotkey — recorded with HotkeyKit's `TriggerRecorder`, registered via Carbon; shows a red conflict warning when registration fails.
- Units — US Imperial / Metric.
- Emoji default skin tone.
- "Edit Emoji Aliases…" — opens the Aliases window.
- Start at Login (SMAppService).

**Emoji Aliases window** (its own window, not a Settings table):

- Search field (same matcher as the picker).
- Filters: category (Unicode group), "Has aliases", "Recently used".
- Sortable columns: Emoji · Name · Category · Aliases.
- Aliases edited inline; changes save immediately.

**Menu** (standard Menubarn layout): Open Menu Crane (⌘Space) · Settings… ·
Start at Login · Icon ▸ (Crane / Dot) · Version · Quit. The icon is optional to keep
visible; hiding it in Barn is expected, since the hotkey is the real UI.

**Stored data** in `~/Library/Application Support/MenuCrane/`:

- `aliases.json` — `{ "🤓": ["nerd"], … }`. Hand-editable; watched and reloaded live.
- `usage.json` — app launch counts/dates, recent emoji.
- Settings in `UserDefaults`.
- All writes are atomic (temp file + rename).

## 6. Artwork

**Mascot:** Mendoza, generated with the Menubarn Gemini pipeline and cleaned up
(tile border removed, background transparent, enlarged to fill the square).
Committed in `art/mascot/`:

| File | State | Used for |
|---|---|---|
| `mendoza-idle(-1024).png` | idle | `AppIcon.icns`, README, site |
| `mendoza-open.png` | searching (panel open) | glyph reference |
| `mendoza-grab.png` | got it (copied / launched) | glyph reference |
| `mendoza-miss.png` | no results | glyph reference |
| `mendoza-clip.png` | clipboard captured | v2 clipboard-mode icon |

`art/scripts/` holds the generation and cleanup scripts as a record (they were run
from a scratch directory and reference those paths). Add `menu-crane` to the site's
`art/prompts.json` so the pipeline knows the mascot.

**Menu-bar glyph:** hand-drawn in StatusItemKit as
`CharacterIcon.menuCrane(state:)` with `.idle`, `.searching`, `.grabbed`, `.miss`
(`.clipboard` in v2). Traced from Mendoza's side-on head: red cap, big touching
eyes, beak to the right, bucket hanging bottom-right, all enlarged to fill 18 pt.
Animation: panel open → bucket opens and eyes look down; copy/launch → brief
`.grabbed` (~0.5 s) then idle; no results → `.miss` while the query has no matches.
After any glyph change, regenerate images with
`~/Code/widgets.nicksmith.software/art/glyphs/render-glyphs.sh`.

## 7. Errors and edge cases

| Situation | Behaviour |
|---|---|
| Hotkey registration fails (Raycast running, Spotlight re-enabled, …) | Menu shows `⚠ Hotkey unavailable — ⌘Space is in use`; "Open Menu Crane" still works; Settings names the conflict. |
| Unreadable folder / broken symlink during indexing | Skipped and logged; never crashes. |
| App launch fails | Footer shows `Couldn't open <name>` for a few seconds. |
| Math: garbage, ÷0, overflow | No math row; other results unaffected. |
| Conversion: unknown unit or mismatched dimensions (`5 kg to mph`) | No conversion row. |
| `aliases.json` malformed | Keep last good copy in memory, one-line warning in the Aliases window, never overwrite the file. |
| Emoji data missing from bundle | Emoji command hidden, logged as a fault (build bug). |

All diagnostics via `os_log`, subsystem `com.nicholaspsmith.MenuCrane`.

## 8. Testing

`MenuCraneCoreTests` (XCTest, `swift test`):

- **Matcher** — ranking order, word-order independence, acronyms, frecency boost.
- **Calculator** — precedence, parentheses, leading minus, decimals, `x` as multiply,
  rejects garbage, ÷0 yields nothing.
- **Converter** — table-driven per dimension; aliases; US Imperial vs Metric bare
  suggestions; explicit `to` overrides; rounding.
- **EmojiStore** — 🤞 via all four queries in §1; alias outranks CLDR; recents order;
  malformed `aliases.json` keeps last good state.
- **AppIndex** — temp directory with a symlinked `.app`, duplicate bundle ids, a
  broken symlink.
- **Performance** — one query across all providers (full emoji set + ~150 apps) under
  5 ms; test fails above that.

Manual checklist (in the README): focus returns to the previous app; panel appears
over full-screen apps; Esc behaviour in both modes; `e`↩ opens emoji; copied emoji
pastes correctly into Messages, Slack and a terminal; hotkey conflict warning appears
while Raycast is running.

## 9. Release and cutover

- Menubarn release rules: every push is a release. `CHANGELOG.md` section per
  push; `.github/workflows/release.yml` calls StatusItemKit's reusable
  `menubarn-release.yml`; run `StatusItemKit/scripts/release/adopt.sh` to arm the
  pre-push hook. First release **v1.0.0**. README carries the
  `**Version X.Y.Z** · [Changelog](…/releases)` line, the mascot, and a
  "Why not a Spotlight extension?" section (the Menubarn equivalent of "Why not a
  SwiftBar plugin?").
- `make-app.sh` signs with "StatusItemKit Local Signing"; `.app` symlinked into
  `~/Applications`.
- Add Menu Crane to the Menubarn site (screenshots OCR-scrubbed as usual) and to the
  CLAUDE.md app list.
- **Cutover:** quit Raycast and disable its launch-at-login → launch Menu Crane →
  confirm it holds ⌘Space. Leave Raycast installed for a one-week soak, then
  uninstall it.

## 10. Phases

| Version | Adds |
|---|---|
| v1.0 | apps, math, conversions, emoji (+ aliases window), settings, glyph, release |
| v1.1 | file search: `'` prefix, name-only matching in `~` via `NSMetadataQuery`, ranked by last-opened; ↩ opens, ⌘↩ reveals in Finder |
| v2.0 | clipboard manager (own spec): its own hotkey opening the panel in clipboard mode, paste-back via HotkeyKit + Accessibility, `.clipboard` glyph state |
