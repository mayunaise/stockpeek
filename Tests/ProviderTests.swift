import Foundation

final class ProviderProtocol: URLProtocol, @unchecked Sendable {
    // Small sanitized excerpts from the live responses verified on 2026-09-10.
    static let eastQuotes = Data(#"{"rc":0,"data":{"diff":[{"f2":1283.98,"f5":10701,"f6":1375928521.0,"f12":"600519","f13":1,"f14":"贵州茅台","f15":1294.99,"f16":1283.01,"f17":1291,"f18":1290.88,"f124":1789011078}]}}"#.utf8)
    static let eastMinutes = Data(#"{"rc":0,"data":{"code":"600519","market":1,"trends":["2026-09-10 09:30,1291,1291,1291,1291,90,11619000,1291","2026-09-10 09:31,1292,1293.60,1294.99,1291.99,337,43592205,1293.003"]}}"#.utf8)
    nonisolated(unsafe) static var eastFails = false
    nonisolated(unsafe) static var hosts: [String] = []
    nonisolated(unsafe) static var tencentQuotes = Data()
    nonisolated(unsafe) static var tencentMinutes = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        Self.hosts.append(host)
        let east = host.contains("eastmoney")
        if east && Self.eastFails { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
        let data = east ? (host == "push2.eastmoney.com" ? Self.eastQuotes : Self.eastMinutes) : (host == "qt.gtimg.cn" ? Self.tencentQuotes : Self.tencentMinutes)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct ProviderTests {
    @MainActor static func main() async throws {
        let parsed = try MarketClient.parseQuotes(ProviderProtocol.eastQuotes, requested: ["SH.600519"])["SH.600519"]!
        precondition(parsed.source == .eastmoney && parsed.price == 1283.98 && parsed.volumeLots == 10701)
        precondition(abs(parsed.turnoverWan! - 137592.8521) < 0.0001)
        let minutes = try MarketClient.parseMinutes(ProviderProtocol.eastMinutes, id: "SH.600519")
        precondition(minutes.source == .eastmoney && minutes.day == "20260910" && minutes.points.last!.price == 1293.6)
        do { _ = try MarketClient.parseMinutes(ProviderProtocol.eastMinutes, id: "SZ.600519"); preconditionFailure("Must reject wrong symbol") } catch {}
        do { _ = try MarketClient.parseQuotes(Data(#"{"rc":0,"data":null}"#.utf8), requested: ["SH.600519"]); preconditionFailure("Must reject empty payload") } catch {}
        ProviderProtocol.tencentQuotes = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/tencent-quotes-gb18030.txt"))
        ProviderProtocol.tencentMinutes = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/tencent-minutes.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let base = TencentClient(session: session)
        let client = MarketClient(tencent: base, preferred: .eastmoney, fallback: true)
        let quotes = try await client.quotes(ids: ["SH.600519", "SZ.300750"])
        precondition(quotes["SH.600519"]!.source == .eastmoney && quotes["SZ.300750"]!.source == .tencent, "Partial results should fill only missing IDs")
        ProviderProtocol.hosts = []
        let largeIDs = (0..<101).map { String(format: "SH.%06d", 600519 + $0) }
        _ = try await MarketClient(tencent: base, preferred: .tencent, fallback: false).quotes(ids: largeIDs)
        precondition(ProviderProtocol.hosts.count == 3, "101 symbols must be split into three bounded requests")
        ProviderProtocol.eastFails = true
        let backup = try await client.quotes(ids: ["SH.600519"])
        precondition(backup["SH.600519"]!.source == .tencent)
        let backupMinutes = try await client.minutes(id: "SH.600519")
        precondition(backupMinutes.source == .tencent)
        ProviderProtocol.hosts = []
        do { _ = try await MarketClient(tencent: base, preferred: .eastmoney, fallback: false).quotes(ids: ["SH.600519"]); preconditionFailure("Fallback off must surface error") } catch {}
        precondition(ProviderProtocol.hosts == ["push2.eastmoney.com"])
        let suite = "ProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: path, defaults: defaults, startTimer: false, client: base)
        await store.reloadQuotes()
        precondition(!store.quotes.isEmpty)
        store.preferredProvider = .eastmoney
        precondition(store.quotes.isEmpty && store.series.isEmpty && store.lastSuccess == nil)
        store.fallbackEnabled = true
        let restored = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: path, defaults: defaults, startTimer: false)
        precondition(restored.preferredProvider == .eastmoney && restored.fallbackEnabled)
        print("PASS: provider fields/units, symbol isolation, partial/full fallback, fallback off, source reset and persistence")
    }
}
