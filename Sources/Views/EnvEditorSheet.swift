import SwiftUI

struct EnvEditorSheet: View {
    let game: GameEntry
    let manager: BuildManager

    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var errorMessage: String?

    private var titleID: String? {
        manager.effectiveTitleID(for: game)
    }

    private var fileURL: URL? {
        guard let titleID else { return nil }
        return manager.envFileURL(for: titleID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit env.txt — \(game.name)")
                        .font(.headline)
                    if let fileURL {
                        Text(fileURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if let titleID {
                    Text("Title ID: \(titleID)")
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            TextEditor(text: $content)
                .font(.callout.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .frame(minHeight: 240)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if let fileURL {
                    let revealTarget: URL? = {
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            return fileURL
                        }
                        let parent = fileURL.deletingLastPathComponent()
                        return FileManager.default.fileExists(atPath: parent.path) ? parent : nil
                    }()

                    Button {
                        if let revealTarget {
                            manager.revealInFinder(revealTarget)
                        }
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .disabled(revealTarget == nil)
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(titleID == nil)
            }
        }
        .padding(16)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 320, idealHeight: 390)
        .task(id: game.id) {
            load()
        }
    }

    private func load() {
        errorMessage = nil
        guard let titleID else {
            content = ""
            errorMessage = "A Title ID is required to locate env.txt."
            return
        }
        do {
            content = try manager.readEnvFile(for: titleID)
        } catch {
            errorMessage = "Failed to read env.txt: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard let titleID else { return }
        do {
            try manager.saveEnvFile(content, for: titleID)
            dismiss()
        } catch {
            errorMessage = "Failed to save env.txt: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview("With Title ID") {
    let manager = BuildManager.previewSample(isBuilding: false)
    if let game = manager.games.first {
        EnvEditorSheet(game: game, manager: manager)
    }
}

#Preview("Missing Title ID") {
    let manager = BuildManager(previewGames: [])
    let game = GameEntry(
        id: "no-tid",
        name: "Unknown Game",
        folderURL: URL(fileURLWithPath: "/tmp/Unknown"),
        sourcePackages: [],
        detectedTitleID: nil,
        hasSwitch2Source: false
    )
    EnvEditorSheet(game: game, manager: manager)
}
#endif
