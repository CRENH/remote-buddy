import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation

extension BridgeAppModel {
    /// Fn-tap pre-roll covers one shared four-second focus/destination budget.
    /// Cancelling the returned wait is silent because the Fn session owns stop.
    func prepareIntegratedVoiceInputDestination(
        completion: @escaping (VoiceInputDestinationWaitResult) -> Void,
        schedule: @escaping OperationScheduler = ScheduledOperation.mainQueue
    ) -> VoiceInputDestinationWait {
        clearApplicationIntegrationStatus()
        guard !settings.enabledApplicationIntegrations.isEmpty else {
            return voiceInputDestinationCoordinator.waitUntilReady(completion: completion)
        }
        let report: (VoiceInputDestinationWaitResult) -> Void = { [weak self] result in
            if case let .cancelled(reason) = result {
                self?.recordApplicationIntegrationStatus(.cancelled(reason))
            }
            completion(result)
        }
        let sequence = VoiceInputPreparationSequence(schedule: schedule)
        let wait = sequence.start(stages: [
            { [weak self] done in self?.applicationIntegrationController.prepareForVoiceInput(completion: done) ?? .cancelled(.superseded) },
            { [weak self] done in self?.voiceInputDestinationCoordinator.waitUntilReady(completion: done) ?? .cancelled(.superseded) },
        ], completion: report)
        if case let .cancelled(reason) = wait {
            recordApplicationIntegrationStatus(.cancelled(reason))
        }
        return wait
    }

    // Main-queue lifecycle, like HID settings and the remote voice callbacks.
    func voiceToolDidChange() {
        pendingVoiceToolMappingRefresh = true
        flushPendingVoiceToolMappingRefresh()
    }

    var canRefreshHIDMappingsNow: Bool {
        started && !isTerminating && !audio.suspensionState.suspendsHIDMonitoring &&
            !isStreaming && !voiceSession.isActive && !hasPendingBluetoothVoiceWork &&
            voiceSession.pendingStart.identifier == nil && !voiceKeyLatch.isHeld &&
            !voiceKeyActivationInProgress && !voiceFnTapSession.requiresCleanupBeforeMapping
    }

    func flushPendingVoiceToolMappingRefresh(applyMappings: (() -> Void)? = nil) {
        guard canRefreshHIDMappingsNow else { return }
        if pendingVoiceToolMappingRefresh {
            pendingVoiceToolMappingRefresh = false
            if applyMappings == nil {
                pendingHIDServiceMappingRefresh = false
            }
            if let applyMappings { applyMappings() } else { applyHIDSettings() }
            if applyMappings != nil {
                flushPendingHIDServiceMappingRefreshIfNeeded(applyMappings: applyMappings)
            }
            return
        }
        flushPendingHIDServiceMappingRefreshIfNeeded(applyMappings: applyMappings)
    }
    var requiresOrderedVoiceFn: Bool {
        (settings.effectiveVoiceKeyMode == .function && !settings.effectiveVoiceFnTapModeEnabled &&
            !settings.enabledApplicationIntegrations.isEmpty) || OrderedVoiceActivationPolicy.needsSoftwareFn(
            mode: settings.effectiveVoiceKeyMode,
            fnTapEnabled: settings.effectiveVoiceFnTapModeEnabled,
            preferredInputSourceID: settings.onboardingVoiceTool.preferredInputSourceID
        )
    }
    /// Native Xiaomi services remain present when the selected card is a
    /// G9N9N. Their mapping follows the global trigger, not the selected family.
    var shouldNeutralizeNativeVoiceKey: Bool {
        settings.effectiveVoiceKeyMode != .function || settings.effectiveVoiceFnTapModeEnabled || requiresOrderedVoiceFn
    }

    var isVoiceConfigurationBusy: Bool {
        isStreaming || hasActiveVirtualAudioSource || voiceKeyLatch.isHeld ||
            voiceKeyActivationInProgress || voiceSession.pendingStart.identifier != nil ||
            voiceFnTapSession.requiresCleanupBeforeMapping || voiceKeyReleaseRetry != nil
    }

    func handleVoiceFnTapFailure(_ failure: VoiceFnTapFailure) {
        releaseVirtualAudioOutputIfUnused(reason: "voice_fn_tap_failed")
        if voiceFnTapSession.releaseRecoveryBlocked {
            voiceShortcutStatus = LocalizedMessage("voice_button.status.cleanup_failed")
            AppLogger.shared.write("VOICE FN TAP cleanup blocked reason=accessibility_unavailable")
            return
        }
        AppLogger.shared.write("VOICE FN TAP failed reason=\(failure.rawValue) fallback=hardware_fn")
        if settings.isTestingVoiceTrigger {
            settings.discardOnboardingVoiceTrial()
        } else {
            settings.voiceFnTapModeEnabled = false
        }
        voiceFnTapSession.setEnabled(false)
        applyHIDSettings()
    }

    func requestNextHIDPermissionIfNeeded(
        voiceFnTapModeRequested: Bool? = nil,
        voiceKeyModeRequested: VoiceKeyMode? = nil
    ) {
        let request = HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: settings.customMappingEnabled,
            voiceFnTapModeEnabled: (voiceFnTapModeRequested ?? settings.effectiveVoiceFnTapModeEnabled) || requiresOrderedVoiceFn,
            voiceKeyMode: voiceKeyModeRequested ?? settings.effectiveVoiceKeyMode,
            inputMonitoringGranted: HIDRemoteMonitor.isInputMonitoringGranted,
            accessibilityGranted: KeyboardInjector.isAccessibilityTrusted
        )
        switch request {
        case .none:
            break
        case .inputMonitoring:
            _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        case .accessibility:
            _ = KeyboardInjector.requestAccessibilityAccess()
        }
    }

    func requestInputMonitoringPermission() {
        _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    func requestAccessibilityPermission() {
        _ = KeyboardInjector.requestAccessibilityAccess()
        openPrivacyPane("Privacy_Accessibility")
    }
}
