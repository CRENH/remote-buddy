# Remote Buddy fork (CRENH)

[简体中文](FORK.md) | **English**

This repository is a fork of [zfdang/remote-buddy](https://github.com/zfdang/remote-buddy), maintained by [CRENH](https://github.com/CRENH). For everyday usage see the [README](README.en.md); this page only covers how the fork differs from upstream. The source lives on the `crenh` branch.

## Differences from upstream

### Common phrases on 11 Chromecast remote buttons

For the Chromecast Voice Remote (G9N9N). Upstream assigns common phrases to 5 buttons (the four arrows and OK); this fork extends that to 11:

| Original 5 buttons | 6 new buttons |
|---|---|
| Up, Down, Left, Right, OK | Home, Mute, YouTube, Netflix, Power, Input |

- The 6 new buttons only take effect when the current remote is a Chromecast remote; Xiaomi and Siri remotes behave exactly as upstream.
- The common phrase panel adds a 6-button grid below the D-pad, laid out like the physical remote: Home, YouTube, Power on the left; Mute, Netflix, Input on the right.
- While the panel is open: Back and the voice button close it (the voice button does not start dictation); the volume buttons still change the volume; the other 11 buttons insert their phrases. Mute only inserts a phrase and does not mute the system.
- The **Edit Common Phrases** page lets you assign a phrase to each of the 11 buttons.
- Default phrases for the new buttons (in Chinese, editable): Home 「不对吧？」, Mute 「其他方案」, YouTube 「你会怎么选？」, Netflix 「总结结论」, Power 「先说怎么做」, Input 「都不接受，重新考虑」. Existing phrase data gains these defaults on upgrade; existing assignments are kept.
- The Input button uses an icon that matches the physical remote (an arrow entering a box from the left), also on the button mapping page.

### UI fixes

- With the English UI, the backup buttons and hint at the top of **Edit Common Phrases** are no longer truncated.
- Long action names on the button mapping page (such as “Open Common Phrases”) wrap instead of being truncated.

### Self-use build settings

- **Automatic updates are disabled**, so the build is not replaced by an official upstream release. To switch back, install from the [upstream Releases](https://github.com/zfdang/remote-buddy/releases).
- **The installer is not notarized by Apple**, and its signature differs from the official build (see installation below).

## Download and install

1. Download the latest `.pkg` from this repository's [Releases](https://github.com/CRENH/remote-buddy/releases). Only Apple Silicon (arm64) builds are provided for now; like upstream, it requires macOS 14 or later.
2. Double-click to install. If macOS says it cannot verify the developer, open **System Settings → Privacy & Security**, click **Open Anyway** near the bottom, then double-click the installer again.
3. After installing, grant Accessibility, Input Monitoring and Bluetooth again. Because the signature differs from the official build, macOS treats it as a new app, even if you authorized the official build before.

## Relationship with upstream

- This repository merges upstream `main` into the `crenh` branch automatically every day, so the source keeps up with upstream; installers are published manually from time to time.
- The common phrase extension has been submitted upstream as [PR #158](https://github.com/zfdang/remote-buddy/pull/158). Once merged, it will ship in the official build.
- Support for GY3LE, another Chromecast remote model, is planned.

## Feedback

- Issues specific to this fork (the features above, the installers): open an issue in this repository.
- Everything else: please report to the [upstream repository](https://github.com/zfdang/remote-buddy/issues).

## License

Same as upstream: [GPL-3.0](LICENSE).
