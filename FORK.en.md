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
- **The installer is not notarized by Apple.** It is signed with this repository's own fixed certificate, which differs from the official build (see [Signing certificate](#signing-certificate) below).

## Download and install

1. Download the latest `.pkg` from this repository's [Releases](https://github.com/CRENH/remote-buddy/releases). Only Apple Silicon (arm64) builds are provided for now; like upstream, it requires macOS 14 or later.
2. Double-click to install. If macOS says it cannot verify the developer, open **System Settings → Privacy & Security**, click **Open Anyway** near the bottom, then double-click the installer again.
3. After first installing a build signed with the fixed certificate, grant Accessibility, Input Monitoring and Bluetooth. Its signature differs from both the official build and this fork's earlier ad-hoc builds, so macOS treats it as a new app, even if you authorized one of those before. Later upgrades signed with the same certificate keep these permissions.

## Signing certificate

This fork's installers are signed with a fixed self-signed certificate (not an Apple Developer certificate). The public certificate is `scripts/signing/release-certificate.pem`:

- SHA-1 fingerprint: `ACA2B855C9F8F9A6C6711428F920BCB863BD53C4`
- Valid until 2036-11-12
- The fingerprint in upstream's `docs/releases.md` belongs to the official upstream certificate and does not apply to this fork.

To check an installed app, run `codesign --display -r- "/Applications/Remote Buddy.app"`; the output should contain `certificate leaf = H"aca2b855c9f8f9a6c6711428f920bcb863bd53c4"`.

Maintainers: keep the signing identity in `~/Library/Application Support/RemoteBuddySigning/` (see upstream [docs/build-and-signing.md](docs/build-and-signing.md) for how to generate one), then run `bash .github/scripts/build-signed-package.sh` from the repository root. The installer is written to `dist/release/`.

## Relationship with upstream

- This repository merges upstream `main` into the `crenh` branch automatically every day, so the source keeps up with upstream; installers are published manually from time to time.
- The common phrase extension has been submitted upstream as [PR #158](https://github.com/zfdang/remote-buddy/pull/158). Once merged, it will ship in the official build.
- Support for GY3LE, another Chromecast remote model, is planned.

## Feedback

- Issues specific to this fork (the features above, the installers): open an issue in this repository.
- Everything else: please report to the [upstream repository](https://github.com/zfdang/remote-buddy/issues).

## License

Same as upstream: [GPL-3.0](LICENSE).
