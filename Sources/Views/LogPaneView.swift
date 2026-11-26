import AppKit
import SwiftUI

struct LogPaneView: View {
    @Bindable var manager: BuildManager
    @Binding var showCombinedLog: Bool

    @AppStorage("logFontSize") private var logFontSize: Double = 11.5
    @AppStorage("logWrapLines") private var logWrapLines = true

    @State private var logController = LogViewerController()
    @State private var showIssuesOnly = false
    @State private var copiedLog = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var showClearLogsConfirm = false
    @FocusState private var isSearchFocused: Bool

    private static let minFontSize: Double = 9.0
    private static let maxFontSize: Double = 20.0

    private var inspectedLogGame: GameEntry? {
        let targetID = manager.inspectedLogGameID ?? manager.selectedGameID
        guard let targetID else { return nil }
        return manager.games.first(where: { $0.id == targetID })
    }

    private var displayedLog: String {
        if showCombinedLog {
            return manager.globalLog
        }
        if let game = inspectedLogGame {
            if game.log.isEmpty,
               let queueItem = manager.queueItem(for: game.id),
               queueItem.status == .queued {
                return "\(game.name) in queue waiting to be built\n"
            }
            return game.log
        }
        return manager.globalLog
    }

    private var issueCount: Int {
        LogFormatter.countIssues(in: displayedLog)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Build Log", systemImage: "terminal") {
                if manager.isBuilding {
                    activeBuildBadge
                }
            }

            Divider()

            logToolbar
                .panelToolbarStyle()

            if logController.isSearchVisible {
                Divider()
                logSearchBar
            }

            Divider()

