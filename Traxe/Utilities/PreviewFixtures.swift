import Foundation
import SwiftData

struct SettingsPreviewContext {
    let container: ModelContainer
    let viewModel: SettingsViewModel
}

struct DashboardPreviewContext {
    let container: ModelContainer
    let viewModel: DashboardViewModel
}

enum PreviewFixtures {
    static let sampleDeviceID = "192.168.1.101"
    static let sampleSecondaryDeviceID = "192.168.1.102"
    static let sampleDualPoolName = "mine.ocean.xyz (65%) • publicpool.io (35%)"
    static let sampleAISummary = AISummary(
        content:
            "Fleet is steady at 6.6 TH/s, temperatures are holding in the low 60s, and power draw remains consistent."
    )
    static let sampleLatestBlockHeightsByPoolSlug: [String: Int] = [
        "ocean": 941_416,
        "publicpool": 839_405,
    ]

    static let sampleSavedDevices = [
        SavedDevice(name: "nerdqaxe++", ipAddress: sampleDeviceID),
        SavedDevice(name: "bitaxe", ipAddress: sampleSecondaryDeviceID),
        SavedDevice(name: "garage", ipAddress: "192.168.1.103"),
    ]

    static let sampleDeviceMetricsByIP: [String: DeviceMetrics] = [
        sampleDeviceID: DeviceMetrics(
            hashrate: 5_100,
            expectedHashrate: 5_250,
            temperature: 61,
            power: 610,
            uptime: 36 * 60 * 60,
            fanSpeedPercent: 84,
            bestDifficulty: 1_250,
            inputVoltage: 12.1,
            asicVoltage: 1.2,
            measuredVoltage: 1.2,
            frequency: 525,
            sharesAccepted: 1_240,
            poolURL: sampleDualPoolName,
            hostname: "nerdqaxe++",
            blockHeight: 941_416,
            networkDifficulty: 83_250_000_000_000,
            blockFound: 1
        ),
        sampleSecondaryDeviceID: DeviceMetrics(
            hashrate: 720,
            expectedHashrate: 735,
            temperature: 64,
            power: 18,
            uptime: 18 * 60 * 60,
            fanSpeedPercent: 78,
            bestDifficulty: 598.7,
            inputVoltage: 12.0,
            asicVoltage: 1.1,
            measuredVoltage: 1.1,
            frequency: 490,
            sharesAccepted: 985,
            poolURL: "publicpool.io",
            hostname: "bitaxe",
            blockHeight: 941_405,
            networkDifficulty: 83_250_000_000_000
        ),
        "192.168.1.103": DeviceMetrics(
            hashrate: 430,
            expectedHashrate: 450,
            temperature: 69,
            power: 16,
            uptime: 12 * 60 * 60,
            fanSpeedPercent: 82,
            bestDifficulty: 412.2,
            inputVoltage: 11.9,
            asicVoltage: 1.0,
            measuredVoltage: 1.0,
            frequency: 450,
            sharesAccepted: 754,
            poolURL: "solo.ckpool.org",
            hostname: "garage",
            blockHeight: 941_400,
            networkDifficulty: 83_250_000_000_000
        ),
    ]

    static let sampleSubscriptionAccessPolicy = SubscriptionAccessPolicy(
        proIsActive: false,
        miners5IsActive: true,
        hasLoadedSubscription: true
    )

    static let sampleLockedSubscriptionAccessPolicy = SubscriptionAccessPolicy(
        proIsActive: false,
        miners5IsActive: false,
        hasLoadedSubscription: true
    )

    static var sampleReachableIPs: Set<String> {
        Set(sampleDeviceMetricsByIP.keys)
    }

    static var samplePoolRows: [PoolDisplayLineViewData] {
        PoolDisplayPresenter.makeRows(from: sampleDualPoolName)
    }

    static var sampleDeviceListItemViewData: DeviceListItemViewData {
        DeviceListItemPresenter.makeViewData(
            device: sampleSavedDevices[0],
            metrics: sampleDeviceMetricsByIP[sampleDeviceID],
            index: 0,
            reachableIPs: sampleReachableIPs,
            isLoadingAggregatedStats: false,
            subscriptionAccessPolicy: sampleSubscriptionAccessPolicy,
            bestDifficultyRank: 1,
            sortOption: .scoreboard
        )
    }

