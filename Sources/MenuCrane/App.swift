// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

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