            ZStack {
                LogTextView(
                    text: displayedLog,
                    sourceKey: showCombinedLog ? "__combined__" : (inspectedLogGame?.id ?? "__combined__"),
                    revision: manager.logRevision,
                    autoScroll: manager.autoScroll,
                    fontSize: CGFloat(logFontSize),
                    wrapLines: logWrapLines,
                    filterIssuesOnly: showIssuesOnly,
                    controller: logController
                )

                if displayedLog.isEmpty {
                    ContentUnavailableView {
                        Label("No Build Output", systemImage: "terminal")
                    } description: {
                        Text(showCombinedLog
                             ? "Start a build to stream combined output here."
                             : "Select a game or start a build to view its log.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                } else if showIssuesOnly && issueCount == 0 {
                    ContentUnavailableView {
                        Label("No Errors or Warnings", systemImage: "checkmark.circle")
                    } description: {
                        Text("No errors or warnings were found in the current log.")
                    } actions: {
                        Button("Show All Output") {
                            showIssuesOnly = false
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .frame(minHeight: 220)
        .confirmationDialog(
            "Clear all build logs?",
            isPresented: $showClearLogsConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Logs", role: .destructive) {
                manager.clearLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes captured build output for the current session.")
        }
    }

    private var logToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSpacing.sm) {
                logScopePicker
                Spacer(minLength: DesignSpacing.xs)
                logActionButtons
            }

            VStack(alignment: .leading, spacing: 6) {
                logScopePicker
                HStack(spacing: DesignSpacing.sm) {
                    logActionButtons
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var logScopePicker: some View {
        Picker("", selection: $showCombinedLog) {
            Text("Selected Game").tag(false)
            Text("All Output").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("Log output scope")
    }

    @ViewBuilder
    private var logActionButtons: some View {
        HStack(spacing: DesignSpacing.sm) {
            HStack(spacing: DesignSpacing.xs) {
                Toggle(isOn: Binding(
                    get: { manager.followActiveBuild },
                    set: { manager.setFollowActiveBuild($0) }
                )) {
                    Image(systemName: manager.followActiveBuild ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .frame(width: 14, height: 14)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(manager.followActiveBuild ? "Following active build log" : "Log pinned to selection (click to follow active build)")
                .accessibilityLabel("Follow active build")
                .accessibilityValue(manager.followActiveBuild ? "On" : "Off")

                Toggle(isOn: $manager.autoScroll) {
                    Image(systemName: manager.autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .frame(width: 14, height: 14)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(manager.autoScroll ? "Auto-scroll on" : "Auto-scroll off")
                .accessibilityLabel("Auto-scroll log")
                .accessibilityValue(manager.autoScroll ? "On" : "Off")

                Button {
                    logController.isSearchVisible = true
                    isSearchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("f", modifiers: .command)
                .help("Search log (⌘F)")
                .accessibilityLabel("Search log")

                Button {
                    logController.jumpToNextError()
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(displayedLog.isEmpty)
                .help("Jump to next error")
                .accessibilityLabel("Jump to next error")

                Toggle(isOn: $showIssuesOnly) {
                    HStack(spacing: DesignSpacing.xs) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .frame(width: 14, height: 14)
                        if issueCount > 0 {
                            Text("\(issueCount)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(displayedLog.isEmpty)
                .help(showIssuesOnly ? "Showing errors & warnings only" : "Filter to errors & warnings")
                .accessibilityLabel("Filter errors and warnings")
                .accessibilityValue(showIssuesOnly ? "On, \(issueCount) issues" : "Off, \(issueCount) issues")
            }
            .fixedSize()

            Divider()
                .frame(height: 14)

            HStack(spacing: DesignSpacing.xs) {
                Toggle(isOn: $logWrapLines) {
                    Image(systemName: "arrow.turn.down.left")
                        .frame(width: 14, height: 14)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(logWrapLines ? "Line wrapping on" : "Line wrapping off (horizontal scroll)")
                .accessibilityLabel("Wrap log lines")
                .accessibilityValue(logWrapLines ? "On" : "Off")

                Button {
                    logFontSize = max(Self.minFontSize, logFontSize - 1.0)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logFontSize <= Self.minFontSize)
                .keyboardShortcut("-", modifiers: .command)
                .help("Decrease log font size (⌘-)")
                .accessibilityLabel("Decrease log font size")

                Button {
                    logFontSize = min(Self.maxFontSize, logFontSize + 1.0)
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logFontSize >= Self.maxFontSize)
                .keyboardShortcut("=", modifiers: .command)
                .help("Increase log font size (⌘+)")
                .accessibilityLabel("Increase log font size")
            }
            .fixedSize()

            Divider()
                .frame(height: 14)

            HStack(spacing: DesignSpacing.xs) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LogFormatter.stripANSI(displayedLog), forType: .string)
                    copiedLog = true
                    copyResetTask?.cancel()
                    copyResetTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        guard !Task.isCancelled else { return }
                        copiedLog = false
                    }
                } label: {
                    Image(systemName: copiedLog ? "checkmark" : "doc.on.doc")
                        .frame(width: 14, height: 14)
                        .foregroundStyle(copiedLog ? .green : .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(displayedLog.isEmpty)
                .help("Copy full log")
                .accessibilityLabel(copiedLog ? "Log copied" : "Copy full log")

                Button {
                    let baseName = showCombinedLog ? "NXNative-Combined" : (inspectedLogGame?.name ?? "NXNative")
                    logController.saveLog(LogFormatter.stripANSI(displayedLog), defaultName: baseName)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(displayedLog.isEmpty)
                .help("Save log to file…")
                .accessibilityLabel("Save log to file")

                Button(role: .destructive) {
                    showClearLogsConfirm = true
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(displayedLog.isEmpty)
                .keyboardShortcut("k", modifiers: .command)
                .help("Clear logs (⌘K)")
                .accessibilityLabel("Clear build logs")
            }
            .fixedSize()
        }
    }

    private var activeBuildBadge: some View {
        HStack(spacing: DesignSpacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text("\(min(manager.completedCount + 1, manager.totalCount))/\(manager.totalCount) \(manager.currentBuildName)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var logSearchBar: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search log…", text: $logController.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isSearchFocused)
                .onSubmit {
                    logController.nextMatch()
                }

            if !logController.searchQuery.isEmpty {
                Text(logController.matchRanges.isEmpty ? "No matches" : "\(logController.currentMatchIndex + 1) of \(logController.matchRanges.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Button {
                logController.previousMatch()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(logController.matchRanges.isEmpty)
            .help("Previous match")
            .accessibilityLabel("Previous match")

            Button {
                logController.nextMatch()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(logController.matchRanges.isEmpty)
            .help("Next match")
            .accessibilityLabel("Next match")

            Button {
                logController.isSearchVisible = false
                logController.searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close search")
            .accessibilityLabel("Close log search")
        }
        .panelToolbarStyle(hasBackground: true)
    }
}

#if DEBUG
#Preview("Empty Log") {
    LogPaneView(
        manager: BuildManager(previewGames: []),
        showCombinedLog: .constant(false)
    )
    .frame(width: 640, height: 320)
}

#Preview("Active Build — Dark") {
    LogPaneView(
        manager: .previewSample(isBuilding: true),
        showCombinedLog: .constant(true)
    )
    .frame(width: 640, height: 320)
    .preferredColorScheme(.dark)
}
#endif
