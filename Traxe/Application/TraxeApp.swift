//  Traxe
//
//  Created by Matthew Ramsden.
//

import RevenueCat
import SwiftData
import SwiftUI
import TipKit
import WidgetKit

@main
struct TraxeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HistoricalDataPoint.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \\(error)")
        }
    }()

    @StateObject private var dashboardViewModel: DashboardViewModel

    init() {
        // Register default settings
        UserDefaults.standard.register(defaults: [
            "ai_enabled": true
        ])

        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_qmpDjLonGDKmmzmItMjeuLZLYLj")
        Task {
            do {
                _ = try await Purchases.shared.syncPurchases()
            } catch {
                // Log and continue—syncPurchases failures aren’t fatal but help with debugging
            }
        }

        #if os(iOS)
            _ = WatchSyncManager.shared
        #endif

        let modelContext = sharedModelContainer.mainContext
        _dashboardViewModel = StateObject(
            wrappedValue: DashboardViewModel(modelContext: modelContext)
        )
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if hasCompletedOnboarding {
                    DeviceListView(
                        dashboardViewModel: dashboardViewModel,
                        navigateToDeviceList: $hasCompletedOnboarding
                    )
                } else {
                    OnboardingView(dashboardViewModel: dashboardViewModel)
                }
            }
            .id(hasCompletedOnboarding)
            .modelContainer(sharedModelContainer)
            .task {
                //                #if DEBUG
                //                                    /// Optionally, call `Tips.resetDatastore()` before `Tips.configure()` to reset the state of all tips. This will allow tips to re-appear even after they have been dismissed by the user.
                //                                    /// This is for testing only, and should not be enabled in release builds.
                //                                    try? Tips.resetDatastore()
                //                #endif
                try? Tips.configure(
                    [
                        .datastoreLocation(.applicationDefault),
                        .displayFrequency(.immediate),
                    ]
                )
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
                }
            }
        }
    }
}
