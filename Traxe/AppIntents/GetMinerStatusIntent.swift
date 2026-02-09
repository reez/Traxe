import AppIntents
import Foundation

struct GetMinerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Miner Status"

    static var description = IntentDescription(
        "Checks how one specific miner is doing right now."
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Miner")
    var miner: MinerEntity

    init() {}

    init(miner: MinerEntity) {
        self.miner = miner
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let allDevices = TraxeIntentSupport.loadSavedDevices()
        guard !allDevices.isEmpty else {
            return .result(dialog: "You do not have any miners saved in Traxe yet.")
        }

        guard let targetDevice = allDevices.first(where: { $0.ipAddress == miner.id }) else {
            return .result(dialog: "I could not find that miner in Traxe.")
        }

        let accessPolicy = await TraxeIntentSupport.resolveSubscriptionAccessPolicy()
        let accessibleDevices = accessPolicy.accessibleDevices(from: allDevices)

        guard accessibleDevices.contains(where: { $0.ipAddress == targetDevice.ipAddress }) else {
            return .result(
                dialog: "That miner is outside your current plan. Open Traxe to manage access."
            )
        }

        do {
            let systemInfo = try await NetworkService().fetchSystemInfo(
                ipAddressOverride: targetDevice.ipAddress
            )
            let metrics = DeviceMetrics(from: systemInfo)

            let formattedHashrate = metrics.hashrate.formattedHashRateWithUnit()
            let formattedPower = metrics.power.formatted(.number.precision(.fractionLength(1)))
            let formattedTemperature = metrics.temperature.formatted(
                .number.precision(.fractionLength(1))
            )
            let formattedUptime = TraxeIntentSupport.formattedUptime(from: metrics.uptime)

            return .result(
                dialog:
                    "\(targetDevice.name) is at \(formattedHashrate.value) \(formattedHashrate.unit), \(formattedTemperature) degrees Celsius, \(formattedPower) watts, uptime \(formattedUptime)."
            )
        } catch {
            return .result(
                dialog:
                    "I could not reach \(targetDevice.name) at \(targetDevice.ipAddress) right now."
            )
        }
    }
}
