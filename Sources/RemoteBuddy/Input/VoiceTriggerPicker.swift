import SwiftUI

/// Shared by settings and the wizard so both edit the same trigger.
struct VoiceTriggerPicker: View {
    let selection: VoiceKeyMode
    let onSelect: (VoiceKeyMode) -> Void
    @EnvironmentObject private var localization: LocalizationStore
    @State private var editing = false
    @State private var recording = false
    @State private var errorKey: String?

    private var choices: [VoiceKeyMode] {
        VoiceKeyMode.allCases.contains(selection) ? VoiceKeyMode.allCases : VoiceKeyMode.allCases + [selection]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(localization.text("connection.voice_key_mode.title"), selection: Binding(
                    get: { selection }, set: onSelect
                )) {
                    ForEach(choices) { mode in
                        Text(mode.displayName(using: localization)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Button(localization.text("connection.voice_key.customize")) { editing = true }
            }
            Text(localization.text("connection.voice_key_mode.help"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 14) {
                Text(localization.text("connection.voice_key.customize")).font(.headline)
                Text(localization.text("connection.voice_key.custom_help"))
                HStack {
                    Text(selection.displayName(using: localization)).font(.title3)
                    Spacer()
                    Button(localization.text(recording ? "onboarding.shortcut_learning.waiting" : "shortcut.action.record")) {
                        errorKey = nil
                        recording = true
                    }
                    .disabled(recording)
                }
                if recording {
                    ShortcutCaptureView(onCapture: accept, onFailure: { failure in
                        recording = false
                        errorKey = failure == .accessibilityPermissionRequired
                            ? "shortcut.editor.permission_required" : "shortcut.editor.capture_unavailable"
                    })
                    .frame(width: 1, height: 1)
                }
                if let errorKey {
                    Text(localization.text(errorKey)).foregroundStyle(.orange)
                }
                ScrollView {
                    KeyboardShortcutPicker(shortcut: customShortcut,
                        showsStandardKeyboardInitially: true, onSelect: accept)
                }
                HStack {
                    Spacer()
                    Button(localization.text("common.action.close")) { recording = false; editing = false }
                }
            }
            .padding(20)
            .frame(width: 820, height: 600)
        }
    }

    private var customShortcut: CustomKeyboardShortcut? {
        if case let .shortcut(shortcut) = selection { return shortcut }
        return nil
    }

    private func accept(_ shortcut: CustomKeyboardShortcut) {
        recording = false
        if let modifier = shortcut.standaloneModifier,
           let mode = VoiceKeyMode(standaloneModifier: modifier) {
            onSelect(mode)
            editing = false
        } else if VoiceKeyMode.supportsShortcut(shortcut) {
            onSelect(.shortcut(shortcut))
            editing = false
        } else {
            errorKey = "connection.voice_key.custom_unsupported"
        }
    }
}
