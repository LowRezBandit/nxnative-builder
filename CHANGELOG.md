# Changelog

All notable changes to **NXNative Builder** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-26

### Added
- **Native macOS SwiftUI App:** Initial public release targeting macOS 14+ with Swift 6 tools (`Package.swift`, `build.sh`).
- **Library Scanning & Update Tracking:** Automatic scanning of `.nsp`, `.xci`, `.nsz`, and `.nup` packages with Base / Update / DLC detection and installed `.app` version comparison.
- **Multi-Game Package Support:** Automatic splitting of folders containing multiple `Application` Title IDs and grouping by 13-character Title ID prefix.
- **Per-Game Controls:** `Auto`, `Switch 1 (Keys)`, and `Switch 2` platform mode selector, editable & copyable `Title ID`, custom `App` output name overrides, built-in `env.txt` editor, and per-title `readme.md` viewer.
- **Icon Normalization:** Automatic discovery and normalization of folder/per-title artwork into `1024×1024` rounded-corner macOS PNGs.
- **Build Queue & Live Logs:** Sequential single/batch build queue (with cancel, retry, and resume), searchable per-game and combined logs with error jumping, preflight diagnostics, onboarding setup sheet, and `.app` / temporary build folder cleanup actions.
- **Unit Test Suite:** Swift Testing suite covering package parsing, version comparison, queue state, `env.txt` management, icon normalization, and preflight checks (`Tests/NXNativeBuilderTests.swift`).
- **Documentation & Licensing:** GPL-3.0 `LICENSE`, `README.md` with screenshots (`Docs/screenshots/`), `Docs/HOWTO.md`, and `CONTRIBUTING.md`.
- **GitHub Automation:** CI workflow (`.github/workflows/ci.yml`) for `swift build` / `swift test` and tag-triggered release workflow (`.github/workflows/release.yml`).

### Changed
- **Public Repo Defaults:** Replaced hardcoded local development paths in `BuildManager.swift` and `build.sh` with empty/user-configurable defaults and `dist/` bundle output.
