import AppKit
import Foundation
import Testing
@testable import NXNativeBuilder

@Suite("PackageHeaderReader")
struct PackageHeaderReaderTests {
    private func makeTempFile(_ data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnb-test-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private func appendUInt64LE(_ value: UInt64, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    @Test("readNupContents parses Application, Patch, and AddOnContent records")
    func readNupContentsValid() throws {
        var data = Data(repeating: 0, count: 0x80)
        // Magic "NUP\x01"
        data[0] = 0x4E; data[1] = 0x55; data[2] = 0x50; data[3] = 0x01
        let tocOffset: UInt64 = 0x80
        let npkg = 3
        let tocSize = UInt64(0x30 + npkg * 0x40)

        var offData = Data()
        appendUInt64LE(tocOffset, to: &offData)
        appendUInt64LE(tocSize, to: &offData)
        data.replaceSubrange(0x08..<0x18, with: offData)

        var npkgData = Data()
        appendUInt32LE(UInt32(npkg), to: &npkgData)
        data.replaceSubrange(0x48..<0x4C, with: npkgData)

        var toc = Data(repeating: 0, count: Int(tocSize))
        // Magic "TOC\x01"
        toc[0] = 0x54; toc[1] = 0x4F; toc[2] = 0x43; toc[3] = 0x01

        let entries: [(titleID: UInt64, version: UInt32, kind: UInt8)] = [
            (0x0400_1234_5678_0000, 0, 0),
            (0x0400_1234_5678_0800, 65536, 1),
            (0x0400_1234_5678_0001, 0, 2)
        ]
        for (i, entry) in entries.enumerated() {
            let base = 0x30 + i * 0x40
            var tidBytes = Data()
            appendUInt64LE(entry.titleID, to: &tidBytes)
            toc.replaceSubrange(base..<(base + 8), with: tidBytes)

            var verBytes = Data()
            appendUInt32LE(entry.version, to: &verBytes)
            toc.replaceSubrange((base + 0x14)..<(base + 0x18), with: verBytes)

            toc[base + 0x18] = entry.kind
        }
        data.append(toc)

        let url = try makeTempFile(data, extension: "nup")
        defer { try? FileManager.default.removeItem(at: url) }

        let records = try #require(PackageHeaderReader.readNupContents(at: url))
        #expect(records.count == 3)
        #expect(records[0] == PackageContentRecord(kind: "Application", titleID: "0400123456780000", version: 0))
        #expect(records[1] == PackageContentRecord(kind: "Patch", titleID: "0400123456780800", version: 65536))
        #expect(records[2] == PackageContentRecord(kind: "AddOnContent", titleID: "0400123456780001", version: 0))
    }

    @Test("readNupContents returns nil for invalid magic")
    func readNupContentsInvalidMagic() throws {
        let url = try makeTempFile(Data(repeating: 0xAA, count: 0x100), extension: "nup")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PackageHeaderReader.readNupContents(at: url) == nil)
    }

    @Test("readPFS0TitleID extracts title ID from .tik or .cnmt.xml entry")
    func readPFS0TitleIDValid() throws {
        var strTable = Data()
        strTable.append(contentsOf: "readme.txt\0".utf8)
        strTable.append(contentsOf: "0100300012f2a000.tik\0".utf8)

        var header = Data()
        header.append(contentsOf: [0x50, 0x46, 0x53, 0x30]) // "PFS0"
        appendUInt32LE(2, to: &header) // fileCount
        appendUInt32LE(UInt32(strTable.count), to: &header)
        appendUInt32LE(0, to: &header) // reserved

        // 2 * 24-byte file entries
        header.append(Data(repeating: 0, count: 2 * 24))
        header.append(strTable)

        let url = try makeTempFile(header, extension: "nsp")
        defer { try? FileManager.default.removeItem(at: url) }

        let titleID = PackageHeaderReader.readPFS0TitleID(at: url)
        #expect(titleID == "0100300012F2A000")
    }
}

@Suite("GameScanner Package Parsing")
struct GameScannerParsingTests {
    @Test("classifyPackageKinds classifies base, update, dlc, and combined packages")
    func classifyKinds() {
        #expect(GameScanner.classifyPackageKinds(filename: "Game [0100ABCD12340000][v0].nsp", explicitKind: nil, totalCount: 2) == [.base])
        #expect(GameScanner.classifyPackageKinds(filename: "Game [0100ABCD12340800][v65536].nsp", explicitKind: nil, totalCount: 2) == [.update])
        #expect(GameScanner.classifyPackageKinds(filename: "Game [0100ABCD12340001][v0].nsp", explicitKind: nil, totalCount: 2) == [.dlc])
        #expect(GameScanner.classifyPackageKinds(filename: "Game + Update + DLC.nsp", explicitKind: nil, totalCount: 1) == [.base, .update, .dlc])
        #expect(GameScanner.classifyPackageKinds(filename: "Custom.nsp", explicitKind: .dlc, totalCount: 3) == [.dlc])
        #expect(GameScanner.classifyPackageKinds(filename: "OnlyFile.nsp", explicitKind: nil, totalCount: 1) == [.base])
    }

