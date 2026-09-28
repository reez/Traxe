//  Traxe
//
//  Created by Matthew Ramsden.
//

import AppIntents
import Observation
import RevenueCat
import SwiftData
import SwiftUI
import TipKit
import UserNotifications
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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var dashboardViewModel: DashboardViewModel
    private let notificationDelegate = MinerAlertNotificationDelegate()

    init() {
        // Register default settings
        UserDefaults.standard.register(defaults: [
            "ai_enabled": true
        ])

        // Moves the old global miner-alerts switch onto the miners saved at update time.
        MinerAlertPreferences.appGroup()?.migrateLegacyGlobalPreferenceIfNeeded()

        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_qmpDjLonGDKmmzmItMjeuLZLYLj")
        TraxeShortcutsProvider.updateAppShortcutParameters()
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
        _dashboardViewModel = State(
            initialValue: DashboardViewModel(modelContext: modelContext)
        )

        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            // Each branch owns its own navigation container: DeviceListView uses a
            // NavigationSplitView (sidebar + detail), OnboardingView a NavigationStack.
            Group {
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
