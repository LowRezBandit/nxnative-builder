import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var manager: BuildManager
    @AppStorage("showCombinedLog") private var showCombinedLog = false
    @State private var showCleanAllFoldersConfirm = false

    private var totalWorkFolderCount: Int {
        manager.games.reduce(0) { $0 + $1.workFolders.count }
    }

    var body: some View {
        PersistentSplitView(
            isVertical: true,
            autosaveName: "MainWindowHSplitView",
            defaultPosition: { $0.width / 2 },
            minFirstThickness: 550,
            minSecondThickness: 420
        ) {
            SidebarPaneView(
                manager: manager,
                showCleanAllFoldersConfirm: $showCleanAllFoldersConfirm
            )
        } second: {
            PersistentSplitView(
                isVertical: false,
                autosaveName: "RightPaneVSplitView",
                defaultPosition: { _ in DesignLayout.gameCardHeight },
                minFirstThickness: 140,
                minSecondThickness: 220
            ) {
                BuildQueueView(manager: manager, showCombinedLog: $showCombinedLog)
            } second: {
                LogPaneView(manager: manager, showCombinedLog: $showCombinedLog)
            }
        }
        .frame(minWidth: 1100, idealWidth: 1320, minHeight: 680)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !manager.isBuilding {
                manager.loadGames()
            }
        }
        .confirmationDialog(
            "Delete all build folders?",
            isPresented: $showCleanAllFoldersConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                manager.cleanAllBuildFolders()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(totalWorkFolderCount) *_build / *_survey folder(s) across all games to free disk space. They will be recreated on the next build.")
        }
        .confirmationDialog(
            "Delete build folders?",
            isPresented: Binding(
                get: { manager.pendingCleanFoldersGame != nil },
                set: { if !$0 { manager.pendingCleanFoldersGame = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let game = manager.pendingCleanFoldersGame {
                    manager.cleanBuildFolders(for: game)
                }
                manager.pendingCleanFoldersGame = nil
            }
            Button("Cancel", role: .cancel) {
                manager.pendingCleanFoldersGame = nil
            }
        } message: {
            if let game = manager.pendingCleanFoldersGame {
                let names = game.workFolders.map { $0.lastPathComponent }.joined(separator: ", ")
                Text("This will permanently delete \(names) in \(game.name) to free disk space. They will be recreated on the next build.")
            }
        }
        .confirmationDialog(
            "Move built .app to Trash?",
            isPresented: Binding(
                get: { manager.pendingCleanBuiltAppGame != nil },
                set: { if !$0 { manager.pendingCleanBuiltAppGame = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let game = manager.pendingCleanBuiltAppGame {
                    manager.cleanBuiltApps(for: game)
                }
                manager.pendingCleanBuiltAppGame = nil
            }
            Button("Cancel", role: .cancel) {
                manager.pendingCleanBuiltAppGame = nil
            }
        } message: {
            if let game = manager.pendingCleanBuiltAppGame {
                let names = game.builtAppURLs.map { $0.lastPathComponent }.joined(separator: ", ")
                Text("This will move \(names) to the Trash. Source files in _sources will not be affected.")
            }
        }
        .sheet(item: $manager.pendingEnvEditorGame) { game in
            EnvEditorSheet(game: game, manager: manager)
        }
        .sheet(isPresented: $manager.showOnboardingSheet) {
            OnboardingSetupSheet(manager: manager)
        }
    }
}

#if DEBUG
#Preview("Populated — Active Build") {
    ContentView(manager: .previewSample(isBuilding: true))
}

#Preview("Empty State — Dark Mode") {
    ContentView(manager: BuildManager(previewGames: []))
        .preferredColorScheme(.dark)
}
#endif
