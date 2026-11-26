import SwiftUI
import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers
import UserNotifications

@MainActor
@Observable
final class BuildManager {
    nonisolated private static let logger = Logger(subsystem: "com.nxnative.builder", category: "BuildManager")
    var games: [GameEntry] = []
    var isLoadingGames: Bool = false
    var selectedGameID: String? {
        didSet {
            if let selectedGameID {
                UserDefaults.standard.set(selectedGameID, forKey: DefaultsKey.lastSelectedGameID)
                inspectedLogGameID = selectedGameID
            }
        }
    }
    var isBuilding: Bool = false
    var queueItems: [BuildQueueItem] = [] {
        didSet {
            syncPendingQueueDefaults()
        }
    }
    var resumableQueueGameIDs: [String] = []
    private var pendingRestoreQueueIDs: [String] = []
    private var lastSavedPendingQueueIDs: [String] = []
    var inspectedLogGameID: String?
    var followActiveBuild: Bool = true
    var currentBuildName: String = ""
    var currentBuildStartDate: Date?
    var queueStartDate: Date?
    var currentStepProgress: Double = 0
    var currentStepLabel: String = ""
    var completedCount: Int = 0
    var totalCount: Int = 0
    var autoScroll: Bool = true
    var globalLog: String = ""
    var logRevision: Int = 0
    var preflightChecks: [PreflightCheckItem] = []
    var isRunningPreflight: Bool = false
    var repoStatus: NXNativeRepoStatus?
    var isPullingRepoUpdates: Bool = false
    var repoUpdateMessage: String?
    var showOnboardingSheet: Bool = false
    var pendingCleanFoldersGame: GameEntry?
    var pendingCleanBuiltAppGame: GameEntry?
    var pendingEnvEditorGame: GameEntry?

    private static let maxLogCharacters = 500_000

    static let defaultGamesRootPath = "/Applications"
    static let defaultCustomGamesRootPath = ""
    static let defaultSourcesPath = ""
    static let defaultExtraPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
    static let defaultNXNativeRepoPath = ""
    static let defaultProdKeysPath = ""

    private enum DefaultsKey {
        static let outputMode = "outputMode"
        static let gamesRootPath = "gamesRootPath"
        static let sourcesPath = "sourcesPath"
        static let extraPath = "extraPath"
        static let nxnativeRepoPath = "nxnativeRepoPath"
        static let prodKeysPath = "prodKeysPath"
        static let titleIDOverrides = "titleIDOverrides"
        static let appNameOverrides = "appNameOverrides"
        static let checkedGameIDs = "checkedGameIDs"
        static let lastSelectedGameID = "lastSelectedGameID"
        static let pendingQueueGameIDs = "pendingQueueGameIDs"
    }

    var outputMode: BuildOutputMode {
        didSet {
            UserDefaults.standard.set(outputMode.rawValue, forKey: DefaultsKey.outputMode)
            if !isBuilding { loadGames() }
        }
    }

    var customGamesRootPath: String {
        didSet {
            UserDefaults.standard.set(customGamesRootPath, forKey: DefaultsKey.gamesRootPath)
            if !isBuilding && outputMode == .custom { loadGames() }
        }
    }

    var sourcesPath: String {
        didSet {
            UserDefaults.standard.set(sourcesPath, forKey: DefaultsKey.sourcesPath)
            if !isBuilding { loadGames() }
        }
    }

    var extraPath: String {
        didSet {
            UserDefaults.standard.set(extraPath, forKey: DefaultsKey.extraPath)
        }
    }

    var nxnativeRepoPath: String {
        didSet {
            UserDefaults.standard.set(nxnativeRepoPath, forKey: DefaultsKey.nxnativeRepoPath)
        }
    }

    var prodKeysPath: String {
        didSet {
            UserDefaults.standard.set(prodKeysPath, forKey: DefaultsKey.prodKeysPath)
        }
    }

    var titleIDOverrides: [String: String] {
        didSet {
            UserDefaults.standard.set(titleIDOverrides, forKey: DefaultsKey.titleIDOverrides)
        }
    }

    var appNameOverrides: [String: String] {
        didSet {
            UserDefaults.standard.set(appNameOverrides, forKey: DefaultsKey.appNameOverrides)
        }
    }

    var gamesRootURL: URL {
        switch outputMode {
        case .applications:
            return URL(fileURLWithPath: Self.defaultGamesRootPath)
        case .custom:
            let trimmed = customGamesRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(fileURLWithPath: trimmed.isEmpty ? Self.defaultGamesRootPath : trimmed)
        }
    }

    var useFlatOutputLayout: Bool {
        outputMode == .applications || gamesRootURL.standardizedFileURL.path == Self.defaultGamesRootPath
    }

