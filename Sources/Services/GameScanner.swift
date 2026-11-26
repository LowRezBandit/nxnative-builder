import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GameScanner {
    private static let titleIDRegex = try? NSRegularExpression(pattern: #"(?:0100|0400)[0-9A-Fa-f]{12}"#)
    private static let buildVersionRegexes: [NSRegularExpression] = [
        #"[\[\(]v(\d+)[\]\)]"#,
        #"(?:^|[\s_\-])v(\d{4,})(?=$|[\s_\-\.])"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    private static let semverRegexes: [NSRegularExpression] = [
        #"[\[\(](?:Up(?:date)?\s+)?v?(\d+(?:\.\d+)+)[\]\)]"#,
        #"\bUpdate\s+v?(\d+(?:\.\d+)+)\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    private static let stripNameRegexes: [NSRegularExpression] = [
        #"\[[^\]]*\]"#,
        #"\([^)]*\)"#,
        #"(?:^|[\s_\-])v\d{4,}(?=$|[\s_\-\.])"#,
        #"\+\s*update(?:\s+v?\d+(?:\.\d+)+)?"#,
        #"\+\s*dlc\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    private static let bracketRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]"#)
    private static let dlcMetadataRegex = try? NSRegularExpression(
        pattern: #"^(?:0100[0-9A-Fa-f]{12}|v\d+|up(?:date)?\s+v?\d+(?:\.\d+)*|us|usa|eur|eu|jpn|jp|nsp|xci|nsz|nup|dlc|aoc|base|upd|patch)$"#,
        options: [.caseInsensitive]
    )
    private static let dottedVersionRegex = try? NSRegularExpression(
        pattern: #"(?<![0-9.])v?(\d+(?:\.\d+)+)\b"#,
        options: [.caseInsensitive]
    )

    struct ExistingGameState {
        let isSelected: Bool
        let status: BuildStatus
        let lastBuildDuration: TimeInterval?
        let log: String
    }

    static func scanGames(
        sourcesURL: URL,
        gamesRootURL: URL,
        flatOutputLayout: Bool = false,
        metadataCache: [String: CachedPackageMetadata],
        appNameOverrides: [String: String] = [:],
        previousByID: [String: ExistingGameState],
        savedChecked: Set<String>,
        useSavedChecked: Bool
    ) -> [GameEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: sourcesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var loaded: [GameEntry] = []

        for url in contents.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let sourcePackages = parseSourcePackages(in: url, metadataCache: metadataCache)
            guard !sourcePackages.isEmpty else { continue }

            let entries = expandFolderEntries(
                folderURL: url,
                sourcePackages: sourcePackages,
                metadataCache: metadataCache,
                gamesRootURL: gamesRootURL,
                flatOutputLayout: flatOutputLayout,
                appNameOverrides: appNameOverrides,
                previousByID: previousByID,
                savedChecked: savedChecked,
                useSavedChecked: useSavedChecked
            )
            loaded.append(contentsOf: entries)
        }

        return loaded
    }

    static func expandFolderEntries(
        folderURL: URL,
        sourcePackages: [SourcePackageInfo],
        metadataCache: [String: CachedPackageMetadata],
        gamesRootURL: URL,
        flatOutputLayout: Bool = false,
        appNameOverrides: [String: String] = [:],
        previousByID: [String: ExistingGameState] = [:],
        savedChecked: Set<String> = [],
        useSavedChecked: Bool = false
    ) -> [GameEntry] {
        let folderName = folderURL.lastPathComponent
        let applicationTitleIDs = uniqueApplicationTitleIDs(
            in: folderURL,
            sourcePackages: sourcePackages,
            metadataCache: metadataCache
        )
        let workFolders = buildWorkFolders(in: folderURL)

        if applicationTitleIDs.count > 1 {
            return applicationTitleIDs.map { titleID in
                let gameID = "\(folderName)::\(titleID)"
                let filteredPackages = filterPackages(
                    sourcePackages,
                    forApplicationTitleID: titleID,
                    folderURL: folderURL,
                    metadataCache: metadataCache
                )
                let customAppName = appNameOverrides[gameID]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let appName = (customAppName?.isEmpty == false ? customAppName : nil) ?? folderName
                let buildInfo = readBuildInfo(for: [appName], gamesRootURL: gamesRootURL, flatOutputLayout: flatOutputLayout)
                let builtAppURLs = builtAppURLs(forAppNames: [appName], gamesRootURL: gamesRootURL, flatOutputLayout: flatOutputLayout)
                let availableUpdate = availableUpdateVersion(for: buildInfo, sourcePackages: filteredPackages, folderURL: folderURL)
                let iconInfo = findIcon(in: folderURL, titleID: titleID)
                let hasSwitch2 = hasSwitch2Source(packages: filteredPackages, detectedTitleID: titleID)

                let existing = previousByID[gameID]
                let isChecked = useSavedChecked ? savedChecked.contains(gameID) : (existing?.isSelected ?? false)

                return GameEntry(
                    id: gameID,
                    name: folderName,
                    folderURL: folderURL,
                    iconImage: iconInfo?.image,
                    iconURL: iconInfo?.url,
                    sourcePackages: filteredPackages,
                    detectedTitleID: titleID,
                    hasSwitch2Source: hasSwitch2,
                    isSelected: isChecked,
                    status: existing?.status ?? .idle,
                    buildInfo: buildInfo,
                    builtAppURLs: builtAppURLs,
                    workFolders: workFolders,
                    availableUpdateVersion: availableUpdate,
                    lastBuildDuration: existing?.lastBuildDuration,
                    log: existing?.log ?? ""
                )
            }
        } else {
            let detectedTitleID = applicationTitleIDs.first ?? detectBaseTitleID(from: sourcePackages)
            let customAppName = appNameOverrides[folderName]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let appName = (customAppName?.isEmpty == false ? customAppName : nil) ?? folderName
            let buildInfo = readBuildInfo(for: [appName], gamesRootURL: gamesRootURL, flatOutputLayout: flatOutputLayout)
            let builtAppURLs = builtAppURLs(forAppNames: [appName], gamesRootURL: gamesRootURL, flatOutputLayout: flatOutputLayout)
            let availableUpdate = availableUpdateVersion(for: buildInfo, sourcePackages: sourcePackages, folderURL: folderURL)
            let iconInfo = findIcon(in: folderURL, titleID: detectedTitleID)
            let hasSwitch2 = hasSwitch2Source(packages: sourcePackages, detectedTitleID: detectedTitleID)

            let existing = previousByID[folderName]
            let isChecked = useSavedChecked ? savedChecked.contains(folderName) : (existing?.isSelected ?? false)

            return [GameEntry(
                id: folderName,
                name: folderName,
                folderURL: folderURL,
                iconImage: iconInfo?.image,
                iconURL: iconInfo?.url,
                sourcePackages: sourcePackages,
                detectedTitleID: detectedTitleID,
                hasSwitch2Source: hasSwitch2,
                isSelected: isChecked,
                status: existing?.status ?? .idle,
                buildInfo: buildInfo,
                builtAppURLs: builtAppURLs,
                workFolders: workFolders,
                availableUpdateVersion: availableUpdate,
                lastBuildDuration: existing?.lastBuildDuration,
                log: existing?.log ?? ""
            )]
        }
    }

    static func uniqueApplicationTitleIDs(
        in folderURL: URL,
        sourcePackages: [SourcePackageInfo],
        metadataCache: [String: CachedPackageMetadata]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for pkg in sourcePackages {
            let fileURL = folderURL.appendingPathComponent(pkg.rawFilename)
            if let cached = metadataCache[fileURL.path] {
                for rec in cached.contents where rec.kind == "Application" {
                    let tid = rec.titleID.uppercased()
                    if seen.insert(tid).inserted {
                        result.append(tid)
                    }
                }
            } else if pkg.kinds.contains(.base), let tid = pkg.titleID?.uppercased() {
                if seen.insert(tid).inserted {
                    result.append(tid)
                }
            }
        }
        return result
    }

    static func filterPackages(
        _ packages: [SourcePackageInfo],
        forApplicationTitleID appTitleID: String,
        folderURL: URL,
        metadataCache: [String: CachedPackageMetadata]
    ) -> [SourcePackageInfo] {
        let targetPrefix = baseTitleIDPrefix(appTitleID)
        guard targetPrefix.count == 13 else { return packages }

        return packages.filter { pkg in
            let fileURL = folderURL.appendingPathComponent(pkg.rawFilename)
            if let cached = metadataCache[fileURL.path], !cached.contents.isEmpty {
                return cached.contents.contains { baseTitleIDPrefix($0.titleID) == targetPrefix }
            }
            if let tid = pkg.titleID {
                return baseTitleIDPrefix(tid) == targetPrefix
            }
            return true
        }
    }

    static func fileSignature(for url: URL) -> (size: Int64, modTime: TimeInterval)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return (size, modDate.timeIntervalSince1970)
    }

    static func cachedContents(for url: URL, metadataCache: [String: CachedPackageMetadata]) -> [PackageContentRecord]? {
        guard let sig = fileSignature(for: url),
              let cached = metadataCache[url.path],
              cached.fileSize == sig.size,
              abs(cached.modTime - sig.modTime) < 1.0 else {
            return nil
        }
        return cached.contents
    }

    static func runNXExtractContents(
        files: [URL],
        nxExtractURL: URL,
        prodKeysURL: URL
    ) -> [String: [PackageContentRecord]] {
        let process = Process()
        process.executableURL = nxExtractURL
        process.arguments = [prodKeysURL.path, "--contents"] + files.map { $0.path }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var map: [String: [PackageContentRecord]] = [:]
        var currentFilename: String?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("package ") {
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                if parts.count == 3 {
                    currentFilename = URL(fileURLWithPath: String(parts[2])).lastPathComponent
                }
            } else if line.hasPrefix("content "), let filename = currentFilename {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 4, let ver = UInt32(parts[3]) {
                    let rec = PackageContentRecord(
                        kind: String(parts[1]),
                        titleID: String(parts[2]).uppercased(),
                        version: ver
                    )
                    map[filename, default: []].append(rec)
                }
            }
        }
        return map
    }

    static func detectBaseTitleID(from packages: [SourcePackageInfo]) -> String? {
        for pkg in packages {
            if let tid = pkg.titleID, tid.hasSuffix("000") {
                return tid
            }
        }

        guard let regex = titleIDRegex else { return nil }
        for pkg in packages {
            let name = pkg.rawFilename
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            if let match = regex.firstMatch(in: name, range: range),
               let r = Range(match.range, in: name) {
                let tid = String(name[r]).uppercased()
                if tid.hasSuffix("000") {
                    return tid
                }
            }
        }
        return nil
    }

    static func parseSourcePackages(
        in folderURL: URL,
        metadataCache: [String: CachedPackageMetadata]
    ) -> [SourcePackageInfo] {
        var found: [(filename: String, explicitKind: SourcePackageKind?)] = []
        var seen = Set<String>()

        if let items = try? FileManager.default.contentsOfDirectory(
               at: folderURL,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            let exts: Set<String> = ["nsp", "xci", "nsz", "nup"]
            for item in items where exts.contains(item.pathExtension.lowercased()) {
                let filename = item.lastPathComponent
                if seen.insert(filename).inserted {
                    found.append((filename, nil))
                }
            }
        }

        let packages = found.map { item -> SourcePackageInfo in
            let fileURL = folderURL.appendingPathComponent(item.filename)
            let ext = fileURL.pathExtension.lowercased()

            var headerRecords: [PackageContentRecord]?
            var pfs0TitleID: String?

            if ext == "nup" {
                headerRecords = PackageHeaderReader.readNupContents(at: fileURL)
            } else {
                headerRecords = cachedContents(for: fileURL, metadataCache: metadataCache)
                if headerRecords == nil && (ext == "nsp" || ext == "nsz") {
                    pfs0TitleID = PackageHeaderReader.readPFS0TitleID(at: fileURL)
                }
            }

            let kinds: [SourcePackageKind]
            let headerTitleID: String?
            var headerVersionNum: UInt32?

            if let records = headerRecords, !records.isEmpty {
                var kindSet = Set<SourcePackageKind>()
                for rec in records {
                    switch rec.kind {
                    case "Application": kindSet.insert(.base)
                    case "Patch": kindSet.insert(.update)
                    case "AddOnContent": kindSet.insert(.dlc)
                    default: break
                    }
                }
                kinds = kindSet.isEmpty ? [.base] : kindSet.sorted()
                headerTitleID = records.first(where: { $0.kind == "Application" })?.titleID ?? records.first?.titleID
                headerVersionNum = records.first(where: { $0.kind == "Patch" && $0.version > 0 })?.version
                    ?? records.first(where: { $0.version > 0 })?.version
            } else if let pfs0TitleID {
                headerTitleID = pfs0TitleID
                if pfs0TitleID.hasSuffix("000") {
                    kinds = [.base]
                } else if pfs0TitleID.hasSuffix("800") {
                    kinds = [.update]
                } else {
                    kinds = [.dlc]
                }
            } else {
                headerTitleID = nil
                kinds = classifyPackageKinds(
                    filename: item.filename,
                    explicitKind: item.explicitKind,
                    totalCount: found.count
                )
            }

            let version = extractPackageVersion(
                from: item.filename,
                kinds: kinds,
                headerVersion: headerVersionNum
            )
            let cleaned = cleanPackageName(item.filename, kinds: kinds)
            return SourcePackageInfo(
                id: item.filename,
                kinds: kinds,
                displayName: cleaned,
                version: version,
                rawFilename: item.filename,
                titleID: headerTitleID
            )
        }

        return packages.sorted {
            let lhsKind = $0.kinds.first ?? .other
            let rhsKind = $1.kinds.first ?? .other
            if lhsKind != rhsKind { return lhsKind < rhsKind }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func classifyPackageKinds(filename: String, explicitKind: SourcePackageKind?, totalCount: Int) -> [SourcePackageKind] {
        let lower = filename.lowercased()
        let hasPlusUpdate = lower.range(of: #"\+\s*update\b"#, options: .regularExpression) != nil
        let hasPlusDLC = lower.range(of: #"\+\s*dlc\b"#, options: .regularExpression) != nil

        if hasPlusUpdate || hasPlusDLC {
            var kinds: [SourcePackageKind] = [.base]
            if hasPlusUpdate { kinds.append(.update) }
            if hasPlusDLC { kinds.append(.dlc) }
            return kinds
        }

        if let explicitKind {
            return [explicitKind]
        }

        if let regex = titleIDRegex,
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..<filename.endIndex, in: filename)),
           let range = Range(match.range, in: filename) {
            let titleID = filename[range].uppercased()
            if titleID.hasSuffix("000") { return [.base] }
            if titleID.hasSuffix("800") { return [.update] }
            return [.dlc]
        }

        if lower.contains("[up ") || lower.contains("update") || lower.contains("upd") || lower.contains("patch") {
            return [.update]
        }
        if lower.contains("dlc") || lower.contains("addon") || lower.contains("add-on") || lower.contains("expansion") {
            return [.dlc]
        }
        if totalCount == 1 {
            return [.base]
        }
        if lower.range(of: #"(?:^|[\s_\-\[\(])v\d{4,}(?:$|[\s_\-\]\)\.])"#, options: .regularExpression) != nil {
            return [.update]
        }
        return [.base]
    }

    static func extractPackageVersion(
        from filename: String,
        kinds: [SourcePackageKind],
        headerVersion: UInt32? = nil
    ) -> String? {
        let nsRange = NSRange(filename.startIndex..<filename.endIndex, in: filename)

        for regex in semverRegexes {
            if let match = regex.firstMatch(in: filename, range: nsRange),
               let range = Range(match.range(at: 1), in: filename) {
                return "v\(filename[range])"
            }
        }

        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        if let dotted = extractDottedVersion(from: stem) {
            return "v\(dotted)"
        }

        if let headerVersion, headerVersion > 0 {
            return "v\(headerVersion)"
        }

        for regex in buildVersionRegexes {
            if let match = regex.firstMatch(in: filename, range: nsRange),
               let range = Range(match.range(at: 1), in: filename) {
                let num = String(filename[range])
                if !(kinds == [.base] && num == "0") {
                    return "v\(num)"
                }
                break
            }
        }

        return nil
    }

    static func cleanPackageName(_ filename: String, kinds: [SourcePackageKind]) -> String {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent

        if kinds == [.dlc] {
            if let descriptor = extractDLCDescriptor(from: stem) {
                return descriptor
            }
            if stem.contains("_") && !stem.contains(" ") {
                let cleanedDLC = stem
                    .replacingOccurrences(of: #"^v-"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: #"(?:\s+(?:aoc|dlc))+$"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
                if !cleanedDLC.isEmpty {
                    return cleanedDLC
                }
            }
            return stem
        }

        var cleaned = stem
        if cleaned.contains("_") && !cleaned.contains(" ") {
            cleaned = cleaned.replacingOccurrences(of: #"^[a-z]{1,4}-"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        for regex in stripNameRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        if cleaned.contains("_") && !cleaned.contains(" ") {
            cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_+"))
        return cleaned.isEmpty ? stem : cleaned
    }

    static func extractDLCDescriptor(from stem: String) -> String? {
        guard let regex = bracketRegex else {
            return nil
        }
        let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)

        for match in regex.matches(in: stem, range: range) {
            guard let innerRange = Range(match.range(at: 1), in: stem) else { continue }
            let raw = String(stem[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            let rawNSRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            if let dlcMetadataRegex, dlcMetadataRegex.firstMatch(in: raw, range: rawNSRange) != nil {
                continue
            }

            let cleaned = raw
                .replacingOccurrences(of: #"(?:\s+(?:aoc|dlc))+$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -_"))

            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    static func builtAppURL(for appName: String, gamesRootURL: URL, flatOutputLayout: Bool) -> URL {
        if flatOutputLayout {
            return gamesRootURL.appendingPathComponent("\(appName).app")
        }
        return gamesRootURL
            .appendingPathComponent(appName)
            .appendingPathComponent("\(appName).app")
    }

    static func readBuildInfo(for appNames: [String], gamesRootURL: URL, flatOutputLayout: Bool = false) -> [BuildArtifactInfo] {
        let fm = FileManager.default
        var results: [BuildArtifactInfo] = []

        for appName in appNames {
            let appURL = builtAppURL(for: appName, gamesRootURL: gamesRootURL, flatOutputLayout: flatOutputLayout)
            let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
            guard fm.fileExists(atPath: plistURL.path),
                  let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                continue
            }

            let version = (plist["CFBundleShortVersionString"] as? String)
                ?? (plist["CFBundleVersion"] as? String)
                ?? "?"
            let chain = plist["DMChain"] as? String
            let commitVersion = (plist["DMCommit"] as? String) ?? "latest"
            let bundleID = plist["CFBundleIdentifier"] as? String
            let minSystemVersion = plist["LSMinimumSystemVersion"] as? String
            let execName = (plist["CFBundleExecutable"] as? String) ?? "nxnative"
            let execURL = appURL.appendingPathComponent("Contents/MacOS/\(execName)")
            let dateURL = fm.fileExists(atPath: execURL.path) ? execURL : plistURL
            let attrs = try? fm.attributesOfItem(atPath: dateURL.path)
            let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            let sizeBytes = directorySize(at: appURL)

            results.append(BuildArtifactInfo(
                appName: appName,
                version: version,
                buildDate: modDate,
                commit: commitVersion,
                chain: chain,
                sizeBytes: sizeBytes,
                bundleIdentifier: bundleID,
                minimumSystemVersion: minSystemVersion
            ))
        }
        return results
    }

    static func directorySize(at url: URL) -> Int64? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total > 0 ? total : nil
    }

    static let supportedIconExtensions: [String] = ["png", "jpg", "jpeg", "webp", "heic", "icns"]
    static let preferredIconBaseNames: [String] = ["icon", "cover", "game", "game-icon", "game-cover", "1024-mac"]

    static func findIcon(in folder: URL, titleID: String? = nil) -> (image: NSImage, url: URL)? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let supportedSet = Set(supportedIconExtensions)
        let imageFiles = items
            .filter { supportedSet.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        guard !imageFiles.isEmpty else { return nil }

        let byStemAndExt: [String: URL] = Dictionary(
            imageFiles.map { url in
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                return ("\(stem).\(ext)", url)
            },
            uniquingKeysWith: { first, _ in first }
        )

        func firstMatchingImage(baseNames: [String]) -> (image: NSImage, url: URL)? {
            for base in baseNames {
                for ext in supportedIconExtensions {
                    if let url = byStemAndExt["\(base).\(ext)"], let img = NSImage(contentsOf: url) {
                        return (img, url)
                    }
                }
            }
            return nil
        }

        if let titleID {
            let tidLower = titleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !tidLower.isEmpty {
                let perTitleBases = preferredIconBaseNames.map { "\($0)-\(tidLower)" } + [tidLower]
                if let match = firstMatchingImage(baseNames: perTitleBases) {
                    return match
                }
            }
        }

        if let match = firstMatchingImage(baseNames: preferredIconBaseNames) {
            return match
        }

        for url in imageFiles {
            if let img = NSImage(contentsOf: url) {
                return (img, url)
            }
        }
        return nil
    }

    private static let normalizedIconDescription = "nxnative-1024-squircle"

    static func prepareBuildIcon(from sourceURL: URL, outputDirectory: URL? = nil) -> URL? {
        if isAlreadyNormalizedIcon(at: sourceURL) {
            return sourceURL
        }

        guard let pngData = renderNormalizedIconData(from: sourceURL) else {
            return nil
        }

        let targetDir = outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("nxnative-builder-icons", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let destURL = targetDir.appendingPathComponent("\(stem)-1024.png")
            try pngData.write(to: destURL, options: .atomic)
            return destURL
        } catch {
            return nil
        }
    }

    /// Normalizes an image into the standard 1024x1024 macOS squircle PNG and writes it to the game's folder.
    static func saveNormalizedIcon(from sourceURL: URL, in folder: URL, titleID: String?) -> URL? {
        let destFilename: String = {
            if let tid = titleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !tid.isEmpty {
                return "icon-\(tid).png"
            }
            return "icon.png"
        }()
        let destURL = folder.appendingPathComponent(destFilename)

        if sourceURL.standardizedFileURL == destURL.standardizedFileURL,
           isAlreadyNormalizedIcon(at: destURL) {
            return destURL
        }

        let pngData: Data?
        if isAlreadyNormalizedIcon(at: sourceURL) {
            pngData = try? Data(contentsOf: sourceURL)
        } else {
            pngData = renderNormalizedIconData(from: sourceURL)
        }

        guard let pngData else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try pngData.write(to: destURL, options: .atomic)
            return destURL
        } catch {
            return nil
        }
    }

    private static func isAlreadyNormalizedIcon(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "png",
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width == 1024,
              height == 1024,
              let pngDict = props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let description = pngDict[kCGImagePropertyPNGDescription] as? String else {
            return false
        }
        return description == normalizedIconDescription
    }

    private static func renderNormalizedIconData(from sourceURL: URL) -> Data? {
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let canvasSize = 1024
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

        // Standard macOS app icon grid: 824x824 rounded squircle centered on 1024x1024 canvas.
        let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let cornerRadius: CGFloat = 185.4
        let clipPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(clipPath)
        context.clip()

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let scale = max(iconRect.width / max(srcW, 1), iconRect.height / max(srcH, 1))
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawRect = CGRect(
            x: iconRect.midX - drawW / 2,
            y: iconRect.midY - drawH / 2,
            width: drawW,
            height: drawH
        )
        context.draw(cgImage, in: drawRect)

        guard let rendered = context.makeImage() else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGDescription: normalizedIconDescription
            ]
        ]
        CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    static func builtAppURLs(forAppNames appNames: [String], gamesRootURL: URL, flatOutputLayout: Bool = false) -> [URL] {
        let fm = FileManager.default
        return appNames.compactMap { appName in
            let appURL = builtAppURL(for: appName, gamesRootURL: gamesRootURL, flatOutputLayout: flatOutputLayout)
            return fm.fileExists(atPath: appURL.path) ? appURL : nil
        }
    }

    static func buildWorkFolders(in folderURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = url.lastPathComponent
            return isDir && (name.hasSuffix("_build") || name.hasSuffix("_survey"))
        }
    }

    static func availableUpdateVersion(
        for buildInfo: [BuildArtifactInfo],
        sourcePackages: [SourcePackageInfo],
        folderURL: URL
    ) -> String? {
        guard !buildInfo.isEmpty else { return nil }
        let builtVersions = buildInfo.compactMap { extractDottedVersion(from: $0.version) }
        guard let builtVer = builtVersions.min(by: { compareDottedVersions($0, $1) == .orderedAscending }) else {
            return nil
        }
        let latestBuiltDate = buildInfo.map(\.buildDate).max() ?? Date.distantPast

        let fm = FileManager.default
        let sourceUpdateVersions: [String] = sourcePackages
            .filter { $0.kinds.contains(.update) }
            .compactMap { pkg in
                guard let ver = pkg.version.flatMap({ extractDottedVersion(from: $0) }) else { return nil }
                if pkg.rawFilename.lowercased().hasSuffix(".nup") && (builtVer == "1.0" || builtVer == "1.0.0") {
                    let pkgURL = folderURL.appendingPathComponent(pkg.rawFilename)
                    let modDate = (try? fm.attributesOfItem(atPath: pkgURL.path)[.modificationDate] as? Date) ?? Date.distantPast
                    if modDate <= latestBuiltDate {
                        return nil
                    }
                }
                return ver
            }

        guard let latestSource = sourceUpdateVersions.max(by: { compareDottedVersions($0, $1) == .orderedAscending }),
              compareDottedVersions(builtVer, latestSource) == .orderedAscending else {
            return nil
        }
        return "v\(latestSource)"
    }

    static func extractDottedVersion(from text: String) -> String? {
        guard let regex = dottedVersionRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }

    static func hasSwitch2Source(packages: [SourcePackageInfo], detectedTitleID: String?) -> Bool {
        packages.contains { pkg in
            let lower = pkg.rawFilename.lowercased()
            return lower.hasSuffix(".nup")
                || lower.range(of: #"0400[0-9a-f]{12}"#, options: .regularExpression) != nil
                || (pkg.titleID?.hasPrefix("0400") == true)
        } || (detectedTitleID?.hasPrefix("0400") == true)
    }

    static func compareDottedVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }
}
