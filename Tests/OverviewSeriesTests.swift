import Foundation

final class OverviewProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var quotes = Data()
    nonisolated(unsafe) static var minuteText = ""
    nonisolated(unsafe) static var active = 0
    nonisolated(unsafe) static var maximum = 0
    nonisolated(unsafe) static var requests = 0
    private var work: DispatchWorkItem?
    private var counted = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let symbol = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
        if symbol != nil {
            Self.lock.lock(); Self.active += 1; Self.maximum = max(Self.maximum, Self.active); Self.requests += 1; counted = true; Self.lock.unlock()
        }
        let task = DispatchWorkItem { [self] in
            finishCount()
            let data = symbol.map { Data(Self.minuteText.replacingOccurrences(of: "sh600519", with: $0).utf8) } ?? Self.quotes
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        work = task
        DispatchQueue.global().asyncAfter(deadline: .now() + (symbol == nil ? 0 : 0.12), execute: task)
    }
    private func finishCount() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if counted { Self.active -= 1; counted = false }
    }
    override func stopLoading() { work?.cancel(); finishCount() }
}

@main
struct OverviewSeriesTests {
    @MainActor static func main() async throws {
        OverviewProtocol.quotes = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/tencent-quotes-gb18030.txt"))
        OverviewProtocol.minuteText = try String(contentsOfFile: "Tests/Fixtures/tencent-minutes.json", encoding: .utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OverviewProtocol.self]
        let session = URLSession(configuration: configuration)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: root) }
        let store = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: root.appendingPathComponent("one.json"), startTimer: true, client: TencentClient(session: session))
        store.openOverview()
        for _ in 0..<100 {
            if store.series.count == 4 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(store.series.count == 4, "Overview must fetch real minute series for every watchlist row")
        precondition(OverviewProtocol.maximum > 2 && OverviewProtocol.maximum <= 6, "Overview must bound concurrent minute requests")
        store.save()
        let cached = StockStore(clock: { MarketClock.date("20260910180000")! }, fileURL: root.appendingPathComponent("one.json"), startTimer: false, client: TencentClient(session: session))
        precondition(cached.series.count == 4 && cached.quotes.count == 4, "Quotes and minute charts must survive a closed-market restart")
        cached.openDetail("SH.600519")
        precondition(cached.series["SH.600519"]?.points.count == store.series["SH.600519"]?.points.count)
        let count = OverviewProtocol.requests
        store.openDetail("SH.600519")
        try await Task.sleep(for: .milliseconds(20))
        precondition(OverviewProtocol.requests == count, "Entering detail should reuse fresh overview cache")
        store.backToOverview()
        precondition(store.series.count == 4)
        store.collapse()
        store.sleeping = true
        let cancelled = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: root.appendingPathComponent("two.json"), startTimer: true, client: TencentClient(session: session))
        cancelled.openOverview()
        try await Task.sleep(for: .milliseconds(20))
        cancelled.collapse()
        try await Task.sleep(for: .milliseconds(200))
        precondition(cancelled.series.isEmpty, "A response after collapse must not revive cancelled overview work")
        cancelled.sleeping = true
        print("PASS: overview series for all stocks, concurrency cap, cache reuse, cancellation")
    }
}
