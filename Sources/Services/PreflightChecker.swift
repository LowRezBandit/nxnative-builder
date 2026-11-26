import Foundation

enum PreflightChecker {
    struct Configuration: Sendable {
        let sourcesPath: String
        let nxnativeRepoPath: String
        let prodKeysPath: String
        let extraPath: String
    }

    struct PullResult: Sendable {
        let succeeded: Bool
        let message: String
    }

    /// Runs environment health checks for required paths, Python, CLI tools, and optional Switch 1 assets.
    static func runChecks(config: Configuration) -> [PreflightCheckItem] {
        let fm = FileManager.default
        let effectivePath = buildEffectivePATH(extraPath: config.extraPath)

        let repoTrimmed = config.nxnativeRepoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let repoURL = URL(fileURLWithPath: repoTrimmed)
        let scriptURL = repoURL.appendingPathComponent("scripts/build_ipa_from_nsp.py")
        var isRepoDir: ObjCBool = false
        let repoExists = !repoTrimmed.isEmpty
            && fm.fileExists(atPath: repoURL.path, isDirectory: &isRepoDir)
            && isRepoDir.boolValue
        let scriptExists = repoExists && fm.fileExists(atPath: scriptURL.path)

        let repoCheck = PreflightCheckItem(
            id: "nxnative-repo",
            title: "NXNative Repository",
            status: scriptExists ? .passed : .failed,
            detail: scriptExists
                ? "Found scripts/build_ipa_from_nsp.py"
                : (repoExists ? "Missing scripts/build_ipa_from_nsp.py in \(repoURL.path)" : "Folder not found: \(repoTrimmed)"),
            isRequired: true
        )

        let sourcesTrimmed = config.sourcesPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var isSourcesDir: ObjCBool = false
        let sourcesExists = !sourcesTrimmed.isEmpty
            && fm.fileExists(atPath: sourcesTrimmed, isDirectory: &isSourcesDir)
            && isSourcesDir.boolValue
        let sourcesCheck = PreflightCheckItem(
            id: "sources-folder",
            title: "Game Sources Folder",
            status: sourcesExists ? .passed : .failed,
            detail: sourcesExists ? sourcesTrimmed : "Folder not found: \(sourcesTrimmed)",
            isRequired: true
        )

        let venvPython = repoURL.appendingPathComponent(".venv/bin/python3")
        let pythonDetail: String? = {
            if repoExists && fm.isExecutableFile(atPath: venvPython.path) {
                return "Using repo .venv (\(venvPython.path))"
            }
            if let resolved = resolveExecutable("python3", searchPath: effectivePath) {
                return "Using system python3 (\(resolved))"
            }
            return nil
        }()
        let pythonCheck = PreflightCheckItem(
            id: "python",
            title: "Python 3",
            status: pythonDetail != nil ? .passed : .failed,
            detail: pythonDetail ?? "Neither .venv/bin/python3 nor python3 on PATH was found",
            isRequired: true
        )

        let xcodebuildPath = resolveExecutable("xcodebuild", searchPath: effectivePath)
        let gitPath = resolveExecutable("git", searchPath: effectivePath)
        let toolsMissing = [
            xcodebuildPath == nil ? "xcodebuild" : nil,
            gitPath == nil ? "git" : nil
        ].compactMap { $0 }
        let toolsCheck = PreflightCheckItem(
            id: "cli-tools",
            title: "Xcode & Git CLI Tools",
            status: toolsMissing.isEmpty ? .passed : .failed,
            detail: toolsMissing.isEmpty
                ? "xcodebuild & git available"
                : "Missing on PATH: \(toolsMissing.joined(separator: ", "))",
            isRequired: true
        )

        let keysTrimmed = config.prodKeysPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var isKeysDir: ObjCBool = false
        let keysExists = !keysTrimmed.isEmpty
            && fm.fileExists(atPath: keysTrimmed, isDirectory: &isKeysDir)
            && !isKeysDir.boolValue
        let keysCheck = PreflightCheckItem(
            id: "prod-keys",
            title: "Switch 1 Keys (prod.keys)",
            status: keysExists ? .passed : .warning,
            detail: keysExists
                ? keysTrimmed
                : "Not found (required for Switch 1 builds; Switch 2 builds work without it)",
            isRequired: false
        )

        let nxExtractURL = repoURL.appendingPathComponent("dm/tools/nx_extract_bin/nx_extract")
        let nxExtractExists = repoExists && fm.fileExists(atPath: nxExtractURL.path)
        let nxExtractCheck = PreflightCheckItem(
            id: "nx-extract",
            title: "nx_extract Metadata Tool",
            status: nxExtractExists ? .passed : .warning,
            detail: nxExtractExists
                ? "Found at dm/tools/nx_extract_bin/nx_extract"
                : "Not found (optional; used for deep package metadata scanning)",
            isRequired: false
        )

        return [repoCheck, sourcesCheck, pythonCheck, toolsCheck, keysCheck, nxExtractCheck]
    }

    static func needsOnboarding(sourcesPath: String, nxnativeRepoPath: String) -> Bool {
        let fm = FileManager.default
        let sourcesTrimmed = sourcesPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var isSourcesDir: ObjCBool = false
        let sourcesOK = !sourcesTrimmed.isEmpty
            && fm.fileExists(atPath: sourcesTrimmed, isDirectory: &isSourcesDir)
            && isSourcesDir.boolValue

        let repoTrimmed = nxnativeRepoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let scriptURL = URL(fileURLWithPath: repoTrimmed).appendingPathComponent("scripts/build_ipa_from_nsp.py")
        let repoOK = !repoTrimmed.isEmpty && fm.fileExists(atPath: scriptURL.path)

        return !(sourcesOK && repoOK)
    }

    static func readRepoStatus(at repoURL: URL, extraPath: String) -> NXNativeRepoStatus? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: repoURL.appendingPathComponent(".git").path),
              let gitPath = resolveExecutable("git", searchPath: buildEffectivePATH(extraPath: extraPath)) else {
            return nil
        }

        let branchResult = runGit(["rev-parse", "--abbrev-ref", "HEAD"], gitPath: gitPath, in: repoURL)
        let hashResult = runGit(["rev-parse", "--short", "HEAD"], gitPath: gitPath, in: repoURL)
        guard branchResult.exitCode == 0, hashResult.exitCode == 0 else { return nil }

        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, !hash.isEmpty else { return nil }
        return NXNativeRepoStatus(branch: branch, commitHash: hash)
    }

    static func pullUpdates(at repoURL: URL, extraPath: String) -> PullResult {
        guard let gitPath = resolveExecutable("git", searchPath: buildEffectivePATH(extraPath: extraPath)) else {
            return PullResult(succeeded: false, message: "git executable not found on PATH.")
        }
        let result = runGit(["pull", "--ff-only"], gitPath: gitPath, in: repoURL)
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 {
            return PullResult(succeeded: true, message: trimmed.isEmpty ? "Repository is up to date." : trimmed)
        }
        return PullResult(succeeded: false, message: trimmed.isEmpty ? "git pull failed (exit \(result.exitCode))." : trimmed)
    }

    static func buildEffectivePATH(extraPath: String) -> String {
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let extra = extraPath
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let envPath = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        var seen = Set<String>()
        var combined: [String] = []
        for entry in extra + defaults + envPath where seen.insert(entry).inserted {
            combined.append(entry)
        }
        return combined.joined(separator: ":")
    }

    static func resolveExecutable(_ name: String, searchPath: String) -> String? {
        let fm = FileManager.default
        for dir in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func runGit(_ arguments: [String], gitPath: String, in directory: URL) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
