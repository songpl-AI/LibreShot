# Installation and upgrades

[README](../README_EN.md) · [中文](installation.md)

## Install

Supports macOS 13+, with Apple Silicon and Intel in the same package. Translation requires macOS 26+.

1. Download the DMG and SHA256SUMS from the [official Release](https://github.com/songpl-AI/LibreShot/releases).
2. Run `shasum -a 256 -c SHA256SUMS` in the folder containing both files.
3. Open the DMG and drag LibreShot.app into Applications.

Packages use ad-hoc signing and are not notarized. If macOS blocks opening the app, follow [Apple's instructions](https://support.apple.com/102445) in System Settings → Privacy & Security. If it reports a damaged file, redownload and check the checksum first. Do not disable Gatekeeper globally.

## Permissions

- **Screen Recording / Screen & System Audio Recording**: Needed to read area, full-screen and scrolling captures.
- **Input Monitoring**: Needed for optional double-Option capture.
- **Save folder**: Select a folder through LibreShot Settings to grant access to that location.

Find permissions in System Settings → Privacy & Security. Quit and reopen LibreShot after granting them when prompted.

## Upgrades and stale permissions

Quit the old app, then replace `/Applications/LibreShot.app`. Existing preferences and the save location are retained. Different ad-hoc builds may require permission renewal.

If a permission switch is on but the new app still reports it missing:

1. Quit LibreShot normally.
2. Remove its old entry from the affected permission page.
3. Add the current `/Applications/LibreShot.app` with “+” and confirm the switch is on.
4. Reopen from Applications, capture and save, then restart the app and check again.

Handle Screen Recording and Input Monitoring separately, renewing only failed entries. Complete system authentication yourself. If capture works but saving fails, select the original save folder again in LibreShot Settings.

## Report a problem

Include app version/build, macOS version, processor architecture, display setup and reproduction steps in an [Issue](https://github.com/songpl-AI/LibreShot/issues). Remove private content from attached images.

Maintainer procedures (Chinese): [Installation acceptance](operations/install-and-permissions.md), [upgrade script](operations/local-upgrade-script.md), and [release workflow](operations/release-and-issue-response.md).
