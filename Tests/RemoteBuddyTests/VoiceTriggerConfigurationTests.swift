import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import RemoteBuddy

@Suite("Voice shortcut configuration")
@MainActor
struct VoiceTriggerConfigurationTests {
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let name = "voice-trigger-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(AppSettings(defaults: defaults), defaults)
    }

    @Test func selectedChordPersistsWithoutReplacingTheCommittedTriggerUntilVerified() throws {
        try withSettings { settings, defaults in
            settings.voiceKeyMode = .rightOption
            settings.setOnboardingControlSource(.xiaomiRemote)
            settings.setOnboardingVoiceTool(.weixin)
            settings.setOnboardingStep(.voiceTrigger)
            settings.selectOnboardingVoiceTrigger(.suggestedShortcut)
            #expect(settings.voiceKeyMode == .rightOption)
            #expect(AppSettings(defaults: defaults).voiceKeyMode == .rightOption)
            #expect(AppSettings(defaults: defaults).selectedVoiceTrigger.voiceKeyMode == .suggestedShortcut)
            let view = OnboardingView(model: BridgeAppModel(settings: settings, initialAudioDevices: []))
            let plan = try #require(view.proposedPairingPlan)
            #expect(plan.binding.shortcut == .suggestedShortcut)
            #expect(plan.binding.gestureMode == .hold)
            settings.beginOnboardingVoiceTrial(plan)
            #expect(settings.effectiveVoiceKeyMode == .rightOption)
            settings.setOnboardingStep(.voiceTest)
            #expect(settings.effectiveVoiceKeyMode == .suggestedShortcut)
            #expect(settings.voiceKeyMode == .rightOption)
            #expect(AppSettings(defaults: defaults).effectiveVoiceKeyMode == .suggestedShortcut)
            settings.verifyOnboardingVoiceBinding()
            #expect(settings.voiceKeyMode == .suggestedShortcut)
            #expect(AppSettings(defaults: defaults).voiceKeyMode == .suggestedShortcut)
            #expect(settings.verifiedVoiceToolBinding?.validationState == .verified)
        }
    }

    @Test func cancellingIntegrationDiscardsBothPendingTriggerAndTapChanges() throws {
        try withSettings { settings, _ in
            let profile = settings.registerBluetoothRemote(identifier: UUID(), model: .rc003)
            settings.selectRemoteProfile(profile)
            settings.voiceKeyMode = .rightOption
            settings.setOnboardingVoiceTool(.weixin)
            settings.completeOnboarding()
            SettingsPageBehavior.beginIntegrationSetup(tool: .weixin, settings: settings)
            settings.selectOnboardingVoiceTrigger(.function)
            settings.selectOnboardingFnTapMode(true)
            #expect(settings.voiceKeyMode == .rightOption)
            #expect(!settings.voiceFnTapModeEnabled)
            let view = OnboardingView(model: BridgeAppModel(settings: settings, initialAudioDevices: []))
            settings.beginOnboardingVoiceTrial(try #require(view.proposedPairingPlan))
            settings.setOnboardingStep(.voiceTest)
            #expect(settings.effectiveVoiceKeyMode == .function)
            #expect(settings.effectiveVoiceFnTapModeEnabled)
            settings.dismissOnboarding()
            #expect(settings.voiceKeyMode == .rightOption)
            #expect(!settings.voiceFnTapModeEnabled)
            #expect(settings.onboardingVoiceTrigger == nil)
            #expect(settings.stagedVoiceToolBinding == nil)
        }
    }

    @Test func rerunningAnUnchangedVerifiedBindingStillRequiresANewVoiceTest() throws {
        try withSettings { settings, _ in
            settings.setOnboardingControlSource(.xiaomiRemote)
            settings.setOnboardingVoiceTool(.weixin)
            settings.voiceKeyMode = .rightOption
            let verified = VoiceToolUserBinding(tool: .weixin, shortcut: .rightOption,
                gestureMode: .hold, source: .manuallyConfirmed, validationState: .verified,
                verifiedToolVersion: "1", verifiedAt: Date())
            settings.verifiedVoiceToolBinding = verified
            let view = OnboardingView(model: BridgeAppModel(settings: settings, initialAudioDevices: []))
            settings.beginOnboardingVoiceTrial(try #require(view.proposedPairingPlan))
            settings.setOnboardingStep(.voiceTest)
            #expect(settings.isTestingVoiceTrigger)
            #expect(settings.stagedVoiceToolBinding?.validationState == .staged)
            #expect(settings.stagedVoiceToolBinding?.verifiedAt == nil)
            #expect(settings.verifiedVoiceToolBinding == verified)
            #expect(!view.canContinue)
        }
    }

    @Test func oldVerificationCannotOverrideANewTriggerAndFnInstructionsFollowTheSelection() throws {
        try withSettings { settings, _ in
            settings.setOnboardingControlSource(.xiaomiRemote)
            settings.setOnboardingVoiceTool(.weixin)
            settings.verifiedVoiceToolBinding = VoiceToolUserBinding(tool: .weixin,
                shortcut: .function, gestureMode: .hold, source: .manuallyConfirmed,
                validationState: .verified, verifiedToolVersion: "1", verifiedAt: Date())
            settings.selectOnboardingVoiceTrigger(.rightOption)
            let view = OnboardingView(model: BridgeAppModel(settings: settings, initialAudioDevices: []))
            let plan = try #require(view.proposedPairingPlan)
            #expect(plan.binding.shortcut == .rightOption)
            #expect(plan.binding.validationState == .staged)
            #expect(plan.binding.verifiedAt == nil)
            #expect(!view.inputMethodGuideSteps(for: .weixin).contains { step in
                if case .systemFunctionKey = step.content { return true }; return false
            })
            settings.selectOnboardingVoiceTrigger(.function)
            #expect(view.inputMethodGuideSteps(for: .weixin).contains { step in
                if case .systemFunctionKey = step.content { return true }; return false
            })
        }
    }

    @Test func tapToolsUseTheSelectedChordAndDictationKeepsItsSpecificSystemSequence() throws {
        for tool in [OnboardingVoiceTool.bageshuo, .typeless] {
            let plan = try #require(OnboardingVoicePairingPlan.resolve(tool: tool, controlSource: .xiaomiRemote,
                selectedShortcut: .suggestedShortcut))
            #expect(plan.binding.shortcut == .suggestedShortcut)
            #expect(plan.fnTapModeEnabled)
        }
        #expect(OnboardingVoicePairingPlan.resolve(tool: .macosDictation, controlSource: .xiaomiRemote,
            selectedShortcut: .suggestedShortcut) == nil)
    }

    @Test func optionTapModeIsOnlyCommittedWithTheVerifiedBinding() throws {
        try withSettings { settings, _ in
            settings.voiceKeyMode = .rightOption
            settings.setOnboardingControlSource(.xiaomiRemote)
            settings.setOnboardingVoiceTool(.weixin)
            settings.selectOnboardingFnTapMode(true)
            #expect(!settings.voiceFnTapModeEnabled)
            let view = OnboardingView(model: BridgeAppModel(settings: settings, initialAudioDevices: []))
            let plan = try #require(view.proposedPairingPlan)
            #expect(plan.binding.shortcut == .rightOption)
            #expect(plan.fnTapModeEnabled)
            settings.beginOnboardingVoiceTrial(plan)
            settings.setOnboardingStep(.voiceTest)
            #expect(settings.effectiveVoiceFnTapModeEnabled)
            #expect(!settings.voiceFnTapModeEnabled)
            view.continueFlow() // No real transcript was observed, so this cannot commit.
            #expect(!settings.voiceFnTapModeEnabled)
            #expect(settings.verifiedVoiceToolBinding == nil)
            settings.verifyOnboardingVoiceBinding()
            #expect(settings.voiceFnTapModeEnabled)
            #expect(settings.voiceKeyMode == .rightOption)
        }
    }

    @Test func customTriggersRoundTripInSettingsAndBindings() throws {
        for mode in VoiceKeyMode.allCases + [.shortcut(CustomKeyboardShortcut(
            keyCode: 40, modifierFlags: [.command, .option], keyLabel: "K"))] {
            #expect(VoiceKeyMode(rawValue: mode.rawValue) == mode)
            #expect(try JSONDecoder().decode(VoiceKeyMode.self, from: JSONEncoder().encode(mode)) == mode)
        }
        #expect(VoiceKeyMode(rawValue: "shortcut:9:0") == nil)
        #expect(VoiceKeyMode(rawValue: "shortcut:65535:917504") == nil)
    }

    @Test func integrationAlwaysSelectsTheTriggerBeforeToolSetupAndKeepsExistingValues() throws {
        try withSettings { settings, _ in
            let profile = settings.registerBluetoothRemote(identifier: UUID(), model: .rc003)
            settings.selectRemoteProfile(profile)
            settings.voiceKeyMode = .rightOption
            settings.completeOnboarding()
            SettingsPageBehavior.beginIntegrationSetup(tool: .typeless, settings: settings)
            #expect(settings.onboardingStep == .voiceTrigger)
            #expect(settings.voiceKeyMode == .rightOption)
            #expect(!settings.voiceFnTapModeEnabled)
            #expect(OnboardingPurpose.integration.previousStep(before: .voiceTrigger) == nil)
            #expect(OnboardingPurpose.integration.nextStep(after: .voiceTrigger) == .voiceTool)
        }
    }
}

