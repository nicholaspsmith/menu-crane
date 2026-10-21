# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.11.0] - 2026-10-20

### Changed

- Icon ▸ (Crane / Dot) moves out of Settings ▸ into the main menu, directly below Settings and above Quit Menu Crane. Settings keeps Hotkey, Units & Emoji…, Reset Panel Position, Start at Login and the version. Needs StatusItemKit 0.35.0 (`SettingsMenu.addFooter(belowSettings:)`)

## [1.10.1] - 2026-10-20

- `install.sh` now hands the install to parity on a Mac parity syncs, instead of building a second copy of the app that macOS could launch in place of parity's. `PARITY=off ./install.sh` still builds it locally.

## [1.10.0] - 2026-10-20

- Menu icons now update more smoothly with significantly less impact on system performance, while maintaining the same appearance and responsiveness to light and dark mode.

## [1.9.0] - 2026-10-15

- The menu bar owl icon now supports custom pupil colors, allowing users to choose their preferred eye color instead of the default green-to-red gradient.

## [1.8.0] - 2026-10-15

- Carol now sleeps in the menu bar, with her eyes closing, body breathing, and Zs floating above her.

## [1.7.0] - 2026-10-15

- Carol's headband no longer gets cut off at the top of the menu bar icon.
- Carol's walking animation is smoother and more responsive to changes in her pace.

## [1.6.0] - 2026-10-15

- The caterpillar icon in the menu bar can now walk, with a smooth rolling motion that is distinct from its previous running animation.

## [1.5.0] - 2026-10-09

- Carol's caterpillar icon now shows her headphones around her neck when SoundChain is not keeping them connected to this Mac.

## [1.4.0] - 2026-10-08

- The crane now performs a grab animation once a minute, opening and closing its bucket before returning to its resting position.

## [1.3.1] - 2026-10-08

- Fixes 1.3.0 crashing at launch (the grab animation was consulted before it existed)

## [1.3.0] - 2026-10-08

- Mendoza animates like the other Menumon mascots: twice a minute, while idle, he drops his bucket open, snaps it shut and lifts it home, taking his turn in the cue after Homestead. Skipped under Reduce Motion and with the dot icon

## [1.2.0] - 2026-10-07

- No user-visible changes.

## [1.1.1] - 2026-10-06

- Ticking a checkbox in the menu no longer closes it: Settings ▸ Start at Login stays open when you turn it on or off

## [1.1.0] - 2026-10-06

- ⌘↩ hands the query to Spotlight: Menu Crane closes and macOS's own Spotlight panel opens with exactly what you typed, for its richer results. It needs Menu Crane allowed in Accessibility; without it, the query stays put and the footer says why.
- A row's alternate action (reveal an app in Finder, copy a conversion with its unit) moves from ⌘↩ to ⌥↩.
- Settings submenu: the Settings window (now "Hotkey, Units & Emoji…"), Reset Panel Position, Icon, Start at Login and the version live under Settings ▸, as in every Menumon app.
- New app icon: Mendoza as he looks in the menu bar.

## [1.0.2] - 2026-09-28

- App results show where the app is installed (e.g. `~/Applications/VidSnatch.app`) instead of the build folder a linked app points into, and ⌘↩ reveals it there.

## [1.0.1] - 2026-09-28

- `install.sh` now asks whether to turn on Start at Login (skipped when it is already on, or when there is no terminal to ask in) instead of turning it on unasked, then relaunches the app, quitting any running copy first so the new build takes over

## [1.0.0] - 2026-09-27

First release: Menu Crane replaces Raycast for launching apps, arithmetic, unit conversions and emoji.

- ⌘Space opens a search panel over any app, including full-screen ones. It can be dragged by its background and reopens where you left it.
- Apps rank by how well they match and how often you open them.
- Math with `+ - * /` and parentheses; ↩ copies the answer.
- Conversions for temperature, mass, volume, length, speed and acceleration, with a US Imperial / Metric setting for bare values.
- Emoji search in any word order, your own aliases, recents first, and a default skin tone.
- Mendoza the crane in the menu bar opens his bucket while you search and snaps it shut when you copy.
