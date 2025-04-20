import SwiftData
import SwiftUI
import WidgetKit

@main
struct TraxeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // Use AppStorage to automatically track if an IP is set
    @AppStorage("bitaxeIPAddress") private var bitaxeIPAddress: String = ""

    // Shared SwiftData model container
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HistoricalDataPoint.self  // Register your SwiftData model
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Handle container creation error more gracefully in production
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Create ViewModel instances here, injecting dependencies
    @StateObject private var dashboardViewModel: DashboardViewModel

    init() {
        let modelContext = sharedModelContainer.mainContext
        _dashboardViewModel = StateObject(
            wrappedValue: DashboardViewModel(modelContext: modelContext)
        )
    }

    var body: some Scene {
        WindowGroup {
            // Conditionally show Onboarding or Dashboard based on saved IP
            if bitaxeIPAddress.isEmpty {
                // Inject DashboardViewModel even into Onboarding for when it navigates
                OnboardingView(dashboardViewModel: dashboardViewModel)
            } else {
                // If IP exists, go straight to Dashboard
                // Wrap DashboardView in NavigationView if it's the root
                NavigationView {
                    DashboardView(viewModel: dashboardViewModel)
                        .onAppear {
                            // Only start fetching data when the dashboard appears and we have an IP
                            Task {
                                await dashboardViewModel.connect()
                            }
                        }
                }
                .navigationViewStyle(.stack)  // Consistent style
            }
        }
        .modelContainer(sharedModelContainer)  // Inject the container into the environment
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                print("App became active, reloading widget timeline.")
                WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
            }
        }
    }
}