    @Test("extractPackageVersion prefers public semver over internal version")
    func extractVersion() {
        #expect(GameScanner.extractPackageVersion(from: "Game [v65536].nsp", kinds: [.update]) == "v65536")
        #expect(GameScanner.extractPackageVersion(from: "Game [v0].nsp", kinds: [.base]) == nil)
        #expect(GameScanner.extractPackageVersion(from: "Game [Update v1.2.3][v131072].nsp", kinds: [.update]) == "v1.2.3")
        #expect(GameScanner.extractPackageVersion(from: "Game [1.4.0].nsp", kinds: [.update], headerVersion: 262144) == "v1.4.0")
        #expect(GameScanner.extractPackageVersion(from: "Diablo II Resurrected [0100726014352800][v2293760](1.0.35).nsp", kinds: [.update], headerVersion: 2293760) == "v1.0.35")
    }

    @Test("cleanPackageName and extractDLCDescriptor strip tags cleanly")
    func cleanNames() {
        #expect(GameScanner.cleanPackageName("Super Mario Game [0100123456780000][v0].nsp", kinds: [.base]) == "Super Mario Game")
        #expect(GameScanner.cleanPackageName("hr-Super_Mario_Game.nsp", kinds: [.base]) == "Super Mario Game")
        #expect(GameScanner.cleanPackageName("Game [0100123456780001][Season Pass DLC][v0].nsp", kinds: [.dlc]) == "Season Pass")
        #expect(GameScanner.extractDLCDescriptor(from: "Game [0100123456780001][USA][Expansion Pack AOC][v0]") == "Expansion Pack")
    }
}

@Suite("GameScanner Version Comparison")
struct GameScannerVersionTests {
    @Test("extractDottedVersion finds dotted semver strings")
    func extractDotted() {
        #expect(GameScanner.extractDottedVersion(from: "v1.2.3") == "1.2.3")
        #expect(GameScanner.extractDottedVersion(from: "v131072 · v2.0.1") == "2.0.1")
        #expect(GameScanner.extractDottedVersion(from: "v65536") == nil)
    }

    @Test("compareDottedVersions handles different component counts")
    func compareVersions() {
        #expect(GameScanner.compareDottedVersions("1.0", "1.0.0") == .orderedSame)
        #expect(GameScanner.compareDottedVersions("1.2", "1.10.0") == .orderedAscending)
        #expect(GameScanner.compareDottedVersions("2.0.0", "1.9.9") == .orderedDescending)
    }

    @Test("availableUpdateVersion detects newer update package")
    func availableUpdate() {
        let built = [
            BuildArtifactInfo(
                appName: "TestGame",
                version: "1.0.0",
                buildDate: Date(timeIntervalSince1970: 1000),
                commit: "abc123",
                chain: nil,
                sizeBytes: nil
            )
        ]
        let packages = [
            SourcePackageInfo(
                id: "update.nsp",
                kinds: [.update],
                displayName: "TestGame",
                version: "v131072 · v1.2.0",
                rawFilename: "TestGame [Update v1.2.0][v131072].nsp",
                titleID: nil
            )
        ]
        let folder = URL(fileURLWithPath: "/tmp")
        #expect(GameScanner.availableUpdateVersion(for: built, sourcePackages: packages, folderURL: folder) == "v1.2.0")
    }
}

@Suite("BuildManager Log & Progress Parsing")
struct BuildManagerLogTests {
    @Test("stripANSI removes CSI and OSC escape sequences")
    @MainActor
    func stripANSISequences() {
        let manager = BuildManager()
        let raw = "\u{1B}[31mError:\u{1B}[0m failed \u{1B}]0;title\u{07}done"
        #expect(manager.stripANSI(raw) == "Error: failed done")
    }

