import SwiftUI

struct BuiltAppMenuItems: View {
    let builtApps: [URL]
    let revealSystemImage: String
    var showDisabledPlaceholders: Bool = false
    let manager: BuildManager

    var body: some View {
        if builtApps.isEmpty {
            if showDisabledPlaceholders {
                Button {} label: {
                    Label("Launch .app (Not Built)", systemImage: "play.fill")
                }
                .disabled(true)

                Button {} label: {
                    Label("Reveal .app in Finder", systemImage: revealSystemImage)
                }
                .disabled(true)
            }
        } else if builtApps.count == 1, let appURL = builtApps.first {
            Button {
                manager.launchApp(at: appURL)
            } label: {
                Label("Launch \(appURL.deletingPathExtension().lastPathComponent)", systemImage: "play.fill")
            }

            Button {
                manager.revealInFinder(appURL)
            } label: {
                Label("Reveal .app in Finder", systemImage: revealSystemImage)
            }
        } else {
            Menu {
                ForEach(builtApps, id: \.self) { appURL in
                    Button(appURL.deletingPathExtension().lastPathComponent) {
                        manager.launchApp(at: appURL)
                    }
                }
            } label: {
                Label("Launch .app", systemImage: "play.fill")
            }

            Menu {
                ForEach(builtApps, id: \.self) { appURL in
                    Button(appURL.deletingPathExtension().lastPathComponent) {
                        manager.revealInFinder(appURL)
                    }
                }
            } label: {
                Label("Reveal .app in Finder", systemImage: revealSystemImage)
            }
        }
    }
}

struct EditEnvMenuItem: View {
    let game: GameEntry
    let manager: BuildManager

    var body: some View {
        let hasTitleID = manager.effectiveTitleID(for: game) != nil
        Button {
            manager.pendingEnvEditorGame = game
        } label: {
            Label(hasTitleID ? "Edit env.txt…" : "Edit env.txt… (Title ID Required)", systemImage: "slider.horizontal.3")
        }
        .disabled(!hasTitleID)
    }
}

struct GameMenuActions: View {
    let game: GameEntry
    let manager: BuildManager
    var includeBuildAction: Bool = false
    var showDisabledPlaceholders: Bool = false

    var body: some View {
        let builtApps = game.builtAppURLs
        let workFolders = game.workFolders

        if includeBuildAction {
            if game.status == .building {
                Button(role: .destructive) {
                    manager.cancelQueueItem(id: game.id)
                } label: {
                    Label("Cancel Build", systemImage: "stop.fill")
                }
            } else {
                Button {
                    manager.buildSingle(game.id)
                } label: {
                    if manager.isBuilding {
                        Label(
                            game.status == .queued ? "Remove \(game.name) from Queue" : "Add \(game.name) to Queue",
                            systemImage: game.status == .queued ? "minus.circle" : "plus.circle"
                        )
                    } else {
                        Label("Build \(game.name)", systemImage: "hammer")
                    }
                }
            }

            Divider()
        }

        BuiltAppMenuItems(
            builtApps: builtApps,
            revealSystemImage: "arrow.up.forward.app",
            showDisabledPlaceholders: showDisabledPlaceholders,
            manager: manager
        )

        if includeBuildAction || !builtApps.isEmpty {
            Divider()
        }

        Button {
            manager.revealInFinder(game.folderURL)
        } label: {
            Label("Reveal Source Folder in Finder", systemImage: "folder")
        }

        EditEnvMenuItem(game: game, manager: manager)

        if showDisabledPlaceholders || !builtApps.isEmpty || !workFolders.isEmpty {
            Divider()

            if showDisabledPlaceholders || !builtApps.isEmpty {
                Button(role: .destructive) {
                    manager.pendingCleanBuiltAppGame = game
                } label: {
                    Label("Move Built .app to Trash…", systemImage: "trash")
                }
                .disabled(builtApps.isEmpty || manager.isBuilding)
            }

            if showDisabledPlaceholders || !workFolders.isEmpty {
                Button(role: .destructive) {
                    manager.pendingCleanFoldersGame = game
                } label: {
                    Label(
                        workFolders.isEmpty ? "Delete Build Folders…" : "Delete Build Folders (\(workFolders.count))…",
                        systemImage: "folder.badge.minus"
                    )
                }
                .disabled(workFolders.isEmpty || manager.isBuilding)
            }
        }
    }
}
