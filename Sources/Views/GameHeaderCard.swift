import SwiftUI
import UniformTypeIdentifiers

struct GameHeaderCard: View {
    let game: GameEntry
    let manager: BuildManager
    @State private var showTitleIDPopover = false
    @State private var titleIDDraft = ""
    @State private var showAppNamePopover = false
    @State private var appNameDraft = ""
    @State private var copiedTitleID = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var isHoveringIcon = false
    @State private var isDropTargeted = false
    @State private var pendingIconURL: URL?
    @State private var showReplaceIconConfirm = false
    @State private var iconErrorMessage: String?
    @State private var showIconError = false
    @State private var showReadmeSheet = false
    @State private var showTechnicalDetailsPopover = false

    var body: some View {
        let builtApps = game.builtAppURLs
        let workFolders = game.workFolders

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DesignSpacing.md) {
                gameIconView(size: 200, cornerRadius: 12, symbolSize: 44)

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    HStack(alignment: .center, spacing: DesignSpacing.sm) {
                        titleAndStatusRow
                            .layoutPriority(0)
                        Spacer(minLength: DesignSpacing.sm)
                        actionButtonsRow(builtApps: builtApps, workFolders: workFolders)
                            .fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        FlowLayout(spacing: 6, rowSpacing: 5) {
                            platformAndTitleIDPills
                        }

                        if game.buildInfo.isEmpty {
                            FlowLayout(spacing: 6, rowSpacing: 4) {
                                Text("Not built")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                                    .help("Game has not been built yet")

                                let effectiveName = manager.effectiveAppName(for: game)
                                if effectiveName != game.name {
                                    Text("Folder: \(game.name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(minHeight: 22, alignment: .leading)
                        } else {
                            let updateVer = game.availableUpdateVersion
                            ForEach(Array(game.buildInfo.enumerated()), id: \.element.appName) { index, info in
                                FlowLayout(spacing: 6, rowSpacing: 4) {
                                    if game.buildInfo.count > 1 {
                                        Text(info.appName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }

                                    MetadataPill(icon: "tag", text: "App v\(info.version)")
                                        .help("Built .app version")

                                    if index == 0, let updateVer {
                                        Image(systemName: "arrow.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                        MetadataPill(icon: "arrow.up.circle.fill", text: "Update \(updateVer) available", tint: .orange)
                                            .help("Newer update package detected in source folder")
                                    }

                                    let metaText: String = {
                                        var items: [String] = []
                                        if let sizeBytes = info.sizeBytes {
                                            items.append("Size: \(manager.formatBytes(sizeBytes))")
                                        }
                                        items.append("Built: \(manager.formatDate(info.buildDate))")
                                        return items.joined(separator: " · ")
                                    }()
                                    Text(metaText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .help(toolchainTooltip(for: info))
                                }
                                .frame(minHeight: 22, alignment: .leading)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Source Files")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        if game.sourcePackages.isEmpty {
                            Label("No .nsp / .xci / .nsz / .nup source files detected", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(game.sourcePackages) { pkg in
                                        HStack(spacing: 7) {
                                            HStack(spacing: DesignSpacing.xs) {
                                                ForEach(Array(pkg.kinds.enumerated()), id: \.element) { index, kind in
                                                    if index > 0 {
                                                        Text("+")
                                                            .font(.caption2.weight(.semibold))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Text(kind.label)
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(kind.color)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background(kind.color.opacity(0.14), in: Capsule())
                                                }
                                            }

                                            Text(pkg.displayName)
                                                .font(.callout)
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            if let version = pkg.version {
                                                Text(version)
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                            }

                                            Spacer(minLength: 0)
                                        }
                                        .help(pkg.rawFilename)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 200, alignment: .top)
            }
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, 10)
        .frame(minHeight: DesignLayout.gameCardHeight, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .onChange(of: game.id) {
            copyResetTask?.cancel()
            copiedTitleID = false
        }
        .sheet(isPresented: $showReadmeSheet) {
            GameReadmeSheet(game: game, manager: manager)
        }
    }

    @ViewBuilder
    private func gameIconView(size: CGFloat, cornerRadius: CGFloat, symbolSize: CGFloat) -> some View {
        Button {
            openIconPicker()
        } label: {
            ZStack(alignment: .bottom) {
                if let img = game.iconImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(.rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: size, height: size)
                        .overlay(
                            VStack(spacing: DesignSpacing.sm) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: symbolSize))
                                    .foregroundStyle(.secondary)
                                Text("Add Icon or Cover")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        )
                }

                if isHoveringIcon && game.iconImage != nil {
                    Label("Replace Icon", systemImage: "photo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSpacing.sm)
                        .padding(.vertical, DesignSpacing.xs)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(.bottom, DesignSpacing.sm)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHoveringIcon = $0 }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleIconDrop(providers)
        }
        .help(game.iconImage == nil ? "Click or drop an image to add a game icon" : "Click or drop an image to replace the game icon")
        .accessibilityLabel(game.iconImage == nil ? "Add game icon" : "Replace game icon")
        .accessibilityHint("Opens a file picker or accepts a dropped image to save a uniform 1024×1024 macOS icon")
        .confirmationDialog(
            "Replace existing game icon?",
            isPresented: $showReplaceIconConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace & Move Old to Trash", role: .destructive) {
                applyPendingIcon(trashPrevious: true)
            }
            Button("Replace & Keep Old File") {
                applyPendingIcon(trashPrevious: false)
            }
            Button("Cancel", role: .cancel) {
                pendingIconURL = nil
            }
        } message: {
            if let oldName = game.iconURL?.lastPathComponent {
                Text("\"\(oldName)\" will be moved to the Trash and replaced with a uniform 1024×1024 macOS icon.")
            } else {
                Text("The previous icon will be replaced with a uniform 1024×1024 macOS icon.")
            }
        }
        .alert("Unable to Update Icon", isPresented: $showIconError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(iconErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func openIconPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Game Icon or Cover"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = GameScanner.supportedIconExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            handlePickedOrDroppedIconURL(url)
        }
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        if let fileProvider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) {
            _ = fileProvider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.lowercased()
                guard GameScanner.supportedIconExtensions.contains(ext) else {
                    Task { @MainActor in
                        iconErrorMessage = "Unsupported image format (.\(ext)). Supported formats: \(GameScanner.supportedIconExtensions.joined(separator: ", "))."
                        showIconError = true
                    }
                    return
                }
                Task { @MainActor in
                    handlePickedOrDroppedIconURL(url)
                }
            }
            return true
        }

        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            imageProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dropped-icon-\(UUID().uuidString).png")
                do {
                    try data.write(to: tempURL, options: .atomic)
                    Task { @MainActor in
                        handlePickedOrDroppedIconURL(tempURL)
                    }
                } catch {
                    Task { @MainActor in
                        iconErrorMessage = error.localizedDescription
                        showIconError = true
                    }
                }
            }
            return true
        }

        return false
    }

    private func handlePickedOrDroppedIconURL(_ url: URL) {
        if game.iconURL != nil {
            pendingIconURL = url
            showReplaceIconConfirm = true
        } else {
            applyIcon(from: url, trashPrevious: false)
        }
    }

    private func applyPendingIcon(trashPrevious: Bool) {
        guard let url = pendingIconURL else { return }
        pendingIconURL = nil
        applyIcon(from: url, trashPrevious: trashPrevious)
    }

    private func applyIcon(from url: URL, trashPrevious: Bool) {
        do {
            try manager.setGameIcon(from: url, for: game.id, trashPreviousIcon: trashPrevious)
        } catch {
            iconErrorMessage = error.localizedDescription
            showIconError = true
        }
    }

    private var titleAndStatusRow: some View {
        HStack(spacing: 6) {
            Text(manager.effectiveAppName(for: game))
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Button {
                appNameDraft = manager.appNameOverrides[game.id] ?? game.name
                showAppNamePopover = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit output .app name (--app-name)")
            .accessibilityLabel("Edit output app name")
            .popover(isPresented: $showAppNamePopover) {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("App Name for \(game.name)")
                        .font(.headline)
                    TextField("e.g. Super Mario Galaxy", text: $appNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit {
                            manager.setAppNameOverride(appNameDraft, for: game.id)
                            showAppNamePopover = false
                        }
                    HStack {
                        Button("Reset") {
                            manager.setAppNameOverride("", for: game.id)
                            showAppNamePopover = false
                        }
                        Spacer()
                        Button("Save") {
                            manager.setAppNameOverride(appNameDraft, for: game.id)
                            showAppNamePopover = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(DesignSpacing.md)
            }

            if game.status != .idle {
                Text(game.status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(game.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(game.status.color.opacity(0.14), in: Capsule())
            }

            if game.status != .building, let duration = game.lastBuildDuration {
                Text("Built in \(manager.formatDuration(duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Last build duration")
            }

            Button {
                showTechnicalDetailsPopover = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("View technical build & disk details")
            .accessibilityLabel("Technical build and disk details")
            .popover(isPresented: $showTechnicalDetailsPopover, arrowEdge: .bottom) {
                GameTechnicalDetailsPopover(game: game, manager: manager)
            }
        }
    }

    private func toolchainTooltip(for info: BuildArtifactInfo) -> String {
        var parts = ["Built: \(manager.formatDate(info.buildDate))"]
        if !info.commit.isEmpty {
            parts.append("NXNative Commit: \(info.commit)")
        }
        if let chain = info.chain, !chain.isEmpty {
            parts.append("Build Chain: \(chain)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var platformAndTitleIDPills: some View {
        let effectiveTitleID = manager.effectiveTitleID(for: game)
        let effectiveAppName = manager.effectiveAppName(for: game)
        let isSw2 = manager.effectiveIsSwitch2(for: game)

        Text(isSw2 ? "Switch 2" : "Switch 1")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSw2 ? .red : .blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((isSw2 ? Color.red : Color.blue).opacity(0.12), in: Capsule())
            .help(isSw2 ? "Switch 2 (builds without prod.keys)" : "Switch 1 (builds with prod.keys)")

        HStack(spacing: DesignSpacing.xs) {
            Button {
                titleIDDraft = manager.titleIDOverrides[game.id] ?? game.detectedTitleID ?? ""
                showTitleIDPopover = true
            } label: {
                titleIDPillLabel(effectiveTitleID ?? "Not Set", isMissing: effectiveTitleID == nil)
            }
            .buttonStyle(.plain)
            .help("Edit Title ID (--title-id)")
            .popover(isPresented: $showTitleIDPopover) {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("Title ID for \(effectiveAppName)")
                        .font(.headline)
                    TextField("e.g. 0100300012F2A000", text: $titleIDDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 220)
                        .onSubmit {
                            manager.setTitleIDOverride(titleIDDraft, for: game.id)
                            showTitleIDPopover = false
                        }
                    HStack {
                        Button("Clear") {
                            manager.setTitleIDOverride("", for: game.id)
                            showTitleIDPopover = false
                        }
                        Spacer()
                        Button("Save") {
                            manager.setTitleIDOverride(titleIDDraft, for: game.id)
                            showTitleIDPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(DesignSpacing.md)
            }

            if let effectiveTitleID {
                titleIDCopyButton(effectiveTitleID)
            }
        }

        readmePill(titleID: effectiveTitleID)
    }

    @ViewBuilder
    private func readmePill(titleID: String?) -> some View {
        let readmeURL = titleID.flatMap { manager.readmeFileURL(for: $0) }
        if readmeURL != nil {
            Button {
                showReadmeSheet = true
            } label: {
                Label("NXNative README", systemImage: "doc.text")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Open nxnative README.md in read-only viewer")
            .accessibilityLabel("Open NXNative README")
        } else {
            Label("Untested (No README)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.14), in: Capsule())
                .help("No readme.md found in nxnative/dm/games — this title has not been tested yet")
                .accessibilityLabel("Untested, no NXNative README present")
        }
    }

    private func titleIDPillLabel(_ text: String, isMissing: Bool) -> some View {
        HStack(spacing: 4) {
            Text("Title ID:")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(isMissing ? .orange : .secondary)
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isMissing ? .orange : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func titleIDCopyButton(_ titleID: String) -> some View {
        Button {
            copyTitleID(titleID)
        } label: {
            Image(systemName: copiedTitleID ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copiedTitleID ? .green : .secondary)
                .frame(width: 20, height: 20)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help(copiedTitleID ? "Copied Title ID" : "Copy Title ID")
        .accessibilityLabel(copiedTitleID ? "Title ID copied" : "Copy Title ID")
    }

    private func copyTitleID(_ titleID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(titleID, forType: .string)
        copiedTitleID = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            copiedTitleID = false
        }
    }

    private func actionButtonsRow(builtApps: [URL], workFolders: [URL]) -> some View {
        HStack(spacing: 6) {
            if game.status == .building {
                Button {
                    manager.cancelQueueItem(id: game.id)
                } label: {
                    Label("Cancel Build", systemImage: "stop.fill")
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Cancel the active build for \(manager.effectiveAppName(for: game))")
            } else if manager.isBuilding && game.status == .queued {
                Button {
                    manager.buildSingle(game.id)
                } label: {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove \(manager.effectiveAppName(for: game)) from the build queue")
            } else {
                Button {
                    manager.buildSingle(game.id)
                } label: {
                    if manager.isBuilding {
                        Label("Add to Queue", systemImage: "plus.circle")
                    } else {
                        Label("Build", systemImage: "hammer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(manager.isBuilding ? "Add \(manager.effectiveAppName(for: game)) to the build queue" : "Build \(manager.effectiveAppName(for: game))")
            }

            Menu {
                GameMenuActions(
                    game: game,
                    manager: manager,
                    includeBuildAction: false,
                    showDisabledPlaceholders: false
                )
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
            .accessibilityLabel("More actions")
        }
    }
}

struct GameHeaderEmptyState: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Game Selected")
                    .font(.system(size: 14, weight: .semibold))
                Text("Select a game from the list below to view details, source files, and actions.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .frame(minHeight: DesignLayout.gameCardHeight, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}

private struct GameTechnicalDetailsPopover: View {
    let game: GameEntry
    let manager: BuildManager

    @Environment(\.dismiss) private var dismiss
    @State private var isCalculatingDiskUsage = true
    @State private var workFoldersBytes: Int64?
    @State private var sourceFilesBytes: Int64?

    private var titleID: String? {
        manager.effectiveTitleID(for: game)
    }

    private var envFileURL: URL? {
        titleID.flatMap { manager.envFileURL(for: $0) }
    }

    private var hasCustomEnv: Bool {
        guard let envFileURL else { return false }
        return FileManager.default.fileExists(atPath: envFileURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text("Technical Details")
                .font(.headline)

            if !game.buildInfo.isEmpty {
                detailSection("Toolchain & Info.plist") {
                    ForEach(Array(game.buildInfo.enumerated()), id: \.element.appName) { index, info in
                        if game.buildInfo.count > 1 {
                            Text(info.appName)
                                .font(.caption.weight(.semibold))
                                .padding(.top, index > 0 ? DesignSpacing.xs : 0)
                        }
                        if !info.commit.isEmpty {
                            detailRow("NXNative Commit", value: info.commit, monospaced: true)
                        }
                        if let chain = info.chain, !chain.isEmpty {
                            detailRow("Build Chain", value: chain)
                        }
                        if let bundleID = info.bundleIdentifier, !bundleID.isEmpty {
                            detailRow("Bundle ID", value: bundleID, monospaced: true)
                        }
                        if let minOS = info.minimumSystemVersion, !minOS.isEmpty {
                            detailRow("Min macOS", value: minOS)
                        }
                        detailRow("Built", value: manager.formatDate(info.buildDate))
                    }
                    if let duration = game.lastBuildDuration {
                        detailRow("Last Duration", value: manager.formatDuration(duration))
                    }
                }
            }

            detailSection("Disk Usage") {
                let builtBytes = game.buildInfo.compactMap(\.sizeBytes).reduce(0, +)
                if builtBytes > 0 {
                    detailRow("Built .app", value: manager.formatBytes(builtBytes))
                }
                if isCalculatingDiskUsage {
                    HStack(spacing: DesignSpacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating folder sizes…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let sourceFilesBytes {
                        detailRow("Source Files", value: manager.formatBytes(sourceFilesBytes))
                    }
                    let wfCount = game.workFolders.count
                    let wfSize = workFoldersBytes.map { " (\(manager.formatBytes($0)))" } ?? ""
                    detailRow("Build Folders", value: wfCount == 0 ? "None" : "\(wfCount)\(wfSize)")
                }
            }

            detailSection("Paths & Configuration") {
                envRow
                pathRow("Source Folder", url: game.folderURL)
                ForEach(game.builtAppURLs, id: \.path) { appURL in
                    pathRow("Built .app", url: appURL)
                }
            }
        }
        .padding(DesignSpacing.md)
        .frame(width: 360)
        .task(id: game.id) {
            await loadDiskUsage()
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func detailRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var envRow: some View {
        HStack(spacing: DesignSpacing.xs) {
            Text("env.txt Override")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(hasCustomEnv ? "Configured" : "Default")
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                dismiss()
                manager.pendingEnvEditorGame = game
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(titleID == nil)
            .help(titleID == nil ? "A Title ID is required to edit env.txt" : "Edit env.txt")
            .accessibilityLabel("Edit env.txt")
        }
    }

    private func pathRow(_ label: String, url: URL) -> some View {
        HStack(spacing: DesignSpacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(url.path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                manager.revealInFinder(url)
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal \(label) in Finder")
        }
    }

    private func loadDiskUsage() async {
        isCalculatingDiskUsage = true
        let workFolders = game.workFolders
        let folderURL = game.folderURL
        let sourceFilenames = game.sourcePackages.map(\.rawFilename)

        let (workTotal, sourceTotal) = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var workSum: Int64 = 0
            for wf in workFolders {
                workSum += GameScanner.directorySize(at: wf) ?? 0
            }

            var srcSum: Int64 = 0
            for name in sourceFilenames {
                let fileURL = folderURL.appendingPathComponent(name)
                if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attrs[.size] as? Int64 {
                    srcSum += fileSize
                }
            }
            return (workSum > 0 ? workSum : nil, srcSum > 0 ? srcSum : nil)
        }.value

        workFoldersBytes = workTotal
        sourceFilesBytes = sourceTotal
        isCalculatingDiskUsage = false
    }
}

#if DEBUG
#Preview("Switch 1 Game Card") {
    let manager = BuildManager.previewSample(isBuilding: true)
    if let game = manager.games.first {
        GameHeaderCard(game: game, manager: manager)
            .frame(width: 760)
    }
}

#Preview("Switch 2 Long Title — Dark") {
    let manager = BuildManager.previewSample(isBuilding: false)
    if manager.games.count > 1 {
        GameHeaderCard(game: manager.games[1], manager: manager)
            .frame(width: 680)
            .preferredColorScheme(.dark)
    }
}

#Preview("Empty Header State") {
    GameHeaderEmptyState()
        .frame(width: 680)
}
#endif
