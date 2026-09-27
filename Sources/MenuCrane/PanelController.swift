// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

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
