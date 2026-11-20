import Foundation

enum AppRoute: String, CaseIterable, Hashable, Identifiable, Sendable {
    case overview
    case capture
    case gallery

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: L10n.text("Übersicht")
        case .capture: L10n.text("Erfassen")
        case .gallery: L10n.text("Galerie")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "list.bullet.rectangle"
        case .capture: "square.and.pencil"
        case .gallery: "square.grid.2x2"
        }
    }

    static let primary: [AppRoute] = [.overview, .gallery, .capture]
}
