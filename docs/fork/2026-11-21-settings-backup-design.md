# 设计：按键映射与全局设置的备份和恢复

- 需求：[CRENH/remote-buddy#4](https://github.com/CRENH/remote-buddy/issues/4)
- 日期：2026-11-21
- 状态：待 Eric 审批
- 本文件只放在 `crenh` 分支（`docs/fork/` 是本分支专用目录），不进上游 PR。

## 1. 目的

开发阶段版本迭代快，新旧版本来回切换时，按键映射可能整份丢失：

- 2026-11-17 上游 `48ff77e` 去掉了旧的映射存储，切换版本后映射全部丢失，中间几个版本里的调整没有备份，找不回来。
- 现在的读取逻辑是：存储里只要有一个认不出的按键或动作，整份映射都作废，并重置为默认值。

要做两件事：

1. **手动导出 / 导入**：全局设置加每个遥控器的按键映射，存成一个 JSON 文件；导入时按遥控器型号对应。
2. **逐项读取**：无论读备份文件还是 App 启动时读自己的存储，认不出的项只跳过那一项，其余照常读入。

做好后向上游（zfdang/remote-buddy）提 PR。上游合并后，本分支就不需要单独维护这个功能了。

## 2. 目标与不做的事

**目标**

- 在「通用」设置页导出、导入一个 JSON 备份文件。
- 导入按遥控器型号对应，不依赖本机的设备档案 ID。
- 认不出的按键、动作或型号只跳过那一项；导入完成后弹窗列出跳过了哪些、为什么。
- App 启动读取存储时同样逐项读取，不再因为一个值整份作废。

**不做**

- 自动备份（Eric 2026-11-21 决定，这次只做手动）。
- 常用语：已有单独的导入 / 导出。
- 配对识别数据：蓝牙 ID、HID 指纹、兼容 HID 绑定。这些只在本机有效；同一台 Mac 上配对一直保留，换一台 Mac 要重新配对，导出了也没用。
- 安装向导进度、语音工具及语音键设置（`voiceKeyMode`、`voiceFnTapModeEnabled`、已验证的语音工具绑定）：这几项由安装向导一起设置并验证，和本机权限、验证状态绑定；单独导入语音键模式可能和本机验证过的语音工具对不上，导致语音键失灵。
- 兼容旧格式（上游 PR #153 删掉的那种文件）：上游规则是「假定没有旧数据」，不读旧格式。

**反目标（做出来但不能接受的情况）**

- 导入失败却没有提示，看起来像导入成功了。
- 导入把配对关系弄乱，遥控器需要重新配对。
- 逐项读取在启动时悄悄丢掉数据、原始数据也没保留，比现在更难恢复。

## 3. 约束

- 尽量放在新文件里，少改上游现有文件，减少每天同步时的冲突，也减少上游审核的工作量。
- 上游 `AGENTS.md`：Conventional Commits，`swift test --disable-keychain`，有行为变化必须加测试；不做旧数据迁移。
- 本机（MBP2015）编不了，编译和测试靠 GitHub Actions：
  - 以 `crenh` 为目标的 PR 跑 `Fork test`；
  - 上游 PR 跑上游自己的 CI。
- 本仓库是公开的，提交、PR 里不留 AI 署名。

## 4. 做法比较（Eric 选了 B）

| 做法 | 内容 | 取舍 |
|---|---|---|
| A | 全部放新文件，只有导入时逐项读 | 上游文件几乎不动；但「升级后启动时整份作废」这个根本问题还在 |
| **B（已选）** | 把逐项读放进存储格式本身，导入导出放新文件 | 多改上游 2 个文件（约 30–50 行）；导入和启动读取共用同一套逻辑，升级丢映射从根上解决，PR 理由也最充分 |
| C | 恢复上游 PR #153 删掉的旧代码 | 含上游明确不要的东西（旧存储、导入后待验证状态），旧格式也对不上现在的数据；不考虑 |

## 5. 备份文件格式（v1）

```json
{
  "format": "remote-buddy-settings",
  "formatVersion": 1,
  "exportedAt": "2026-11-21T08:00:00Z",
  "appVersion": "26.11.21",
  "general": {
    "applicationLanguage": "zh-Hans",
    "appIconIdentifier": "standard",
    "showDockIcon": false,
    "showStatusBarIcon": true,
    "openMainWindowAtLaunch": true,
    "checksForPreReleaseUpdates": false,
    "diagnosticLoggingEnabled": true,
    "customMappingEnabled": true,
    "disabledApplicationIntegrations": []
  },
  "customApplications": [
    {
      "id": "…UUID…",
      "displayName": "Ghostty",
      "bundleIdentifier": "com.mitchellh.ghostty",
      "applicationPath": "/Applications/Ghostty.app",
      "focusStrategy": "none"
    }
  ],
  "remotes": [
    {
      "model": "chromecast_voice_remote",
      "name": "客厅遥控器",
      "gainDB": 10,
      "g9n9nInputMode": "full",
      "g9n9nVoiceButtonMode": "smart_toggle",
      "mappings": { "buttonBindings": {}, "buttonShortcuts": {}, "buttonApplicationProfileIDs": {}, "secondaryButtonBindings": {} }
    }
  ]
}
```

- `general` 的各字段，以及 `customApplications`、`mappings` 的结构，直接沿用 App 现有的 Codable 类型（`CustomApplicationProfile`、`RemoteDeviceMappings`），不另造一套。
- `remotes` 里每个本机遥控器档案一项；不含 `bluetoothIdentifier`、`hidFingerprint`、`compatibleHIDBinding`。
- `exportedAt`、`appVersion` 只用来显示和排查问题，导入时不参与判断。

## 6. 导入规则

1. **整份拒绝**只有一种情况：`format` 不是 `remote-buddy-settings`，或者没有 `formatVersion`。这时提示「不是 Remote Buddy 设置文件」，什么都不改。
2. **版本更新的文件**（`formatVersion` 大于当前版本）：照样逐项导入，提示里加一句「文件来自更新的版本，部分设置可能没有导入」。
3. **导入前确认**：弹窗说明「会覆盖当前的按键映射和设置，建议先导出一份」，用户确认后才开始。
4. **全局设置**：逐个字段读，认不出的值（比如未知的语言或图标标识）跳过并列出；文件里没有的字段保持本机现值。
5. **自定义 App**：按 `bundleIdentifier` 认。
   - 本机已有同一 bundle ID 的 App：沿用本机那一项的 ID，其余字段用文件里的值。
   - 本机没有：新增一项（文件里的 ID 和本机其他 App 撞了就换一个新 ID）。
   - 系统找不到这个 App（没安装）：照样导入，弹窗里提示「本机未安装：xxx」。
   - 文件里的 App ID 和本机 ID 之间建一张对照表，映射里引用 App 的地方按这张表换成本机 ID；对照表里找不到的引用，丢弃那一项并列出。
6. **遥控器**：按型号对应。
   - 本机每个遥控器档案，在文件里找同型号的一项：同型号有多项时，先找名称相同的，找不到就用第一项。
   - 本机有多个同型号遥控器：每个都按上一条各自找；文件里只有一项，就都套用这一项。
   - 套用的内容：映射整份替换（是恢复，不是合并），加上音量增益和 G9N9N 的两种模式；遥控器名称、配对数据不改。
   - 文件里有、本机没有的型号：跳过并提示「本机没有 T1 遥控器，已跳过」。
   - 认不出的型号字符串：跳过并列出。
   - 本机有、文件里没有的型号：不动。
   - 当前选中的遥控器被改了：重新载入它的映射，界面马上更新（逻辑同 `selectRemoteProfile`）。
7. **映射里的单项**：认不出的按键、触发方式（单击 / 双击 / 长按）或动作，只跳过那一项。
8. **结果弹窗**：
   - 全部成功：一句「已导入 N 个遥控器的设置」。
   - 有跳过：按「遥控器 → 按键 → 原因」分组列出，原因用用户看得懂的话（「这个版本不认识的动作」「本机没有这个型号」）。

## 7. 启动时逐项读取（做法 B 的核心）

- 新增一个通用的「逐项解码」工具（新文件），按字典 / 数组逐项解码，解不出的项丢掉并计数。
- 用在两处：
  - `RemoteDeviceMappings` 的解码：四张映射表逐项读；
  - `AppSettings.init` 读 `remoteDeviceProfiles` 时：逐个档案读，一个档案的型号认不出只丢这个档案。
- **保留原始数据**：只要丢了任何一项，就沿用现有机制，把原始字节存到 `<key>.corrupt`，并把这个 key 加进 `corruptedSettingKeys`。这样映射页现有的「部分设置无法读取」提示照常出现，原始数据也还在。和现在的区别只是「其余能读的照常读入」，不再整份重置。
- 写日志：`SETTINGS decode_partial key=… dropped=N`，和现有的 `decode_failed` 日志风格一致。

## 8. 界面

- 「通用」设置页新增一个分组「备份与恢复」，两行：「导出设置…」「导入设置…」，样式沿用该页现有的 `aboutSection` / `preferenceRow`。
- 导出：用 `NSSavePanel`，默认文件名 `RemoteBuddy-Settings-YYYYMMDD.json`。
- 导入：用 `NSOpenPanel`，只选 `.json`；文件大小设上限（参照常用语导入的 `maximumImportBytes`）。
- 文案中英文都加（`Resources/en.lproj`、`Resources/zh-Hans.lproj`）。

## 9. 改动范围（预估）

| 类型 | 文件 | 说明 |
|---|---|---|
| 新增 | `Sources/RemoteBuddy/Support/LossyDecoding.swift` | 逐项解码工具 |
| 新增 | `Sources/RemoteBuddy/Settings/SettingsBackup.swift` | 备份文件格式、导入报告的数据结构 |
| 新增 | `Sources/RemoteBuddy/Settings/AppSettings.SettingsBackup.swift` | 导出、导入逻辑（`extension AppSettings`） |
| 新增 | `Sources/RemoteBuddy/Settings/SettingsView.SettingsBackup.swift` | 通用页的分组、文件面板、确认和结果弹窗 |
| 新增 | `Tests/RemoteBuddyTests/SettingsBackupTests.swift`、`LossySettingsDecodingTests.swift` | 测试 |
| 修改 | `Sources/RemoteBuddy/Devices/RemoteDeviceProfile.swift` | `RemoteDeviceMappings` 改为逐项解码 |
| 修改 | `Sources/RemoteBuddy/Settings/AppSettings.swift` | `remoteDeviceProfiles` 逐个档案读、保留原始数据 |
| 修改 | `Sources/RemoteBuddy/Settings/SettingsView.Preferences.swift` | 通用页插入一个分组（几行） |
| 修改 | 两个 `Localizable.strings` | 新文案 |

预计新增 500–700 行，其中约一半是测试。

## 10. 测试

- 逐项解码：映射里混一个未知动作，其余项保留，丢弃数为 1；档案数组里混一个未知型号，其余档案保留；原始数据写进 `.corrupt`。
- 导出再导入（同一台机器）：映射、增益、G9N9N 模式、全局设置都还原。
- 型号对应：本机没有的型号跳过并出现在报告里；同型号多项时按名称、再按第一项选；本机两个同型号遥控器都被套用。
- 自定义 App：同 bundle ID 沿用本机 ID，映射里的引用被换成本机 ID；没安装的 App 出现在报告里；找不到的引用被丢弃并报告。
- 格式：`format` 不对时整份拒绝、什么都不改；`formatVersion` 更大时照样导入并提示。
- 当前选中的遥控器被导入改写后，界面上的映射同步更新。

## 11. 交付方式

1. 从上游 `main` 切 `feat/settings-backup` 分支开发。
2. 开 PR 到本仓库 `crenh`：跑 `Fork test` 验证，Eric 合并后自己就能用上。
3. 同一分支向上游开 PR，中文正文；说明 #153 之后的实际丢失经历，强调这是备份，不是兼容旧数据。
4. 硬件验收（Eric 在 M2 上）：导出 → 改乱几个键 → 导入 → 映射复原；再手工改一个动作名，确认只跳过那一项、弹窗列出。

## 12. 留给实现者决定的细节

- 各个类型、函数的具体命名，弹窗的具体排版。
- 结果弹窗列出的条目过多时的截断方式（例如最多列 20 条，再加一句「另有 N 项」）。
- 导入时全局设置字段的应用顺序（参照 `AppSettings.init` 的顺序即可）。

## 13. 我替 Eric 做的决定（请审阅时确认）

1. 遥控器名称不随导入改写（名称只用来在同型号里配对）。
2. 自定义 App 匹配到本机已有项时，用文件里的值覆盖本机的聚焦方式等字段（导入就是恢复）。
3. 映射整份替换，不和本机现有映射合并。
4. 包含 `diagnosticLoggingEnabled` 和「已关闭的应用集成」列表。
5. 不导出、不导入安装向导状态和语音相关设置（语音工具、语音键模式、Fn 轻点模式）；换机器后语音部分重新走一遍安装向导。
