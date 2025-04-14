import SwiftData
import SwiftUI

@main
struct TraxeApp: App {
    // Shared SwiftData model container
    let sharedModelContainer: ModelContainer

    // Create ViewModel instances here, injecting dependencies
    @StateObject private var dashboardViewModel: DashboardViewModel
    // Use AppStorage to automatically track if an IP is set
    @AppStorage("bitaxeIPAddress") private var bitaxeIPAddress: String = ""

    init() {
        do {
            let schema = Schema([
                HistoricalDataPoint.self  // Register your SwiftData model
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            sharedModelContainer = container

            // Initialize ViewModel with the main context from the container
            // But don't start fetching data until we have an IP
            _dashboardViewModel = StateObject(
                wrappedValue: DashboardViewModel(
                    modelContext: container.mainContext
                )
            )

        } catch {
            // Handle container creation error more gracefully in production
            fatalError("Could not create ModelContainer: \(error)")
        }
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
    }
}
