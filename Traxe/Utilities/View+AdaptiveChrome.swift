import SwiftUI

extension View {
    /// The app's primary call-to-action button: Liquid Glass on iOS 26 and the
    /// bordered prominent style before that. Callers still apply `.tint`.
    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Pins `content` to the bottom edge as system chrome outside any scroll view:
    /// a Liquid Glass bar on iOS 26, and an opaque safe-area inset before that.
    @ViewBuilder
    func bottomActionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom) { content() }
        } else {
            safeAreaInset(edge: .bottom) {
                content()
                    .background(Color(.systemBackground))
            }
        }
    }
}
