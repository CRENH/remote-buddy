import Foundation

extension AppSettings {
    static let maximumSettingsBackupBytes = 4_000_000

    func settingsBackupData(appVersion: String, now: Date = Date()) throws -> Data {
        let general = SettingsBackupDocument.General(
            applicationLanguage: applicationLanguage.rawValue,
            appIconIdentifier: appIconIdentifier.rawValue,
            showDockIcon: showDockIcon,
            showStatusBarIcon: showStatusBarIcon,
            openMainWindowAtLaunch: openMainWindowAtLaunch,
            checksForPreReleaseUpdates: checksForPreReleaseUpdates,
            diagnosticLoggingEnabled: diagnosticLoggingEnabled,
            customMappingEnabled: customMappingEnabled,
            disabledApplicationIntegrations: ApplicationIntegration.allCases.map(\.rawValue)
                .filter { !enabledApplicationIntegrations.contains($0) }
        )
        let remotes = remoteDeviceProfiles.map { profile in
            SettingsBackupDocument.Remote(
                model: profile.model,
                name: profile.customName,
                gainDB: gainDB(for: profile.id),
                g9n9nVoiceButtonMode: profile.model.isChromecastRemote
                    ? profile.effectiveG9N9NVoiceButtonMode : nil,
                mappings: profile.mappings
            )
        }
        let document = SettingsBackupDocument(
            exportedAt: now,
            appVersion: appVersion,
            general: general,
            customApplications: customApplicationProfiles,
            remotes: remotes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }
}
