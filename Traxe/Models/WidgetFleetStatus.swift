import Foundation

struct WidgetFleetStatus: Equatable {
    let total: Int
    let online: Int
    let paused: Int
    let offline: Int
    let unknown: Int

    static let empty = WidgetFleetStatus(
        total: 0,
        online: 0,
        paused: 0,
        offline: 0,
        unknown: 0
    )

    static func make(
        deviceIDs: [String],
        respondedDeviceIDs: Set<String>,
        deviceIDsWithMetrics: Set<String>,
        pausedDeviceIDs: Set<String>
    ) -> WidgetFleetStatus {
        var online = 0
        var paused = 0
        var offline = 0
        var unknown = 0

        for deviceID in deviceIDs {
            guard respondedDeviceIDs.contains(deviceID) else {
                offline += 1
                continue
            }

            guard deviceIDsWithMetrics.contains(deviceID) else {
                unknown += 1
                continue
            }

            if pausedDeviceIDs.contains(deviceID) {
                paused += 1
            } else {
                online += 1
            }
        }

        return WidgetFleetStatus(
            total: deviceIDs.count,
            online: online,
            paused: paused,
            offline: offline,
            unknown: unknown
        )
    }
}