    @Test("parseProgress updates step progress and label")
    @MainActor
    func parseStepProgress() {
        let manager = BuildManager()
        manager.parseProgress(from: "[12:34:56] [2/4] Extracting assets: 50%\n")
        #expect(manager.currentStepLabel == "[2/4] Extracting assets")
        #expect(abs(manager.currentStepProgress - 0.375) < 0.0001)

        manager.parseProgress(from: "✓ [2/4] Extracting assets\n")
        #expect(abs(manager.currentStepProgress - 0.5) < 0.0001)
    }
}

@Suite("BuildManager Queue")
struct BuildManagerQueueTests {
    @MainActor
    private func makeTestManager() -> BuildManager {
        let manager = BuildManager()
        let folder = URL(fileURLWithPath: "/tmp")
        manager.games = [
            GameEntry(id: "g1", name: "Game One", folderURL: folder, iconImage: nil, iconURL: nil, sourcePackages: [], detectedTitleID: nil, hasSwitch2Source: false, isSelected: true),
            GameEntry(id: "g2", name: "Game Two", folderURL: folder, iconImage: nil, iconURL: nil, sourcePackages: [], detectedTitleID: nil, hasSwitch2Source: false, isSelected: true),
            GameEntry(id: "g3", name: "Game Three", folderURL: folder, iconImage: nil, iconURL: nil, sourcePackages: [], detectedTitleID: nil, hasSwitch2Source: false, isSelected: false)
        ]
        return manager
    }

    @Test("enqueueGames skips active duplicates and clears checkboxes")
    @MainActor
    func enqueueDeduplicatesAndClearsCheckboxes() {
        let manager = makeTestManager()
        let added1 = manager.enqueueGames(ids: ["g1", "g2"], clearCheckboxes: true, startIfIdle: false)
        #expect(added1 == ["g1", "g2"])
        #expect(manager.queueItems.map(\.id) == ["g1", "g2"])
        #expect(manager.games[0].isSelected == false)
        #expect(manager.games[1].isSelected == false)

        let added2 = manager.enqueueGames(ids: ["g1", "g3"], clearCheckboxes: true, startIfIdle: false)
        #expect(added2 == ["g3"])
        #expect(manager.queueItems.map(\.id) == ["g1", "g2", "g3"])
    }

    @Test("cancelQueueItem removes queued item and updates overall progress")
    @MainActor
    func cancelQueuedItem() {
        let manager = makeTestManager()
        manager.enqueueGames(ids: ["g1", "g2"], clearCheckboxes: false, startIfIdle: false)
        manager.queueItems[0].status = .building
        manager.queueItems[0].progress = 0.5
        #expect(abs(manager.overallQueueProgress - 0.25) < 0.0001)

        manager.cancelQueueItem(id: "g2")
        #expect(manager.queueItems.map(\.id) == ["g1"])
        #expect(manager.games[1].status == .idle)
        #expect(abs(manager.overallQueueProgress - 0.5) < 0.0001)
    }

    @Test("retryQueueItem places failed item next in line after building item")
    @MainActor
    func retryNextInLine() {
        let manager = makeTestManager()
        manager.enqueueGames(ids: ["g1", "g2", "g3"], clearCheckboxes: false, startIfIdle: false)
        manager.isBuilding = true
        manager.queueItems[0].status = .failed(1)
        manager.queueItems[1].status = .building

        manager.retryQueueItem(id: "g1", startIfIdle: false)
        #expect(manager.queueItems.map(\.id) == ["g2", "g1", "g3"])
        #expect(manager.queueItems[1].status == .queued)
    }

