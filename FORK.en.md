# Remote Buddy fork (CRENH)

[简体中文](FORK.md) | **English**

This repository is a fork of [zfdang/remote-buddy](https://github.com/zfdang/remote-buddy), maintained by [CRENH](https://github.com/CRENH). For everyday usage see the [README](README.en.md); this page only covers how the fork differs from upstream. The source lives on the `crenh` branch.

## Differences from upstream

The extra common-phrase buttons ([PR #158](https://github.com/zfdang/remote-buddy/pull/158)) and Power inserting a phrase on the Chromecast remote ([PR #253](https://github.com/zfdang/remote-buddy/pull/253)) are both merged upstream; this fork uses the upstream implementation as-is.

### Settings backup and restore

- Settings → General → Backup & Restore exports the general settings and every remote's key mappings to one JSON file and imports it back, matched by remote model. Upstream declined this feature ([PR #249](https://github.com/zfdang/remote-buddy/pull/249)).
- At launch this fork decodes remote mappings entry by entry: an unrecognized value skips only that entry and the raw data is kept, instead of resetting the whole set.
- To back up only the key mappings, or when using an upstream build, see "Backing up only the key mappings" below.

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

Run the commands from the repository root. The script's output is in Chinese.

**Back up** (the app may stay open):

```bash
python3 .github/scripts/remote_buddy_mappings.py backup
```

It reports how many remotes and custom apps were saved and the file path. Backups go to `~/RemoteBuddy-Backup/` by default; `--output <path>` changes that.

**Restore**:

1. Dry run first (read only, the app may stay open) to see what will change:

   ```bash
   python3 .github/scripts/remote_buddy_mappings.py restore ~/RemoteBuddy-Backup/mappings-<time>.json
   ```

   One line per remote: which backup entry it matches, how, and which keys would change; the last line gives the total. Right after a backup it should be 0 keys.
2. Quit Remote Buddy from its status bar icon. The script refuses to write while the app is running.
3. Run the same command with `--apply` at the end. It reports how many keys changed and where it saved the full settings from before the restore (`before-restore-<time>.plist`).
4. Reopen Remote Buddy, check the keys on the mapping page, and try them on the physical remote.

**Undo**: quit the app and run the command printed in step 3:

```bash
defaults import com.zfdang.remote-buddy ~/RemoteBuddy-Backup/before-restore-<time>.plist
```

**Rules and limits**:

- Local remotes are matched to the backup by same profile → same model and name → same model. On the same Mac without re-pairing, the profile match keeps several remotes of one model apart. Remotes with no matching model in the backup are left unchanged.
- Custom application references are remapped to the local app with the same bundle ID; apps missing locally are added to the list; keys whose app can't be found are listed.
- When restoring into an older build, a value it doesn't recognize makes it reset the whole mapping set to defaults (upstream's decoding rule), so restore into the same or a newer build where possible.
- Tested on 2026-11-22 on an Apple Silicon Mac with two Chromecast remotes: back up → change one key in the app → quit → `--apply` → reopen: that key was restored and the other remote was unchanged.

## Relationship with upstream

- This repository merges upstream `main` into the `crenh` branch automatically every day, so the source keeps up with upstream; installers are published manually from time to time.
- The common phrase extension was merged upstream on 2026-11-16 in [PR #158](https://github.com/zfdang/remote-buddy/pull/158); Power inserting a phrase on the Chromecast remote was merged upstream on 2026-11-22 in [PR #253](https://github.com/zfdang/remote-buddy/pull/253).
- Support for GY3LE, another Chromecast remote model, is planned.

## Feedback

- Issues specific to this fork (settings backup and restore, the mapping backup script, the installers): open an issue in this repository.
- Everything else: please report to the [upstream repository](https://github.com/zfdang/remote-buddy/issues).

## License

Same as upstream: [GPL-3.0](LICENSE).
