import AppIntents

struct TraxeShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetMinerStatusIntent(),
            phrases: [
                "How is \(\.$miner) doing in \(.applicationName)",
                "Check \(\.$miner) in \(.applicationName)",
                "What is the status of \(\.$miner) in \(.applicationName)",
            ],
            shortTitle: "Miner Status",
            systemImageName: "cpu"
        )

        AppShortcut(
            intent: GetFleetStatusIntent(),
            phrases: [
                "How are my miners doing in \(.applicationName)",
                "Check my miner fleet in \(.applicationName)",
                "What is my total hashrate in \(.applicationName)",
            ],
            shortTitle: "Fleet Status",
            systemImageName: "bolt.fill"
        )
    }
}
