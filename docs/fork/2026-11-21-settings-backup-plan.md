# Plan: 按键映射与全局设置的备份和恢复

> **给执行者：** 用 `superpowers:executing-plans` 按任务逐个执行（Native 模式：本会话内联实现，每个任务一个 commit，最后一次全分支审查）。勾选框跟踪进度，勾选随该任务的 commit 一起提交。

- Spec：[docs/fork/2026-11-21-settings-backup-design.md](2026-11-21-settings-backup-design.md)（先读它）
- Issue：[CRENH/remote-buddy#4](https://github.com/CRENH/remote-buddy/issues/4)
- 代码分支：`feat/settings-backup`，**从 `upstream/main` 切出**（要提给上游）。本计划文件只在 `crenh` 侧（`docs/settings-backup-design` 分支），不进代码分支。
- 创建：2026-11-21

**目标：** 在「通用」设置页手动导出 / 导入一个 JSON 备份（全局设置 + 按型号的遥控器映射）；存储和备份都逐项解码，认不出的项只跳过那一项。

**架构：** 一个基于 `decoder.userInfo` 的逐项解码工具，同时用于 `RemoteDeviceMappings`、`AppSettings.init` 读档案，以及备份文件解析；导出 / 导入逻辑是 `extension AppSettings`，放在新文件里；界面是一个独立的 SwiftUI 子视图，插进 `generalPage`。

**技术栈：** Swift 6.2、SwiftUI / AppKit（`NSSavePanel`、`NSOpenPanel`）、Swift Testing（`@Suite` / `@Test` / `#expect`）。

## Global Constraints

- 本机（MBP2015）编不了 Swift 6.2：**所有编译和测试都在 CI 上跑**。T1 开始前先开一个以 `crenh` 为目标的 draft PR，之后每次 push 都会跑 `Fork test`（约 3–4 分钟），用 `gh pr checks <N> -R CRENH/remote-buddy --watch` 等结果。
- 测试命令（CI 内）：`swift test --disable-keychain`。
- 公开仓库：commit、PR 里不写 AI 署名、会话 ID、`@CRENH`、`(claude)`；分支名不带 `-claude`。
- Conventional Commits；commit 用 `git -C <dir> commit -m '…'`。
- 新代码放新文件；改上游已有文件只限：`Devices/RemoteDeviceProfile.swift`、`Settings/AppSettings.swift`、`Settings/SettingsView.Preferences.swift`、两个 `Localizable.strings`。
- 不导出、不导入：`bluetoothIdentifier`、`hidFingerprint`、`compatibleHIDBinding`、`g9n9nInputMode`、`voiceKeyMode`、`voiceFnTapModeEnabled`、安装向导状态、常用语。
- 备份文件标识 `"format": "remote-buddy-settings"`，`formatVersion` 当前为 `1`，大小上限 `4_000_000` 字节。

## Review Focus

1. **启动时丢档案后被立刻覆盖写回**：逐项解码丢了一个档案后，`didSet` 会马上存回不完整的数组；原始字节必须在此之前写进 `remoteDeviceProfiles.corrupt`。由 T1 的 `profilesDropOnlyTheUnknownModelAndKeepRawBytes` 覆盖。
2. **当前选中遥控器的界面不更新**：导入改了选中档案，但界面读的是 `buttonBindings` 等已发布属性。由 T3 的 `importRefreshesSelectedRemoteLiveMappings` 覆盖。
3. **自定义 App 引用断链**：文件里的 App UUID 和本机不同，映射引用必须换成本机 ID，否则按键点了没反应。由 T3 的 `applicationReferencesAreRemappedToLocalIDs` 覆盖。
4. **导入失败但看起来成功**：`format` 不对时必须抛错且一个设置都不改。由 T3 的 `wrongFormatThrowsAndChangesNothing` 覆盖。
5. **兼容模式遥控器被绕过保护改写映射**：由 T3 的 `compatibilityModeRemoteKeepsMappings` 覆盖。

---

## Execution budget

| Session | Tasks | Mode | Subagents (model) | Stop condition |
|---|---|---|---|---|
| 1 | T0–T4 | inline，每任务 1 commit，每任务 push 一次等 CI | 无 | T4 的 CI 绿，或 Eric 运行 `/ho` |
| 2（如需要） | T5 + 全分支审查 + T6 | inline + 1 次全分支审查 | reviewer（`opus`） | 上游 PR 开出 |

CI 失败（编译错误）就在同一任务内修，修到绿再勾选；同一任务连续 3 次 CI 失败就停下来报告。

## Tasks

- [x] **T0 — 建分支和 draft PR** [needs-human: push、开 PR]
  - `git -C ~/Documents/GitHub/Remote-Buddy fetch upstream`，`git -C ~/Documents/GitHub/Remote-Buddy switch --create feat/settings-backup upstream/main`。
  - 先完成 T1 的第一个 commit 再 push，然后 `gh pr create -R CRENH/remote-buddy --base crenh --head feat/settings-backup --draft`，中文标题 `feat: 按键映射与全局设置的备份和恢复`，正文写 `Closes #4` 之外的说明（本 PR 用于在 `crenh` 上验证和使用）。
  - Acceptance：`gh pr checks <N> -R CRENH/remote-buddy` 出现 `test` 检查。

### T1 — 逐项解码工具，并用于存储读取 [auto] depends: T0

**Files:**
- Create：`Sources/RemoteBuddy/Support/LossyDecoding.swift`
- Modify：`Sources/RemoteBuddy/Devices/RemoteDeviceProfile.swift`（给 `RemoteDeviceMappings` 加 `init(from:)`）
- Modify：`Sources/RemoteBuddy/Settings/AppSettings.swift`（`init` 里读 `remoteDeviceProfiles` 的那段）
- Test：`Tests/RemoteBuddyTests/LossySettingsDecodingTests.swift`

**Interfaces（Produces）：**
- `final class LossyDecodingLog { private(set) var droppedPaths: [[String]]; func record(_ codingPath: [any CodingKey]) }` — 记录每个被丢弃项的 coding path（每段取 `stringValue`，数组下标取 `intValue` 转字符串）。
- `extension CodingUserInfoKey { static let lossyDecodingLog: CodingUserInfoKey }`
- `struct LossyArray<Element: Decodable>: Decodable { var elements: [Element] }` — 逐个元素解码，失败的元素用一个空的 `Decodable` 占位类型吞掉以推进游标，并 `record`。
- `extension KeyedDecodingContainer { func decodeLossyDictionary<Value: Decodable>(_: Value.Type, forKey: Key) throws -> [String: Value] }` — key 不存在返回 `[:]`；值逐项解码，失败的 `record`（路径含该字典 key）。
- `extension KeyedDecodingContainer { func decodeLossyIfPresent<Value: Decodable>(_: Value.Type, forKey: Key) -> Value? }` — 解不出返回 nil 并 `record`（T2 要用）。
- `extension JSONDecoder { static func lossy(log: LossyDecodingLog) -> JSONDecoder }`
- `AppSettings` 内：`private static func decodeLossySetting<T: Decodable>(_: T.Type, forKey: String, from: UserDefaults, corrupted: inout [String]) -> T?`。

- [x] **Step 1：写失败测试** `LossySettingsDecodingTests`（`@Suite("Lossy settings decoding") @MainActor`）：
  - `mappingsDropOnlyTheUnknownAction`：JSON `{"buttonBindings":{"home":"showDesktop","ok":"future_action"},"buttonShortcuts":{},"secondaryButtonBindings":{"ok":{"longPress":{"action":"future_action"},"doubleClick":{"action":"escape"}}}}`，用 `JSONDecoder.lossy(log:)` 解 `RemoteDeviceMappings`；`#expect(parsedButtonBindings[.home] == .showDesktop)`、`parsedButtonBindings[.ok] == nil`、`parsedSecondaryButtonBindings[.ok]?[.doubleClick]?.action == .escape`、`parsedSecondaryButtonBindings[.ok]?[.longPress] == nil`、`log.droppedPaths.count == 2`。
  - `plainDecoderStillDecodesCleanMappings`：用普通 `JSONDecoder()` 解一份全部合法的映射，结果与原值相等（确认没有 log 也能工作）。
  - `profilesDropOnlyTheUnknownModelAndKeepRawBytes`：用临时 suite 建 `AppSettings`，`registerBluetoothRemote` 两个（`.rc003`、`.chromecastVoiceRemote`）；读出 `remoteDeviceProfiles` 的 data，用 `JSONSerialization` 把第一个档案的 `model` 改成 `"future_remote"` 再写回；新建 `AppSettings(defaults:)`：`#expect(remoteDeviceProfiles.count == 1)`、`remoteDeviceProfiles.first?.model == .chromecastVoiceRemote`、`corruptedSettingKeys.contains("remoteDeviceProfiles")`、`values.data(forKey: "remoteDeviceProfiles.corrupt") == 改写后的原始字节`。
  - `profileWithUnknownActionKeepsItsOtherMappings`：同上，但把 Chromecast 档案 `mappings.buttonBindings.home` 改成 `"future_action"`、`youtube` 保持合法；重载后档案仍在，`action(for: .youtube, profileID:)` 不变，`.home` 回到默认值，`corruptedSettingKeys.contains("remoteDeviceProfiles")`。
  - `cleanProfilesReportNothing`：未改动时重载，`corruptedSettingKeys.isEmpty`，`remoteDeviceProfiles.corrupt` 不存在。
- [x] **Step 2：commit 测试并 push，确认 CI 失败**（编译失败或断言失败都算）。
- [x] **Step 3：实现。**
  - `RemoteDeviceMappings.init(from:)`：四个字段都用 `decodeLossyDictionary`；`secondaryButtonBindings` 外层按按钮逐项、内层按触发方式逐项，内层空了就去掉该按钮。编码保持系统合成的不变（显式写 `CodingKeys`）。
  - `decodeLossySetting`：用 `JSONDecoder.lossy(log:)` 解；顶层解失败时，处理方式和现有 `decodeSetting` 完全一致（存 `.corrupt`、删 key、记 `decode_failed`）；解成功但 `log.droppedPaths` 非空时，存 `\(key).corrupt` = 原始字节、`corrupted.append(key)`、写日志 `SETTINGS decode_partial category=\(diagnosticSettingCategory(key)) dropped=\(count)`，返回解出的值。
  - `AppSettings.init` 中 `remoteDeviceProfiles` 改为 `decodeLossySetting(LossyArray<RemoteDeviceProfile>.self, …)?.elements`，其余逻辑不变。
- [x] **Step 4：push，CI 绿。**
- [x] **Step 5：勾选 T1，commit** `feat(settings): decode remote mappings entry by entry`（测试和实现可合为同一 commit 前的两个 commit，最终都在分支上）。

### T2 — 备份文件格式与导出 [auto] depends: T1

**Files:**
- Create：`Sources/RemoteBuddy/Settings/SettingsBackup.swift`
- Create：`Sources/RemoteBuddy/Settings/AppSettings.SettingsBackup.swift`
- Test：`Tests/RemoteBuddyTests/SettingsBackupTests.swift`

**Interfaces（Produces）：**
- `struct SettingsBackupDocument: Codable`，字段：`format: String`、`formatVersion: Int`、`exportedAt: Date`、`appVersion: String`、`general: General`、`customApplications: [CustomApplicationProfile]`、`remotes: [Remote]`；`static let formatIdentifier = "remote-buddy-settings"`、`static let currentFormatVersion = 1`。
  - `struct General: Codable`：全部可选，`applicationLanguage: String?`、`appIconIdentifier: String?`（存 rawValue，导入时再校验）、`showDockIcon: Bool?`、`showStatusBarIcon: Bool?`、`openMainWindowAtLaunch: Bool?`、`checksForPreReleaseUpdates: Bool?`、`diagnosticLoggingEnabled: Bool?`、`customMappingEnabled: Bool?`、`disabledApplicationIntegrations: [String]?`；`init(from:)` 每个字段用 `decodeLossyIfPresent`。
  - `struct Remote: Codable`：`model: RemoteModel`、`name: String`、`gainDB: Double?`、`g9n9nVoiceButtonMode: G9N9NVoiceButtonMode?`、`mappings: RemoteDeviceMappings`。
  - 文档 `init(from:)`：`format`、`formatVersion` 必须能解出，否则抛 `SettingsBackupError.notASettingsFile`；`format` 不等于标识也抛同一个错；`general` 解不出用空 `General`；`customApplications`、`remotes` 用 `LossyArray`。
- `enum SettingsBackupError: Error, Equatable { case notASettingsFile, fileTooLarge }`
- `extension AppSettings { static let maximumSettingsBackupBytes = 4_000_000; func settingsBackupData(appVersion: String, now: Date = Date()) throws -> Data }` — `JSONEncoder` 用 `[.prettyPrinted, .sortedKeys]` 和 `.iso8601`；`remotes` 按 `remoteDeviceProfiles` 顺序，`name` 取 `customName`。

- [x] **Step 1：写失败测试**（`@Suite("Settings backup") @MainActor`）：
  - `exportContainsHeaderGeneralAndRemotes`：两个遥控器、一个自定义 App；解析导出 JSON（`JSONSerialization`）：`format == "remote-buddy-settings"`、`formatVersion == 1`、`remotes` 有 2 项、`customApplications` 有 1 项、`general.showStatusBarIcon` 存在。
  - `exportLeavesOutPairingAndVoiceSettings`：导出字符串不含 `bluetoothIdentifier`、`hidFingerprint`、`compatibleHIDBinding`、`g9n9nInputMode`、`voiceKeyMode`、`voiceFnTapModeEnabled`。
  - `documentWithoutFormatIsRejected`：`{"formatVersion":1}` 和 `{"format":"other","formatVersion":1}` 解码都抛 `SettingsBackupError.notASettingsFile`。
- [x] **Step 2：push，CI 失败。**
- [x] **Step 3：实现上述类型和 `settingsBackupData`。**
- [x] **Step 4：push，CI 绿。**
- [x] **Step 5：勾选 T2，commit** `feat(settings): export settings backup`。

### T3 — 导入 [auto] depends: T2

**Files:**
- Modify：`Sources/RemoteBuddy/Settings/SettingsBackup.swift`（加报告类型）
- Modify：`Sources/RemoteBuddy/Settings/AppSettings.SettingsBackup.swift`
- Test：`Tests/RemoteBuddyTests/SettingsBackupTests.swift`

**Interfaces（Produces）：**
- `struct SettingsBackupImportReport: Equatable { var importedRemoteCount: Int; var skippedItems: [SkippedItem]; var missingApplications: [String]; var isFromNewerVersion: Bool; var isClean: Bool { skippedItems.isEmpty && missingApplications.isEmpty && !isFromNewerVersion } }`
- `struct SkippedItem: Equatable { enum Reason: Equatable { case unrecognizedValue, remoteModelNotOnThisMac, unknownApplicationReference, mappingLockedByCompatibilityMode }; var location: [String]; var reason: Reason }` — `location` 例：`["chromecast_voice_remote", "home", "longPress"]`、`["general", "appIconIdentifier"]`、`["t1_remote"]`。
- `func importSettingsBackup(from data: Data, isApplicationInstalled: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) throws -> SettingsBackupImportReport`
- 新文件内私有：`reloadSelectedRemoteProfileMappings()`，内容同 `selectRemoteProfile` 的 `withLoadingRemoteProfile { … }` 部分，但不改 `selectedRemoteProfileID`。

**导入顺序（spec §6）：** 大小超限抛 `fileTooLarge` → 用 `JSONDecoder.lossy(log:)` 解文档（抛错则什么都不改）→ log 里的路径转成 `.unrecognizedValue` 项 → 应用 `general`（`AppLanguage(rawValue:)` / `AppIconIdentifier(rawValue:)` 解不出记 `.unrecognizedValue`；`disabledApplicationIntegrations` 只保留 `ApplicationIntegration` 认识的值）→ 合并自定义 App，建 `[UUID: UUID]` 对照表 → 逐个本机档案按型号选文件项（同型号先比 `name == customName`，再取第一个）→ 套用：`allowsMappingEdits(for:)` 为 false 记 `.mappingLockedByCompatibilityMode` 并跳过映射；否则映射整份替换（引用 App 的项按对照表换 ID，找不到的删掉该项并记 `.unknownApplicationReference`）；`setGainDB(_:for:)`；`g9n9nVoiceButtonMode` 用 `setG9N9NVoiceButtonMode` → 文件里本机没有的型号记 `.remoteModelNotOnThisMac` → 选中档案被改则 `reloadSelectedRemoteProfileMappings()` → `formatVersion > currentFormatVersion` 时 `isFromNewerVersion = true`。

- [x] **Step 1：写失败测试**（同一 suite）：
  - `roundTripRestoresMappingsGainAndVoiceButtonMode`：导出 → 改乱（`setAction`、`setGainDB(3, …)`、`setG9N9NVoiceButtonMode(.holdToTalk, …)`）→ 导入：全部回到导出时的值，`report.isClean`，`importedRemoteCount == 2`。
  - `remoteModelMissingOnThisMacIsSkipped`：文件含 T1，本机没有：`skippedItems.contains(.init(location: ["t1_remote"], reason: .remoteModelNotOnThisMac))`。
  - `sameModelPicksMatchingNameThenFirst`：文件两个 `.rc003`（名 "A"、"B"），本机一个名 "B"：套用的是 "B" 的映射；改名为 "C" 再导入：套用 "A"。
  - `everyLocalRemoteOfTheModelReceivesTheMapping`：本机两个 `.chromecastVoiceRemote`，文件一项：两个档案的 `.home` 动作都等于文件值。
  - `unknownActionSkipsOnlyThatEntry`：文件里 Chromecast `home` 改为 `"future_action"`：`youtube` 照常导入，`skippedItems` 含 location 以 `"home"` 结尾、reason `.unrecognizedValue` 的一项。
  - `applicationReferencesAreRemappedToLocalIDs`：本机已有 bundle ID `com.example.app`（ID X），文件里同 bundle ID 的 App 是 ID Y，映射引用 Y：导入后 `customApplicationProfiles.count == 1`，引用变成 X。
  - `uninstalledApplicationIsImportedAndReported`：`isApplicationInstalled: { _ in false }`：App 被加入，`missingApplications == ["<displayName>"]`。
  - `unknownApplicationReferenceIsDropped`：映射引用一个文件和本机都没有的 UUID：该项被删，记 `.unknownApplicationReference`。
  - `wrongFormatThrowsAndChangesNothing`：抛 `notASettingsFile`，`remoteDeviceProfiles` 和 `showDockIcon` 等与导入前相等。
  - `newerFormatVersionStillImports`：`formatVersion: 2`：映射照常导入，`isFromNewerVersion == true`。
  - `importRefreshesSelectedRemoteLiveMappings`：选中档案被导入改写后，`settings.action(for: .home)`（不带 profileID）等于文件值。
  - `compatibilityModeRemoteKeepsMappings`：直接把本机 Chromecast 档案的 `g9n9nInputMode` 设为 `.twoKeyCompatibility`：映射不变，记 `.mappingLockedByCompatibilityMode`，增益照常导入。
  - `pairingDataIsUntouched`：导入前后各档案的 `bluetoothIdentifier`、`hidFingerprint`、`customName` 不变。
- [x] **Step 2：push，CI 失败。**
- [x] **Step 3：实现 `importSettingsBackup` 和报告类型。**
- [x] **Step 4：push，CI 绿。**
- [x] **Step 5：勾选 T3，commit** `feat(settings): import settings backup by remote model`。

### T4 — 通用页界面与文案 [auto] depends: T3

**Files:**
- Create：`Sources/RemoteBuddy/Settings/SettingsView.SettingsBackup.swift`
- Modify：`Sources/RemoteBuddy/Settings/SettingsView.Preferences.swift`（`generalPage` 里在 `settings.general.language_group` 分组之后加一个 `aboutSection(titleKey: "settings.general.backup_group") { SettingsBackupSection(settings: settings, localization: localization) }`）
- Modify：`Resources/en.lproj/Localizable.strings`、`Resources/zh-Hans.lproj/Localizable.strings`
- Test：`Tests/RemoteBuddyTests/SettingsBackupTests.swift`

**Interfaces：**
- `struct SettingsBackupSection: View`，`@ObservedObject var settings: AppSettings`、`let localization: LocalizationStore`；两行（导出 / 导入），行样式照抄 `preferenceRow` 的外观。
- `enum SettingsBackupMessage { static func summary(for report: SettingsBackupImportReport, localize: (String) -> String) -> String }` — 结果弹窗正文：首行 `settings.backup.import.done`（含遥控器数量）；有跳过时按 location 用 ` › ` 连接，型号段用 `RemoteModel(rawValue:)?.localizationKey` 本地化；最多列 20 条，超出加 `settings.backup.import.more`。
- 导出：`NSSavePanel`，`allowedContentTypes = [.json]`，默认名 `RemoteBuddy-Settings-yyyyMMdd.json`，`appVersion` 取 `Bundle.main` 的 `CFBundleShortVersionString`。
- 导入：先 `.alert` 确认（`settings.backup.import.confirm_*`），确认后 `NSOpenPanel` 选 `.json`，读文件、调 `importSettingsBackup`，结果 `.alert` 显示 `summary`；抛错时显示 `settings.backup.import.not_settings_file` / `settings.backup.import.too_large`。

**文案 key（中英各一）：** `settings.general.backup_group`（备份与恢复 / Backup & Restore）、`settings.backup.export.title`、`settings.backup.export.help`、`settings.backup.export.action`、`settings.backup.import.title`、`settings.backup.import.help`、`settings.backup.import.action`、`settings.backup.import.confirm_title`、`settings.backup.import.confirm_message`（会覆盖当前按键映射和设置，建议先导出一份）、`settings.backup.import.done`（已导入 %d 个遥控器的设置）、`settings.backup.import.skipped_header`、`settings.backup.import.reason.unrecognized_value`（这个版本不认识）、`settings.backup.import.reason.model_not_on_this_mac`（本机没有这个型号）、`settings.backup.import.reason.unknown_application`（找不到对应的 App）、`settings.backup.import.reason.compatibility_mode`（兼容模式下不能改映射）、`settings.backup.import.missing_apps`（本机未安装：%@）、`settings.backup.import.newer_version`、`settings.backup.import.more`（另有 %d 项）、`settings.backup.import.not_settings_file`、`settings.backup.import.too_large`、`settings.backup.error.title`。

- [x] **Step 1：写失败测试：**
  - `summaryListsSkippedItemsWithReasons`：一个含 `.remoteModelNotOnThisMac`（`["t1_remote"]`）和 `.unrecognizedValue`（`["chromecast_voice_remote","home"]`）的报告，用 `LocalizationStore` 的中文文本：正文含「本机没有这个型号」和「这个版本不认识」。
  - `summaryTruncatesAfterTwentyItems`：25 个跳过项：正文含「另有 5 项」。
  - `backupStringsExistInBothLanguages`：上面列出的每个 key，在中英两个 `Localizable.strings` 中都有（参照仓库里已有的本地化完整性测试写法）。
- [x] **Step 2：push，CI 失败。**
- [x] **Step 3：实现界面、`SettingsBackupMessage`、文案。**
- [x] **Step 4：push，CI 绿。**
- [x] **Step 5：勾选 T4，commit** `feat(settings): add backup and restore to the general page`；把 draft PR 转为正式（`gh pr ready`）。

- [x] **T5 — 全分支审查** [needs-human: 看审查结论] depends: T4
  - 派 1 个 reviewer（`model: opus`），审 `upstream/main...feat/settings-backup` 全部改动，对照 spec 和本计划的 Review Focus。
  - 修完审查意见再 push，CI 绿。
  - Acceptance：审查无未处理的严重问题；PR 的 `test` 检查为 pass。

- [ ] **T6 — 硬件验收与上游 PR** [needs-human: Eric 在 M2 上验收；合并 fork PR] depends: T5
  - Eric 合并本仓库 PR（建议 squash），打包安装后在 M2 上验收：导出 → 改乱几个键 → 导入 → 映射复原；在导出文件里把一个动作改成不存在的名字再导入，只跳过那一项、弹窗列出。
  - 验收通过后，同一分支向上游开 PR：`gh pr create -R zfdang/remote-buddy --base main --head CRENH:feat/settings-backup`，中文正文：#153 之后的实际丢失经历、这是备份不是兼容旧数据、逐项解码顺带修了「一个值整份作废」、测试清单、未做硬件验收的部分。
  - Acceptance：上游 PR 链接已给 Eric。

## Handoff

- Last session ended：2026-11-21，T0–T5 完成。代码在 `feat/settings-backup`，最后一个 commit `dccaf7c`（worktree `~/.claude/worktrees/remote-buddy-settings-backup`）；PR [CRENH/remote-buddy#7](https://github.com/CRENH/remote-buddy/pull/7) 是正式 PR、可合并，`Fork test` 绿（959 个测试）。计划在 `docs/settings-backup-design` 分支，已推送，**还没有 PR**。下一步 T6，不是多任务批次。
- T6 交接要点：
  - 先 `gh pr view 7 -R CRENH/remote-buddy --json state,mergedAt` 看 Eric 是否已合并。已合并：用 `~/Documents/GitHub/Claude-Code-Config/git-tools/pull-main.sh ~/Documents/GitHub/Remote-Buddy` 更新 `crenh`（主目录目前停在 docs 分支，脚本若要求切到默认分支，先 `git -C ~/Documents/GitHub/Remote-Buddy switch crenh`）。
  - M2 打包安装步骤还没给 Eric：先在仓库里找打包 / 安装脚本（`scripts/`、`README`、`AGENTS.md`），再按 shared memory「M2: 仓库路径与 Swift 编译」（路径 `~/Documents/Projects/GitHub/Remote-Buddy`，`swift` 前要 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`；M2 无 git，靠 Syncthing 同步）写成可复制的逐步命令，并给出验收判据。
  - 验收通过后向上游开 PR（squash 合并 #7 不影响 `feat/settings-backup` 分支本身，上游 PR 用它）；上游 PR 正文中文、无 AI 痕迹。
  - 计划 / 设计文档（`docs/fork/`）要进 `crenh`：T6 结束时为 `docs/settings-backup-design` 开一个到 `crenh` 的 PR。
- 实现时与计划不同的地方（T5 审查时对照）：
  - `LossyDictionary` / `LossyCodingKey` 也是公开工具类型；`secondaryButtonBindings` 内层为空时保留原样（不去掉按钮），与旧解码行为一致。
  - `SettingsBackupDocument.exportedAt` / `appVersion` 为可选；`Remote` 的 `name`、`gainDB`、`g9n9nVoiceButtonMode` 也逐项解码，未知语音键模式不会让整个遥控器被丢掉。
  - `appIconIdentifier` 不校验（App 本身接受任意字符串，显示时回退到标准图标）。
  - 引用找不到的 App 时，删掉该按键的整项映射（单击连同动作和快捷键），按键回到默认值。
  - `SkippedItem` 嵌套为 `SettingsBackupImportReport.SkippedItem`，报告自动去重；`SettingsBackupMessage.summary(for:using:)` 用 `LocalizationStore` 而不是闭包，以便复用按键 / 手势的显示名。
  - 新增文案 `settings.backup.export.failed`、`settings.backup.import.item`、`settings.backup.import.read_failed`、`settings.backup.import.result_title`。
  - `SettingsBackupSection` 多一个 `onImported` 回调：导入后调用 `localization.select`、`setDockIconVisible`、`setStatusBarIconVisible`，否则语言和 Dock / 状态栏图标要重启才生效。
- State（开工前）：
  - 设计已获 Eric 批准（2026-11-21）；执行预算已获 Eric 批准（2026-11-21），**T0–T4 是一批，一口气做完，中途不再等确认**（同一任务 CI 连续 3 次失败的停止条件照旧）。T4 完成后向 Eric 汇报，T5（opus 全分支审查）、T6（Eric 硬件验收 + 上游 PR）随后。
  - PR #6（同步上游 + `Fork test`）已合并，`crenh` 在 `9ddeda5`；本地 `origin/HEAD` 已指向 `crenh`（LazyGit `U`/`N` 因此恢复正常）。
  - 远程旧分支（`main`、`feat/chromecast-phrase-keys`、`feat/g9n9n-phrase-keys`、`chore/sync-upstream-cba678d`）由 Eric 在 MBP2015 上手动删除（Claude 的 `git push --delete` 被权限拦截）。开工前跑 `git -C ~/Documents/GitHub/Remote-Buddy ls-remote --heads origin` 确认；没删就提醒 Eric 一句，不阻塞 T0。
  - 电源键（Chromecast 常用语第 11 键）单独一个上游 PR，排在本计划之后，另行 brainstorm；调查结论：常用语分配是全型号共用一张表，面板布局按型号分开；小米 RC003 / T1 的电源键有系统睡眠语义（App 在自定义按键开启时改成 F20），Chromecast 没有。
- Gotchas：
  - MBP2015 编不了 Swift 6.2，测试全靠 `Fork test`（push 到以 `crenh` 为目标的 PR 时触发）。
  - **计划文件只在 `docs/settings-backup-design` 分支上**，而 `feat/settings-backup` 从 `upstream/main` 切出、没有这个文件。代码放到单独的 worktree 里做，主目录留在 docs 分支上，好随时勾选计划：`git -C ~/Documents/GitHub/Remote-Buddy worktree add ~/.claude/worktrees/remote-buddy-settings-backup -b feat/settings-backup upstream/main`（worktree 放在 Syncthing 目录外，不会同步到 M2）。
  - 公开仓库：commit / PR 不带 AI 署名、会话 ID、`@CRENH`、`(claude)`；PR 正文中文。
  - `setG9N9NInputMode` 在安装向导完成后是 no-op，测试里要直接改 `remoteDeviceProfiles[i].g9n9nInputMode`。
  - `aboutSection` / `preferenceRow` 是 `private`，新分组只能在 `SettingsView.Preferences.swift` 的 `generalPage` 里调用。
  - 删除远程分支、`reset --hard` 这类命令会被权限拦截，换不破坏性的做法或交给 Eric。
- Open questions：无。
- T5 结果（2026-11-21）：`opus` 审查结论「修完可合并」，无严重问题；5 个 Review Focus 都已覆盖。已在 `dccaf7c` 修复，CI 绿（959 个测试）：
  - 导入后「自定义映射」开关不生效：`onImported` 加 `setCustomMappingEnabled`（会刷新权限并 `applyHIDSettings`）。
  - 认不出的按键 / 手势 key 被静默丢弃：`RemoteDeviceMappings` 解码时记录这些 key（数据保留），启动时因此写 `.corrupt`、导入时列在报告里。代价：未编辑过的档案每次启动都会出现「部分设置无法读取」提示，直到改过一次映射。
  - 小问题：数组里的 `null` 元素、超出范围的增益（报告列出）、`exportedAt` / `appVersion` 不再报告、`SettingsBackupSection` 不再订阅 settings、英文完成提示的单复数；补了通用设置往返、未知语言、未知型号字符串、未知按键、长按手势的 App 引用换算等测试。
  - 未处理（记为后续）：启动时 App / 快捷键引用断掉后动作留空（上游原有行为）；「部分设置无法读取」提示文案写的是「已重置为默认」，部分读入时不够准确（上游文件的文案）；自定义 App 列表启动时仍是整份解码（spec 范围外）。
- Next step：T6——Eric 合并 [CRENH/remote-buddy#7](https://github.com/CRENH/remote-buddy/pull/7)（建议 squash），打包后在 M2 上做硬件验收；通过后同一分支向上游开 PR。
- Resume prompt：`读 ~/Documents/GitHub/Remote-Buddy/docs/fork/2026-11-21-settings-backup-plan.md，从 T6 继续`
