import Foundation

actor PoolBlockLookupService {
    private struct PoolBlockResponse: Decodable {
        let height: Int
    }

    private let session: URLSession
    private let baseURL = URL(string: "https://mempool.space/api")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestBlockHeights(for poolSlugs: [String]) async -> [String: Int] {
        let uniqueSlugs = Array(Set(poolSlugs)).sorted()
        guard !uniqueSlugs.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, Int?).self) { group in
            for poolSlug in uniqueSlugs {
                group.addTask { [session, baseURL] in
                    guard let baseURL else {
                        return (poolSlug, nil)
                    }

                    let url =
                        baseURL
                        .appending(path: "v1")
                        .appending(path: "mining")
                        .appending(path: "pool")
                        .appending(path: poolSlug)
                        .appending(path: "blocks")

                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5

                    do {
                        let (data, response) = try await session.data(for: request)
                        guard
                            let httpResponse = response as? HTTPURLResponse,
                            httpResponse.statusCode == 200
                        else {
                            return (poolSlug, nil)
                        }

                        let decoder = JSONDecoder()
                        let blocks = try decoder.decode([PoolBlockResponse].self, from: data)
                        return (poolSlug, blocks.first?.height)
                    } catch {
                        return (poolSlug, nil)
                    }
                }
            }

            var latestBlockHeights: [String: Int] = [:]
            for await (poolSlug, height) in group {
                guard let height else { continue }
                latestBlockHeights[poolSlug] = height
            }
            return latestBlockHeights
        }
    }
}
