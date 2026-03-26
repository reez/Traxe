import Foundation

enum PoolDisplayPresenter {
    static func makeRows(from poolDisplayName: String?) -> [PoolDisplayLineViewData] {
        guard let poolDisplayName else { return [] }

        return
            poolDisplayName
            .components(separatedBy: "\u{2022}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, segment in
                let logoName = PoolHostPresenter.metadata(from: segment)?.logoName

                return PoolDisplayLineViewData(
                    id: "\(index)-\(segment.lowercased())",
                    text: segment,
                    logoName: logoName
                )
            }
    }
}
