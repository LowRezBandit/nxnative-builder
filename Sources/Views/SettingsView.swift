import AppKit
import SwiftUI

struct SettingsView: View {
  @Bindable var manager: BuildManager
  @State private var showResetConfirm = false

  private func pathExists(_ path: String, isDirectory: Bool) -> Bool {
    var isDir: ObjCBool = false
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir)
      && isDir.boolValue == isDirectory
  }

  private func revealPath(_ path: String) {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    manager.revealInFinder(URL(fileURLWithPath: trimmed))
  }

  private func choosePath(
    title: String, initialPath: String, chooseDirectories: Bool, onSelect: (String) -> Void
  ) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canChooseFiles = !chooseDirectories
    panel.canChooseDirectories = chooseDirectories
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = chooseDirectories
    let initialURL =
      chooseDirectories
      ? URL(fileURLWithPath: initialPath)
      : URL(fileURLWithPath: initialPath).deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: initialURL.path) {
      panel.directoryURL = initialURL
    }
    if panel.runModal() == .OK, let url = panel.url {
      onSelect(url.path)
    }
  }

  var body: some View {
    Form {
      Section("Directories") {
        pathFieldRow(
          title: "Game Sources Folder",
          path: $manager.sourcesPath,
          chooseTitle: "Choose Sources Folder",
          chooseDirectories: true
        )

        VStack(alignment: .leading, spacing: 8) {
          Picker("Build Output Location", selection: $manager.outputMode) {
            ForEach(BuildOutputMode.allCases, id: \.self) { mode in
              Text(mode.label).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .disabled(manager.isBuilding)

          if manager.outputMode == .applications {
            HStack(spacing: 6) {
              pathStatusLabel(for: BuildManager.defaultGamesRootPath, isDirectory: true)
              Spacer()
              Button {
                revealPath(BuildManager.defaultGamesRootPath)
              } label: {
                Label("Open", systemImage: "folder")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .help("Reveal /Applications in Finder")
            }
            Text("Built .app bundles are placed directly in /Applications.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            pathFieldRow(
              title: "Custom Output Folder",
              path: $manager.customGamesRootPath,
              chooseTitle: "Choose Custom Output Folder",
              chooseDirectories: true,
              helperText: "Built .app bundles are placed in a named subfolder under this folder."
            )
          }
        }
      }

      Section("NXNative Build Runner Settings") {
        pathFieldRow(
          title: "NXNative Repo Folder",
          path: $manager.nxnativeRepoPath,
          chooseTitle: "Choose NXNative Repo Folder",
          chooseDirectories: true
        )

        repoStatusRow

        pathFieldRow(
          title: "Switch 1 Keys (prod.keys)",
          path: $manager.prodKeysPath,
          chooseTitle: "Choose prod.keys",
          chooseDirectories: false,
          foundText: "Keys file found",
          missingText: "Keys file not found"
        )
      }

      Section("Build Environment") {
        VStack(alignment: .leading, spacing: 5) {
          Text("Extra PATH (colon-separated)")
            .font(.callout.weight(.medium))
          TextField("", text: $manager.extraPath)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .disabled(manager.isBuilding)
          Text("Prepended to PATH when running builds.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Preflight Diagnostics") {
        PreflightDiagnosticsView(manager: manager)
      }

      Section {
        HStack {
          Button("Reset to Defaults…") {
            showResetConfirm = true
          }
          .disabled(manager.isBuilding)

          Spacer()

          Button("Reload Games") {
            manager.loadGames()
          }
          .disabled(manager.isBuilding)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 620)
    .fixedSize(horizontal: false, vertical: true)
    .task {
      manager.runPreflightChecks()
      manager.refreshNXNativeRepoStatus()
    }
    .onChange(of: manager.nxnativeRepoPath) { _, _ in
      manager.refreshNXNativeRepoStatus()
      manager.runPreflightChecks()
    }
    .onChange(of: manager.sourcesPath) { _, _ in
      manager.runPreflightChecks()
    }
    .onChange(of: manager.prodKeysPath) { _, _ in
      manager.runPreflightChecks()
    }
    .onChange(of: manager.extraPath) { _, _ in
      manager.runPreflightChecks()
    }
    .confirmationDialog(
      "Reset all paths to defaults?",
      isPresented: $showResetConfirm,
      titleVisibility: .visible
    ) {
      Button("Reset to Defaults", role: .destructive) {
        manager.resetPathsToDefaults()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This will reset Build Output Location to Applications and restore the default Sources, NXNative Repo, Keys, and Extra PATH values."
      )
    }
  }

  @ViewBuilder
  private func pathFieldRow(
    title: String,
    path: Binding<String>,
    chooseTitle: String,
    chooseDirectories: Bool,
    helperText: String? = nil,
    foundText: String = "Folder found",
    missingText: String = "Folder not found"
  ) -> some View {
    let exists = pathExists(path.wrappedValue, isDirectory: chooseDirectories)

    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.callout.weight(.medium))

      HStack(spacing: 8) {
        TextField("", text: path)
          .labelsHidden()
          .multilineTextAlignment(.leading)
          .textFieldStyle(.roundedBorder)
          .disabled(manager.isBuilding)

        Button("Choose…") {
          choosePath(
            title: chooseTitle, initialPath: path.wrappedValue, chooseDirectories: chooseDirectories
          ) { selected in
            path.wrappedValue = selected
          }
        }
        .disabled(manager.isBuilding)

        Button {
          revealPath(path.wrappedValue)
        } label: {
          Image(systemName: "folder")
        }
        .disabled(!exists)
        .help("Reveal in Finder")
      }

      if let helperText {
        Text(helperText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      pathStatusLabel(
        for: path.wrappedValue,
        isDirectory: chooseDirectories,
        foundText: foundText,
        missingText: missingText
      )
    }
  }

  private var repoStatusRow: some View {
    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
      HStack(spacing: DesignSpacing.sm) {
        if let status = manager.repoStatus {
          Label("\(status.branch) · \(status.commitHash)", systemImage: "arrow.triangle.branch")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        } else {
          Text("Git status unavailable")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if manager.isPullingRepoUpdates {
          ProgressView()
            .controlSize(.small)
        }

        Button {
          manager.pullNXNativeRepoUpdates()
        } label: {
          Label("Pull Updates", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(manager.isBuilding || manager.isPullingRepoUpdates || manager.repoStatus == nil)
        .help("Run git pull --ff-only in the NXNative repo folder")
        .accessibilityLabel("Pull NXNative repository updates")
      }

      if let message = manager.repoUpdateMessage, !message.isEmpty {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
  }

  @ViewBuilder
  private func pathStatusLabel(
    for path: String,
    isDirectory: Bool,
    foundText: String = "Folder found",
    missingText: String = "Folder not found"
  ) -> some View {
    let exists = pathExists(path, isDirectory: isDirectory)
    Label(
      exists ? foundText : missingText,
      systemImage: exists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    )
    .font(.caption)
    .foregroundStyle(exists ? .green : .orange)
  }
}
