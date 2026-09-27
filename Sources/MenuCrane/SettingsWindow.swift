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
    /// Registers the trigger and reports what's actually active afterward — a failed rebind
    /// leaves the previous trigger active, so the Hotkey row must show that, not the rejected one.
    let onHotkey: (Trigger) -> (trigger: Trigger, error: String?)
    let openAliases: () -> Void
    var onTone: ((SkinTone) -> Void)?
    /// Whether the Settings window is currently key; set by the controller. A captured key is
    /// ignored once it's false, since the recorder's monitor is app-wide and would otherwise be
    /// able to swallow a keystroke meant for another of our windows (e.g. Emoji Aliases).
    var isWindowKey: () -> Bool = { true }
    private let recorder = TriggerRecorder()
    private var recordTimeout: DispatchWorkItem?
    /// How long an abandoned recording (no key pressed) stays armed before it gives up on its own.
    static let recordTimeoutSeconds: TimeInterval = 10

    init(trigger: Trigger, hotkeyError: String?, onHotkey: @escaping (Trigger) -> (trigger: Trigger, error: String?), openAliases: @escaping () -> Void) {
        self.trigger = trigger; self.hotkeyError = hotkeyError; self.onHotkey = onHotkey; self.openAliases = openAliases
    }

    func record() {
        recording = true
        let timeout = DispatchWorkItem { [weak self] in self?.stopRecording() }
        recordTimeout?.cancel()
        recordTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordTimeoutSeconds, execute: timeout)
        recorder.start { [weak self] t in
            guard let self else { return }
            self.recordTimeout?.cancel()
            self.recordTimeout = nil
            self.recording = false
            guard self.isWindowKey() else { return }   // the window lost key status mid-capture
            guard !t.modifiers.isEmpty else { self.hotkeyError = "Add at least one modifier (⌘, ⌥, ⌃ or ⇧)."; return }
            let result = self.onHotkey(t)
            self.trigger = result.trigger   // whatever App actually adopted, not necessarily `t`
            self.hotkeyError = result.error
        }
    }

    /// Cancels an in-progress recording: the window closed, resigned key, is being shown again, or
    /// the timeout fired. Leaving the recorder's app-wide monitor installed would otherwise swallow
    /// the next keystroke anywhere in the app.
    func stopRecording() {
        guard recording else { return }
        recordTimeout?.cancel()
        recordTimeout = nil
        recorder.stop()
        recording = false
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

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let model: SettingsModel
    init(model: SettingsModel) {
        self.model = model
        super.init()
        model.isWindowKey = { [weak self] in self?.window?.isKeyWindow ?? false }
    }

    func show() {
        model.stopRecording()   // showing again abandons any recording left running
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            // NSWindow(contentViewController:) doesn't size itself to a hosted SwiftUI view on its
            // own — without this the window opens as just its title bar. This tracks the Form's
            // real intrinsic size instead of a guessed constant, the way AliasesWindowController's
            // explicit setContentSize does for its own (fixed-size) window.
            hosting.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: hosting)
            w.title = "Menu Crane Settings"
            w.styleMask.remove(.resizable)
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        model.loginEnabled = LoginItem.isEnabled
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) { model.stopRecording() }
    func windowWillClose(_ notification: Notification) { model.stopRecording() }
}
