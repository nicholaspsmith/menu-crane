# Menu Crane

<img src="art/mascot/mendoza-idle.png" alt="Mendoza Crane, the Menu Crane" width="160">

**Status: in development.** Nothing to install yet.

A ⌘Space launcher for macOS that does only what I used Raycast for, and nothing else:

- **Open apps**, ranked by match and by how often you open them.
- **Arithmetic** with `+ - * /` (and `x`), parentheses and decimals. Return copies the answer.
- **Unit conversions** for temperature, mass, volume, length, speed and acceleration
  (`72f to c`, `12 fl oz in pt`, `100 km/h`), with a US Imperial / Metric setting.
- **Emoji search** that ignores word order (`fingers crossed` or `crossed fingers`),
  with your own aliases, recents first and a default skin tone. Type `e` or `emoji` and press Return.

File search (v1.1) and a clipboard manager (v2) come later.

Its mascot is **Mendoza Crane, the Menu Crane**, a goofy red-crowned crane with a
construction-crane grab bucket hanging from his beak. He lives in the menu bar and
opens his bucket while you search.

Part of [Menubarn](https://widgets.nicksmith.software), built on
[StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) and
[HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit).

## Why not a Spotlight extension?

macOS has no third-party hook into Spotlight's result list. Spotlight importers only
index file metadata, and App Intents can surface actions but can't draw custom rows
like an emoji grid or a live calculation.

## Design

- [Design spec](docs/superpowers/specs/2026-09-26-menu-crane-design.md)
- [v1 implementation plan](docs/superpowers/plans/2026-09-26-menu-crane-v1.md)

## License

[MIT](LICENSE)
