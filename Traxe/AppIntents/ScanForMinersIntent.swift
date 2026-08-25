import AppIntents
import Foundation

// iOS 27's LongRunningIntent lets this scan run past the 30-second intent limit
// with system-managed progress surfaced as a Live Activity. Compiler-gated so
// the iOS 26 SDK (current App Store toolchain) still builds this target.
#if compiler(>=6.4)

    @available(iOS 27.0, *)
    struct ScanForMinersIntent: LongRunningIntent {
        static let title: LocalizedStringResource = "Scan for Miners"
        static let description = IntentDescription(
            "Scans your local network for Bitaxe miners and reports any that aren't saved yet."
        )
        static let openAppWhenRun = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            let hosts = Self.scannableHosts()
            guard !hosts.isEmpty else {
                return .result(
                    dialog: "Couldn't find a Wi-Fi network to scan. Connect to the network your miners are on."
                )
            }

            progress.totalUnitCount = Int64(hosts.count)

            let found: [(ip: String, name: String)] = try await performBackgroundTask {
                await withTaskGroup(of: (String, String)?.self) { group in
                    var results: [(String, String)] = []
                    var iterator = hosts.makeIterator()
                    var inFlight = 0
                    let maxConcurrent = 32

                    func addNext() {
                        guard let host = iterator.next() else { return }
                        inFlight += 1
                        group.addTask {
                            guard
                                let device = try? await DeviceManagementService.checkDevice(
                                    ip: host,
                                    timeout: 1.0,
                                    retryOnTimeout: false
                                )
                            else { return nil }
                            return (host, device.name)
                        }
                    }

                    for _ in 0..<maxConcurrent { addNext() }
                    while inFlight > 0 {
                        guard let result = await group.next() else { break }
                        inFlight -= 1
                        progress.completedUnitCount += 1
                        if let result { results.append(result) }
                        addNext()
                    }
                    return results
                }
            }

            let savedIPs = Set(TraxeIntentSupport.loadSavedDevices().map(\.ipAddress))
            let new = found.filter { !savedIPs.contains($0.ip) }

            if found.isEmpty {
                return .result(dialog: "Scan complete. No miners responded.")
            }
            if new.isEmpty {
                return .result(
                    dialog:
                        "Scan complete. Found \(found.count) miner\(found.count == 1 ? "" : "s"), all already saved."
                )
            }
            let names = new.map { "\($0.name) (\($0.ip))" }.joined(separator: ", ")
            return .result(
                dialog:
                    "Found \(new.count) new miner\(new.count == 1 ? "" : "s"): \(names). Open Traxe to add them."
            )
        }

        /// The /24 around this device's Wi-Fi address, minus our own IP.
        private static func scannableHosts() -> [String] {
            var ifaddr: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddr) == 0 else { return [] }
            defer { freeifaddrs(ifaddr) }

            var ownAddress: String?
            var ptr = ifaddr
            while let interface = ptr?.pointee {
                defer { ptr = interface.ifa_next }
                guard let addr = interface.ifa_addr,
                    addr.pointee.sa_family == UInt8(AF_INET),
                    let nameBytes = interface.ifa_name,
                    ["en0", "en1"].contains(String(cString: nameBytes))
                else { continue }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr, socklen_t(addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count),
                    nil, 0, NI_NUMERICHOST
                ) == 0 {
                    ownAddress = String(cString: hostname, encoding: .utf8)
                    break
                }
            }

            guard let ownAddress else { return [] }
            let octets = ownAddress.split(separator: ".")
            guard octets.count == 4 else { return [] }
            let base = octets.prefix(3).joined(separator: ".")
            return (1...254)
                .map { "\(base).\($0)" }
                .filter { $0 != ownAddress }
        }
    }

#endif
