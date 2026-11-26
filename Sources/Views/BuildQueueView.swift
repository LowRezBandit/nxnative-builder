import SwiftUI

struct BuildQueueView: View {
    @Bindable var manager: BuildManager
    @Binding var showCombinedLog: Bool
    @State private var showCancelAllConfirm = false

    private var activeCount: Int {
        manager.queueItems.filter { $0.status == .queued || $0.status == .building }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: "Build Queue",
                systemImage: "list.bullet.rectangle",
                badgeCount: manager.queueItems.isEmpty ? nil : manager.queueItems.count
            ) {
                if manager.isBuilding && manager.queueItems.count > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let totalElapsed = manager.queueStartDate.map { context.date.timeIntervalSince($0) } ?? 0
                        Text("· \(activeCount) remaining · \(manager.formatDuration(totalElapsed))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                    }
                }

                if manager.hasFinishedQueueItems {
                    Button("Clear Finished") {
                        manager.clearFinishedQueueItems()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }

                Button("Cancel All") {
                    if manager.isBuilding {
                        showCancelAllConfirm = true
                    } else {
                        manager.cancelAllBuilds()
                    }
                }
                .tint(.red)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(!manager.hasQueuedOrBuildingItems)
            }

            Divider()

            if !manager.resumableQueueGameIDs.isEmpty && !manager.isBuilding {
                resumableQueueBanner
                Divider()
            }

            if manager.queueItems.isEmpty {
                ContentUnavailableView {
                    Label("No Builds Queued", systemImage: "tray")
                } description: {
                    Text("Select games in the list and click Build Selected or Add Selected to Queue.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSpacing.xs) {
                        ForEach(Array(manager.queueItems.enumerated()), id: \.element.id) { index, item in
                            BuildQueueRow(
                                index: index + 1,
                                item: item,
                                iconImage: manager.games.first(where: { $0.id == item.id })?.iconImage,
                                isInspected: !showCombinedLog && manager.inspectedLogGameID == item.id,
                                manager: manager,
                                onSelect: {
                                    showCombinedLog = false
                                    manager.inspectQueueItemLog(item.id)
                                }
                            )
                        }
                    }
                    .padding(DesignSpacing.sm)
                }
            }
        }
        .frame(minHeight: 140, idealHeight: DesignLayout.gameCardHeight)
        .confirmationDialog(
            "Cancel all queued builds?",
            isPresented: $showCancelAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel All Builds", role: .destructive) {
                manager.cancelAllBuilds()
            }
            Button("Keep Building", role: .cancel) {}
        } message: {
            Text("This will stop the active build and cancel all remaining items in the queue.")
        }
    }

    private var resumableQueueBanner: some View {
        let count = manager.resumableQueueGameIDs.count
        return HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Interrupted build queue (\(count) \(count == 1 ? "game" : "games"))")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Resume remaining builds from the start or discard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: DesignSpacing.xs)

            Button("Discard") {
                manager.discardInterruptedQueue()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .help("Discard the saved interrupted build queue")

            Button("Resume Queue") {
                manager.resumeInterruptedQueue()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
            .fixedSize()
            .help("Re-queue the interrupted games and start building")
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, DesignSpacing.sm)
        .background(Color.orange.opacity(0.08))
    }
}

private struct BuildQueueRow: View {
    let index: Int
    let item: BuildQueueItem
    let iconImage: NSImage?
    let isInspected: Bool
    let manager: BuildManager
    let onSelect: () -> Void
    @State private var showCancelActiveConfirm = false

    private var effectiveProgress: Double {
        switch item.status {
        case .succeeded: return 1.0
        case .building: return min(max(item.progress, 0.0), 1.0)
        case .queued, .idle, .failed, .stopped, .cancelled: return item.progress
        }
    }

    private var progressTint: Color {
        switch item.status {
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled, .stopped: return .secondary
        case .building, .queued, .idle: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            HStack(spacing: DesignSpacing.sm) {
                Button(action: onSelect) {
                    HStack(spacing: DesignSpacing.sm) {
                        Text("#\(index)")
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                            .fixedSize()

                        if let iconImage {
                            Image(nsImage: iconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .clipShape(.rect(cornerRadius: 4))
                        } else {
                            Image(systemName: "gamecontroller")
                                .frame(width: 22, height: 22)
                                .foregroundStyle(.secondary)
                        }

                        Text(item.gameName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        Text(item.status.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item.status.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.status.color.opacity(0.14), in: Capsule())
                            .fixedSize()

                        if item.status == .building, !item.stepLabel.isEmpty {
                            Text(item.stepLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer(minLength: DesignSpacing.xs)

                        if item.status == .building, let start = item.startDate {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(manager.formatDuration(context.date.timeIntervalSince(start)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        } else if let duration = item.duration {
                            Text(manager.formatDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }

                        if item.status == .building {
                            Text("\(Int((effectiveProgress * 100).rounded()))%")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                                .fixedSize()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Inspect log for \(item.gameName), \(item.status.label)")
                .accessibilityValue(item.status == .building ? "\(Int((effectiveProgress * 100).rounded())) percent" : "")
                .accessibilityAddTraits(isInspected ? .isSelected : [])

                actionButton
                    .fixedSize()
            }

            ProgressView(value: effectiveProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(progressTint)
                .controlSize(.small)
                .accessibilityValue("\(Int((effectiveProgress * 100).rounded())) percent")
        }
        .padding(.horizontal, DesignSpacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isInspected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isInspected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .confirmationDialog(
            "Cancel build for \(item.gameName)?",
            isPresented: $showCancelActiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel Build", role: .destructive) {
                manager.cancelQueueItem(id: item.id)
            }
            Button("Keep Building", role: .cancel) {}
        } message: {
            Text("This will stop the active build and continue with the remaining queue.")
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.status {
        case .queued:
            Button {
                manager.cancelQueueItem(id: item.id)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Remove from queue")
            .accessibilityLabel("Remove \(item.gameName) from queue")
        case .building:
            Button {
                showCancelActiveConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption2.weight(.semibold))
            }
            .tint(.red)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Cancel this build and continue queue")
            .accessibilityLabel("Cancel build for \(item.gameName)")
        case .failed, .cancelled, .stopped:
            Button {
                manager.retryQueueItem(id: item.id)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Retry (place next in line)")
            .accessibilityLabel("Retry build for \(item.gameName)")
        case .succeeded, .idle:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Active Queue") {
    BuildQueueView(
        manager: .previewSample(isBuilding: true),
        showCombinedLog: .constant(false)
    )
    .frame(width: 520, height: 280)
}

#Preview("Resumable Banner — Dark") {
    let manager = BuildManager(previewGames: [])
    manager.resumableQueueGameIDs = ["g1", "g2"]
    return BuildQueueView(
        manager: manager,
        showCombinedLog: .constant(false)
    )
    .frame(width: 520, height: 260)
    .preferredColorScheme(.dark)
}

#Preview("Empty Queue — Large Text") {
    BuildQueueView(
        manager: BuildManager(previewGames: []),
        showCombinedLog: .constant(false)
    )
    .frame(width: 460, height: 220)
    .environment(\.sizeCategory, .accessibilityLarge)
}
#endif
