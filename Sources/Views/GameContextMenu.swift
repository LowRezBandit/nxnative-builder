import SwiftUI

struct GameContextMenu: View {
    let game: GameEntry
    let manager: BuildManager

    var body: some View {
        GameMenuActions(
            game: game,
            manager: manager,
            includeBuildAction: true,
            showDisabledPlaceholders: true
        )
    }
}
