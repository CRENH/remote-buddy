import Foundation
import Testing
@testable import RemoteBuddy

@Suite("Settings backup")
@MainActor
struct SettingsBackupTests {
    private struct Fixture {
        let settings: AppSettings
        let values: UserDefaults
        let name: String
        let xiaomi: UUID
        let google: UUID

        func tearDown() { values.removePersistentDomain(forName: name) }
    }

    private func fixture() throws -> Fixture {
        let name = "settings-backup-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(defaults: values)
        let xiaomi = settings.registerBluetoothRemote(identifier: UUID(), model: .rc003)
        let google = settings.registerBluetoothRemote(identifier: UUID(), model: .chromecastVoiceRemote)
        return Fixture(settings: settings, values: values, name: name, xiaomi: xiaomi, google: google)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func exportContainsHeaderGeneralAndRemotes() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        fixture.settings.addCustomApplicationProfile(.init(
            displayName: "Example", bundleIdentifier: "com.example.app", applicationPath: "/Applications/Example.app"))

        let object = try jsonObject(try fixture.settings.settingsBackupData(appVersion: "1.0"))
        #expect(object["format"] as? String == "remote-buddy-settings")
        #expect(object["formatVersion"] as? Int == 1)
        #expect((object["remotes"] as? [Any])?.count == 2)
        #expect((object["customApplications"] as? [Any])?.count == 1)
        let general = try #require(object["general"] as? [String: Any])
        #expect(general["showStatusBarIcon"] != nil)
    }

    @Test func exportLeavesOutPairingAndVoiceSettings() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        fixture.settings.bindHIDFingerprint("fingerprint", to: fixture.xiaomi)

        let text = String(decoding: try fixture.settings.settingsBackupData(appVersion: "1.0"), as: UTF8.self)
        for key in ["bluetoothIdentifier", "hidFingerprint", "compatibleHIDBinding", "g9n9nInputMode",
                    "voiceKeyMode", "voiceFnTapModeEnabled"] {
            #expect(!text.contains(key), "export must not contain \(key)")
        }
    }

    @Test func documentWithoutFormatIsRejected() {
        for json in [#"{"formatVersion":1}"#, #"{"format":"other","formatVersion":1}"#, "[]"] {
            #expect(throws: SettingsBackupError.notASettingsFile) {
                try JSONDecoder().decode(SettingsBackupDocument.self, from: Data(json.utf8))
            }
        }
    }
}
