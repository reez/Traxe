import AppIntents
import Foundation

struct GetFleetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Fleet Status"

    static var description = IntentDescription(
        "Checks how all of your accessible miners are doing right now."
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let allDevices = TraxeIntentSupport.loadSavedDevices()
        guard !allDevices.isEmpty else {
            return .result(dialog: "You do not have any miners saved in Traxe yet.")
        }

        let accessPolicy = await TraxeIntentSupport.resolveSubscriptionAccessPolicy()
        let accessibleDevices = accessPolicy.accessibleDevices(from: allDevices)
        guard !accessibleDevices.isEmpty else {
            return .result(dialog: "I could not find any accessible miners to check.")
        }

        let discoveredDevices = await withTaskGroup(of: DiscoveredDevice?.self) { group in
            for device in accessibleDevices {
                group.addTask {
                    do {
                        return try await DeviceManagementService.checkDevice(
                            ip: device.ipAddress,
                            timeout: 2.0,
                            retryOnTimeout: false
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var discovered: [DiscoveredDevice] = []
            for await result in group {
                guard let result else { continue }
                discovered.append(result)
            }
            return discovered
        }

        let onlineCount = discoveredDevices.count
        let totalCheckedCount = accessibleDevices.count
        guard onlineCount > 0 else {
            return .result(
                dialog:
                    "I could not reach any of your \(totalCheckedCount) checked miners right now."
            )
        }

        let totalHashrate = discoveredDevices.reduce(0.0) { $0 + $1.hashrate }
        let totalPower = discoveredDevices.reduce(0.0) { $0 + $1.power }
        let formattedHashrate = totalHashrate.formattedHashRateWithUnit()
        let formattedPower = totalPower.formatted(.number.precision(.fractionLength(1)))

        let coveragePrefix: String
        if accessPolicy.hasLoadedSubscription && totalCheckedCount < allDevices.count {
            coveragePrefix =
                "I checked \(totalCheckedCount) miners available on your current plan. "
        } else {
            coveragePrefix = ""
        }

        return .result(
            dialog:
                "\(coveragePrefix)\(onlineCount) of \(totalCheckedCount) miners are online. Total hashrate is \(formattedHashrate.value) \(formattedHashrate.unit) at \(formattedPower) watts."
        )
    }
}
