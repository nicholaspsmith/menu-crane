// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import Combine
import HotkeyKit
import MenuCraneCore
import StatusItemKit
import os

let log = Logger(subsystem: "com.nicholaspsmith.MenuCrane", category: "app")

/// Menu Crane — a ⌘Space launcher for apps, math, unit conversions and emoji.
final class App: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    private var yieldClient: YieldClient!
    private let hotkey = HotkeyService()
    private var trigger = HotkeySettings.load(from: .standard)
    private var usage: UsageStore!
    private var aliases: AliasStore!
    private var emojiStore: EmojiStore?
    private var appIndex: AppIndex!
    private var appWatcher: FSEventsWatcher?
    private var panel: PanelController!
    private var settings: SettingsWindowController!
    private var aliasesWindow: AliasesWindowController?
    private var mood = CharacterIcon.CraneState.idle
    /// The pending "grabbed" flash reverting itself; cancelled (not just overwritten) on a new
    /// grab or a hide/show, so a stale revert never fires after the mood's already moved on.
    private var grabRevert: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    /// Mendoza's turn in the minute cue: a grab while idle, with the crane showing.
    private var minuteCue: MinuteCue?
    private var grab: IconAnimation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeServices()
        status = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.poll() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) },
            autosaveName: "MenuCrane"
        )
        status.start()
        yieldClient = YieldClient(item: status)
        yieldClient.start()
        refreshIcon()
        wireMoods()
        let grab = IconAnimation(duration: CharacterIcon.menuCraneGrabDuration, frame: { [weak self] t in
            self?.status.setIcon(CharacterIcon.menuCrane(state: .idle, grab: t))
        }, completion: { [weak self] in self?.refreshIcon() })
        self.grab = grab
        let cue = MinuteCue { [weak self] in
            guard let self, self.mood == .idle, Preferences.iconStyle != "dot" else { return }
            grab.start()
        }
        cue.start()
        minuteCue = cue

        hotkey.onPress = { [weak self] in self?.openPanel() }
        hotkey.register(trigger)
    }

    private func setMood(_ m: CharacterIcon.CraneState) {
        mood = m
        grab?.cancel()
        refreshIcon()
    }

    private func refreshIcon() {
        guard grab?.isRunning != true else { return }   // the grab's own frames are drawing the icon
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
        // Showing cancels a stale grab and starts searching. Hiding leaves a pending grab alone
        // — a launch or copy hides the panel right after grabbing — and its revert re-derives
        // the mood (idle, once hidden) when it fires.
        panel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            if visible {
                self.grabRevert?.cancel()
                self.grabRevert = nil
                self.setMood(.searching)
            } else if self.grabRevert == nil {
                self.setMood(.idle)
            }
        }
        panel.onGrab = { [weak self] in
            guard let self else { return }
            self.grabRevert?.cancel()
            self.setMood(.grabbed)
            let revert = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.grabRevert = nil
                self.setMood(self.panel.isVisible ? (self.panel.state.isMiss ? .miss : .searching) : .idle)
            }
            self.grabRevert = revert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: revert)
        }
        panel.state.$results.combineLatest(panel.state.$emoji)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible, self.grabRevert == nil else { return }
                self.setMood(self.panel.state.isMiss ? .miss : .searching)
            }
            .store(in: &cancellables)
    }

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
        panel.onShow = { [weak self] in self?.aliases.reload() }

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
            if e.keyCode == 40 && !mods.contains(.shift), self.panel.emojiUI.editing == nil,
               let hit = self.panel.state.selectedEmoji {                                              // ⌘K
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

        if let store = emojiStore {
            aliasesWindow = AliasesWindowController(model: AliasesModel(store: store, aliasStore: aliases, usage: usage))
        }
        let settingsModel = SettingsModel(
            trigger: trigger, hotkeyError: nil,
            onHotkey: { [weak self] t in
                guard let self else { return (t, nil) }
                let previous = self.trigger
                let failure = self.hotkey.register(t)
                if failure == nil {
                    HotkeySettings.save(t, to: .standard)
                } else {
                    self.hotkey.register(previous)   // restore the hotkey that was working
                }
                let decision = HotkeyRebind.decide(new: t, failure: failure, previous: previous)
                self.trigger = decision.trigger
                return (decision.trigger, decision.message)
            },
            openAliases: { [weak self] in self?.aliasesWindow?.show() })
        settingsModel.onTone = { [weak self] t in self?.panel.emojiUI.tone = t }
        settings = SettingsWindowController(model: settingsModel)
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
        panel.menuCraneTrigger = { [weak self] in self?.trigger ?? HotkeySettings.defaultTrigger }
    }

    /// Retry a hotkey another app was holding (e.g. right after Raycast quits).
    private func poll() {
        if hotkey.failure != nil { hotkey.register(trigger) }
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if let failure = hotkey.failure {
            let warn = NSMenuItem(title: "⚠ Hotkey unavailable — \(failure)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(menuItem("Open Menu Crane (\(TriggerText.describe(trigger)))", #selector(openPanel)))
        SettingsMenu.addFooter(to: menu, appName: "Menu Crane", items: { [self] settings in
            settings.addItem(menuItem("Hotkey, Units & Emoji…", #selector(openSettings), key: ","))
            settings.addItem(menuItem("Reset Panel Position", #selector(resetPanelPosition)))
            // Crane or dot: this app's own picker, not AppearanceMenu.
            let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, style) in [("Crane", "crane"), ("Dot", "dot")] {
                let item = menuItem(title, #selector(chooseIcon(_:)))
                item.representedObject = style
                item.state = Preferences.iconStyle == style ? .on : .off
                sub.addItem(item)
            }
            icon.submenu = sub
            settings.addItem(icon)
        })
    }

    @objc private func chooseIcon(_ sender: NSMenuItem) {
        Preferences.iconStyle = sender.representedObject as? String ?? "crane"
        refreshIcon()
    }

    func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func openPanel() { panel.toggle() }
    @objc func openSettings() {
        settings.model.trigger = trigger
        settings.model.hotkeyError = hotkey.failure
        settings.show()
    }
    /// Forget the dragged-to position; the next summon opens centered a third down the screen
    /// under the mouse.
    @objc private func resetPanelPosition() { PanelPlacement.clear(from: .standard) }
}