    static var sampleLockedDeviceListItemViewData: DeviceListItemViewData {
        DeviceListItemPresenter.makeViewData(
            device: sampleSavedDevices[2],
            metrics: sampleDeviceMetricsByIP["192.168.1.103"],
            index: 2,
            reachableIPs: sampleReachableIPs,
            isLoadingAggregatedStats: false,
            subscriptionAccessPolicy: sampleLockedSubscriptionAccessPolicy,
            bestDifficultyRank: 3,
            sortOption: .scoreboard
        )
    }

    static func sampleHistoricalData(
        deviceId: String = sampleDeviceID,
        pointCount: Int = 24
    ) -> [HistoricalDataPoint] {
        let now = Date()
        let calendar = Calendar.current

        return (0..<pointCount).map { index in
            let timestamp =
                calendar.date(byAdding: .hour, value: index - (pointCount - 1), to: now) ?? now
            let hashrateDrift = Double((index % 6) - 3) * 22
            let temperatureDrift = Double((index % 5) - 2)

            return HistoricalDataPoint(
                timestamp: timestamp,
                hashrate: 720 + hashrateDrift,
                temperature: 63 + temperatureDrift,
                deviceId: deviceId
            )
        }
    }

    static func sampleWeeklyRecap(
        deviceId: String = sampleDeviceID,
        baseHashrate: Double = 720,
        baseTemperature: Double = 63
    ) -> WeeklyRecap {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let samples: [WeeklyRecapSample] = (0..<7).flatMap { dayOffset in
            (0..<3).map { sampleIndex in
                let timestamp =
                    calendar.date(
                        byAdding: .hour,
                        value: (dayOffset - 6) * 24 + (sampleIndex * 5),
                        to: today
                    ) ?? today
                let hashrateDrift = Double((dayOffset + sampleIndex) % 4 - 1) * 18
                let temperatureDrift = Double((dayOffset + sampleIndex) % 3 - 1)

                return WeeklyRecapSample(
                    timestamp: timestamp,
                    hashrate: baseHashrate + hashrateDrift,
                    temperature: baseTemperature + temperatureDrift
                )
            }
        }

        guard let recap = WeeklyRecapBuilder.build(from: samples, now: now, calendar: calendar)
        else {
            fatalError("Failed to build weekly recap preview for \(deviceId)")
        }

        return recap
    }

    static var sampleWeeklyRecapPoints: [WeeklyRecapPoint] {
        sampleWeeklyRecap().dailyPoints.filter { $0.sampleCount > 0 }
    }

    static var sampleFleetRecaps: [WeeklyRecapFleetRecap] {
        [
            WeeklyRecapFleetRecap(
                id: sampleDeviceID,
                name: "nerdqaxe++",
                poolName: sampleDualPoolName,
                currentHashrate: 5_100,
                recap: sampleWeeklyRecap(
                    deviceId: sampleDeviceID,
                    baseHashrate: 5_100,
                    baseTemperature: 61
                )
            ),
            WeeklyRecapFleetRecap(
                id: sampleSecondaryDeviceID,
                name: "bitaxe",
                poolName: "publicpool.io",
                currentHashrate: 720,
                recap: sampleWeeklyRecap(
                    deviceId: sampleSecondaryDeviceID,
                    baseHashrate: 720,
                    baseTemperature: 64
                )
            ),
        ]
    }

    static var sampleFleetScope: WeeklyRecapView.Scope {
        .fleet(
            devices: [
                WeeklyRecapFleetDevice(
                    id: sampleDeviceID,
                    name: "nerdqaxe++",
                    poolName: sampleDualPoolName,
                    currentHashrate: 5_100
                ),
                WeeklyRecapFleetDevice(
                    id: sampleSecondaryDeviceID,
                    name: "bitaxe",
                    poolName: "publicpool.io",
                    currentHashrate: 720
                ),
            ]
        )
    }

