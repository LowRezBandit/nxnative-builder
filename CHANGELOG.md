# Changelog

All notable changes to **NXNative Builder** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-11-26

### Added

- **ANSI SGR Color Rendering:** Preserved ANSI SGR color and style sequences (`bold`, `dim`, foreground/background colors) from build scripts and compilers in the log terminal while keeping progress parsing and exported text clean.
- **Semantic Log Highlighting:** Automatic color-coding for `=== ... ===` section banners (green/red/orange/accent), `[step/total]` markers, `✓` checkmarks, `Running:` commands, `note:`, `warning:`, and `[RED]` / `error:` / `fatal error:` / `FAILED` lines.
- **Errors & Warnings Filter:** Non-destructive **Issues** filter toggle in the log toolbar with a live issue count badge and an empty-issues state.
- **Log Viewing Controls:** Persisted **Wrap Lines** toggle (switching between wrapped text and horizontal scrolling) and **Font Size** controls (`A-` / `A+` with `⌘-` / `⌘+` shortcuts).
- **Multi-Match Search Highlights:** `⌘F` log search now highlights all matching occurrences simultaneously with a stronger highlight on the active match.
- **Unit Tests:** Added `LogFormatterTests` in `Tests/NXNativeBuilderTests.swift` covering ANSI parsing, semantic highlighting, issue filtering/counting, and `stripNonSGRANSI`.
- **Documentation & Community Templates:** Added environment setup instructions, macOS Gatekeeper instructions, GitHub issue templates, `CONTRIBUTING.md`, updated `README.md`, `Docs/HOWTO.md`, and refreshed screenshots and `AppIcon.png`.

### Changed

- **Log Terminal Typography:** Added `12×10` container insets and `1.22` line height in `LogTextView` for improved readability in both Light and Dark mode.
- **Plain-Text Copy & Save:** Copying or saving logs from the toolbar now strips ANSI escape sequences for clean plain-text output.

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
