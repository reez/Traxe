import Foundation

struct ASICHashrateMonitor: Equatable, Hashable {
    let index: Int
    let total: Double
    let domains: [Double]
}
