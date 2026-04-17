import AppIntents
import Foundation

struct MinerEntityQuery: EntityStringQuery {
    private let savedDevicesLoader: @Sendable () -> [SavedDevice]
    private let subscriptionAccessPolicyResolver: @Sendable () async -> SubscriptionAccessPolicy

    init() {
        self.savedDevicesLoader = { TraxeIntentSupport.loadSavedDevices() }
        self.subscriptionAccessPolicyResolver = {
            await TraxeIntentSupport.resolveSubscriptionAccessPolicy()
        }
    }

    init(
        loadSavedDevices: @escaping @Sendable () -> [SavedDevice],
        resolveSubscriptionAccessPolicy: @escaping @Sendable () async -> SubscriptionAccessPolicy
    ) {
        self.savedDevicesLoader = loadSavedDevices
        self.subscriptionAccessPolicyResolver = resolveSubscriptionAccessPolicy
    }

    func entities(for identifiers: [MinerEntity.ID]) async throws -> [MinerEntity] {
        let devices = savedDevicesLoader()
        let deviceByIPAddress = Dictionary(uniqueKeysWithValues: devices.map { ($0.ipAddress, $0) })

        return identifiers.compactMap { identifier in
            guard let device = deviceByIPAddress[identifier] else {
                return nil
            }
            return MinerEntity(savedDevice: device)
        }
    }

    func entities(matching string: String) async throws -> [MinerEntity] {
        let devices = await accessibleDevices()
        guard !string.isEmpty else {
            return devices.map(MinerEntity.init(savedDevice:))
        }

        return
            devices
            .filter { device in
                device.name.localizedStandardContains(string)
                    || device.ipAddress.localizedStandardContains(string)
            }
            .map(MinerEntity.init(savedDevice:))
    }

    func suggestedEntities() async throws -> [MinerEntity] {
        let devices = await accessibleDevices()
        return devices.map(MinerEntity.init(savedDevice:))
    }

    private func accessibleDevices() async -> [SavedDevice] {
        let allDevices = savedDevicesLoader()
        let accessPolicy = await subscriptionAccessPolicyResolver()
        return accessPolicy.accessibleDevices(from: allDevices)
    }
}
