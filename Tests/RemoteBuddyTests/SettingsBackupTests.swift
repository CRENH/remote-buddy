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

    private func remote(
        _ model: RemoteModel,
        name: String = "",
        gainDB: Double? = nil,
        _ change: (inout RemoteDeviceMappings) -> Void = { _ in }
    ) -> SettingsBackupDocument.Remote {
        var mappings = AppSettings.defaultMappings(for: model)
        change(&mappings)
        return .init(model: model, name: name, gainDB: gainDB, g9n9nVoiceButtonMode: nil, mappings: mappings)
    }

    private func backup(
        _ remotes: [SettingsBackupDocument.Remote],
        applications: [CustomApplicationProfile] = [],
        formatVersion: Int = SettingsBackupDocument.currentFormatVersion
    ) throws -> Data {
        var document = SettingsBackupDocument(
            exportedAt: Date(), appVersion: "test", general: .init(),
            customApplications: applications, remotes: remotes
        )
        document.formatVersion = formatVersion
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private func importBackup(_ data: Data, into settings: AppSettings) throws -> SettingsBackupImportReport {
        try settings.importSettingsBackup(from: data, isApplicationInstalled: { _ in true })
    }

    @Test func roundTripRestoresMappingsGainAndVoiceButtonMode() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        settings.selectRemoteProfile(fixture.xiaomi)
        settings.setAction(.showDesktop, for: .home)
        settings.setBaseBinding(.init(action: .escape, shortcut: nil), for: .youtube,
            trigger: .singleClick, profileID: fixture.google)
        settings.setGainDB(5, for: fixture.google)
        let exported = try settings.settingsBackupData(appVersion: "1.0")

        settings.setAction(.commandCopy, for: .home)
        settings.setBaseBinding(.init(action: .commandPaste, shortcut: nil), for: .youtube,
            trigger: .singleClick, profileID: fixture.google)
        settings.setGainDB(3, for: fixture.google)
        settings.setG9N9NVoiceButtonMode(.holdToTalk, for: fixture.google)

        let report = try importBackup(exported, into: settings)
        #expect(settings.action(for: .home) == .showDesktop)
        #expect(settings.action(for: .youtube, profileID: fixture.google) == .escape)
        #expect(settings.gainDB(for: fixture.google) == 5)
        #expect(settings.g9n9nVoiceButtonMode(for: fixture.google) == .smartToggle)
        #expect(report.isClean)
        #expect(report.importedRemoteCount == 2)
    }

    @Test func remoteModelMissingOnThisMacIsSkipped() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let report = try importBackup(try backup([remote(.t1Remote)]), into: fixture.settings)
        #expect(report.skippedItems.contains(.init(location: ["t1_remote"], reason: .remoteModelNotOnThisMac)))
        #expect(report.importedRemoteCount == 0)
    }

    @Test func sameModelPicksMatchingNameThenFirst() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        settings.updateRemoteProfile(fixture.xiaomi, model: .rc003, customName: "B")
        let data = try backup([
            remote(.rc003, name: "A") { $0.buttonBindings["home"] = .showDesktop },
            remote(.rc003, name: "B") { $0.buttonBindings["home"] = .escape },
        ])
        _ = try importBackup(data, into: settings)
        #expect(settings.action(for: .home, profileID: fixture.xiaomi) == .escape)

        settings.updateRemoteProfile(fixture.xiaomi, model: .rc003, customName: "C")
        _ = try importBackup(data, into: settings)
        #expect(settings.action(for: .home, profileID: fixture.xiaomi) == .showDesktop)
    }

    @Test func everyLocalRemoteOfTheModelReceivesTheMapping() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        let second = settings.registerBluetoothRemote(identifier: UUID(), model: .chromecastVoiceRemote)
        #expect(second != fixture.google)
        let report = try importBackup(
            try backup([remote(.chromecastVoiceRemote) { $0.buttonBindings["home"] = .showDesktop }]),
            into: settings
        )
        #expect(settings.action(for: .home, profileID: fixture.google) == .showDesktop)
        #expect(settings.action(for: .home, profileID: second) == .showDesktop)
        #expect(report.importedRemoteCount == 2)
    }

    @Test func unknownActionSkipsOnlyThatEntry() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let data = try backup([remote(.chromecastVoiceRemote) { $0.buttonBindings["youtube"] = .escape }])
        var object = try jsonObject(data)
        var remotes = try #require(object["remotes"] as? [[String: Any]])
        var mappings = try #require(remotes[0]["mappings"] as? [String: Any])
        var bindings = try #require(mappings["buttonBindings"] as? [String: Any])
        bindings["home"] = "future_action"
        mappings["buttonBindings"] = bindings
        remotes[0]["mappings"] = mappings
        object["remotes"] = remotes

        let report = try importBackup(try JSONSerialization.data(withJSONObject: object), into: fixture.settings)
        #expect(fixture.settings.action(for: .youtube, profileID: fixture.google) == .escape)
        #expect(report.skippedItems.contains(
            .init(location: ["chromecast_voice_remote", "home"], reason: .unrecognizedValue)))
        #expect(report.importedRemoteCount == 1)
    }

    @Test func applicationReferencesAreRemappedToLocalIDs() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        let localID = settings.addCustomApplicationProfile(.init(
            displayName: "Example", bundleIdentifier: "com.example.app", applicationPath: "/Applications/Example.app"))
        let fileApplication = CustomApplicationProfile(
            displayName: "Example 2", bundleIdentifier: "com.example.app", applicationPath: "/Applications/Example.app")
        let data = try backup([remote(.chromecastVoiceRemote) {
            $0.buttonBindings["home"] = .openCustomApplication
            $0.buttonApplicationProfileIDs = ["home": fileApplication.id]
        }], applications: [fileApplication])

        let report = try importBackup(data, into: settings)
        #expect(settings.customApplicationProfiles.count == 1)
        #expect(settings.customApplicationProfiles.first?.id == localID)
        #expect(settings.customApplicationProfiles.first?.displayName == "Example 2")
        #expect(settings.applicationProfileID(for: .home, profileID: fixture.google) == localID)
        #expect(report.isClean)
    }

    @Test func uninstalledApplicationIsImportedAndReported() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let application = CustomApplicationProfile(
            displayName: "Missing", bundleIdentifier: "com.example.missing", applicationPath: "/Applications/Missing.app")
        let report = try fixture.settings.importSettingsBackup(
            from: try backup([], applications: [application]), isApplicationInstalled: { _ in false })
        #expect(fixture.settings.customApplicationProfiles.contains { $0.bundleIdentifier == "com.example.missing" })
        #expect(report.missingApplications == ["Missing"])
    }

    @Test func unknownApplicationReferenceIsDropped() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let data = try backup([remote(.chromecastVoiceRemote) {
            $0.buttonBindings["home"] = .openCustomApplication
            $0.buttonApplicationProfileIDs = ["home": UUID()]
        }])
        let report = try importBackup(data, into: fixture.settings)
        #expect(fixture.settings.applicationProfileID(for: .home, profileID: fixture.google) == nil)
        #expect(fixture.settings.action(for: .home, profileID: fixture.google) == .appSwitcher)
        #expect(report.skippedItems.contains(
            .init(location: ["chromecast_voice_remote", "home"], reason: .unknownApplicationReference)))
    }

    @Test func wrongFormatThrowsAndChangesNothing() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        let profiles = settings.remoteDeviceProfiles
        let showDockIcon = settings.showDockIcon
        let data = Data(#"{"format":"other","formatVersion":1,"general":{"showDockIcon":true},"remotes":[]}"#.utf8)
        #expect(throws: SettingsBackupError.notASettingsFile) { try importBackup(data, into: settings) }
        #expect(throws: SettingsBackupError.notASettingsFile) {
            try importBackup(Data("not json".utf8), into: settings)
        }
        #expect(settings.remoteDeviceProfiles == profiles)
        #expect(settings.showDockIcon == showDockIcon)
    }

    @Test func oversizedFileIsRejected() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let data = Data(count: AppSettings.maximumSettingsBackupBytes + 1)
        #expect(throws: SettingsBackupError.fileTooLarge) { try importBackup(data, into: fixture.settings) }
    }

    @Test func newerFormatVersionStillImports() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let data = try backup([remote(.chromecastVoiceRemote) { $0.buttonBindings["home"] = .showDesktop }],
            formatVersion: 2)
        let report = try importBackup(data, into: fixture.settings)
        #expect(fixture.settings.action(for: .home, profileID: fixture.google) == .showDesktop)
        #expect(report.isFromNewerVersion)
    }

    @Test func importRefreshesSelectedRemoteLiveMappings() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        settings.selectRemoteProfile(fixture.google)
        _ = try importBackup(
            try backup([remote(.chromecastVoiceRemote) { $0.buttonBindings["home"] = .showDesktop }]),
            into: settings
        )
        #expect(settings.action(for: .home) == .showDesktop)
        #expect(AppSettings(defaults: fixture.values).action(for: .home) == .showDesktop)
    }

    @Test func compatibilityModeRemoteKeepsMappings() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        let index = try #require(settings.remoteDeviceProfiles.firstIndex { $0.id == fixture.google })
        settings.remoteDeviceProfiles[index].g9n9nInputMode = .twoKeyCompatibility
        let data = try backup([remote(.chromecastVoiceRemote, gainDB: 7) { $0.buttonBindings["home"] = .showDesktop }])

        let report = try importBackup(data, into: settings)
        #expect(settings.action(for: .home, profileID: fixture.google) == .appSwitcher)
        #expect(settings.gainDB(for: fixture.google) == 7)
        #expect(report.skippedItems.contains(
            .init(location: ["chromecast_voice_remote"], reason: .mappingLockedByCompatibilityMode)))
    }

    @Test func pairingDataIsUntouched() throws {
        let fixture = try fixture()
        defer { fixture.tearDown() }
        let settings = fixture.settings
        settings.bindHIDFingerprint("fingerprint", to: fixture.xiaomi)
        settings.updateRemoteProfile(fixture.google, model: .chromecastVoiceRemote, customName: "Living room")
        let before = settings.remoteDeviceProfiles.map { [$0.id.uuidString, $0.bluetoothIdentifier?.uuidString ?? "",
                                                          $0.hidFingerprint ?? "", $0.customName] }
        _ = try importBackup(try backup([remote(.rc003, name: "Other"), remote(.chromecastVoiceRemote, name: "Den")]),
            into: settings)
        let after = settings.remoteDeviceProfiles.map { [$0.id.uuidString, $0.bluetoothIdentifier?.uuidString ?? "",
                                                         $0.hidFingerprint ?? "", $0.customName] }
        #expect(after == before)
    }

    @Test func documentWithoutFormatIsRejected() {
        for json in [#"{"formatVersion":1}"#, #"{"format":"other","formatVersion":1}"#, "[]"] {
            #expect(throws: SettingsBackupError.notASettingsFile) {
                try JSONDecoder().decode(SettingsBackupDocument.self, from: Data(json.utf8))
            }
        }
    }
}