    var sourcesURL: URL {
        URL(fileURLWithPath: sourcesPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var nxnativeRepoURL: URL {
        URL(fileURLWithPath: nxnativeRepoPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var activeProcess: Process?
    private var stopRequested = false
    private var cancelCurrentRequested = false
    private var lineBuffer = ""
    private var metadataCache: [String: CachedPackageMetadata] = [:]
    private var loadGamesTask: Task<Void, Never>?
    private var metadataScanTask: Task<Void, Never>?
    private var buildActivity: NSObjectProtocol?

    private static let stepRegex = try? NSRegularExpression(
        pattern: #"^(?:\[\d{2}:\d{2}:\d{2}\]\s+)?([✓✗]\s+)?\[(\d+)/(\d+)\]\s+(.+)$"#
    )
    private static let percentRegex = try? NSRegularExpression(pattern: #":\s*(\d+)%"#)
    private static let ansiRegex = try? NSRegularExpression(
        pattern: #"\x1B(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#
    )
    private static let nonSGRANSIRegex = try? NSRegularExpression(
        pattern: #"\x1B(?:\[(?![0-9;]*m)[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#
    )

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, HH:mm"
        return df
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let bf = ByteCountFormatter()
        bf.countStyle = .file
        return bf
    }()

    func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    func formatBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: bytes)
    }

    init() {
        let defaults = UserDefaults.standard
        let savedCustomPath = defaults.string(forKey: DefaultsKey.gamesRootPath)
        if let rawMode = defaults.string(forKey: DefaultsKey.outputMode),
           let mode = BuildOutputMode(rawValue: rawMode) {
            self.outputMode = mode
            self.customGamesRootPath = savedCustomPath ?? Self.defaultCustomGamesRootPath
        } else if let savedCustomPath,
                  !savedCustomPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  URL(fileURLWithPath: savedCustomPath).standardizedFileURL.path != Self.defaultGamesRootPath {
            self.outputMode = .custom
            self.customGamesRootPath = savedCustomPath
        } else {
            self.outputMode = .applications
            self.customGamesRootPath = savedCustomPath ?? Self.defaultCustomGamesRootPath
        }
        self.sourcesPath = defaults.string(forKey: DefaultsKey.sourcesPath) ?? Self.defaultSourcesPath
        self.extraPath = defaults.string(forKey: DefaultsKey.extraPath) ?? Self.defaultExtraPath
        self.nxnativeRepoPath = defaults.string(forKey: DefaultsKey.nxnativeRepoPath) ?? Self.defaultNXNativeRepoPath
        self.prodKeysPath = defaults.string(forKey: DefaultsKey.prodKeysPath) ?? Self.defaultProdKeysPath
        self.titleIDOverrides = (defaults.dictionary(forKey: DefaultsKey.titleIDOverrides) as? [String: String]) ?? [:]
        self.appNameOverrides = (defaults.dictionary(forKey: DefaultsKey.appNameOverrides) as? [String: String]) ?? [:]
        self.selectedGameID = defaults.string(forKey: DefaultsKey.lastSelectedGameID)
        let savedPending = defaults.stringArray(forKey: DefaultsKey.pendingQueueGameIDs) ?? []
        self.pendingRestoreQueueIDs = savedPending
        self.lastSavedPendingQueueIDs = savedPending
        self.showOnboardingSheet = PreflightChecker.needsOnboarding(
            sourcesPath: self.sourcesPath,
            nxnativeRepoPath: self.nxnativeRepoPath
        )
        loadMetadataCache()
        loadGames()
        requestNotificationPermission()
    }

    #if DEBUG
    init(
        previewGames: [GameEntry] = [],
        previewQueue: [BuildQueueItem] = [],
        isBuilding: Bool = false,
        selectedGameID: String? = nil
    ) {
        self.outputMode = .applications
        self.customGamesRootPath = Self.defaultCustomGamesRootPath
        self.sourcesPath = Self.defaultSourcesPath
        self.extraPath = Self.defaultExtraPath
        self.nxnativeRepoPath = Self.defaultNXNativeRepoPath
        self.prodKeysPath = Self.defaultProdKeysPath
        self.titleIDOverrides = [:]
        self.appNameOverrides = [:]
        self.games = previewGames
        self.queueItems = previewQueue
        self.isBuilding = isBuilding
        self.selectedGameID = selectedGameID
        self.inspectedLogGameID = selectedGameID
        if isBuilding {
            self.currentBuildName = previewQueue.first(where: { $0.status == .building })?.gameName ?? previewGames.first?.name ?? ""
            self.currentBuildStartDate = Date().addingTimeInterval(-42)
            self.queueStartDate = Date().addingTimeInterval(-95)
            self.currentStepLabel = "Translating Shader Cache"
            self.totalCount = max(previewQueue.count, 1)
            self.completedCount = previewQueue.filter { $0.status == .succeeded }.count
        }
    }

    static func previewSample(isBuilding: Bool = true) -> BuildManager {
        let game1 = GameEntry(
            id: "0100726014352000",
            name: "Diablo II Resurrected",
            folderURL: URL(fileURLWithPath: "/tmp/Diablo II Resurrected"),
            sourcePackages: [
                SourcePackageInfo(
                    id: "1",
                    kinds: [.base],
                    displayName: "Diablo II Resurrected",
                    version: "v1.0.0",
                    rawFilename: "Diablo II Resurrected [0100726014352000][v0].nsp",
                    titleID: "0100726014352000"
                ),
                SourcePackageInfo(
                    id: "2",
                    kinds: [.update],
                    displayName: "Diablo II Resurrected Update",
                    version: "v1.0.35",
                    rawFilename: "Diablo II Resurrected [0100726014352800][v2293760](1.0.35).nsp",
                    titleID: "0100726014352800"
                )
            ],
            detectedTitleID: "0100726014352000",
            hasSwitch2Source: false,
            isSelected: true,
            status: isBuilding ? .building : .succeeded,
            buildInfo: [
                BuildArtifactInfo(
                    appName: "Diablo II Resurrected.app",
                    version: "1.0.34",
                    buildDate: Date().addingTimeInterval(-86_400),
                    commit: "abc1234",
                    chain: "metal-4",
                    sizeBytes: 12_450_000_000
                )
            ],
            availableUpdateVersion: "1.0.35",
            lastBuildDuration: 84,
            log: "[1/4] Extracting NSP...\n[2/4] Translating shaders...\n"
        )
        let game2 = GameEntry(
            id: "0400123456780000",
            name: "Ultra Long Switch 2 Adventure Title With Subtitle Edition",
            folderURL: URL(fileURLWithPath: "/tmp/Switch2Game"),
            sourcePackages: [
                SourcePackageInfo(
                    id: "3",
                    kinds: [.base, .update],
                    displayName: "Ultra Long Switch 2 Adventure",
                    version: "v2.1.0",
                    rawFilename: "Adventure [0400123456780000].nup",
                    titleID: "0400123456780000"
                )
            ],
            detectedTitleID: "0400123456780000",
            hasSwitch2Source: true,
            status: .failed(1),
            log: "error: missing required asset\n"
        )
        let queue = [
            BuildQueueItem(id: game1.id, gameName: game1.name, status: .building, progress: 0.62, stepLabel: "Translating shaders", startDate: Date().addingTimeInterval(-42)),
            BuildQueueItem(id: game2.id, gameName: game2.name, status: .failed(1), progress: 0.35, duration: 19),
            BuildQueueItem(id: "queued-3", gameName: "Super Mario Galaxy", status: .queued)
        ]
        return BuildManager(
            previewGames: [game1, game2],
            previewQueue: isBuilding ? queue : [],
            isBuilding: isBuilding,
            selectedGameID: game1.id
        )
    }
    #endif

    func saveCheckedGames() {
        let checked = games.filter { $0.isSelected }.map { $0.id }
        UserDefaults.standard.set(checked, forKey: DefaultsKey.checkedGameIDs)
    }

    private static var metadataCacheURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("NXNativeBuilder", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create metadata cache directory: \(error.localizedDescription)")
            return nil
        }
        return dir.appendingPathComponent("package_metadata.json")
    }

    private func loadMetadataCache() {
        guard let url = Self.metadataCacheURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CachedPackageMetadata].self, from: data) else {
            return
        }
        metadataCache = decoded
    }

    private func saveMetadataCache() {
        guard let url = Self.metadataCacheURL else { return }
        do {
            let data = try JSONEncoder().encode(metadataCache)
            try data.write(to: url, options: [.atomic])
        } catch {
            Self.logger.error("Failed to save metadata cache: \(error.localizedDescription)")
        }
    }

    func resetPathsToDefaults() {
        outputMode = .applications
        customGamesRootPath = Self.defaultCustomGamesRootPath
        sourcesPath = Self.defaultSourcesPath
        extraPath = Self.defaultExtraPath
        nxnativeRepoPath = Self.defaultNXNativeRepoPath
        prodKeysPath = Self.defaultProdKeysPath
        runPreflightChecks()
        refreshNXNativeRepoStatus()
    }

    func runPreflightChecks() {
        let config = PreflightChecker.Configuration(
            sourcesPath: sourcesPath,
            nxnativeRepoPath: nxnativeRepoPath,
            prodKeysPath: prodKeysPath,
            extraPath: extraPath
        )
        isRunningPreflight = true
        Task { [weak self] in
            let checks = await Task.detached(priority: .utility) {
                PreflightChecker.runChecks(config: config)
            }.value
            guard let self else { return }
            self.preflightChecks = checks
            self.isRunningPreflight = false
        }
    }

    func refreshNXNativeRepoStatus() {
        let repoURL = nxnativeRepoURL
        let extra = extraPath
        Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                PreflightChecker.readRepoStatus(at: repoURL, extraPath: extra)
            }.value
            guard let self else { return }
            self.repoStatus = status
        }
    }

    func pullNXNativeRepoUpdates() {
        guard !isBuilding, !isPullingRepoUpdates else { return }
        let repoURL = nxnativeRepoURL
        let extra = extraPath
        isPullingRepoUpdates = true
        repoUpdateMessage = nil
        Task { [weak self] in
            let (result, status) = await Task.detached(priority: .userInitiated) {
                let pull = PreflightChecker.pullUpdates(at: repoURL, extraPath: extra)
                let newStatus = PreflightChecker.readRepoStatus(at: repoURL, extraPath: extra)
                return (pull, newStatus)
            }.value
            guard let self else { return }
            self.repoUpdateMessage = result.message
            self.repoStatus = status
            self.isPullingRepoUpdates = false
            self.runPreflightChecks()
        }
    }

    func effectiveIsSwitch2(for game: GameEntry) -> Bool {
        if let tid = effectiveTitleID(for: game), tid.hasPrefix("0400") {
            return true
        }
        return game.hasSwitch2Source
    }

    func effectiveTitleID(for game: GameEntry) -> String? {
        if let custom = titleIDOverrides[game.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom.uppercased()
        }
        return game.detectedTitleID
    }

    func setTitleIDOverride(_ value: String, for gameID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.isEmpty {
            titleIDOverrides.removeValue(forKey: gameID)
        } else {
            titleIDOverrides[gameID] = trimmed
        }
    }

    func effectiveAppName(for game: GameEntry) -> String {
        if let custom = appNameOverrides[game.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return game.name
    }

    func setAppNameOverride(_ value: String, for gameID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            appNameOverrides.removeValue(forKey: gameID)
        } else {
            appNameOverrides[gameID] = trimmed
        }
        Task {
            await refreshBuildInfo(for: gameID)
        }
    }

    enum GameIconError: LocalizedError {
        case gameNotFound
        case normalizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .gameNotFound:
                return "The selected game could not be found."
            case .normalizationFailed(let filename):
                return "Could not process \"\(filename)\" as a 1024×1024 macOS icon."
            }
        }
    }

    func setGameIcon(from sourceURL: URL, for gameID: String, trashPreviousIcon: Bool) throws {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else {
            throw GameIconError.gameNotFound
        }

        let previousURL = games[index].iconURL
        let titleID = effectiveTitleID(for: games[index])
        guard let savedURL = GameScanner.saveNormalizedIcon(
            from: sourceURL,
            in: games[index].folderURL,
            titleID: titleID
        ),
        let newImage = NSImage(contentsOf: savedURL) else {
            throw GameIconError.normalizationFailed(sourceURL.lastPathComponent)
        }

        if trashPreviousIcon,
           let previousURL,
           previousURL.standardizedFileURL != savedURL.standardizedFileURL {
            let isSharedWithOtherGame = games.enumerated().contains { offset, entry in
                offset != index && entry.iconURL?.standardizedFileURL == previousURL.standardizedFileURL
            }
            if !isSharedWithOtherGame {
                do {
                    try FileManager.default.trashItem(at: previousURL, resultingItemURL: nil)
                } catch {
                    Self.logger.error("Failed to trash previous icon \(previousURL.path): \(error.localizedDescription)")
                }
            }
        }

        games[index].iconURL = savedURL
        games[index].iconImage = newImage
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            do {
                try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            }
        }
    }

    func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }

    private func formatArtifact(_ info: BuildArtifactInfo, includeName: Bool) -> String {
        var parts = [
            "v\(info.version)",
            Self.dateFormatter.string(from: info.buildDate),
            info.commit
        ]
        if let chain = info.chain, !chain.isEmpty {
            parts.append(chain)
        }
        let summary = parts.joined(separator: " · ")
        return includeName ? "\(info.appName): \(summary)" : summary
    }

    func formattedBuildSummary(for game: GameEntry) -> String {
        if game.buildInfo.isEmpty {
            return "Not built yet"
        }
        if game.buildInfo.count == 1, let info = game.buildInfo.first {
            return formatArtifact(info, includeName: false)
        }
        return game.buildInfo.map { formatArtifact($0, includeName: true) }.joined(separator: " | ")
    }

    func formattedCompactSummary(for game: GameEntry) -> String {
        if game.buildInfo.isEmpty {
            return "Not built"
        }
        if game.buildInfo.count == 1, let info = game.buildInfo.first {
            if let size = info.sizeBytes {
                return "v\(info.version) · \(formatBytes(size))"
            }
            return "v\(info.version)"
        }
        return game.buildInfo.map { "\($0.appName) v\($0.version)" }.joined(separator: " · ")
    }

    /// Returns a summary of unique source package kinds (e.g. "Base + Update + DLC"), or nil when none exist.
    func formattedSourceSummary(for game: GameEntry) -> String? {
        let kinds = Set(game.sourcePackages.flatMap(\.kinds)).sorted()
        guard !kinds.isEmpty else { return nil }
        return kinds.map(\.label).joined(separator: " + ")
    }

    func availableUpdateVersion(for game: GameEntry) -> String? {
        game.availableUpdateVersion
    }

    func loadGames() {
        loadGamesTask?.cancel()
        let sourcesURL = self.sourcesURL
        let gamesRootURL = self.gamesRootURL
        let flatOutputLayout = self.useFlatOutputLayout
        let metadataCache = self.metadataCache
        let appNameOverrides = self.appNameOverrides
        let savedChecked = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.checkedGameIDs) ?? [])
        let previousByID = Dictionary(uniqueKeysWithValues: games.map {
            ($0.id, GameScanner.ExistingGameState(
                isSelected: $0.isSelected,
                status: $0.status,
                lastBuildDuration: $0.lastBuildDuration,
                log: $0.log
            ))
        })
        let useSavedChecked = games.isEmpty
        isLoadingGames = true

        loadGamesTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                GameScanner.scanGames(
                    sourcesURL: sourcesURL,
                    gamesRootURL: gamesRootURL,
                    flatOutputLayout: flatOutputLayout,
                    metadataCache: metadataCache,
                    appNameOverrides: appNameOverrides,
                    previousByID: previousByID,
                    savedChecked: savedChecked,
                    useSavedChecked: useSavedChecked
                )
            }.value

            if Task.isCancelled { return }
            guard let self else { return }

            self.games = loaded
            self.isLoadingGames = false
            self.resolveResumableQueue(against: loaded)
            if self.selectedGameID == nil || !loaded.contains(where: { $0.id == self.selectedGameID }) {
                self.selectedGameID = loaded.first?.id
            }
            self.scheduleBackgroundMetadataScan(for: loaded)
        }
    }

    private func scheduleBackgroundMetadataScan(for entries: [GameEntry]) {
        metadataScanTask?.cancel()

        let nxExtractURL = nxnativeRepoURL.appendingPathComponent("dm/tools/nx_extract_bin/nx_extract")
        let keysPath = prodKeysPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let keysURL = URL(fileURLWithPath: keysPath)
        let cacheSnapshot = metadataCache

        struct ScanJob {
            let folderURL: URL
            let files: [(url: URL, size: Int64, modTime: TimeInterval)]
        }

        metadataScanTask = Task { [weak self] in
            let jobs: [ScanJob] = await Task.detached(priority: .utility) {
                let fm = FileManager.default
                guard fm.fileExists(atPath: nxExtractURL.path), fm.fileExists(atPath: keysURL.path) else {
                    return []
                }
                let scanExts: Set<String> = ["nsp", "xci", "nsz"]
                var collected: [ScanJob] = []
                var seenFolders = Set<URL>()
                for entry in entries where seenFolders.insert(entry.folderURL).inserted {
                    var uncached: [(URL, Int64, TimeInterval)] = []
                    for pkg in entry.sourcePackages {
                        let fileURL = entry.folderURL.appendingPathComponent(pkg.rawFilename)
                        guard scanExts.contains(fileURL.pathExtension.lowercased()),
                              fm.fileExists(atPath: fileURL.path),
                              GameScanner.cachedContents(for: fileURL, metadataCache: cacheSnapshot) == nil,
                              let sig = GameScanner.fileSignature(for: fileURL) else {
                            continue
                        }
                        uncached.append((fileURL, sig.size, sig.modTime))
                    }
                    if !uncached.isEmpty {
                        collected.append(ScanJob(folderURL: entry.folderURL, files: uncached))
                    }
                }
                return collected
            }.value

            if Task.isCancelled || jobs.isEmpty { return }

            for job in jobs {
                if Task.isCancelled { return }
                let urls = job.files.map { $0.url }
                let results = await Task.detached(priority: .utility) {
                    GameScanner.runNXExtractContents(files: urls, nxExtractURL: nxExtractURL, prodKeysURL: keysURL)
                }.value

                if Task.isCancelled { return }
                guard let self, !results.isEmpty else { continue }

                var updated = false
                for (fileURL, size, modTime) in job.files {
                    if let records = results[fileURL.lastPathComponent], !records.isEmpty {
                        self.metadataCache[fileURL.path] = CachedPackageMetadata(
                            fileSize: size,
                            modTime: modTime,
                            contents: records
                        )
                        updated = true
                    }
                }

                if updated {
                    self.saveMetadataCache()
                    let updatedCache = self.metadataCache
                    let gamesRoot = self.gamesRootURL
                    let flatOutputLayout = self.useFlatOutputLayout
                    let appNameOverrides = self.appNameOverrides
                    let previousByID = Dictionary(uniqueKeysWithValues: self.games.map {
                        ($0.id, GameScanner.ExistingGameState(
                            isSelected: $0.isSelected,
                            status: $0.status,
                            lastBuildDuration: $0.lastBuildDuration,
                            log: $0.log
                        ))
                    })

                    let expanded = await Task.detached(priority: .utility) {
                        let newPackages = GameScanner.parseSourcePackages(in: job.folderURL, metadataCache: updatedCache)
                        return GameScanner.expandFolderEntries(
                            folderURL: job.folderURL,
                            sourcePackages: newPackages,
                            metadataCache: updatedCache,
                            gamesRootURL: gamesRoot,
                            flatOutputLayout: flatOutputLayout,
                            appNameOverrides: appNameOverrides,
                            previousByID: previousByID
                        )
                    }.value

                    if Task.isCancelled { return }
                    if let firstIdx = self.games.firstIndex(where: { $0.folderURL == job.folderURL }) {
                        self.games.removeAll { $0.folderURL == job.folderURL }
                        self.games.insert(contentsOf: expanded, at: min(firstIdx, self.games.count))
                        if let sel = self.selectedGameID, !self.games.contains(where: { $0.id == sel }) {
                            self.selectedGameID = expanded.first?.id ?? self.games.first?.id
                        }
                    }
                }
            }
        }
    }

    private func refreshBuildInfo(for gameID: String) async {
        guard let game = games.first(where: { $0.id == gameID }) else { return }
        let appNames = [effectiveAppName(for: game)]
        let gamesRoot = gamesRootURL
        let flatOutputLayout = useFlatOutputLayout
        let folderURL = game.folderURL
        let sourcePackages = game.sourcePackages

        let refreshed = await Task.detached(priority: .userInitiated) {
            let info = GameScanner.readBuildInfo(for: appNames, gamesRootURL: gamesRoot, flatOutputLayout: flatOutputLayout)
            let apps = GameScanner.builtAppURLs(forAppNames: appNames, gamesRootURL: gamesRoot, flatOutputLayout: flatOutputLayout)
            let folders = GameScanner.buildWorkFolders(in: folderURL)
            let updateVer = GameScanner.availableUpdateVersion(for: info, sourcePackages: sourcePackages, folderURL: folderURL)
            return (info, apps, folders, updateVer)
        }.value

        guard let idx = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[idx].buildInfo = refreshed.0
        games[idx].builtAppURLs = refreshed.1
        games[idx].workFolders = refreshed.2
        games[idx].availableUpdateVersion = refreshed.3
    }

    func selectAll(_ selected: Bool) {
        for i in games.indices {
            games[i].isSelected = selected
        }
        saveCheckedGames()
    }

    func outdatedGameIDs() -> [String] {
        games.filter { availableUpdateVersion(for: $0) != nil }.map(\.id)
    }

    func selectOutdated() {
        let outdated = Set(outdatedGameIDs())
        for i in games.indices {
            games[i].isSelected = outdated.contains(games[i].id)
        }
        saveCheckedGames()
    }

    func buildOutdated() {
        let ids = outdatedGameIDs()
        enqueueGames(ids: ids, clearCheckboxes: false)
    }

    func cleanAllBuildFolders() {
        let targets: [(id: String, folderURL: URL, folders: [URL])] = games.compactMap { game in
            game.workFolders.isEmpty ? nil : (game.id, game.folderURL, game.workFolders)
        }
        guard !targets.isEmpty else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            var deletedCount = 0
            var failedCount = 0
            var remainingByID: [String: [URL]] = [:]

            for target in targets {
                for folder in target.folders {
                    do {
                        try Self.removeWorkFolder(folder)
                        deletedCount += 1
                    } catch {
                        Self.logger.error("Failed to remove work folder \(folder.path): \(error.localizedDescription)")
                        failedCount += 1
                    }
                }
                remainingByID[target.id] = GameScanner.buildWorkFolders(in: target.folderURL)
            }

            await MainActor.run { [weak self, deletedCount, failedCount, remainingByID] in
                guard let self else { return }
                for i in self.games.indices {
                    if let remaining = remainingByID[self.games[i].id] {
                        self.games[i].workFolders = remaining
                    }
                }
                let msg = failedCount == 0
                    ? "Deleted \(deletedCount) build folder(s) across all games.\n"
                    : "Deleted \(deletedCount) build folder(s) (\(failedCount) failed).\n"
                self.globalLog.append(msg)
            }
        }
    }

    func buildSelected() {
        let ids = games.filter { $0.isSelected }.map(\.id)
        enqueueGames(ids: ids, clearCheckboxes: true)
    }

    func buildAll() {
        let ids = games.map(\.id)
        enqueueGames(ids: ids, clearCheckboxes: false)
    }

    func buildSingle(_ id: String) {
        if isBuilding {
            toggleQueue(id)
        } else {
            enqueueGames(ids: [id], clearCheckboxes: false)
        }
    }

    func retryFailed() {
        let ids = games.compactMap { game -> String? in
            if case .failed = game.status { return game.id }
            return nil
        }
        enqueueGames(ids: ids, clearCheckboxes: false)
    }

    var activeQueueItem: BuildQueueItem? {
        queueItems.first { $0.status == .building }
    }

    var hasQueuedOrBuildingItems: Bool {
        queueItems.contains { $0.status == .queued || $0.status == .building }
    }

    var hasFinishedQueueItems: Bool {
        queueItems.contains { $0.status.isFinished }
    }

    var overallQueueProgress: Double {
        guard !queueItems.isEmpty else { return 0 }
        let sum = queueItems.reduce(0.0) { partial, item in
            switch item.status {
            case .succeeded, .failed, .stopped, .cancelled:
                return partial + 1.0
            case .building:
                return partial + min(max(item.progress, 0.0), 1.0)
            case .idle, .queued:
                return partial
            }
        }
        return min(max(sum / Double(queueItems.count), 0.0), 1.0)
    }

    func queueItem(for gameID: String) -> BuildQueueItem? {
        queueItems.first { $0.id == gameID }
    }

    func queuePosition(for gameID: String) -> Int? {
        guard let idx = queueItems.firstIndex(where: { $0.id == gameID }) else { return nil }
        return idx + 1
    }

    func inspectQueueItemLog(_ id: String) {
        inspectedLogGameID = id
        followActiveBuild = false
    }

    func setFollowActiveBuild(_ follow: Bool) {
        followActiveBuild = follow
        if follow, let activeID = activeQueueItem?.id {
            inspectedLogGameID = activeID
        }
    }

    @discardableResult
    func enqueueGames(ids: [String], clearCheckboxes: Bool = true, startIfIdle: Bool = true) -> [String] {
        guard !ids.isEmpty else { return [] }

        if !isBuilding {
            queueItems.removeAll { $0.status.isFinished }
        }

        var addedIDs: [String] = []
        for id in ids {
            guard let gameIdx = games.firstIndex(where: { $0.id == id }) else { continue }
            if let existing = queueItems.first(where: { $0.id == id }),
               existing.status == .queued || existing.status == .building {
                continue
            }

            queueItems.removeAll { $0.id == id }
            queueItems.append(BuildQueueItem(id: id, gameName: games[gameIdx].name, status: .queued))
            games[gameIdx].status = .queued
            games[gameIdx].lastBuildDuration = nil
            games[gameIdx].log = ""
            if clearCheckboxes {
                games[gameIdx].isSelected = false
            }
            addedIDs.append(id)
        }

        if clearCheckboxes && !addedIDs.isEmpty {
            saveCheckedGames()
        }

        totalCount = queueItems.count

        if startIfIdle && !isBuilding && queueItems.contains(where: { $0.status == .queued }) {
            startQueueLoop()
        }
        return addedIDs
    }

    func toggleQueue(_ id: String) {
        guard isBuilding, let idx = games.firstIndex(where: { $0.id == id }) else { return }
        if games[idx].status == .building { return }

        if games[idx].status == .queued {
            cancelQueueItem(id: id)
        } else {
            enqueueGames(ids: [id], clearCheckboxes: false)
        }
    }

    func cancelQueueItem(id: String) {
        guard let qIdx = queueItems.firstIndex(where: { $0.id == id }) else { return }
        switch queueItems[qIdx].status {
        case .queued:
            queueItems.remove(at: qIdx)
            if let gIdx = games.firstIndex(where: { $0.id == id }) {
                games[gIdx].status = .idle
            }
            totalCount = queueItems.count
        case .building:
            cancelCurrentRequested = true
            terminateActiveProcess()
        case .idle, .succeeded, .failed, .stopped, .cancelled:
            queueItems.remove(at: qIdx)
            totalCount = queueItems.count
        }
    }

    func retryQueueItem(id: String, startIfIdle: Bool = true) {
        guard let gIdx = games.firstIndex(where: { $0.id == id }) else { return }
        if let existing = queueItems.first(where: { $0.id == id }),
           existing.status == .queued || existing.status == .building {
            return
        }

        queueItems.removeAll { $0.id == id }
        games[gIdx].status = .queued
        games[gIdx].lastBuildDuration = nil
        games[gIdx].log = ""

        let newItem = BuildQueueItem(id: id, gameName: games[gIdx].name, status: .queued)
        if let buildingIdx = queueItems.firstIndex(where: { $0.status == .building }) {
            queueItems.insert(newItem, at: buildingIdx + 1)
        } else if isBuilding {
            queueItems.insert(newItem, at: 0)
        } else {
            queueItems.append(newItem)
        }
        totalCount = queueItems.count

        if startIfIdle && !isBuilding {
            startQueueLoop()
        }
    }

    func clearFinishedQueueItems() {
        queueItems.removeAll { $0.status.isFinished }
        if !isBuilding {
            totalCount = queueItems.count
            completedCount = 0
        }
    }

    @discardableResult
    func resumeInterruptedQueue(startIfIdle: Bool = true) -> [String] {
        let ids = resumableQueueGameIDs
        guard !ids.isEmpty else { return [] }
        discardInterruptedQueue()
        return enqueueGames(ids: ids, clearCheckboxes: false, startIfIdle: startIfIdle)
    }

    func discardInterruptedQueue() {
        resumableQueueGameIDs = []
        pendingRestoreQueueIDs = []
        lastSavedPendingQueueIDs = []
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingQueueGameIDs)
    }

    func restoreResumableQueue(from savedIDs: [String]) {
        pendingRestoreQueueIDs = savedIDs
        resolveResumableQueue(against: games)
    }

    private func resolveResumableQueue(against loadedGames: [GameEntry]) {
        guard !pendingRestoreQueueIDs.isEmpty else { return }
        let validIDs = Set(loadedGames.map(\.id))
        let filtered = pendingRestoreQueueIDs.filter { validIDs.contains($0) }
        pendingRestoreQueueIDs = []
        if !isBuilding && !filtered.isEmpty {
            resumableQueueGameIDs = filtered
        } else if filtered.isEmpty {
            lastSavedPendingQueueIDs = []
            UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingQueueGameIDs)
        }
    }

    private func syncPendingQueueDefaults() {
        let pendingIDs = queueItems
            .filter { $0.status == .building || $0.status == .queued }
            .map(\.id)
        guard pendingIDs != lastSavedPendingQueueIDs else { return }
        lastSavedPendingQueueIDs = pendingIDs
        if pendingIDs.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingQueueGameIDs)
        } else {
            UserDefaults.standard.set(pendingIDs, forKey: DefaultsKey.pendingQueueGameIDs)
        }
    }

    func cancelAllBuilds() {
        stopRequested = true
        for i in queueItems.indices where queueItems[i].status == .queued {
            queueItems[i].status = .cancelled
        }
        for i in games.indices where games[i].status == .queued {
            games[i].status = .cancelled
        }
        terminateActiveProcess()
    }

    func stopBuild() {
        cancelAllBuilds()
    }

    private func terminateActiveProcess() {
        if let proc = activeProcess, proc.isRunning {
            let pid = proc.processIdentifier
            Task.detached(priority: .userInitiated) {
                Self.killProcessTree(rootPID: pid, signal: SIGTERM)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, let current = self.activeProcess,
                      current.processIdentifier == pid, current.isRunning else { return }
                Task.detached(priority: .userInitiated) {
                    Self.killProcessTree(rootPID: pid, signal: SIGKILL)
                }
            }
        }
    }

    nonisolated private static func killProcessTree(rootPID: Int32, signal sig: Int32) {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-eo", "pid=,ppid="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice

        var childrenByParent: [Int32: [Int32]] = [:]
        if (try? ps.run()) != nil {
            ps.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(whereSeparator: \.isNewline) {
                    let cols = line.split(whereSeparator: \.isWhitespace)
                    if cols.count >= 2, let pid = Int32(cols[0]), let ppid = Int32(cols[1]) {
                        childrenByParent[ppid, default: []].append(pid)
                    }
                }
            }
        }

        var descendants: [Int32] = []
        var stack = [rootPID]
        while let current = stack.popLast() {
            for child in childrenByParent[current, default: []] {
                descendants.append(child)
                stack.append(child)
            }
        }

        for pid in descendants.reversed() {
            Darwin.kill(pid, sig)
        }
        Darwin.kill(rootPID, sig)
    }

    func clearLogs() {
        globalLog = ""
        for i in games.indices {
            games[i].log = ""
        }
        logRevision &+= 1
    }

    func builtAppURLs(for game: GameEntry) -> [URL] {
        game.builtAppURLs
    }

    func launchApp(at appURL: URL) {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func envFileURL(for titleID: String, baseDirectory: URL? = nil) -> URL? {
        let trimmed = titleID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        guard let root = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("nxnative", isDirectory: true) else {
            return nil
        }
        return root
            .appendingPathComponent(trimmed, isDirectory: true)
            .appendingPathComponent("env.txt", isDirectory: false)
    }

    func readEnvFile(for titleID: String, baseDirectory: URL? = nil) throws -> String {
        guard let url = envFileURL(for: titleID, baseDirectory: baseDirectory) else {
            return ""
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func saveEnvFile(_ content: String, for titleID: String, baseDirectory: URL? = nil) throws {
        guard let url = envFileURL(for: titleID, baseDirectory: baseDirectory) else {
            return
        }
        let dirURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func readmeFileURL(for titleID: String, repoURL: URL? = nil) -> URL? {
        let trimmed = titleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let gamesDir = (repoURL ?? nxnativeRepoURL)
            .appendingPathComponent("dm", isDirectory: true)
            .appendingPathComponent("games", isDirectory: true)
        let fm = FileManager.default
        let candidates = [
            gamesDir.appendingPathComponent(trimmed.uppercased(), isDirectory: true).appendingPathComponent("readme.md", isDirectory: false),
            gamesDir.appendingPathComponent(trimmed.uppercased(), isDirectory: true).appendingPathComponent("README.md", isDirectory: false),
            gamesDir.appendingPathComponent(trimmed.lowercased(), isDirectory: true).appendingPathComponent("readme.md", isDirectory: false),
            gamesDir.appendingPathComponent(trimmed.lowercased(), isDirectory: true).appendingPathComponent("README.md", isDirectory: false)
        ]
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    func readGameReadme(for titleID: String, repoURL: URL? = nil) throws -> String? {
        guard let url = readmeFileURL(for: titleID, repoURL: repoURL) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func cleanBuiltApps(for game: GameEntry) {
        let appURLs = game.builtAppURLs
        guard !appURLs.isEmpty else { return }
        let gameID = game.id

        Task { [weak self] in
            let errors = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var errs: [String] = []
                for appURL in appURLs {
                    do {
                        try fm.trashItem(at: appURL, resultingItemURL: nil)
                    } catch {
                        Self.logger.warning("Failed to trash \(appURL.lastPathComponent), removing directly: \(error.localizedDescription)")
                        do {
                            try fm.removeItem(at: appURL)
                        } catch {
                            Self.logger.error("Failed to remove \(appURL.lastPathComponent): \(error.localizedDescription)")
                            errs.append("Failed to remove \(appURL.lastPathComponent): \(error.localizedDescription)\n")
                        }
                    }
                }
                return errs
            }.value

            guard let self else { return }
            for err in errors {
                self.appendLog(err, for: gameID)
            }
            await self.refreshBuildInfo(for: gameID)
        }
    }

    func buildWorkFolders(for game: GameEntry) -> [URL] {
        game.workFolders
    }

    func cleanBuildFolders(for game: GameEntry) {
        let folders = game.workFolders
        guard !folders.isEmpty else { return }
        let gameID = game.id

        Task.detached(priority: .userInitiated) { [weak self] in
            var removed: [String] = []
            var errors: [String] = []

            for folder in folders {
                do {
                    try Self.removeWorkFolder(folder)
                    removed.append(folder.lastPathComponent)
                } catch {
                    errors.append("\(folder.lastPathComponent): \(error.localizedDescription)")
                }
            }

            let remainingFolders = GameScanner.buildWorkFolders(in: game.folderURL)

            await MainActor.run { [weak self, removed, errors, remainingFolders] in
                guard let self else { return }
                if let idx = self.games.firstIndex(where: { $0.id == gameID }) {
                    self.games[idx].workFolders = remainingFolders
                }
                if !removed.isEmpty {
                    self.appendLog("Deleted build folders for \(game.name): \(removed.joined(separator: ", "))\n", for: gameID)
                }
                if !errors.isEmpty {
                    self.appendLog("Failed to delete build folders for \(game.name): \(errors.joined(separator: "; "))\n", for: gameID)
                }
            }
        }
    }

    nonisolated static func removeWorkFolder(_ folder: URL) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: folder)
            return
        } catch {
            Self.logger.warning("Initial removeItem failed for \(folder.lastPathComponent), restoring write permissions: \(error.localizedDescription)")
        }

        ensureOwnerWritable(at: folder, isDirectory: true, fm: fm)
        if let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            for case let itemURL as URL in enumerator {
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                ensureOwnerWritable(at: itemURL, isDirectory: isDir, fm: fm)
            }
        }

        do {
            try fm.removeItem(at: folder)
        } catch {
            Self.logger.warning("Retry removeItem failed for \(folder.lastPathComponent), falling back to Trash: \(error.localizedDescription)")
            try fm.trashItem(at: folder, resultingItemURL: nil)
        }
    }

    nonisolated private static func ensureOwnerWritable(at url: URL, isDirectory: Bool, fm: FileManager) {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let current = attrs[.posixPermissions] as? Int else {
            try? fm.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
            return
        }
        let requiredBits = isDirectory ? 0o700 : 0o200
        if (current & requiredBits) != requiredBits {
            try? fm.setAttributes([.posixPermissions: current | requiredBits], ofItemAtPath: url.path)
        }
    }

    private func deployBuiltApps(for game: GameEntry) async {
        let gamesRoot = gamesRootURL
        let flatLayout = useFlatOutputLayout
        let appName = effectiveAppName(for: game)
        let sourceAppURL = game.folderURL.appendingPathComponent("\(appName).app")
        let destAppURL = GameScanner.builtAppURL(for: appName, gamesRootURL: gamesRoot, flatOutputLayout: flatLayout)
        let pairs: [(String, URL, URL)] = (sourceAppURL.standardizedFileURL != destAppURL.standardizedFileURL && FileManager.default.fileExists(atPath: sourceAppURL.path))
            ? [(appName, sourceAppURL, destAppURL)]
            : []

        guard !pairs.isEmpty else { return }

        let messages: [String] = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var logs: [String] = []
            for (appName, sourceURL, destURL) in pairs {
                do {
                    let destDir = destURL.deletingLastPathComponent()
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.copyItem(at: sourceURL, to: destURL)
                    try fm.removeItem(at: sourceURL)
                    logs.append("Deployed \(appName).app → \(destURL.path)\n")
                } catch {
                    logs.append("Failed to deploy \(appName).app: \(error.localizedDescription)\n")
                }
            }
            return logs
        }.value

        for msg in messages {
            appendLog(msg, for: game.id)
        }
    }

    private func startQueueLoop() {
        guard !isBuilding, queueItems.contains(where: { $0.status == .queued }) else { return }

        stopRequested = false
        cancelCurrentRequested = false
        isBuilding = true
        completedCount = 0
        totalCount = queueItems.count
        let batchStart = Date()
        queueStartDate = batchStart
        buildActivity = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled,
            reason: "Building NXNative games"
        )

        Task {
            var succeededCount = 0
            var failedCount = 0
            var processedIDs: [String] = []

            while let nextQueueIdx = queueItems.firstIndex(where: { $0.status == .queued }) {
                if stopRequested {
                    markRemainingStopped()
                    break
                }

                let id = queueItems[nextQueueIdx].id
                processedIDs.append(id)
                guard let idx = games.firstIndex(where: { $0.id == id }) else {
                    queueItems.remove(at: nextQueueIdx)
                    totalCount = queueItems.count
                    continue
                }

                cancelCurrentRequested = false
                if followActiveBuild {
                    inspectedLogGameID = id
                }
                currentBuildName = games[idx].name
                currentStepProgress = 0
                currentStepLabel = ""
                lineBuffer = ""
                let gameStart = Date()
                currentBuildStartDate = gameStart
                games[idx].status = .building

                queueItems[nextQueueIdx].status = .building
                queueItems[nextQueueIdx].progress = 0
                queueItems[nextQueueIdx].stepLabel = ""
                queueItems[nextQueueIdx].startDate = gameStart
                queueItems[nextQueueIdx].duration = nil

                let header = "=== Building \(games[idx].name) ===\n"
                appendLog(header, for: id)

                let exitCode = await runBuild(for: games[idx])
                let elapsed = Date().timeIntervalSince(gameStart)
                games[idx].lastBuildDuration = elapsed
                let durationStr = formatDuration(elapsed)

                if let finishedQueueIdx = queueItems.firstIndex(where: { $0.id == id }) {
                    queueItems[finishedQueueIdx].duration = elapsed
                    if stopRequested {
                        queueItems[finishedQueueIdx].status = .cancelled
                        games[idx].status = .cancelled
                        appendLog("\n=== Cancelled \(games[idx].name) after \(durationStr) ===\n\n", for: id)
                    } else if cancelCurrentRequested {
                        cancelCurrentRequested = false
                        queueItems[finishedQueueIdx].status = .cancelled
                        games[idx].status = .cancelled
                        appendLog("\n=== Cancelled \(games[idx].name) after \(durationStr) ===\n\n", for: id)
                    } else if exitCode == 0 {
                        succeededCount += 1
                        queueItems[finishedQueueIdx].status = .succeeded
                        queueItems[finishedQueueIdx].progress = 1.0
                        games[idx].status = .succeeded
                        appendLog("\n=== Finished \(games[idx].name) (exit 0) in \(durationStr) ===\n\n", for: id)
                        await deployBuiltApps(for: games[idx])
                    } else {
                        failedCount += 1
                        queueItems[finishedQueueIdx].status = .failed(exitCode)
                        games[idx].status = .failed(exitCode)
                        appendLog("\n=== Failed \(games[idx].name) (exit \(exitCode)) in \(durationStr) ===\n\n", for: id)
                    }
                }

                await refreshBuildInfo(for: id)
                completedCount += 1
            }

            if stopRequested {
                markRemainingStopped()
            }

            let totalElapsed = Date().timeIntervalSince(batchStart)
            let wasStopped = stopRequested
            if let activity = buildActivity {
                ProcessInfo.processInfo.endActivity(activity)
                buildActivity = nil
            }
            isBuilding = false
            currentBuildName = ""
            currentBuildStartDate = nil
            queueStartDate = nil
            currentStepProgress = 0
            currentStepLabel = ""
            lineBuffer = ""
            activeProcess = nil

            if !wasStopped {
                sendCompletionNotification(
                    succeeded: succeededCount,
                    failed: failedCount,
                    totalDuration: formatDuration(totalElapsed),
                    singleGameName: processedIDs.count == 1 ? games.first(where: { $0.id == processedIDs[0] })?.name : nil
                )
            }
        }
    }

    private func sendCompletionNotification(succeeded: Int, failed: Int, totalDuration: String, singleGameName: String?) {
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        if let name = singleGameName {
            content.title = failed == 0 ? "Build Succeeded: \(name)" : "Build Failed: \(name)"
            content.body = "Completed in \(totalDuration)."
        } else {
            content.title = failed == 0 ? "All Builds Succeeded" : "Builds Finished with Errors"
            if failed == 0 {
                content.body = "Built \(succeeded) game\(succeeded == 1 ? "" : "s") in \(totalDuration)."
            } else {
                content.body = "\(succeeded) succeeded, \(failed) failed in \(totalDuration)."
            }
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func markRemainingStopped() {
        for i in queueItems.indices where queueItems[i].status == .queued {
            queueItems[i].status = .cancelled
        }
        for i in games.indices where games[i].status == .queued {
            games[i].status = .cancelled
        }
    }

    func stripANSI(_ text: String) -> String {
        guard let regex = Self.ansiRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    func stripNonSGRANSI(_ text: String) -> String {
        guard let regex = Self.nonSGRANSIRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func appendBounded(_ chunk: String, to log: inout String) {
        log.append(chunk)
        if log.count > Self.maxLogCharacters {
            let overflow = log.count - Self.maxLogCharacters
            let trimStart = log.index(log.startIndex, offsetBy: overflow)
            if let newlineIdx = log[trimStart...].firstIndex(of: "\n") {
                log.removeSubrange(log.startIndex...newlineIdx)
            } else {
                log.removeSubrange(log.startIndex..<trimStart)
            }
        }
    }

    private func appendLog(_ text: String, for id: String) {
        let logText = stripNonSGRANSI(text)
        appendBounded(logText, to: &globalLog)
        if let idx = games.firstIndex(where: { $0.id == id }) {
            appendBounded(logText, to: &games[idx].log)
        }
        logRevision &+= 1
        parseProgress(from: stripANSI(text))
    }

    func parseProgress(from chunk: String) {
        lineBuffer.append(chunk)
        let lines = lineBuffer.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }
        lineBuffer = lines.last ?? ""

        for rawLine in lines.dropLast() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let regex = Self.stepRegex else { continue }
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: nsRange),
                  let stepRange = Range(match.range(at: 2), in: line),
                  let totalRange = Range(match.range(at: 3), in: line),
                  let descRange = Range(match.range(at: 4), in: line),
                  let step = Int(line[stepRange]),
                  let total = Int(line[totalRange]),
                  total > 0 else {
                continue
            }

            let isDone = match.range(at: 1).location != NSNotFound
            var subProgress = 0.0
            if isDone {
                subProgress = 1.0
            } else if let pctRegex = Self.percentRegex,
                      let pctMatch = pctRegex.firstMatch(in: line, range: nsRange),
                      let pctRange = Range(pctMatch.range(at: 1), in: line),
                      let pct = Double(line[pctRange]) {
                subProgress = min(max(pct / 100.0, 0.0), 1.0)
            }

            let progress = min(max((Double(step - 1) + subProgress) / Double(total), 0.0), 1.0)
            currentStepProgress = progress

            let rawDesc = String(line[descRange])
            let shortDesc = rawDesc
                .components(separatedBy: ":")
                .first?
                .trimmingCharacters(in: CharacterSet(charactersIn: " …")) ?? rawDesc
            let stepText = "[\(step)/\(total)] \(shortDesc)"
            currentStepLabel = stepText

            if let activeIdx = queueItems.firstIndex(where: { $0.status == .building }) {
                queueItems[activeIdx].progress = progress
                queueItems[activeIdx].stepLabel = stepText
            }
        }
    }

    private func refreshXcrunCache() async {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["-k", "-sdk", "macosx", "--find", "metal"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                Self.logger.warning("Failed to refresh xcrun cache: \(error.localizedDescription)")
            }
        }.value
    }

    private func runBuild(for game: GameEntry) async -> Int32 {
        await refreshXcrunCache()
        let gameID = game.id
        let executableURL: URL
        let arguments: [String]
        let workingDirectory: URL
        var extraEnv: [String: String] = [:]

        let repoURL = nxnativeRepoURL
        let venvDir = repoURL.appendingPathComponent(".venv")
        let venvPython = venvDir.appendingPathComponent("bin/python3")

        var args: [String] = []
        if FileManager.default.fileExists(atPath: venvPython.path) {
            executableURL = venvPython
            extraEnv["VIRTUAL_ENV"] = venvDir.path
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            args.append("python3")
        }

        args.append("scripts/build_ipa_from_nsp.py")
        args.append(game.folderURL.path)

        if !effectiveIsSwitch2(for: game) {
            let keys = prodKeysPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keys.isEmpty {
                args.append("-k")
                args.append(keys)
            }
        }

        args.append("--platform")
        args.append("mac-app")
        args.append("--app-name")
        args.append(effectiveAppName(for: game))

        if let iconURL = game.iconURL {
            let buildIconURL = GameScanner.prepareBuildIcon(from: iconURL) ?? iconURL
            args.append("--icon")
            args.append(buildIconURL.path)
        }
        if let titleID = effectiveTitleID(for: game) {
            args.append("--title-id")
            args.append(titleID)
        }

        arguments = args
        workingDirectory = repoURL
        let cmdPreview = ([executableURL.lastPathComponent] + arguments).joined(separator: " ")
        appendLog("Running: \(cmdPreview)\n", for: gameID)

        let (logStream, logContinuation) = AsyncStream.makeStream(of: String.self)
        let logTask = Task { @MainActor [weak self] in
            for await chunk in logStream {
                self?.appendLog(chunk, for: gameID)
            }
        }

        let exitCode = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            var env = ProcessInfo.processInfo.environment
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            let trimmedExtra = extraPath.trimmingCharacters(in: .whitespacesAndNewlines)
            env["PATH"] = trimmedExtra.isEmpty ? currentPath : "\(trimmedExtra):\(currentPath)"
            env["PYTHONUNBUFFERED"] = "1"
            for (k, v) in extraEnv {
                env[k] = v
            }
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                logContinuation.yield(chunk)
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                let remaining = handle.readDataToEndOfFile()
                if !remaining.isEmpty, let tail = String(data: remaining, encoding: .utf8) {
                    logContinuation.yield(tail)
                }
                logContinuation.finish()
                continuation.resume(returning: proc.terminationStatus)
            }

            self.activeProcess = process
            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                logContinuation.yield("Failed to launch process: \(error.localizedDescription)\n")
                logContinuation.finish()
                continuation.resume(returning: -1)
            }
        }

        await logTask.value
        return exitCode
    }
}
