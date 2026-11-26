import SwiftUI
import AppKit

enum BuildStatus: Equatable {
    case idle
    case queued
    case building
    case succeeded
    case failed(Int32)
    case stopped
    case cancelled

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .queued: return "Queued"
        case .building: return "Building..."
        case .succeeded: return "Complete"
        case .failed(let code): return "Failed (\(code))"
        case .stopped: return "Stopped"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .queued: return .orange
        case .building: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .stopped: return .yellow
        case .cancelled: return .secondary
        }
    }

    var isFinished: Bool {
        switch self {
        case .succeeded, .failed, .stopped, .cancelled:
            return true
        case .idle, .queued, .building:
            return false
        }
    }
}

struct BuildQueueItem: Identifiable, Equatable {
    let id: String
    let gameName: String
    var status: BuildStatus = .queued
    var progress: Double = 0
    var stepLabel: String = ""
    var duration: TimeInterval? = nil
    var startDate: Date? = nil
}

struct BuildArtifactInfo: Equatable {
    let appName: String
    let version: String
    let buildDate: Date
    let commit: String
    let chain: String?
    let sizeBytes: Int64?
    var bundleIdentifier: String? = nil
    var minimumSystemVersion: String? = nil
}

enum SourcePackageKind: Int, Comparable, Hashable {
    case base = 0
    case update = 1
    case dlc = 2
    case other = 3

    static func < (lhs: SourcePackageKind, rhs: SourcePackageKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .base: return "Base"
        case .update: return "Update"
        case .dlc: return "DLC"
        case .other: return "Source"
        }
    }

    var color: Color {
        switch self {
        case .base: return .blue
        case .update: return .green
        case .dlc: return .purple
        case .other: return .secondary
        }
    }
}

struct PackageContentRecord: Codable, Equatable {
    let kind: String
    let titleID: String
    let version: UInt32
}

struct CachedPackageMetadata: Codable, Equatable {
    let fileSize: Int64
    let modTime: TimeInterval
    let contents: [PackageContentRecord]
}

struct SourcePackageInfo: Identifiable, Equatable {
    let id: String
    let kinds: [SourcePackageKind]
    let displayName: String
    let version: String?
    let rawFilename: String
    let titleID: String?
}

func baseTitleIDPrefix(_ titleID: String) -> String {
    let trimmed = titleID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return String(trimmed.prefix(13))
}

struct GameEntry: Identifiable {
    let id: String
    let name: String
    let folderURL: URL
    var iconImage: NSImage?
    var iconURL: URL?
    var sourcePackages: [SourcePackageInfo]
    var detectedTitleID: String?
    var hasSwitch2Source: Bool
    var isSelected: Bool = false
    var status: BuildStatus = .idle
    var buildInfo: [BuildArtifactInfo] = []
    var builtAppURLs: [URL] = []
    var workFolders: [URL] = []
    var availableUpdateVersion: String? = nil
    var lastBuildDuration: TimeInterval? = nil
    var log: String = ""
}

enum SidebarFilter: String, CaseIterable {
    case all = "All"
    case unbuilt = "Unbuilt"
    case outdated = "Updates"
    case failed = "Failed"
}

enum BuildOutputMode: String, CaseIterable {
    case applications = "applications"
    case custom = "custom"

    var label: String {
        switch self {
        case .applications: return "Applications"
        case .custom: return "Custom Folder"
        }
    }
}

enum PreflightStatus: Equatable, Sendable {
    case passed
    case warning
    case failed

    var iconName: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

struct PreflightCheckItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let status: PreflightStatus
    let detail: String
    let isRequired: Bool
}

struct NXNativeRepoStatus: Equatable, Sendable {
    let branch: String
    let commitHash: String
}