    @Test("resumable queue filters missing games and supports resume and discard")
    @MainActor
    func resumableQueueLifecycle() {
        defer { UserDefaults.standard.removeObject(forKey: "pendingQueueGameIDs") }

        let manager = makeTestManager()
        manager.enqueueGames(ids: ["g1", "g2"], clearCheckboxes: false, startIfIdle: false)
        #expect(UserDefaults.standard.stringArray(forKey: "pendingQueueGameIDs") == ["g1", "g2"])

        manager.cancelQueueItem(id: "g1")
        #expect(UserDefaults.standard.stringArray(forKey: "pendingQueueGameIDs") == ["g2"])

        manager.cancelQueueItem(id: "g2")
        #expect(UserDefaults.standard.stringArray(forKey: "pendingQueueGameIDs") == nil)

        manager.restoreResumableQueue(from: ["g3", "missing-id", "g1"])
        #expect(manager.resumableQueueGameIDs == ["g3", "g1"])

        let resumed = manager.resumeInterruptedQueue(startIfIdle: false)
        #expect(resumed == ["g3", "g1"])
        #expect(manager.resumableQueueGameIDs.isEmpty)
        #expect(manager.queueItems.map(\.id) == ["g3", "g1"])

        manager.restoreResumableQueue(from: ["g2"])
        #expect(manager.resumableQueueGameIDs == ["g2"])
        manager.discardInterruptedQueue()
        #expect(manager.resumableQueueGameIDs.isEmpty)
    }

    @Test("clearFinishedQueueItems preserves active and queued items")
    @MainActor
    func clearFinishedItems() {
        let manager = makeTestManager()
        manager.enqueueGames(ids: ["g1", "g2", "g3"], clearCheckboxes: false, startIfIdle: false)
        manager.queueItems[0].status = .succeeded
        manager.queueItems[1].status = .building
        manager.isBuilding = true

        manager.clearFinishedQueueItems()
        #expect(manager.queueItems.map(\.id) == ["g2", "g3"])
    }

    @Test("inspectQueueItemLog updates log target without changing selectedGameID")
    @MainActor
    func inspectQueueLogOnly() {
        let manager = makeTestManager()
        manager.selectedGameID = "g1"
        manager.followActiveBuild = true

        manager.inspectQueueItemLog("g2")
        #expect(manager.selectedGameID == "g1")
        #expect(manager.inspectedLogGameID == "g2")
        #expect(manager.followActiveBuild == false)
    }
}

@Suite("Output Layout")
struct OutputLayoutTests {
    @Test("builtAppURL uses flat path for Applications and subfolder for custom folder")
    func outputPaths() {
        let appsRoot = URL(fileURLWithPath: "/Applications")
        let customRoot = URL(fileURLWithPath: "/Volumes/Development/Games")

        let flatURL = GameScanner.builtAppURL(for: "UFO 50", gamesRootURL: appsRoot, flatOutputLayout: true)
        #expect(flatURL.path == "/Applications/UFO 50.app")

        let nestedURL = GameScanner.builtAppURL(for: "UFO 50", gamesRootURL: customRoot, flatOutputLayout: false)
        #expect(nestedURL.path == "/Volumes/Development/Games/UFO 50/UFO 50.app")
    }
}

@Suite("env.txt Management")
struct EnvFileTests {
    @Test("envFileURL resolves title ID subdirectory and read/save round-trips")
    @MainActor
    func envFileReadWrite() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-env-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manager = BuildManager()
        let url = try #require(manager.envFileURL(for: "0100300012f2a000", baseDirectory: tempRoot))
        #expect(url.path == tempRoot.appendingPathComponent("0100300012F2A000/env.txt").path)
        #expect(try manager.readEnvFile(for: "0100300012F2A000", baseDirectory: tempRoot) == "")

        let sample = "MVK_CONFIG_LOG_LEVEL=0\nNX_SOME_FLAG=1\n"
        try manager.saveEnvFile(sample, for: "0100300012F2A000", baseDirectory: tempRoot)
        #expect(try manager.readEnvFile(for: "0100300012F2A000", baseDirectory: tempRoot) == sample)
    }
}

@Suite("Multi-Game Package Expansion")
struct MultiGamePackageTests {
    @Test("expandFolderEntries splits multi-Application folders and groups packages by 13-char Title ID prefix")
    func expandMultiGameFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Super Mario Galaxy 1 + 2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let comboNSP = folder.appendingPathComponent("GalaxyCombo.nsp")
        let upd1NSP = folder.appendingPathComponent("Galaxy1_Update.nsp")
        let upd2NSP = folder.appendingPathComponent("Galaxy2_Update.nsp")

