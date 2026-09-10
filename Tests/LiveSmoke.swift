import Foundation

@main
struct LiveSmoke {
    static func main() async throws {
        let client = TencentClient()
        let ids = ["SH.600519", "SZ.300750", "SH.600036", "SZ.002594"]
        let quotes = try await client.quotes(ids: ids)
        guard quotes.count == 4 else { throw MarketDataError.invalidResponse }
        for id in ids {
            let q = quotes[id]!
            print("\(id) \(q.name) \(q.price) \(MarketClock.timestamp(q.sourceTime)) CST")
        }
        let series = try await client.minutes(id: ids[0])
        print("Live minute series: \(series.day), \(series.points.count) source points")
    }
}
