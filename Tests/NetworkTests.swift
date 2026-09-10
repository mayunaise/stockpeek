import Foundation

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var failure: Error?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct NetworkTests {
    @MainActor static func main() async throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/tencent-quotes-gb18030.txt"))
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "NetworkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        var marketNow = MarketClock.date("20260910100000")!
        let store = StockStore(clock: { marketNow }, fileURL: root.appendingPathComponent("watchlist.json"), defaults: defaults, startTimer: false, client: TencentClient(session: session))
        FixtureProtocol.responseData = raw
        await store.reloadQuotes()
        assert(store.quotes.count == 4 && store.quoteError == nil)
        assert(store.quotes["SH.600519"]?.price == 1285.57)
        let time = store.quotes["SH.600519"]!.sourceTime
        // An older response must never overwrite the observed current price.
        let fields = ["1", "贵州茅台", "600519", "999", "1290.88", "1291"] + Array(repeating: "0", count: 24) + ["20260909105512", "0", "0", "1295", "1283", "", "100", "100"]
        FixtureProtocol.responseData = Data(("v_sh600519=\"" + fields.joined(separator: "~") + "\";").utf8)
        await store.reloadQuotes()
        assert(store.quotes["SH.600519"]?.price == 1285.57 && store.quotes["SH.600519"]?.sourceTime == time)
        assert(store.missingIDs.contains("SZ.300750"), "Missing symbols must be marked, not silently presented as updated")
        FixtureProtocol.failure = URLError(.notConnectedToInternet)
        await store.reloadQuotes()
        assert(store.quoteError != nil && store.quotes["SH.600519"]?.price == 1285.57)
        assert(store.status(for: "SH.600519") == "连接中断")
        FixtureProtocol.failure = nil
        FixtureProtocol.responseData = raw
        await store.reloadQuotes()
        assert(store.quoteError == nil && store.missingIDs.isEmpty)
        assert(store.status(for: "SH.600519", now: time.addingTimeInterval(100)) == "较早报价")
        assert(store.status(for: "SH.600519", now: time.addingTimeInterval(5)) == "已更新")
        store.save()
        let cachedStore = StockStore(clock: { MarketClock.date("20260910180000")! }, fileURL: root.appendingPathComponent("watchlist.json"), defaults: defaults, startTimer: false, client: TencentClient(session: session))
        let beforeRestore = FixtureProtocol.requests
        await cachedStore.reloadQuotes()
        precondition(FixtureProtocol.requests == beforeRestore && cachedStore.quotes["SH.600519"]?.price == 1285.57)
        precondition(cachedStore.quotes["SH.600519"]?.sourceTime == time && cachedStore.status(for: "SH.600519") == "休市中")
        let beforeClose = FixtureProtocol.requests
        marketNow = MarketClock.date("20260910150000")!
        await store.reloadQuotes()
        precondition(FixtureProtocol.requests == beforeClose && store.status(for: "SH.600519") == "休市中")
        precondition(store.quotes["SH.600519"]?.price == 1285.57 && !store.needsAttention("SH.600519"))
        marketNow = MarketClock.date("20260911093000")!
        await store.reloadQuotes()
        precondition(FixtureProtocol.requests == beforeClose + 1, "Next open resumes quotes")
        let beforeStartup = FixtureProtocol.requests
        let startup = StockStore(clock: { MarketClock.date("20260910180000")! }, fileURL: root.appendingPathComponent("startup.json"), defaults: defaults, startTimer: true, client: TencentClient(session: session))
        for _ in 0..<100 { if !startup.quotes.isEmpty && FixtureProtocol.requests >= beforeStartup + 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(startup.quotes.count == 4, "Closed startup must fetch a fresh snapshot once")
        try await Task.sleep(for: .milliseconds(100))
        let afterStartup = FixtureProtocol.requests
        startup.refresh(); startup.requestRefresh()
        try await Task.sleep(for: .milliseconds(100))
        precondition(FixtureProtocol.requests == afterStartup, "Closed startup snapshot must not become polling")
        startup.sleeping = true
        print("PASS: real client/store boundary, partial response, older response isolation, offline cache, recovery, freshness")
    }
}
