import SwiftUI
import WatchKit

@main
struct TraxeWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchBackgroundRefreshManager.self)
    private var refreshManager

    @State private var viewModel = HashrateViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
