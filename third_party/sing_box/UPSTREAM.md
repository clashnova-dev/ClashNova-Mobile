# Pinned sing_box binding fork

Source: https://pub.dev/packages/sing_box/versions/1.0.0 (QUSAD-prod/sing_box).
Dart/Kotlin/Swift binding code is copied from sing_box 1.0.0. LICENSE and THIRD_PARTY_NOTICES.md are retained. Native binary frameworks/AARs are not copied or checked in.

Local changes:

- Android Gradle, CocoaPods and SwiftPM accept the reviewed app-local native build only; no upstream precompiled-library fallback.
- `scripts/prepare-libbox.py` at the app root verifies the sing-box v1.14.4 source checksum, applies `native/go.mod` / `native/go.sum`, and builds with the pinned Go toolchain and gomobile version. No SHA-1 TLS compatibility flag is enabled.
- App-group runtime files are excluded from iOS backups. Config files use private permissions and first-unlock data protection.

Run `python3 scripts/prepare-libbox.py android` and/or `python3 scripts/prepare-libbox.py apple` from airport-mobile before native builds. Generated native libraries are git-ignored. Review native dependency pins and source checksums together when upgrading; do not replace binaries in the pub cache.