        let tid1 = "0100111111110000"
        let tid2 = "0100222222220000"
        let cache: [String: CachedPackageMetadata] = [
            comboNSP.path: CachedPackageMetadata(
                fileSize: 100,
                modTime: 1,
                contents: [
                    PackageContentRecord(kind: "Application", titleID: tid1, version: 0),
                    PackageContentRecord(kind: "Application", titleID: tid2, version: 0)
                ]
            ),
            upd1NSP.path: CachedPackageMetadata(
                fileSize: 50,
                modTime: 1,
                contents: [PackageContentRecord(kind: "Patch", titleID: "0100111111110800", version: 65536)]
            ),
            upd2NSP.path: CachedPackageMetadata(
                fileSize: 50,
                modTime: 1,
                contents: [PackageContentRecord(kind: "Patch", titleID: "0100222222220800", version: 65536)]
            )
        ]

        let packages = [
            SourcePackageInfo(id: "GalaxyCombo.nsp", kinds: [.base], displayName: "GalaxyCombo", version: nil, rawFilename: "GalaxyCombo.nsp", titleID: tid1),
            SourcePackageInfo(id: "Galaxy1_Update.nsp", kinds: [.update], displayName: "Galaxy1_Update", version: "v1.0.1", rawFilename: "Galaxy1_Update.nsp", titleID: "0100111111110800"),
            SourcePackageInfo(id: "Galaxy2_Update.nsp", kinds: [.update], displayName: "Galaxy2_Update", version: "v1.0.1", rawFilename: "Galaxy2_Update.nsp", titleID: "0100222222220800")
        ]

        let folderName = folder.lastPathComponent
        let entries = GameScanner.expandFolderEntries(
            folderURL: folder,
            sourcePackages: packages,
            metadataCache: cache,
            gamesRootURL: folder,
            appNameOverrides: [
                "\(folderName)::\(tid1)": "Super Mario Galaxy",
                "\(folderName)::\(tid2)": "Super Mario Galaxy 2"
            ]
        )

        #expect(entries.count == 2)
        #expect(entries[0].id == "\(folderName)::\(tid1)")
        #expect(entries[0].detectedTitleID == tid1)
        #expect(entries[0].sourcePackages.map(\.rawFilename) == ["GalaxyCombo.nsp", "Galaxy1_Update.nsp"])

        #expect(entries[1].id == "\(folderName)::\(tid2)")
        #expect(entries[1].detectedTitleID == tid2)
        #expect(entries[1].sourcePackages.map(\.rawFilename) == ["GalaxyCombo.nsp", "Galaxy2_Update.nsp"])
    }
}

@Suite("Icon Discovery & Normalization")
struct IconDiscoveryTests {
    private func makeSolidPNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try #require(ctx.makeImage())
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test("findIcon respects base name priority and per-title matching")
    func iconPriority() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-icon-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let pngData = try makeSolidPNG(width: 64, height: 64)
        let legacy = folder.appendingPathComponent("1024-mac.png")
        let gameCover = folder.appendingPathComponent("game-cover.png")
        let cover = folder.appendingPathComponent("cover.png")
        let icon = folder.appendingPathComponent("icon.png")
        let tidCover = folder.appendingPathComponent("cover-0100111111110000.png")

        try pngData.write(to: legacy)
        #expect(GameScanner.findIcon(in: folder)?.url.lastPathComponent == "1024-mac.png")

        try pngData.write(to: gameCover)
        #expect(GameScanner.findIcon(in: folder)?.url.lastPathComponent == "game-cover.png")

        try pngData.write(to: cover)
        #expect(GameScanner.findIcon(in: folder)?.url.lastPathComponent == "cover.png")

        try pngData.write(to: icon)
        #expect(GameScanner.findIcon(in: folder)?.url.lastPathComponent == "icon.png")

