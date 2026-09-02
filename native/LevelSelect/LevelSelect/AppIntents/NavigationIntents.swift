import AppIntents
import SwiftData

/// A top-level section of the app, for the "Open …" shortcuts.
enum LSSection: String, AppEnum {
    /// Raw values are the Shortcuts identifiers — see `LSTab`.
    case home, library, wishlist, journal = "stats"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Section")
    }
    static var caseDisplayRepresentations: [LSSection: DisplayRepresentation] {
        [.home: "Home", .library: "Library", .wishlist: "Wishlist", .journal: "Journal"]
    }

    var tab: LSTab {
        switch self {
        case .home: .home
        case .library: .library
        case .wishlist: .wishlist
        case .journal: .journal
        }
    }
}

/// Open the app to a specific section (Library / Wishlist / Stats / Home).
struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Section"
    static let description = IntentDescription("Opens LevelSelect to a section.")
    static let openAppWhenRun = true

    @Parameter(title: "Section")
    var section: LSSection

    init() {}
    init(_ section: LSSection) { self.section = section }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.go(to: section.tab)
        return .result()
    }
}

/// Open a specific game's page.
struct OpenGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Game"
    static let description = IntentDescription("Opens a game in LevelSelect.")
    static let openAppWhenRun = true

    @Parameter(title: "Game")
    var game: GameEntity

    init() {}
    init(game: GameEntity) { self.game = game }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: game.id) {
            AppNavigator.shared.open(gameID: id)
        }
        return .result()
    }
}

/// Open the game you're currently playing (or most recently played).
struct ContinuePlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Playing"
    static let description = IntentDescription("Opens your current game.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.continuePlaying()
        return .result()
    }
}

/// Start (or resume) a play session for a game — runs in the background,
/// no need to open the app.
struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription("Starts a play session for a game.")
    static let openAppWhenRun = false

    @Parameter(title: "Game")
    var game: GameEntity

    init() {}
    init(game: GameEntity) { self.game = game }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SessionIntentHandler.startSession(gameIDString: game.id)
        return .result(dialog: "Started a session for \(game.name).")
    }
}
