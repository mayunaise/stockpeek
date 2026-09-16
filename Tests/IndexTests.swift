import Foundation
final class IndexProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct IndexTests {
    @MainActor static func main() async throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/index-quotes-gb18030.txt"))
        let ids = ["SH.000001", "SZ.399001", "SZ.399006", "HK.HSI", "HK.HSTECH", "US..IXIC", "US..INX", "US..DJI"]
        let parsed = try TencentClient.parseQuotes(raw, requested: ids)
        precondition(parsed.count == 8 && parsed["US..INX"]!.price == 7636.36 && parsed["HK.HSI"]!.price == 24948.33)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [IndexProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        IndexProtocol.data = raw
        let suite = "IndexTests.\(UUID().uuidString)", defaults: UserDefaults
        defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var marketNow = MarketClock.date("20260910100000")!
        let store = IndexStore(clock: { marketNow }, defaults: defaults, client: TencentClient(session: session))
        store.configure(preferred: .tencent, fallback: false)
        precondition(store.securities.count == 3 && store.quotes.isEmpty)
        store.tick(visible: true)
        for _ in 0..<100 { if store.quotes.count == 3 { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(store.quotes.count == 3 && store.quoteError == nil)
        let requests = IndexProtocol.requests
        marketNow = MarketClock.date("20260910150000")!
        store.detailID = "SH.000001"
        store.tick(visible: true, now: Date().addingTimeInterval(120))
        try await Task.sleep(for: .milliseconds(50))
        precondition(IndexProtocol.requests == requests && store.closedIDs.count == 3, "Closed indices must not request quotes or minutes")
        store.detailID = nil
        marketNow = MarketClock.date("20260911093000")!
        store.tick(visible: true)
        for _ in 0..<100 { if IndexProtocol.requests > requests { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(IndexProtocol.requests > requests)
        let initial = store.currentID
        store.hovered = true; store.tick(visible: true, now: Date().addingTimeInterval(5))
        precondition(store.currentID == initial)
        store.hovered = false; store.tick(visible: true, now: Date().addingTimeInterval(5))
        precondition(store.currentID != initial)
        let index = Security.indexCatalog.first { $0.id == "US..IXIC" }!
        store.add(index); store.add(index)
        precondition(store.securities.count == 4)
        store.top(index.id)
        let restored = IndexStore(clock: { MarketClock.date("20260910100000")! }, defaults: defaults, client: TencentClient(session: session))
        precondition(restored.securities.first?.id == index.id && restored.securities.count == 4)
        let current = store.currentID
        store.detailID = index.id; store.tick(visible: true, now: Date().addingTimeInterval(20))
        precondition(store.currentID == current)
        store.suspend()
        for id in store.securities.map(\.id) { store.remove(id) }
        precondition(store.current == nil && store.detailID == nil)
        precondition(IndexStore(clock: { MarketClock.date("20260910100000")! }, defaults: defaults, client: TencentClient()).securities.isEmpty)
        marketNow = MarketClock.date("20260910180000")!
        let hsi = Security.indexCatalog.first { $0.id == "HK.HSI" }!
        store.add(hsi)
        store.add(index)
        store.tick(visible: false)
        for _ in 0..<100 {
            if store.quotes[hsi.id] != nil && store.quotes[index.id] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(store.quotes[hsi.id] != nil && store.quotes[index.id] != nil, "Closed index additions must fetch snapshots, including queued additions while hidden")
        try await Task.sleep(for: .milliseconds(50))
        let afterAdd = IndexProtocol.requests
        store.tick(visible: true, now: Date().addingTimeInterval(120))
        try await Task.sleep(for: .milliseconds(50))
        precondition(IndexProtocol.requests == afterAdd, "Adding indices must not enable closed-market polling")
        store.refreshCurrentPage()
        for _ in 0..<100 {
            if IndexProtocol.requests > afterAdd { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(IndexProtocol.requests == afterAdd + 1, "Manual refresh must request the visible index once during closed sessions")
        try await Task.sleep(for: .milliseconds(50))
        store.tick(visible: true, now: Date().addingTimeInterval(120))
        try await Task.sleep(for: .milliseconds(50))
        precondition(IndexProtocol.requests == afterAdd + 1, "Manual refresh must not enable closed-market polling")
        store.suspend()
        let bad = Data("broken".utf8); defaults.set(bad, forKey: "marketIndices")
        let corrupt = IndexStore(clock: { MarketClock.date("20260910100000")! }, defaults: defaults, client: TencentClient()); corrupt.add(index)
        precondition(corrupt.persistenceError != nil && defaults.data(forKey: "marketIndices") == bad)
        print("PASS: real index codes, quote decoding, hover pause, detail pause, custom order/persistence, empty and corrupt settings")
    }
}