        try pngData.write(to: tidCover)
        #expect(GameScanner.findIcon(in: folder, titleID: "0100111111110000")?.url.lastPathComponent == "cover-0100111111110000.png")
    }

    @Test("prepareBuildIcon normalizes square image to 1024x1024 rounded PNG")
    func normalizeSquareIcon() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-norm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let srcURL = folder.appendingPathComponent("cover.png")
        try makeSolidPNG(width: 200, height: 200).write(to: srcURL)

        let outURL = try #require(GameScanner.prepareBuildIcon(from: srcURL, outputDirectory: folder))
        let outImage = try #require(NSImage(contentsOf: outURL))
        var rect = NSRect(origin: .zero, size: outImage.size)
        let cgImage = try #require(outImage.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        #expect(cgImage.width == 1024)
        #expect(cgImage.height == 1024)

        // Calling prepareBuildIcon again on an already-normalized icon must not double-pad it.
        let secondPassURL = try #require(GameScanner.prepareBuildIcon(from: outURL, outputDirectory: folder))
        #expect(secondPassURL.standardizedFileURL == outURL.standardizedFileURL)
    }

    @Test("prepareBuildIcon re-normalizes external 1024x1024 PNGs and saveNormalizedIcon persists per-title icon")
    func normalizeAndSaveIcon() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-save-icon-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // External 1024x1024 PNG without our normalization marker must still be normalized.
        let externalURL = folder.appendingPathComponent("external.png")
        try makeSolidPNG(width: 1024, height: 1024).write(to: externalURL)

        let savedTitleURL = try #require(
            GameScanner.saveNormalizedIcon(from: externalURL, in: folder, titleID: "0100111111110000")
        )
        #expect(savedTitleURL.lastPathComponent == "icon-0100111111110000.png")
        #expect(GameScanner.findIcon(in: folder, titleID: "0100111111110000")?.url.standardizedFileURL == savedTitleURL.standardizedFileURL)

        let savedDefaultURL = try #require(
            GameScanner.saveNormalizedIcon(from: externalURL, in: folder, titleID: nil)
        )
        #expect(savedDefaultURL.lastPathComponent == "icon.png")
    }

    @Test("formattedSourceSummary summarizes unique source package kinds")
    @MainActor
    func formattedSourceSummary() {
        let manager = BuildManager()
        let folder = URL(fileURLWithPath: "/tmp/test-game")

        let emptyGame = GameEntry(
            id: "empty",
            name: "Empty",
            folderURL: folder,
            iconImage: nil,
            iconURL: nil,
            sourcePackages: [],
            detectedTitleID: nil,
            hasSwitch2Source: false
        )
        #expect(manager.formattedSourceSummary(for: emptyGame) == nil)

        let combinedGame = GameEntry(
            id: "combined",
            name: "Combined",
            folderURL: folder,
            iconImage: nil,
            iconURL: nil,
            sourcePackages: [
                SourcePackageInfo(id: "dlc2", kinds: [.dlc], displayName: "DLC 2", version: nil, rawFilename: "dlc2.nsp", titleID: nil),
                SourcePackageInfo(id: "base", kinds: [.base, .update], displayName: "Base+Upd", version: "1.1.0", rawFilename: "base.nsp", titleID: nil),
                SourcePackageInfo(id: "dlc1", kinds: [.dlc], displayName: "DLC 1", version: nil, rawFilename: "dlc1.nsp", titleID: nil)
            ],
            detectedTitleID: "0100111111110000",
            hasSwitch2Source: false
        )
        #expect(manager.formattedSourceSummary(for: combinedGame) == "Base + Update + DLC")
    }

    @Test("readmeFileURL and readGameReadme locate dm/games/<TITLE_ID>/readme.md")
    @MainActor
    func gameReadmeLookup() throws {
        let tempRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-readme-test-\(UUID().uuidString)", isDirectory: true)
        let gameDir = tempRepo
            .appendingPathComponent("dm", isDirectory: true)
            .appendingPathComponent("games", isDirectory: true)
            .appendingPathComponent("0100000011D90000", isDirectory: true)
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRepo) }

        let readmeURL = gameDir.appendingPathComponent("readme.md")
        try "# Game Notes\n- Works cleanly".write(to: readmeURL, atomically: true, encoding: .utf8)

        let manager = BuildManager(previewGames: [])
        let resolved = manager.readmeFileURL(for: "0100000011d90000", repoURL: tempRepo)
        #expect(resolved?.standardizedFileURL == readmeURL.standardizedFileURL)
        #expect(try manager.readGameReadme(for: "0100000011D90000", repoURL: tempRepo) == "# Game Notes\n- Works cleanly")
        #expect(manager.readmeFileURL(for: "0100FFFFFFFF0000", repoURL: tempRepo) == nil)
        #expect(try manager.readGameReadme(for: "0100FFFFFFFF0000", repoURL: tempRepo) == nil)
    }

    @Test("MarkdownBlockParser parses headings, lists, blockquotes, code blocks, and paragraphs")
    func markdownBlockParser() {
        let md = """
        # Title

        Intro paragraph.

        - Item A
        - Item B

        1. First
        2. Second

        > Caution

        ```sh
        echo hi
        ```
        """
        let blocks = MarkdownBlockParser.parse(md)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph(text: "Intro paragraph."),
            .bulletList(items: ["Item A", "Item B"]),
            .numberedList(items: ["First", "Second"]),
            .blockquote(text: "Caution"),
            .codeBlock(language: "sh", code: "echo hi")
        ])
    }

    @Test("MarkdownBlockParser parses pipe tables")
    func markdownTableParser() {
        let md = """
        | Key | Value |
        | --- | :--- |
        | `FOO` | **Bar** |
        | `BAZ` | 1 |
        """
        let blocks = MarkdownBlockParser.parse(md)
        #expect(blocks == [
            .table(
                headers: ["Key", "Value"],
                rows: [
                    ["`FOO`", "**Bar**"],
                    ["`BAZ`", "1"]
                ]
            )
        ])
    }

    @Test("readBuildInfo reads Info.plist provenance fields")
    func readBuildInfoFields() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-buildinfo-test-\(UUID().uuidString)", isDirectory: true)
        let contentsDir = root
            .appendingPathComponent("Test Game.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plist: [String: Any] = [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleIdentifier": "com.nxnative.testgame",
            "LSMinimumSystemVersion": "14.0",
            "DMCommit": "abc1234",
            "DMChain": "llvm-18"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsDir.appendingPathComponent("Info.plist"))

        let results = GameScanner.readBuildInfo(for: ["Test Game"], gamesRootURL: root, flatOutputLayout: true)
        let info = try #require(results.first)
        #expect(info.version == "1.2.3")
        #expect(info.bundleIdentifier == "com.nxnative.testgame")
        #expect(info.minimumSystemVersion == "14.0")
        #expect(info.commit == "abc1234")
        #expect(info.chain == "llvm-18")
    }

    @Test("PreflightChecker validates repo, sources, python, and optional assets")
    func preflightChecks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-preflight-test-\(UUID().uuidString)", isDirectory: true)
        let repoDir = root.appendingPathComponent("nxnative", isDirectory: true)
        let scriptsDir = repoDir.appendingPathComponent("scripts", isDirectory: true)
        let venvBinDir = repoDir.appendingPathComponent(".venv/bin", isDirectory: true)
        let sourcesDir = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: venvBinDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(PreflightChecker.needsOnboarding(sourcesPath: sourcesDir.path, nxnativeRepoPath: repoDir.path) == true)

        try "#!/usr/bin/env python3\n".write(to: scriptsDir.appendingPathComponent("build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        let venvPython = venvBinDir.appendingPathComponent("python3")
        try "#!/bin/sh\nexit 0\n".write(to: venvPython, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: venvPython.path)

        #expect(PreflightChecker.needsOnboarding(sourcesPath: sourcesDir.path, nxnativeRepoPath: repoDir.path) == false)

        let checks = PreflightChecker.runChecks(config: PreflightChecker.Configuration(
            sourcesPath: sourcesDir.path,
            nxnativeRepoPath: repoDir.path,
            prodKeysPath: root.appendingPathComponent("missing.keys").path,
            extraPath: ""
        ))
        let byID = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
        #expect(byID["nxnative-repo"]?.status == .passed)
        #expect(byID["sources-folder"]?.status == .passed)
        #expect(byID["python"]?.status == .passed)
        #expect(byID["prod-keys"]?.status == .warning)
        #expect(byID["nx-extract"]?.status == .warning)
    }

    @Test("removeWorkFolder deletes folders containing read-only files and subdirectories")
    func removeReadOnlyWorkFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("nxnative-rm-test-\(UUID().uuidString)", isDirectory: true)
        let buildFolder = root.appendingPathComponent("010047700D540000_build", isDirectory: true)
        let nestedDir = buildFolder.appendingPathComponent("locked_dir", isDirectory: true)
        try fm.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: buildFolder.path)
            try? fm.removeItem(at: root)
        }

        let lockedFile = nestedDir.appendingPathComponent("readonly.bin")
        try Data([0x01, 0x02]).write(to: lockedFile)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: lockedFile.path)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: nestedDir.path)

        try BuildManager.removeWorkFolder(buildFolder)
        #expect(fm.fileExists(atPath: buildFolder.path) == false)
    }
}
