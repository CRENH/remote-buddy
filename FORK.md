# Remote Buddy 分支版本（CRENH）

**简体中文** | [English](FORK.en.md)

本仓库基于 [zfdang/remote-buddy](https://github.com/zfdang/remote-buddy)，由 [CRENH](https://github.com/CRENH) 维护。日常使用说明见 [README](README.md)；本页只说明与上游的区别。源码在 `crenh` 分支。

## 与上游的区别

常用语扩展按键已由 [PR #158](https://github.com/zfdang/remote-buddy/pull/158) 合并进上游，本仓库直接使用上游的实现（含小米、T1 遥控器的扩展键）。本分支只多一处改动：

### Chromecast 遥控器的电源键插入常用语

- 上游：常用语弹窗打开时，电源键和返回键一样关闭弹窗，Chromecast 遥控器有 10 个常用语键。
- 本分支：Chromecast 遥控器（G9N9N）的电源键改为插入常用语，共 11 个键；默认常用语为「不对，再检查一下」，可在「调整常用语」页面修改。小米、T1 遥控器的电源键仍按上游关闭弹窗。
- 保存的常用语里给电源键分配过内容时，上游版本会判定整份常用语数据无效并重置为内置常用语；本分支能正常读取。从本分支切换到上游版本前，先在「调整常用语」页面清除电源键的分配。

### 自用版本的设置

- **「关于」页面**：去掉了「官网」「官网直接下载」两项，「GitHub 发布下载」「GitHub」「问题反馈」指向本仓库。
- **关闭了自动更新。** 避免被上游官方版本覆盖。想换回官方版本，请到 [上游 Releases](https://github.com/zfdang/remote-buddy/releases) 下载安装。
- **安装包没有经过 Apple 公证**，用本仓库自己的固定证书签名，和官方版本不同（见下方「签名证书」）。

## 下载与安装

1. 到本仓库的 [Releases](https://github.com/CRENH/remote-buddy/releases) 下载最新的 `.pkg` 安装包。目前只提供 Apple Silicon（arm64）版本；系统要求与上游相同，为 macOS 14 及以上。
2. 双击安装。如果系统提示无法验证开发者：打开「系统设置 → 隐私与安全性」，在页面下方点「仍要打开」，再重新双击安装包。
3. 第一次安装固定证书签名的版本后，授予权限：辅助功能、输入监控、蓝牙。签名与官方版本、本仓库早期的临时签名版本都不同，系统会把它当成一个新 App，之前授过权也要重新授权。之后升级到同一张证书签名的新版本，授权会保留。

## 签名证书

本仓库的安装包用一张固定的自签名证书签名（不是 Apple 开发者证书）。公开证书在 `scripts/signing/release-certificate.pem`：

- SHA-1 指纹：`ACA2B855C9F8F9A6C6711428F920BCB863BD53C4`
- 有效期至 2036-11-12
- 上游 `docs/releases.md` 里写的是上游官方证书的指纹，不适用于本仓库。

核对已安装的 App：运行 `codesign --display -r- "/Applications/Remote Buddy.app"`，输出里应有 `certificate leaf = H"aca2b855c9f8f9a6c6711428f920bcb863bd53c4"`。

维护者打包：签名身份放在 `~/Library/Application Support/RemoteBuddySigning/`（生成方法见上游 [docs/build-and-signing.md](docs/build-and-signing.md)），在仓库根目录运行 `bash .github/scripts/build-signed-package.sh`，安装包输出到 `dist/release/`。

## 只备份按键映射（上游版本也能用）

本分支版本在「设置 → 通用 → 备份与恢复」里可以导出、导入全部设置。只想备份按键映射，或者用的是上游版本，可以用 `.github/scripts/remote_buddy_mappings.py`。它只读写各遥控器的映射和自定义 App 列表，配对、增益和其他设置都不动。上游版本和本分支版本共用同一个设置域 `com.zfdang.remote-buddy`，两边都能用。

在仓库根目录运行：

```bash
python3 .github/scripts/remote_buddy_mappings.py backup
python3 .github/scripts/remote_buddy_mappings.py restore ~/RemoteBuddy-Backup/mappings-<时间>.json
```

- `backup` 默认写到 `~/RemoteBuddy-Backup/`。
- `restore` 默认只试运行，列出每个遥控器对应备份里的哪一项、哪些键会变；先退出 App，再加 `--apply` 真正写入。写入前会把完整设置另存为 `before-restore-<时间>.plist`，并打印撤销命令。
- 本机遥控器按「同一个档案 → 型号和名称相同 → 型号相同」对应备份。备份里引用的自定义 App 按 bundle ID 换成本机的 App，本机没有的会加进列表。
- 恢复到更旧的版本时，旧版本认不出的值会让它把整份映射重置为默认（上游的读取规则），尽量恢复到同版本或更新的版本。

## 与上游的关系

- 本仓库每天自动把上游 `main` 合并进 `crenh` 分支，源码会持续包含上游的最新改动；安装包则不定期手动发布。
- 常用语扩展功能已于 2026-11-16 通过 [PR #158](https://github.com/zfdang/remote-buddy/pull/158) 合并进上游。
- 计划之后支持 Chromecast 遥控器的另一个型号 GY3LE。

## 问题反馈

- 本分支版本特有的问题（电源键常用语、安装包）：请在本仓库提 issue。
- 其他问题：请到 [上游仓库](https://github.com/zfdang/remote-buddy/issues) 反馈。

## 许可证

与上游相同，采用 [GPL-3.0](LICENSE)。
