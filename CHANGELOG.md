# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

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
