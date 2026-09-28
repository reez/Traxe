import AppIntents
import Foundation

struct MinerEntityQuery: EntityStringQuery {
    private let savedDevicesLoader: @Sendable () -> [SavedDevice]
    private let subscriptionAccessPolicyResolver: @Sendable () async -> SubscriptionAccessPolicy
    private let currentIPAddressResolver: @Sendable (_ identifier: String) -> String

    init() {
        self.init(
            loadSavedDevices: { TraxeIntentSupport.loadSavedDevices() },
            resolveSubscriptionAccessPolicy: {
                await TraxeIntentSupport.resolveSubscriptionAccessPolicy()
            }
        )
    }

    init(
        loadSavedDevices: @escaping @Sendable () -> [SavedDevice],
        resolveSubscriptionAccessPolicy: @escaping @Sendable () async -> SubscriptionAccessPolicy,
        resolveCurrentIPAddress: @escaping @Sendable (_ identifier: String) -> String = {
            identifier in
            SavedDeviceAddressAliases.appGroup()?.currentAddress(for: identifier) ?? identifier
        }
    ) {
        self.savedDevicesLoader = loadSavedDevices
        self.subscriptionAccessPolicyResolver = resolveSubscriptionAccessPolicy
        self.currentIPAddressResolver = resolveCurrentIPAddress
    }

    /// Resolves the identifier a Shortcut stored: a MAC address for miners saved with
    /// one, otherwise an IP address that may since have moved. The stored identifier is
    /// kept on the entity so the Shortcut keeps working without being edited.
    func entities(for identifiers: [MinerEntity.ID]) async throws -> [MinerEntity] {
        let devices = savedDevicesLoader()

        return identifiers.compactMap { identifier in
            if let device = devices.first(where: { $0.macAddress == identifier }) {
                return MinerEntity(id: identifier, savedDevice: device)
            }

            let currentIPAddress = currentIPAddressResolver(identifier)
            guard let device = devices.first(where: { $0.ipAddress == currentIPAddress }) else {
                return nil
            }
            return MinerEntity(id: identifier, savedDevice: device)
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
