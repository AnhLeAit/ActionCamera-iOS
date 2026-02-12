import Foundation

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
