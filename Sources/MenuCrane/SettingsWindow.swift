// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

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
