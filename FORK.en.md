# Remote Buddy fork (CRENH)

[简体中文](FORK.md) | **English**

This repository is a fork of [zfdang/remote-buddy](https://github.com/zfdang/remote-buddy), maintained by [CRENH](https://github.com/CRENH). For everyday usage see the [README](README.en.md); this page only covers how the fork differs from upstream. The source lives on the `crenh` branch.

## Differences from upstream

The extra common-phrase buttons were merged upstream in [PR #158](https://github.com/zfdang/remote-buddy/pull/158); this fork uses the upstream implementation as-is (including the Xiaomi and T1 extra buttons). It differs in one place:

### Power inserts a common phrase on the Chromecast remote

- Upstream: while the common-phrase panel is open, Power closes it like Back, leaving 10 phrase buttons on the Chromecast remote.
- This fork: Power on the Chromecast Voice Remote (G9N9N) inserts a phrase instead, for 11 buttons. Its default phrase is 「不对，再检查一下」 and can be changed on the **Edit Common Phrases** page. On the Xiaomi and T1 remotes Power still closes the panel, as upstream.
- If your saved phrases assign anything to Power, upstream treats the whole phrase data as invalid and resets it to the built-in phrases; this fork reads it normally. Before switching from this fork to the upstream build, clear the Power assignment on the **Edit Common Phrases** page.

### Self-use build settings

- **About page**: the Website and Website downloads rows are removed; GitHub Releases, GitHub and Feedback point to this repository.
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

## Backing up only the key mappings (works with upstream builds too)

This fork exports and imports all settings from Settings → General → Backup & Restore. To back up only the key mappings, or when using an upstream build, use `.github/scripts/remote_buddy_mappings.py`. It reads and writes only each remote's mappings and the custom application list; pairing, gain and other settings are left alone. Upstream and fork builds share the settings domain `com.zfdang.remote-buddy`, so it works with both.

From the repository root:

```bash
python3 .github/scripts/remote_buddy_mappings.py backup
python3 .github/scripts/remote_buddy_mappings.py restore ~/RemoteBuddy-Backup/mappings-<time>.json
```

- `backup` writes to `~/RemoteBuddy-Backup/` by default.
- `restore` is a dry run by default: it lists which backup entry each remote matches and which keys would change. Quit the app, then add `--apply` to write. Before writing it saves the full settings as `before-restore-<time>.plist` and prints the command to undo.
- Local remotes are matched to the backup by same profile → same model and name → same model. Custom application references are remapped to the local app with the same bundle ID; apps missing locally are added to the list.
- When restoring into an older build, a value it doesn't recognize makes it reset the whole mapping set to defaults (upstream's decoding rule), so restore into the same or a newer build where possible.

## Relationship with upstream

- This repository merges upstream `main` into the `crenh` branch automatically every day, so the source keeps up with upstream; installers are published manually from time to time.
- The common phrase extension was merged upstream on 2026-11-16 in [PR #158](https://github.com/zfdang/remote-buddy/pull/158).
- Support for GY3LE, another Chromecast remote model, is planned.

## Feedback

- Issues specific to this fork (the Power phrase button, the installers): open an issue in this repository.
- Everything else: please report to the [upstream repository](https://github.com/zfdang/remote-buddy/issues).

## License

Same as upstream: [GPL-3.0](LICENSE).
