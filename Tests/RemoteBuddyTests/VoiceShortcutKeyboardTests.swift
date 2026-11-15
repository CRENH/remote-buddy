import AppKit
import Testing
@testable import RemoteBuddy

@Suite("Voice shortcut physical keyboard selection")
struct VoiceShortcutKeyboardTests {
    private let v = StandardKeyboardKey("v", keyCode: 9, label: "V")

    @Test func selectingLeftControlAndRightOptionKeepsTheirSidesThroughPersistenceAndInjection() throws {
        var selection = VoiceKeyboardSelection(shortcut: StandaloneKeyboardModifier.function.shortcut)
        selection.toggle(.leftControl)
        selection.toggle(.rightOption)
        selection.select(v)
        #expect(selection.canUse)
        let shortcut = try #require(selection.shortcut)
        #expect(ShortcutEventSequence.selectedModifiers(for: shortcut.cgEventFlags).map(\.key) == [59, 61])
        let mode = VoiceKeyMode.shortcut(shortcut)
        let restored = try #require(VoiceKeyMode(rawValue: mode.rawValue))
        #expect(ShortcutEventSequence.selectedModifiers(for: restored.eventFlags).map(\.key) == [59, 61])
    }

    @Test func changingModifierSideReplacesTheEarlierSideInsteadOfHoldingBoth() throws {
        var selection = VoiceKeyboardSelection(shortcut: StandaloneKeyboardModifier.leftOption.shortcut)
        selection.toggle(.rightOption)
        selection.select(v)
        let shortcut = try #require(selection.shortcut)
        #expect(ShortcutEventSequence.selectedModifiers(for: shortcut.cgEventFlags).map(\.key) == [61])
        selection.toggle(.rightOption)
        #expect(!selection.canUse)
    }

    @Test func recordedSideSpecificChordsAndStandaloneModifiersRoundTripInTheEditor() throws {
        // Device bits from a physical left-Control + right-Shift key event.
        let flags = NSEvent.ModifierFlags.control.union(.shift).union(.init(rawValue: 0x0005))
        let captured = CustomKeyboardShortcut(keyCode: 9, modifierFlags: flags, keyLabel: "V")
        let selection = VoiceKeyboardSelection(shortcut: captured)
        #expect(selection.shortcut == captured)
        #expect(selection.modifiers.contains(.leftControl))
        #expect(selection.modifiers.contains(.rightShift))
        for modifier in [StandaloneKeyboardModifier.function, .leftOption, .rightOption, .leftCommand, .rightCommand] {
            let standalone = VoiceKeyboardSelection(shortcut: modifier.shortcut)
            #expect(standalone.canUse)
            #expect(standalone.shortcut == modifier.shortcut)
        }
    }

    @Test func fnIsStandaloneAndIncompleteSelectionsCannotBeUsed() {
        var selection = VoiceKeyboardSelection(shortcut: StandaloneKeyboardModifier.function.shortcut)
        selection.toggle(.leftControl)
        #expect(!selection.canUse)
        selection.toggle(.leftShift)
        #expect(selection.shortcut == nil)
        selection.select(v)
        #expect(selection.canUse)
        selection.toggle(.function)
        #expect(selection.shortcut == StandaloneKeyboardModifier.function.shortcut)
        #expect(selection.key == nil)
    }
}
