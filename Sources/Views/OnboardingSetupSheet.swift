import AppKit
import SwiftUI

struct OnboardingSetupSheet: View {
    @Bindable var manager: BuildManager
    @Environment(\.dismiss) private var dismiss

    private var hasRequiredFailures: Bool {
        manager.preflightChecks.contains { $0.isRequired && $0.status == .failed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to NXNative Builder")
                        .font(.title3.weight(.semibold))
                    Text("Configure your local paths before scanning and building games.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    pathPickerRow(
                        title: "Game Sources Folder",
                        subtitle: "Folder containing per-game .nsp / .xci / .nsz folders",
                        path: $manager.sourcesPath,
                        chooseTitle: "Choose Game Sources Folder",
                        chooseDirectories: true
                    )

                    pathPickerRow(
                        title: "NXNative Repository Folder",
                        subtitle: "Local clone containing scripts/build_ipa_from_nsp.py",
                        path: $manager.nxnativeRepoPath,
                        chooseTitle: "Choose NXNative Repository",
                        chooseDirectories: true
                    )

                    pathPickerRow(
                        title: "Switch 1 Keys (prod.keys — Optional)",
                        subtitle: "Required only for Switch 1 titles",
                        path: $manager.prodKeysPath,
                        chooseTitle: "Choose prod.keys",
                        chooseDirectories: false
                    )

                    Divider()

                    PreflightDiagnosticsView(manager: manager)
                }
                .padding(.vertical, DesignSpacing.xs)
            }

            Divider()

            HStack {
                Button("Skip for Now") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Finish & Load Games") {
                    manager.loadGames()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isRunningPreflight || hasRequiredFailures)
                .help(hasRequiredFailures ? "Resolve required checks above to continue" : "Save paths and scan for games")
            }
        }
        .padding(DesignSpacing.lg)
        .frame(minWidth: 540, idealWidth: 600, minHeight: 460, idealHeight: 540)
        .task {
            manager.runPreflightChecks()
        }
        .onChange(of: manager.sourcesPath) { _, _ in
            manager.runPreflightChecks()
        }
        .onChange(of: manager.nxnativeRepoPath) { _, _ in
            manager.runPreflightChecks()
        }
        .onChange(of: manager.prodKeysPath) { _, _ in
            manager.runPreflightChecks()
        }
    }

    private func pathPickerRow(
        title: String,
        subtitle: String,
        path: Binding<String>,
        chooseTitle: String,
        chooseDirectories: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(title)
                .font(.callout.weight(.medium))
            HStack(spacing: DesignSpacing.sm) {
                TextField("", text: path)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    choosePath(title: chooseTitle, initialPath: path.wrappedValue, chooseDirectories: chooseDirectories) { selected in
                        path.wrappedValue = selected
                    }
                }
                .buttonStyle(.bordered)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func choosePath(title: String, initialPath: String, chooseDirectories: Bool, onSelect: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = !chooseDirectories
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = chooseDirectories
        let trimmed = initialPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let initialURL = chooseDirectories
                ? URL(fileURLWithPath: trimmed)
                : URL(fileURLWithPath: trimmed).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: initialURL.path) {
                panel.directoryURL = initialURL
            }
        }
        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url.path)
        }
    }
}

#if DEBUG
#Preview("Onboarding Sheet") {
    let manager = BuildManager(previewGames: [])
    manager.preflightChecks = [
        PreflightCheckItem(id: "repo", title: "NXNative Repository", status: .failed, detail: "Folder not found", isRequired: true),
        PreflightCheckItem(id: "sources", title: "Game Sources Folder", status: .passed, detail: "/Games/_sources", isRequired: true)
    ]
    return OnboardingSetupSheet(manager: manager)
}
#endif