    static var sampleFleetPoolAllocations: [WeeklyRecapPoolAllocation] {
        WeeklyRecapPoolAllocationBuilder.buildFleetTotals(
            from: sampleFleetRecaps.map { recap in
                (
                    poolDisplayName: recap.poolName,
                    totalHashrate: recap.recap?.averageHashrate ?? recap.currentHashrate
                )
            }
        )
    }

    @MainActor
    static func makeSettingsPreviewContext(
        configure: (SettingsViewModel) -> Void = { _ in }
    ) -> SettingsPreviewContext {
        let container = makeModelContainer()
        let suiteName = "preview.settings.\(UUID().uuidString)"
        let sharedDefaults = UserDefaults(suiteName: suiteName)
        sharedDefaults?.removePersistentDomain(forName: suiteName)

        let viewModel = SettingsViewModel(
            sharedUserDefaults: sharedDefaults,
            modelContext: container.mainContext
        )
        viewModel.bitaxeIPAddress = sampleDeviceID
        viewModel.currentVersion = "v2.6.0"
        viewModel.fanSpeed = 72
        viewModel.isAutoFan = false
        viewModel.minimumFanSpeed = 35
        viewModel.isConnected = true
        viewModel.hostname = "nerdqaxe"
        viewModel.stratumUser = "traxe.worker"
        viewModel.stratumURL = "mine.ocean.xyz"
        viewModel.stratumPortString = "3333"
        viewModel.fallbackStratumUser = "traxe.backup"
        viewModel.fallbackStratumURL = "publicpool.io"
        viewModel.fallbackStratumPortString = "21496"
        viewModel.poolBalance = 65
        viewModel.poolMode = 1
        viewModel.isDualPool = true
        configure(viewModel)

        return SettingsPreviewContext(container: container, viewModel: viewModel)
    }

    @MainActor
    static func makeDashboardPreviewContext(
        deviceId: String = sampleDeviceID,
        metrics: DeviceMetrics? = nil
    ) -> DashboardPreviewContext {
        let container = makeModelContainer()
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(
                    fetchSystemInfo: { _ in throw NetworkError.configurationMissing }
                ),
                selectedDeviceID: { deviceId },
                notificationCenter: .default,
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { _ in },
                pollingInterval: .seconds(5)
            )
        )

        #if DEBUG
            viewModel.seedPreviewData(
                deviceId: deviceId,
                metrics: metrics ?? sampleDeviceMetricsByIP[deviceId] ?? .placeholder,
                historical: sampleHistoricalData(deviceId: deviceId)
            )
        #endif

        return DashboardPreviewContext(container: container, viewModel: viewModel)
    }

    @MainActor
    static func makeDeviceListViewModel() -> DeviceListViewModel {
        let suiteName = "preview.device-list.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let viewModel = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { ip in
                        let metrics = sampleDeviceMetricsByIP[ip] ?? .placeholder
                        return DiscoveredDevice(
                            ip: ip,
                            name: metrics.hostname ?? "Preview Miner",
                            hashrate: metrics.hashrate,
                            temperature: metrics.temperature,
                            bestDiff: "\(metrics.bestDifficulty)",
                            power: metrics.power,
                            poolURL: metrics.poolURL,
                            blockHeight: metrics.blockHeight,
                            networkDifficulty: metrics.networkDifficulty
                        )
                    },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        viewModel.savedDevices = sampleSavedDevices
        viewModel.deviceMetrics = sampleDeviceMetricsByIP
        viewModel.reachableIPs = sampleReachableIPs
        viewModel.totalHashRate = sampleDeviceMetricsByIP.values.reduce(0) { $0 + $1.hashrate }
        viewModel.totalPower = sampleDeviceMetricsByIP.values.reduce(0) { $0 + $1.power }
        viewModel.bestOverallDiff = sampleDeviceMetricsByIP.values.map(\.bestDifficulty).max() ?? 0
        viewModel.fleetAISummary = AISummaryFormatter.fleetSummary(
            from: Array(sampleDeviceMetricsByIP.values)
        )

        return viewModel
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: HistoricalDataPoint.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Failed to create preview model container: \(error)")
        }
    }
}
