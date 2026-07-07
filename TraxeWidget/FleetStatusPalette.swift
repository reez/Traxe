import SwiftUI

enum FleetStatusPalette {
    static let online = Color.traxeGold
    static let paused = Color.traxeGold.opacity(0.25)
    static let offline = Color(uiColor: .tertiaryLabel)
    static let unknown = Color.secondary
}
