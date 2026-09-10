import Foundation
@main struct GlobalLiveSmoke {
    static func main() async throws {
        let base = TencentClient()
        var securities: [Security] = []
        for term in ["510300", "920002", "00700", "AAPL"] {
            let found = try await base.search(term)
            let expected = ["510300": "SH.510300", "920002": "BJ.920002", "00700": "HK.00700", "AAPL": "US.AAPL"][term]!
            guard let security = found.first(where: { $0.id == expected }) else { throw MarketDataError.invalidResponse }
            securities.append(security)
            print("SEARCH", security.id, security.name, security.kind, security.quoteID ?? "Tencent only")
        }
        let client = MarketClient(tencent: base, preferred: .eastmoney, fallback: true, quoteIDs: Dictionary(uniqueKeysWithValues: securities.compactMap { s in s.quoteID.map { (s.id, $0) } }))
        let quotes = try await client.quotes(ids: securities.map(\.id))
        guard quotes.count == securities.count else { throw MarketDataError.invalidResponse }
        for security in securities {
            let q = quotes[security.id]!
            let series = try await client.minutes(id: security.id)
            print("QUOTE", security.id, q.price, q.currency, q.source.title, "MINUTE", series.points.count, series.day, series.zoneIdentifier, series.source.title)
            guard !series.points.isEmpty else { throw MarketDataError.invalidResponse }
        }
    }
}
