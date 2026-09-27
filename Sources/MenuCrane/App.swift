// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
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
        status.setIcon(CharacterIcon.menuCrane(state: .idle))

        hotkey.onPress = { [weak self] in self?.openPanel() }
        hotkey.register(trigger)
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
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
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

    @objc func openPanel() { panel.toggle() }
    @objc func openSettings() {
        settings.model.hotkeyError = hotkey.failure
        settings.show()
    }
    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
