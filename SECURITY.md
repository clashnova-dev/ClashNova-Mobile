# Security Policy

## Supported versions

Security fixes land on the latest release. Please reproduce issues against the current `master` or the newest tagged build before reporting.

## Reporting a vulnerability

Please do **not** open a public issue for a security vulnerability.

Email **clashnova.dev@gmail.com** with:

- a description of the issue and its impact;
- the steps, configuration, or proof-of-concept needed to reproduce it;
- the affected version or commit, and your platform (iOS / Android, and the OS version).

You can expect an acknowledgement within a few days. We'll confirm the issue, work on a fix, and coordinate a disclosure timeline with you. Please give us a reasonable window to release a fix before any public disclosure.

## Scope

This client runs locally and forwards traffic through the on-device sing-box core (libbox). Useful reports include flaws in subscription parsing or conversion, the config written to the tunnel, the VPN/Network-Extension handling, or the handling of configuration and credentials on the device. Vulnerabilities in sing-box itself should be reported upstream to the [sing-box project](https://github.com/SagerNet/sing-box).

## Local hardening review — 2026-11-21

This is a source review, dependency audit and local build/regression check, not a penetration-test certification or a real-device VPN acceptance test.

Changes implemented:

- API and subscription requests share a bounded streaming HTTP layer: HTTPS in production, a total deadline, a 2 MiB body limit and at most three subscription redirects. Debug-only HTTP is limited to explicit loopback/emulator addresses. API redirects are rejected rather than replaying bearer tokens or login bodies; a new login never sends a previous session's token. Transport errors do not expose the token URL.
- Imported outbounds are checked before parsing results are cached and again before native connect, including existing cached subscriptions. Local file/path references, executable plugins and unsupported outbound types are rejected. Limits cover content size, node count, nesting and YAML expansion; parsing runs off the UI isolate. Control-panel `node-*` tags cannot disguise direct/group outbounds as proxies.
- Saved subscription URLs, credentials and active-subscription selections move from ordinary preferences to platform secure storage (Android Keystore-backed encryption / device-only iOS Keychain). Legacy preferences are removed only after a successful write/read-back; failed or corrupt storage preserves originals and prevents default overwrites. Passwords and session access tokens remain memory-only.
- Android cloud backup/device transfer exclusions cover app data, including the native plugin's runtime copies; cleartext networking is disabled in the release manifest. iOS app-group runtime data is excluded from backup and config files use private permissions and first-unlock file protection. **Libbox still needs sandboxed runtime config/last-input copies; this does not mean every copy is encrypted by the application or protected from a rooted/jailbroken device.** Existing remote backups are not retroactively deleted.
- Android release builds no longer fall back to debug signing. About-page external links are limited to HTTPS/Telegram without URL credentials; QR links use the same subscription URL validation.
- Logout waits for the account VPN to stop. A failed stop does not clear the session or falsely display an idle/signed-out state.
- The upstream plugin's prebuilt libbox was built with Go 1.26.5 and an older dependency graph. A pinned, license-preserving binding fork now loads only locally rebuilt native libraries from checksummed sing-box v1.14.4 source, Go 1.27.4, and the reviewed `native/go.mod` / `native/go.sum`. Android Gradle, CocoaPods and SwiftPM reject missing/stale reviewed builds. The build does not enable upstream's SHA-1 TLS compatibility flag.

Dependency checks use the OSV Pub ecosystem database for hosted Dart dependencies, and `govulncheck` for the libbox package with production build tags plus the rebuilt Android ARM64 native binary. The iOS XCFramework is a static archive and is not directly supported by the binary scanner; its source/dependency scan and compilation are recorded separately. Do not interpret an unsupported binary scan as a clean result.

Regression coverage includes downgrade/redirect and bearer-replay rejection, streaming size/deadline bounds, redacted network failures, unsafe imported/cached profiles, proxy-type filtering, legacy storage migration, failed/corrupt migration preservation and ordered writes. Android/iOS native compilation does not verify real-device Keychain migration, VPN routing, kill-switch behavior, signing/provisioning or app-store acceptance; these still need signed-device testing.

Recorded results: 42 Flutter tests passed; the analyzer has no errors or warnings (18 existing SDK deprecation notices remain). Hosted Pub dependency checks and the tagged libbox source scan reported no findings. The final APK's ARM64, ARMv7 and x86_64 native libraries all identify Go 1.27.4 and each completed a binary vulnerability scan without findings. Android release APK and iOS device-release app compilation passed without distribution signing. Manifest inspection confirms backup exclusions and cleartext restrictions; a deliberately stale native-build record is rejected by Gradle. The unsigned APK is for validation and cannot be distributed as an installable signed release.

Build locally with `python3 scripts/prepare-libbox.py android` / `apple`, then normal Flutter commands. Generated frameworks and AARs are ignored; source pins and binding code remain reviewable. Rebuild after changing native pins. No phone, running VPN, server data or desktop network settings were modified by this review.

References: [Pub security advisories](https://dart.dev/tools/pub/security-advisories), [secure storage plugin](https://pub.dev/packages/flutter_secure_storage), [Android backup](https://developer.android.com/identity/data/autobackup), [Android release signing](https://docs.flutter.dev/deployment/android).
