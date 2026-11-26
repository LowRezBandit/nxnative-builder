# NXNative Builder

A native macOS SwiftUI app for managing, configuring, and building Nintendo Switch games into macOS `.app` bundles using [NXNative](https://github.com/DinosaurMac/nxnative) (`scripts/build_ipa_from_nsp.py`).

## Features

- **Automatic Source Scanning:** Scans your Game Sources folder for `.nsp`, `.xci`, `.nsz`, and `.nup` packages, detects Base / Update / DLC contents, and tracks available updates against already-built `.app` bundles.
- **Multi-Game Package Support:** Folders containing multiple `Application` Title IDs automatically expand into separate game entries with per-title package grouping and custom `.app` naming.
- **Per-Game Controls:** Switch 1 / Switch 2 platform mode (`Auto`, `Switch 1`, `Switch 2`), editable & copyable `Title ID:`, editable `App:` output name, and a built-in `env.txt` editor.
- **Build Queue & Live Logs:** Build single or multiple checked games sequentially with step progress tracking, searchable per-game or combined logs, and desktop notifications.
- **Artifact & Disk Management:** Launch built `.app`s, reveal them in Finder, trash built apps, or clean temporary `*_build` / `*_survey` folders.

## Documentation

See the full user and developer guide in [Docs/HOWTO.md](Docs/HOWTO.md).

## Quick Start (Build & Test)

Requires macOS 14+ and Xcode / Swift 6 toolchain.

```bash
# Build and bundle NXNative Builder.app
./build.sh

# Or build and run unit tests via SwiftPM
swift build
swift test
```