@Suite("Held voice shortcuts")
struct HeldVoiceShortcutTests {
    private var shortcut: CustomKeyboardShortcut {
        CustomKeyboardShortcut(keyCode: 9, modifierFlags: [.control, .shift, .option], keyLabel: "V")
    }

    @Test func voiceChordsReachHIDListenersAndKeepTheComposedFlagsThroughRelease() throws {
        var events: [CGEvent] = []
        var locations: [CGEventTapLocation] = []
        let post: (CGEventTapLocation, CGEvent) -> Void = { location, event in
            locations.append(location)
            events.append(event)
        }
        let chord: CGEventFlags = [.maskControl, .maskShift]
        #expect(KeyboardInjector.postVoiceShortcutState(code: 59, isDown: true,
            flags: .maskControl, eventPoster: post))
        #expect(KeyboardInjector.postVoiceShortcutState(code: 56, isDown: true,
            flags: chord, eventPoster: post))
        #expect(KeyboardInjector.postVoiceShortcutState(code: 9, isDown: true,
            flags: chord, eventPoster: post))
        #expect(KeyboardInjector.postVoiceShortcutState(code: 9, isDown: false,
            flags: chord, eventPoster: post))
        #expect(KeyboardInjector.postVoiceShortcutState(code: 56, isDown: false,
            flags: .maskControl, eventPoster: post))
        #expect(KeyboardInjector.postVoiceShortcutState(code: 59, isDown: false,
            flags: [], eventPoster: post))
        #expect(locations == Array(repeating: .cghidEventTap, count: 6))
        #expect(events.map(\.type) == [.flagsChanged, .flagsChanged, .keyDown, .keyUp, .flagsChanged, .flagsChanged])
        #expect(events.map(\.flags) == [.maskControl, chord, chord, chord, .maskControl, []])
        #expect(events.allSatisfy {
            $0.getIntegerValueField(.eventSourceUserData) == KeyboardInjector.orderedVoiceEventMarker &&
                $0.getIntegerValueField(.eventSourceStateID) != Int64(CGEventSourceStateID.hidSystemState.rawValue)
        })
    }

    @Test func chordStaysPressedUntilReleaseAndReleasesInReverseOrder() {
        let session = HeldVoiceShortcut()
        var edges: [(UInt16, Bool, CGEventFlags)] = []
        let post: KeyboardInjector.KeyStatePoster = { edges.append(($0, $1, $2)); return true }
        #expect(session.setPressed(true, shortcut: shortcut, post: post, hardwareFlags: { [] }))
        #expect(edges.map(\.0) == [59, 58, 56, 9])
        #expect(edges.allSatisfy { $0.1 })
        #expect(edges.last?.2.contains([.maskControl, .maskShift, .maskAlternate]) == true)
        #expect(session.setPressed(true, shortcut: shortcut, post: post, hardwareFlags: { [] }))
        #expect(edges.count == 4)
        #expect(session.setPressed(false, shortcut: shortcut, post: post, hardwareFlags: { [] }))
        #expect(edges.map(\.0) == [59, 58, 56, 9, 9, 56, 58, 59])
        #expect(edges.suffix(4).allSatisfy { !$0.1 })
        #expect(edges.last?.2.isEmpty == true)
    }

    @Test func physicalModifiersAreNotAcquiredAndRemainSetDuringCleanup() {
        let session = HeldVoiceShortcut()
        var physical: CGEventFlags = .maskAlternate
        var edges: [(UInt16, Bool, CGEventFlags)] = []
        let post: KeyboardInjector.KeyStatePoster = { edges.append(($0, $1, $2)); return true }
        #expect(session.setPressed(true, shortcut: shortcut, post: post, hardwareFlags: { physical }))
        #expect(edges.map(\.0) == [59, 56, 9])
        physical.formUnion(.maskCommand)
        #expect(session.setPressed(false, shortcut: shortcut, post: post))
        #expect(edges.last?.2.contains([.maskAlternate, .maskCommand]) == true)
        #expect(!edges.contains { $0.0 == 58 })
    }

    @Test func failedMainKeyPressCleansUpEveryAttemptedKey() {
        let session = HeldVoiceShortcut()
        var edges: [(UInt16, Bool)] = []
        let post: KeyboardInjector.KeyStatePoster = { code, down, _ in
            edges.append((code, down)); return !(code == 9 && down)
        }
        #expect(!session.setPressed(true, shortcut: shortcut, post: post, hardwareFlags: { [] }))
        #expect(edges.suffix(4).map(\.0) == [9, 56, 58, 59])
        #expect(edges.suffix(4).allSatisfy { !$0.1 })
    }

    @Test func failedReleaseIsRetriedBeforeAnotherChordCanAcquireKeys() {
        let session = HeldVoiceShortcut()
        var failRelease = true
        var downs = 0
        let post: KeyboardInjector.KeyStatePoster = { _, down, _ in
            if down { downs += 1 }; return down || !failRelease
        }
        #expect(session.setPressed(true, shortcut: shortcut, post: post, hardwareFlags: { [] }))
        #expect(!session.setPressed(false, shortcut: shortcut, post: post))
        #expect(!session.setPressed(true, shortcut: shortcut, post: post, hardwareFlags: { [] }))
        #expect(downs == 4)
        failRelease = false
        #expect(session.setPressed(false, shortcut: shortcut, post: post))
    }
    @Test func tapConversionClicksTheWholeSelectedChordAtBothSessionEdges() {
        let clock = ControlledTestScheduler()
        let keys = HeldVoiceShortcut()
        var edges: [(UInt16, Bool)] = []
        let post: KeyboardInjector.KeyStatePoster = { code, down, _ in edges.append((code, down)); return true }
        let session = VoiceFnTapSessionController(schedule: clock.voiceSchedule,
            setTriggerPressed: { down in keys.setPressed(down, shortcut: shortcut, post: post, hardwareFlags: { [] }) },
            enqueueAudio: { _ in }, drainAudio: { _, done in done() }, onFailure: { _ in Issue.record("Tap failed") })
        session.setEnabled(true)
        #expect(session.startVoice())
        clock.runAll()
        #expect(edges.map(\.0) == [59, 58, 56, 9, 9, 56, 58, 59])
        #expect(session.stopVoice())
        clock.runAll()
        #expect(edges.map(\.0) == Array(repeating: [59, 58, 56, 9, 9, 56, 58, 59], count: 2).flatMap { $0 })
        #expect(session.phase == .idle)
    }

    @Test func tapTriggerRetainsItsShortcutUntilCleanupCompletes() {
        var selected = VoiceKeyMode.suggestedShortcut
        var posted: [(VoiceKeyMode, Bool)] = []
        let trigger = VoiceTapTrigger(selectedMode: { selected }, setKey: { posted.append(($0, $1)); return true })
        #expect(trigger.setPressed(true))
        selected = .rightOption
        #expect(trigger.setPressed(false))
        #expect(trigger.setPressed(true))
        #expect(trigger.setPressed(false))
        #expect(posted.allSatisfy { $0.0 == .suggestedShortcut })
        trigger.reset()
        #expect(trigger.setPressed(true))
        #expect(posted.last?.0 == .rightOption)
        #expect(trigger.setPressed(false))
    }

}
