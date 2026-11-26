# NXNative Builder — How-To Guide

This guide covers setting up, configuring, and using **NXNative Builder** to build and manage macOS `.app` bundles from `nxnative` game packages.

---

## 1. Installation & Initial Setup

### First Launch (Gatekeeper)

If you downloaded a pre-built `.zip` from GitHub Releases, move **NXNative Builder.app** to `/Applications`. Because the app is unsigned, macOS Gatekeeper will block it on first launch until you clear the quarantine attribute or allow it in System Settings:

- **Terminal (recommended):**
  ```bash
  xattr -cr "/Applications/NXNative Builder.app"
  ```
- **System Settings:** Try opening the app once, dismiss the warning, then open **System Settings → Privacy & Security** and click **Open Anyway**.

### Prerequisites & Environment Setup

Before building games for the first time, make sure the required tools are installed:

1. **Xcode & Git:** Install **Xcode** from the Mac App Store (Command Line Tools alone are not enough—`xcodebuild` is required). Open Xcode once to accept the license (or run `sudo xcodebuild -license accept`), and confirm the active developer directory points to Xcode:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
2. **Python 3:** Install via [Homebrew](https://brew.sh) (`brew install python`) or create a `.venv` inside your `nxnative` checkout.
3. **Clone `nxnative`:** Clone [nxnative](https://github.com/seedds/nxnative) locally and follow its README for any required tools or Python dependencies:
   ```bash
   git clone https://github.com/seedds/nxnative.git
   ```
4. **Verify Setup:** Open **Settings** in NXNative Builder to confirm **NXNative Repository**, **Game Sources Folder**, **Python 3**, and **Xcode & Git CLI Tools** all pass.

### Settings

On first launch, an **Onboarding** sheet walks you through the required paths (and you can inspect setup health anytime via **Settings > Preflight Diagnostics**. Open **Settings** (`⌘,`) to configure the paths NXNative Builder uses:

- **Game Sources Folder:** Root directory containing one subfolder per game (e.g. `~/Games/_sources`).
- **Build Output Location:**
  - **Applications (`/Applications`):** Places built `.app` bundles directly in `/Applications/<Game Name>.app`.
  - **Custom Folder:** Places built `.app` bundles in a named subfolder: `<Custom Folder>/<Game Name>/<Game Name>.app`.
- **NXNative Repo Folder:** Path to your local `nxnative` checkout containing `scripts/build_ipa_from_nsp.py` (uses `.venv/bin/python3` if present, otherwise `python3` from `PATH`).
- **Switch 1 Keys (`prod.keys`):** Path to your `prod.keys` file, used for Switch 1 builds (`-k`) and `nx_extract --contents` metadata scanning.
- **Extra PATH:** Colon-separated paths prepended to `PATH` during builds (e.g. `/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin`).

---

## 2. Source Folder Layout & Icons

Create one subfolder per game inside your **Game Sources Folder**, and place its package files (`.nsp`, `.xci`, `.nsz`, `.nup`) inside:

```text
_sources/
├── Diablo 2 Resurrected/
│   ├── icon.png
│   ├── Diablo II Resurrected [0100726014352000][v0].nsp
│   └── Diablo II Resurrected [0100726014352800][v2293760](1.0.35).nsp
└── Super Macho Galaxy 1 + 2/
    ├── icon-0100111111110000.jpg
    ├── icon-0100222222220000.png
    ├── icon.png
    └── Super Macho Galaxy [010099C022B96000][v0] + Super Macho Galaxy 2 [0100FD8022DAA000][v0].xci
```

### Icons

- **Supported filenames (in priority order):** `icon`, `cover`, `game`, `game-icon`, `game-cover`, and legacy `1024-mac` (falling back to any supported image file in the folder).
- **Supported formats:** `.png`, `.jpg`, `.jpeg`, `.webp`, `.heic`, and `.icns`.
- **Multi-game folders:** Provide per-title icons named `<name>-<TITLE_ID>.<ext>` (e.g. `icon-0100111111110000.png`, `cover-0100111111110000.jpg`) or `<TITLE_ID>.<ext>`, falling back to the shared folder icon.
- **Automatic processing:** Any square/non-rounded or differently sized image (e.g. `2000×2000` `.jpg` or `.png`) is automatically scaled/cropped and masked to a standard `1024×1024` macOS rounded-corner PNG before passing `--icon` to `nxnative`. Existing `1024×1024` PNGs with transparent corners are passed through as-is.
- **Add or replace from the UI:** Click or drag-and-drop an image directly onto the Game Card icon slot to save a normalized `1024×1024` icon (with an option to trash or keep the previous icon file).

---

## 3. Game Card Metadata & Controls

Selecting a game in the sidebar opens its **Game Card** at the top of the detail pane:

- **Build Status & Duration:** Shows the current status (`Queued`, `Building...`, `Complete`, `Failed`, etc.) and `Built in <duration>` after a build finishes.
- **Build Artifact Info:**
  - `App v<version>`: Version of the currently built `.app` bundle (from `Contents/Info.plist`).
  - `Update <version> available`: Shown in orange when a newer update package is detected in the source folder.
  - `Size: <bytes> · Built: <date>`: Disk size and modification date of the built `.app`.
  - `NXNative Commit: <hash>` / `Build Chain: <chain>`: Toolchain metadata recorded in the built `.app`'s `Info.plist` (`DMCommit` / `DMChain`).
- **Platform Pill (`Switch 1` / `Switch 2`):**
  - Autodetected when the Title ID starts with `0400` or `.nup` sources are present; `Switch 2` builds omit `-k prod.keys`.
- **`Title ID:` Pill & Copy Button:**
  - Displays the detected (or overridden) 16-character hex Title ID (`--title-id`), or `Title ID: Not Set` if none was found.
  - **Click the pill** to set or clear a custom Title ID override.
  - **Click the copy icon** next to the pill to copy the raw Title ID to your clipboard.
- **`App:` Pill (Custom `.app` Name):**
  - Displays the target output name (`--app-name`), defaulting to the source folder name.
  - **Click the pill** to rename the output `.app` (for example, to name split multi-game entries or match a pre-existing `.app` whose folder name differs from its source folder).
- **Per-Title `readme.md` Viewer:**
  - When `nxnative/dm/games/<TITLE_ID>/readme.md` exists in your NXNative checkout, click the readme button on the Game Card to view its notes in a read-only sheet.
- **Source Files List:**
  - Lists all detected `.nsp`, `.xci`, `.nsz`, and `.nup` files with `Base`, `Update`, `DLC`, or `Source` badges and version tags (e.g. `v1.0.35`, falling back to internal build numbers only when no public version is present).

---

## 4. Multi-Game Packages

When a source folder contains multiple `Title IDs` (detected via `nx_extract --contents` or base package headers):

1. NXNative Builder automatically splits the folder into separate game entries (`<Folder>::<TitleID>`), each passing its own `--title-id` to `scripts/build_ipa_from_nsp.py`.
2. Base, Update, and DLC packages are grouped to their matching game using the 13-character Title ID prefix.
3. Use the **`App:`** pill on each entry to give each game its own `.app` name (e.g. `Super Macho Galaxy` and `Super Macho Galaxy 2`).

---

## 5. Editing `env.txt`

NXNative reads per-title environment overrides from:

```text
~/Library/Application Support/nxnative/<TITLE_ID>/env.txt
```

To edit a game's `env.txt`:

1. Open the **`...` More Actions** menu on the game card (or right-click the game in the sidebar).
2. Choose **Edit env.txt…** (requires a Title ID to be detected or set).
3. Edit the contents in the built-in editor and click **Save** (missing parent folders and `env.txt` are created automatically), or click **Reveal in Finder** to open its location.

---

## 6. Building, Queueing, Logs & Cleanup

- **Single Build:** Click **Build** on the game card (or right-click a game in the sidebar).
- **Batch Queue:** Check multiple games in the sidebar and click **Build Selected** (or **Add Selected to Queue**) to run them sequentially. From the **Build Queue** pane, you can cancel queued items, retry failed items, clear finished items, click any item to inspect its log without changing sidebar selection, or resume/discard an interrupted queue on relaunch.
- **Logs:** Switch between the selected game's log and the combined session log, filter/search log output, jump to the next error, or copy/save the log to disk.
- **Cleanup:** Use the **`...` More Actions** menu (or right-click context menu) to **Launch .app**, **Reveal .app in Finder**, **Move Built .app to Trash**, or **Delete Build Folders** (`*_build` / `*_survey` temporary directories).

---

## 7. Developer Notes

- **Project Structure:** Swift Package Manager target (`Package.swift`) with `Sources/App`, `Sources/Models`, `Sources/Services`, `Sources/Views`, and `Tests/NXNativeBuilderTests.swift`.
- **Packaging:** `./build.sh` builds the release binary and outputs `dist/NXNative Builder.app` (overridable via `APP_OUT`).
- **Testing:** Run `swift test` (uses the Swift `Testing` framework).
