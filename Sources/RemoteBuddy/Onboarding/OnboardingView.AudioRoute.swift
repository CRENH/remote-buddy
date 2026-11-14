import SwiftUI

extension OnboardingView {
    var microphoneSetupContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localization.text("onboarding.audio.title")).font(.headline)
            Text(verbatim: localization.text("onboarding.audio.detail"))
                .foregroundStyle(.secondary)
            statusCard(icon: "mic.fill", title: BuddyMicrophoneDevicePolicy.deviceName,
                detail: localization.text(microphoneSetupStatusKey),
                isComplete: onboardingAudioReady)
            if !microphoneDriverInstalled || !model.isAudioOutputVerified {
                Text(localization.text("settings.driver.reload_help")).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(localization.text("audio.action.refresh_devices")) { prepareAutomaticDriverCheck() }
                    Button(localization.text("audio.compatibility.open_install_guide")) { model.openVirtualMicrophoneSetupInstructions(using: localization) }
                }.buttonStyle(.bordered)
            }
        }
        .onAppear { prepareAutomaticDriverCheck() }
        .onChange(of: model.audioDevices) { _, _ in prepareAutomaticDriverCheck() }
    }

    private var microphoneSetupStatusKey: String {
        if !microphoneDriverInstalled { return "onboarding.audio.not_detected" }
        return onboardingAudioReady ? "onboarding.audio.automatic_ready" : "onboarding.audio.checking"
    }

    var voiceTriggerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle("onboarding.voice_trigger.title")
            Text(localization.text("onboarding.voice_tool.selected_trigger_help"))
                .foregroundStyle(.secondary)
            VoiceTriggerPicker(selection: settings.selectedVoiceTrigger.voiceKeyMode, onSelect: settings.selectOnboardingVoiceTrigger)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(localization.text("connection.voice_fn_tap.enabled"), isOn: Binding(
                    get: { settings.selectedVoiceTrigger.voiceFnTapModeEnabled },
                    set: settings.selectOnboardingFnTapMode
                ))
                Text(localization.text("connection.voice_fn_tap.hint_short"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(localization.text("onboarding.voice_trigger.save_hint"))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func prepareAutomaticDriverCheck() {
        guard interactionProbe == nil else { return }
        model.refreshAudioDevices()
        model.configureVirtualAudioOutput(reason: "onboarding_driver_check")
    }
}
