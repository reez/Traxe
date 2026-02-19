import AppIntents
import Foundation

struct MinerEntityQuery: EntityStringQuery {
    func entities(for identifiers: [MinerEntity.ID]) async throws -> [MinerEntity] {
        let devices = await accessibleDevices()
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
        let allDevices = TraxeIntentSupport.loadSavedDevices()
        let accessPolicy = await TraxeIntentSupport.resolveSubscriptionAccessPolicy()
        return accessPolicy.accessibleDevices(from: allDevices)
    }
}
