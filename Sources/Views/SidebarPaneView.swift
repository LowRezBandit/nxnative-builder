import SwiftUI

struct SidebarPaneView: View {
    @Bindable var manager: BuildManager
    @Binding var showCleanAllFoldersConfirm: Bool

    @State private var searchText = ""
    @State private var sidebarFilter: SidebarFilter = .all
    @FocusState private var isGameListFocused: Bool

    private var selectedCount: Int {
        manager.games.filter(\.isSelected).count
    }

    private var failedCount: Int {
        manager.games.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    private var outdatedCount: Int {
        manager.outdatedGameIDs().count
    }

    private var totalWorkFolderCount: Int {
        manager.games.reduce(0) { $0 + $1.workFolders.count }
    }

    private var selectedGame: GameEntry? {
        guard let id = manager.selectedGameID else { return nil }
        return manager.games.first(where: { $0.id == id })
    }

    private func matchesSidebarFilter(_ game: GameEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty && !game.name.localizedCaseInsensitiveContains(query) {
            return false
        }
        switch sidebarFilter {
        case .all:
            return true
        case .unbuilt:
            return game.buildInfo.isEmpty
        case .outdated:
            return game.availableUpdateVersion != nil
        case .failed:
            if case .failed = game.status { return true }
            return false
        }
    }

    var body: some View {
        PersistentSplitView(
            isVertical: false,
            autosaveName: "SidebarPaneVSplitView",
            defaultPosition: { _ in DesignLayout.gameCardHeight },
            minFirstThickness: DesignLayout.gameCardHeight,
            minSecondThickness: 240
        ) {
            Group {
                if let game = selectedGame {
                    GameHeaderCard(game: game, manager: manager)
                } else {
                    GameHeaderEmptyState()
                }
            }
        } second: {
            VStack(spacing: 0) {
                gamesHeader

                Divider()

                if !manager.games.isEmpty {
                    filterBar
                    Divider()
                }

                gamesContent

                Divider()

                bottomActionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Filter games…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear game filter")
                .accessibilityLabel("Clear game filter")
            }

            Picker("", selection: $sidebarFilter) {
                ForEach(SidebarFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .panelToolbarStyle(hasBackground: true)
    }

    private var gamesHeader: some View {
        PanelHeader(
            title: "Games",
            systemImage: "gamecontroller",
            badgeCount: manager.games.isEmpty ? nil : manager.games.count
        ) {
            Toggle(isOn: Binding(
                get: { !manager.games.isEmpty && selectedCount == manager.games.count },
                set: { manager.selectAll($0) }
            )) {
                Text("Select All")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(manager.games.isEmpty)

            Button {
                manager.loadGames()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh game list & build info (⌘R)")
            .accessibilityLabel("Refresh games")
            .disabled(manager.isBuilding)

            Menu {
                Button(selectedCount == manager.games.count && !manager.games.isEmpty ? "Deselect All" : "Select All") {
                    manager.selectAll(!(selectedCount == manager.games.count && !manager.games.isEmpty))
                }
                .disabled(manager.games.isEmpty || manager.isBuilding)

                Button("Select Outdated (\(outdatedCount))") {
                    manager.selectOutdated()
                }
                .disabled(outdatedCount == 0 || manager.isBuilding)

                Button {
                    manager.buildOutdated()
                } label: {
                    Label("Build Outdated (\(outdatedCount))", systemImage: "hammer")
                }
                .disabled(outdatedCount == 0 || manager.isBuilding)

                Divider()

                Button(role: .destructive) {
                    showCleanAllFoldersConfirm = true
                } label: {
                    Label("Delete All Build Folders (\(totalWorkFolderCount))…", systemImage: "folder.badge.minus")
                }
                .disabled(totalWorkFolderCount == 0 || manager.isBuilding)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Batch actions")
            .accessibilityLabel("Batch actions")
        }
    }

    @ViewBuilder
    private var gamesContent: some View {
        if manager.games.isEmpty {
            if manager.isLoadingGames {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning games")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Games Found", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(manager.sourcesPath)
                } actions: {
                    SettingsLink {
                        Text("Configure Paths…")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if !manager.games.contains(where: matchesSidebarFilter) {
            ContentUnavailableView {
                Label("No Matching Games", systemImage: "magnifyingglass")
            } description: {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    Text("No games match the \"\(sidebarFilter.rawValue)\" filter.")
                } else {
                    Text("No games match \"\(query)\" in \(sidebarFilter.rawValue).")
                }
            } actions: {
                Button("Clear Filter") {
                    searchText = ""
                    sidebarFilter = .all
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $manager.selectedGameID) {
                ForEach($manager.games) { $game in
                    if matchesSidebarFilter(game) {
                        SidebarGameRow(game: $game, manager: manager, isListFocused: isGameListFocused)
                            .tag(game.id)
                            .contextMenu {
                                GameContextMenu(game: game, manager: manager)
                            }
                    }
                }
            }
            .listStyle(.inset)
            .focused($isGameListFocused)
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: DesignSpacing.sm) {
            if manager.isBuilding {
                Button {
                    manager.buildSelected()
                } label: {
                    Label("Add Selected to Queue (\(selectedCount))", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("b", modifiers: .command)
                .disabled(selectedCount == 0 || manager.games.isEmpty)
                .help("Add checked games to the build queue (⌘B)")
            } else {
                Button {
                    manager.buildSelected()
                } label: {
                    Label("Build Selected (\(selectedCount))", systemImage: "hammer")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("b", modifiers: .command)
                .disabled(selectedCount == 0 || manager.games.isEmpty)
                .help("Build checked games (⌘B)")

                if failedCount > 0 {
                    Button {
                        manager.retryFailed()
                    } label: {
                        Label("Retry Failed (\(failedCount))", systemImage: "arrow.clockwise")
                    }
                    .tint(.orange)
                    .buttonStyle(.bordered)
                    .help("Re-queue all failed builds")
                }
            }

            Spacer()
        }
        .padding(DesignSpacing.md)
    }
}

private struct SidebarGameRow: View {
    @Binding var game: GameEntry
    let manager: BuildManager
    let isListFocused: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    private var isHighlightedSelection: Bool {
        manager.selectedGameID == game.id && controlActiveState != .inactive && isListFocused
    }

    var body: some View {
        HStack(spacing: 10) {
            let effectiveName = manager.effectiveAppName(for: game)

            Toggle("", isOn: Binding(
                get: { game.isSelected },
                set: { newValue in
                    game.isSelected = newValue
                    manager.saveCheckedGames()
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help("Include in batch build")
            .accessibilityLabel("Select \(effectiveName) for batch build")

            if let img = game.iconImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .clipShape(.rect(cornerRadius: 7))
            } else {
                Image(systemName: "gamecontroller")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                let isSelected = isHighlightedSelection

                HStack(spacing: DesignSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.xs) {
                        Text(effectiveName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)

                        if let versionText = builtVersionText {
                            Text(versionText)
                                .font(.caption)
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }

                    Spacer(minLength: DesignSpacing.xs)

                    trailingBadges
                        .fixedSize()
                }

                HStack(spacing: 5) {
                    let isSw2 = manager.effectiveIsSwitch2(for: game)
                    Text(isSw2 ? "Switch 2" : "Switch 1")
                        .sidebarCapsulePill(tint: .secondary, isSelected: isSelected, backgroundOpacity: 0.12)
                        .fixedSize()
                        .help(isSw2 ? "Switch 2 (builds without prod.keys)" : "Switch 1 (builds with prod.keys)")
                        .accessibilityLabel(isSw2 ? "Switch 2" : "Switch 1")

                    let sourceKinds = Set(game.sourcePackages.flatMap(\.kinds)).sorted()
                    if sourceKinds.isEmpty {
                        warningPill("No sources", isSelected: isSelected)
                            .fixedSize()
                            .help("No .nsp / .xci / .nsz / .nup source files detected")
                            .accessibilityLabel("No source files detected")
                    } else {
                        HStack(spacing: 3) {
                            ForEach(Array(sourceKinds.enumerated()), id: \.element) { index, kind in
                                if index > 0 {
                                    Text("+")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                                }
                                Text(kind.label)
                                    .sidebarCapsulePill(tint: kind.color, isSelected: isSelected)
                            }
                        }
                        .fixedSize()
                    }

                    if game.buildInfo.isEmpty {
                        Text("Not built")
                            .sidebarCapsulePill(tint: .orange, isSelected: isSelected)
                            .fixedSize()
                            .help("Game has not been built yet")
                    } else if let sizeText = builtSizeText {
                        Text(sizeText)
                            .font(.caption)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }

                    if let updateVer = game.availableUpdateVersion {
                        Text("↑ \(updateVer)")
                            .sidebarCapsulePill(tint: .orange, isSelected: isSelected)
                            .fixedSize()
                            .help("Update \(updateVer) available in source folder")
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 3)
    }

    private func warningPill(_ text: String, isSelected: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)
            Text(text)
        }
        .sidebarCapsulePill(tint: .orange, isSelected: isSelected)
    }

    private var builtVersionText: String? {
        guard !game.buildInfo.isEmpty else { return nil }
        if game.buildInfo.count == 1, let info = game.buildInfo.first {
            return "v\(info.version)"
        }
        return game.buildInfo.map { "v\($0.version)" }.joined(separator: " · ")
    }

    private var builtSizeText: String? {
        let sizes = game.buildInfo.compactMap(\.sizeBytes)
        guard !sizes.isEmpty else { return nil }
        let total = sizes.reduce(0, +)
        return manager.formatBytes(total)
    }

    @ViewBuilder
    private var trailingBadges: some View {
        let missingTitleID = manager.effectiveTitleID(for: game) == nil
        let isSelected = isHighlightedSelection

        HStack(spacing: DesignSpacing.xs) {
            if game.status == .building {
                ProgressView()
                    .controlSize(.small)
            }

            if game.status != .idle {
                let statusText: String = {
                    if game.status == .queued, let pos = manager.queuePosition(for: game.id) {
                        return "Queued #\(pos)"
                    }
                    return game.status.label
                }()
                Text(statusText)
                    .sidebarCapsulePill(tint: game.status.color, isSelected: isSelected)
                    .lineLimit(1)
            }

            if missingTitleID {
                warningPill("No Title ID", isSelected: isSelected)
                    .help("Title ID not detected or set")
                    .accessibilityLabel("Missing Title ID")
            }
        }
    }
}

private extension View {
    func sidebarCapsulePill(tint: Color, isSelected: Bool, backgroundOpacity: Double = 0.14) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                (isSelected ? Color.white.opacity(0.22) : tint.opacity(backgroundOpacity)),
                in: Capsule()
            )
    }
}
