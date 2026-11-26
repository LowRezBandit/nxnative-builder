import SwiftUI

struct PreflightDiagnosticsView: View {
    @Bindable var manager: BuildManager

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            HStack {
                Text("Environment Health Check")
                    .font(.callout.weight(.medium))

                Spacer()

                if manager.isRunningPreflight {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Re-check") {
                    manager.runPreflightChecks()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isRunningPreflight)
                .help("Re-run environment diagnostics")
                .accessibilityLabel("Re-run environment health checks")
            }

            if manager.preflightChecks.isEmpty {
                if manager.isRunningPreflight {
                    HStack(spacing: DesignSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking environment…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DesignSpacing.xs)
                } else {
                    Text("Click Re-check to validate paths and build tools.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    ForEach(manager.preflightChecks) { item in
                        HStack(alignment: .top, spacing: DesignSpacing.sm) {
                            Image(systemName: item.status.iconName)
                                .foregroundStyle(item.status.color)
                                .font(.callout)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: DesignSpacing.xs) {
                                    Text(item.title)
                                        .font(.callout.weight(.medium))
                                    if !item.isRequired && item.status != .passed {
                                        Text("Optional")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Preflight — Mixed Results") {
    let manager = BuildManager(previewGames: [])
    manager.preflightChecks = [
        PreflightCheckItem(id: "repo", title: "NXNative Repository", status: .passed, detail: "Found scripts/build_ipa_from_nsp.py", isRequired: true),
        PreflightCheckItem(id: "keys", title: "Switch 1 Keys (prod.keys)", status: .warning, detail: "Not found (Switch 2 builds work without it)", isRequired: false),
        PreflightCheckItem(id: "python", title: "Python 3", status: .failed, detail: "Neither .venv/bin/python3 nor python3 on PATH was found", isRequired: true)
    ]
    return PreflightDiagnosticsView(manager: manager)
        .padding()
        .frame(width: 520)
}

#Preview("Preflight — Dark") {
    let manager = BuildManager(previewGames: [])
    manager.preflightChecks = [
        PreflightCheckItem(id: "repo", title: "NXNative Repository", status: .passed, detail: "Found scripts/build_ipa_from_nsp.py", isRequired: true)
    ]
    return PreflightDiagnosticsView(manager: manager)
        .padding()
        .frame(width: 520)
        .preferredColorScheme(.dark)
}
#endif
