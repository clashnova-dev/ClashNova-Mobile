# Contributing

Thanks for taking the time to contribute. ClashNova Mobile is a standalone sing-box proxy client for iOS and Android; contributions that keep it simple, local, and dependency-light are the most welcome.

## Getting started

Set up Flutter and the platform toolchains and run the app as described in the [Building](README.md#building) section of the README. The Flutter version is pinned by the `sdk` constraint in `pubspec.yaml`.

The iOS VPN runs only on a real device and needs the signing and capability setup covered in the README; the simulator runs the UI alone.

## Before opening a pull request

- Keep the analyzer clean: `flutter analyze`.
- Run the tests: `flutter test`. Add or update tests under `test/` when you change subscription parsing, config building, or the connection logic.
- If you change user-facing text, update every locale in `lib/i18n/` so the languages stay in sync.
- Don't commit secrets, subscription URLs, a `.env` file, or signing material.

## Commit and PR style

- Write focused commits with a conventional-commit subject (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`), optionally scoped (`feat(nodes): ...`).
- Explain the "why" in the PR description, and mention anything you could not verify (for example, if you only tested on Android).
- One logical change per PR is easier to review than a large mixed one.

## License

By contributing, you agree that your contributions are licensed under **GPL-3.0**, the same license as the project.

## Contact

Questions that aren't a bug report: clashnova.dev@gmail.com. For security issues, see [SECURITY.md](SECURITY.md).
