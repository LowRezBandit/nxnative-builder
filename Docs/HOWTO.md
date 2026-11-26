# NXNative Builder — How-To Guide

This guide covers setting up, configuring, and using **NXNative Builder** to build and manage macOS `.app` bundles from Switch game packages.

---

## 1. Settings & Initial Setup

Open **Settings** (`⌘,`) to configure the paths NXNative Builder uses:

- **Game Sources Folder:** Root directory containing one subfolder per game (e.g. `~/Games/_sources`).
- **Build Output Location:**
  - **Applications (`/Applications`):** Places built `.app` bundles directly in `/Applications/<App Name>.app`.
  - **Custom Folder:** Places built `.app` bundles in a named subfolder: `<Custom Folder>/<App Name>/<App Name>.app`.
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
└── Super Mario Galaxy 1 + 2/
    ├── icon-0100111111110000.jpg
    ├── icon-0100222222220000.png
    ├── icon.png
    └── Super Mario Galaxy [010099C022B96000][v0] + Super Mario Galaxy 2 [0100FD8022DAA000][v0].xci
```

### Icons

- **Supported filenames (in priority order):** `icon`, `cover`, `game`, `game-icon`, `game-cover`, and legacy `1024-mac` (falling back to any supported image file in the folder).
- **Supported formats:** `.png`, `.jpg`, `.jpeg`, `.webp`, `.heic`, and `.icns`.
- **Multi-game folders:** Provide per-title icons named `<name>-<TITLE_ID>.<ext>` (e.g. `icon-0100111111110000.png`, `cover-0100111111110000.jpg`) or `<TITLE_ID>.<ext>`, falling back to the shared folder icon.
- **Automatic processing:** Any square/non-rounded or differently sized image (e.g. `2000×2000` `.jpg` or `.png`) is automatically scaled/cropped and masked to a standard `1024×1024` macOS rounded-corner PNG before passing `--icon` to NXNative. Existing `1024×1024` PNGs with transparent corners are passed through as-is.

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
  - Click to choose `Auto`, `Switch 1 (Keys)`, or `Switch 2`.
  - `Auto` selects `Switch 2` when the Title ID starts with `0400` or `.nup` sources are present; `Switch 2` builds omit `-k prod.keys`.
- **`Title ID:` Pill & Copy Button:**
  - Displays the detected (or overridden) 16-character hex Title ID (`--title-id`), or `Title ID: Not Set` if none was found.
  - **Click the pill** to set or clear a custom Title ID override.
  - **Click the copy icon** next to the pill to copy the raw Title ID to your clipboard.
- **`App:` Pill (Custom `.app` Name):**
  - Displays the target output name (`--app-name`), defaulting to the source folder name.
  - **Click the pill** to rename the output `.app` (for example, to name split multi-game entries or match a pre-existing `.app` whose folder name differs from its source folder).
- **Source Files List:**
  - Lists all detected `.nsp`, `.xci`, `.nsz`, and `.nup` files with `Base`, `Update`, `DLC`, or `Source` badges and public-facing version tags (e.g. `v1.0.35`, falling back to internal build numbers only when no public version is present).

---

## 4. Multi-Game Packages

When a source folder contains multiple `Application` Title IDs (detected via `nx_extract --contents` or base package headers):

1. NXNative Builder automatically splits the folder into separate game entries (`<Folder>::<TitleID>`), each passing its own `--title-id` to `scripts/build_ipa_from_nsp.py`.
2. Base, Update, and DLC packages are grouped to their matching game using the 13-character Title ID prefix.
3. Use the **`App:`** pill on each entry to give each game its own `.app` name (e.g. `Super Mario Galaxy` and `Super Mario Galaxy 2`).

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
- **Batch Queue:** Check multiple games in the sidebar and click **Build Selected** (or **Build All**) to run them sequentially. You can cancel queued items, retry failed items, or clear finished items from the queue popover.
- **Logs:** Switch between the selected game's log and the combined session log, filter/search log output, jump to the next error, or copy/save the log to disk.
- **Cleanup:** Use the **`...` More Actions** menu (or right-click context menu) to **Launch .app**, **Reveal .app in Finder**, **Move Built .app to Trash**, or **Delete Build Folders** (`*_build` / `*_survey` temporary directories).

---

## 7. Developer Notes

- **Project Structure:** Swift Package Manager target (`Package.swift`) with `Sources/App`, `Sources/Models`, `Sources/Services`, `Sources/Views`, and `Tests/NXNativeBuilderTests.swift`.
- **Packaging:** `./build.sh` builds the release binary and updates the `.app` bundle.
- **Testing:** Run `swift test` (uses the Swift `Testing` framework).
