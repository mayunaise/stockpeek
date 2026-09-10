import Foundation
import Combine

private struct MinuteFetchResult: Sendable {
    let id: String
    let result: Result<MinuteSeries, Error>
}

@MainActor
final class StockStore: ObservableObject {
    @Published var watchlist: WatchlistState
    @Published private(set) var quotes: [String: QuoteSnapshot] = [:]
    @Published private(set) var series: [String: MinuteSeries] = [:]
    @Published private(set) var detailID: String?
    @Published private(set) var quoteError: String?
    @Published private(set) var minuteErrors: [String: String] = [:]
    @Published private(set) var loadingMinuteIDs = Set<String>()
    var minuteError: String? { detailID.flatMap { minuteErrors[$0] } }
    @Published private(set) var missingIDs = Set<String>()
    @Published private(set) var isFetching = false
    @Published private(set) var loadingMinutes = false
    @Published private(set) var lastSuccess: Date?
    let indices: IndexStore
    @Published var showingIndices = false
    @Published var showingSearch = false
    @Published var expanded = false
    @Published var pinned = false
    @Published var hovered = false
    @Published var paused = false
    @Published var hidden = false
    @Published var sleeping = false {
        didSet {
            if sleeping { quoteTask?.cancel(); cancelMinutes(); indices.suspend() }
            else { nextQuotePoll = .distantPast; refresh() }
        }
    }
    @Published var persistenceError: String?
    @Published var interval: Double = 4 {
        didSet { defaults.set(interval, forKey: "rotationInterval"); lastRotation = Date() }
    }
    @Published var redUp = true { didSet { defaults.set(redUp, forKey: "redUp") } }
    @Published var showFullscreen = false { didSet { defaults.set(showFullscreen, forKey: "showFullscreen") } }
    @Published var reduceMotion = false { didSet { defaults.set(reduceMotion, forKey: "reduceMotion") } }
    @Published var preferredProvider: QuoteProvider = .eastmoney { didSet { if oldValue != preferredProvider { resetProvider() } } }
    @Published var fallbackEnabled = true { didSet { if oldValue != fallbackEnabled { resetProvider() } } }
    private var providerGeneration = UUID()
    private var marketClient: MarketClient { MarketClient(tencent: client, preferred: preferredProvider, fallback: fallbackEnabled, quoteIDs: watchlist.quoteIDs) }
    private let clock: () -> Date
    @Published private(set) var closedIDs = Set<String>()
    private let defaults: UserDefaults
    private let fileURL: URL
    private let client: TencentClient
    private let networkEnabled: Bool
    private var timer: Timer?
    private var quoteTask: Task<Void, Never>?
    private var minuteTask: Task<Void, Never>?
    private var nextQuotePoll = Date.distantPast
    private var nextMinutePoll: [String: Date] = [:]
    private var failures = 0
    private var lastRotation = Date()
    private var initialMinutePending = Set<String>()
    private var bootstrappingQuotes = false
    private var canSave = true
    private var cacheDirty = false
    private var cacheSavedAt = Date.distantPast
    private var cacheURL: URL { fileURL.deletingPathExtension().appendingPathExtension("market-snapshot.json") }
    private func restoreCache() {
        guard let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32_000_000,
              let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(MarketSnapshot.self, from: data) else { return }
        let valid = cached.filtered(ids: Set(watchlist.ids))
        quotes = valid.quotes; series = valid.series
        lastSuccess = quotes.values.map(\.sourceTime).max()
    }
    private func persistCache(force: Bool = false) {
        cacheDirty = true
        guard force || Date().timeIntervalSince(cacheSavedAt) >= 15 else { return }
        do {
            let snapshot = MarketSnapshot(quotes: quotes, series: series).filtered(ids: Set(watchlist.ids))
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= 32_000_000 else { return }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            cacheSavedAt = Date(); cacheDirty = false
        } catch { persistenceError = "行情快照保存失败：" + error.localizedDescription }
    }

    var stocks: [Security] { watchlist.ids.compactMap { id in
        if let name = watchlist.names[id] { return Security(id: id, name: name, initials: "", quoteID: watchlist.quoteIDs[id], kind: watchlist.kinds[id] ?? (Security.isDomesticETF(id) ? "ETF" : "股票")) }
        return Security.catalog.first { $0.id == id }
    } }
    var visibleStocks: [Security] { let visible = Set(watchlist.visibleIDs); return stocks.filter { visible.contains($0.id) } }
    var groupTitle: String { watchlist.groups.first { $0.id == watchlist.activeGroupID }?.name ?? "全部" }
    var current: Security? { visibleStocks.first { $0.id == watchlist.selectedID } }
    var currentQuote: QuoteSnapshot? { current.flatMap { quotes[$0.id] } }
    var detail: Security? { stocks.first { $0.id == detailID } }
    var connectionLabel: String {
        if !watchlist.visibleIDs.isEmpty && watchlist.visibleIDs.allSatisfy({ !MarketClock.isTrading($0, at: clock()) }) { return "休市中" }
        if quoteError != nil { return "连接中断" }
        if stocks.isEmpty { return "暂无自选" }
        guard lastSuccess != nil else { return "连接中…" }
        let sources = Set(quotes.values.map { $0.source.title })
        let label = sources.sorted().joined(separator: " / ")
        return label + (quotes.values.contains { $0.source != preferredProvider } ? " · 备用" : "")
    }
    func status(for id: String, now: Date = Date()) -> String {
        if !MarketClock.isTrading(id, at: clock()) { return "休市中" }
        if quoteError != nil { return "连接中断" }
        if missingIDs.contains(id) { return "暂无新报价" }
        guard let quote = quotes[id] else { return "等待行情" }
        return now.timeIntervalSince(quote.sourceTime) > 90 ? "较早报价" : "已更新"
    }
    func needsAttention(_ id: String) -> Bool {
        guard MarketClock.isTrading(id, at: clock()) else { return false }
        return quoteError != nil || missingIDs.contains(id) || quotes[id].map { Date().timeIntervalSince($0.sourceTime) > 90 } == true
    }

    init(clock: @escaping () -> Date = Date.init, fileURL: URL? = nil, defaults: UserDefaults = .standard, startTimer: Bool = true, client: TencentClient? = nil) {
        self.clock = clock
        self.defaults = defaults
        self.client = client ?? TencentClient()
        self.indices = IndexStore(clock: clock, defaults: defaults, client: self.client)
        preferredProvider = client == nil ? (defaults.string(forKey: "quoteProvider").flatMap(QuoteProvider.init(rawValue:)) ?? .eastmoney) : .tencent
        fallbackEnabled = client == nil ? (defaults.object(forKey: "quoteFallback") as? Bool ?? true) : false
        networkEnabled = startTimer
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchStocks/watchlist.json")
        watchlist = WatchlistState(ids: Array(Security.catalog.prefix(4)).map(\.id))
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                watchlist = try JSONDecoder().decode(WatchlistState.self, from: Data(contentsOf: self.fileURL))
                for id in watchlist.ids where TencentClient.symbol(for: id) == nil || (!Security.catalog.contains(where: { $0.id == id }) && watchlist.names[id] == nil) { watchlist.remove(id) }
            } catch {
                canSave = false
                persistenceError = "自选文件无法读取，原文件已保留。本次修改暂不保存。"
            }
        }
        if let saved = defaults.object(forKey: "rotationInterval") as? Double, [3, 4, 6, 10].contains(saved) { interval = saved }
        redUp = defaults.object(forKey: "redUp") as? Bool ?? true
        showFullscreen = defaults.bool(forKey: "showFullscreen")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        if !watchlist.visibleIDs.contains(watchlist.selectedID ?? "") { watchlist.selectedID = watchlist.visibleIDs.first }
        indices.configure(preferred: preferredProvider, fallback: fallbackEnabled)
        restoreCache()
        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            initialMinutePending = Set(watchlist.ids.filter { MarketClock.isChartMinute($0, at: clock()) || series[$0]?.day != MarketClock.day(clock(), id: $0) })
            requestRefresh(includeClosed: true)
            indices.bootstrap()
        }
    }

    private func resetProvider() {
        indices.configure(preferred: preferredProvider, fallback: fallbackEnabled)
        defaults.set(preferredProvider.rawValue, forKey: "quoteProvider")
        defaults.set(fallbackEnabled, forKey: "quoteFallback")
        providerGeneration = UUID()
        quoteTask?.cancel(); quoteTask = nil; cancelMinutes()
        isFetching = false; quotes = [:]; series = [:]; minuteErrors = [:]; missingIDs = []
        quoteError = nil; lastSuccess = nil; failures = 0
        nextQuotePoll = .distantPast; nextMinutePoll = [:]
        refresh()
    }

    func chooseGroup(_ id: String?) {
        guard id == nil || watchlist.groups.contains(where: { $0.id == id }) else { return }
        watchlist.activeGroupID = id
        if !watchlist.visibleIDs.contains(watchlist.selectedID ?? "") { watchlist.selectedID = watchlist.visibleIDs.first }
        backToOverview(); resetRotation(); save()
    }
    func createGroup(_ name: String) -> Bool { let result = watchlist.createGroup(name); if result { save() }; return result }
    func renameGroup(_ id: String, name: String) -> Bool { let result = watchlist.renameGroup(id, name: name); if result { save() }; return result }
    func reorderGroup(_ id: String, to target: String) { watchlist.reorderGroup(id, to: target); save() }
    func reorderStock(_ id: String, to target: String) { watchlist.reorderStock(id, to: target); save() }
    func moveGroupToTop(_ id: String) { watchlist.moveGroupToTop(id); save() }
    func moveGroup(_ id: String, by offset: Int) { watchlist.moveGroup(id, by: offset); save() }
    func deleteGroup(_ id: String) { watchlist.deleteGroup(id); chooseGroup(watchlist.activeGroupID) }
    func toggleMembership(_ stockID: String, groupID: String) {
        watchlist.toggleMembership(stockID, groupID: groupID)
        if !watchlist.visibleIDs.contains(watchlist.selectedID ?? "") { watchlist.selectedID = watchlist.visibleIDs.first }
        if let detailID, !watchlist.visibleIDs.contains(detailID) { backToOverview() }
        save()
    }

    func add(_ security: Security, groupIDs: Set<String>? = nil) {
        let added = watchlist.add(security.id)
        guard added || watchlist.ids.contains(security.id) else { return }
        if added {
            watchlist.names[security.id] = security.name
            watchlist.quoteIDs[security.id] = security.quoteID
            watchlist.kinds[security.id] = security.kind
        }
        if let groupIDs { watchlist.setMemberships(security.id, groups: groupIDs) }
        if !watchlist.visibleIDs.contains(watchlist.selectedID ?? "") { watchlist.selectedID = watchlist.visibleIDs.first }
        if let detailID, !watchlist.visibleIDs.contains(detailID) { backToOverview() }
        save()
        if added { nextQuotePoll = .distantPast; requestRefresh() }
    }
    func remove(_ id: String) {
        watchlist.remove(id)
        if !watchlist.visibleIDs.contains(watchlist.selectedID ?? "") { watchlist.selectedID = watchlist.visibleIDs.first }
        quotes.removeValue(forKey: id)
        series.removeValue(forKey: id)
        minuteErrors.removeValue(forKey: id)
        nextMinutePoll.removeValue(forKey: id)
        missingIDs.remove(id)
        if detailID == id { backToOverview() }
        save()
    }
    func moveToTop(_ id: String) { watchlist.moveToTop(id); save() }
    func move(_ id: String, by offset: Int) { watchlist.move(id, by: offset); save() }
    func select(_ id: String) {
        guard watchlist.visibleIDs.contains(id) else { return }
        watchlist.selectedID = id
        resetRotation()
    }
    func openOverview() {
        backToOverview()
        expanded = true
        if networkEnabled { indices.tick(visible: true) }
        requestMinutes()
    }
    func openDetail(_ id: String) {
        indices.detailID = nil
        guard watchlist.ids.contains(id) else { return }
        cancelMinutes()
        detailID = id
        expanded = true
        requestMinutes()
    }
    func backToOverview() {
        indices.detailID = nil
        cancelMinutes()
        detailID = nil
        if expanded { requestMinutes() }
    }
    func resetRotation() { lastRotation = Date() }
    func collapse() {
        indices.hovered = false
        indices.suspend()
        if pinned { pinned = false }
        expanded = false
        hovered = false
        backToOverview()
        resetRotation()
    }
    func save() {
        persistCache(force: true)
        indices.persistCache()
        guard canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(watchlist).write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = "保存自选失败：\(error.localizedDescription)" }
    }

    func refresh() {
        guard !sleeping else { return }
        if cacheDirty { persistCache() }
        let closed = Set(watchlist.ids.filter { !MarketClock.isTrading($0, at: clock()) })
        if closed != closedIDs { closedIDs = closed; nextQuotePoll = .distantPast }
        if !watchlist.ids.isEmpty && closed.count == watchlist.ids.count && !bootstrappingQuotes {
            quoteTask?.cancel(); quoteTask = nil; isFetching = false
        }
        if networkEnabled { indices.tick(visible: expanded || showingIndices) }
        if Date() >= nextQuotePoll { requestRefresh() }
        if expanded { requestMinutes() }
        if Date().timeIntervalSince(lastRotation) >= interval {
            watchlist.advance(paused: paused || hovered || expanded || pinned || hidden)
            resetRotation()
        }
    }
    func requestRefresh(includeClosed: Bool = false) {
        guard networkEnabled, !sleeping, quoteTask == nil, !watchlist.ids.isEmpty,
              includeClosed || watchlist.ids.contains(where: { MarketClock.isTrading($0, at: clock()) }) else { return }
        bootstrappingQuotes = includeClosed
        let generation = providerGeneration
        quoteTask = Task { [weak self] in
            guard let self else { return }
            await self.reloadQuotes(includeClosed: includeClosed)
            if self.providerGeneration == generation { self.quoteTask = nil; self.bootstrappingQuotes = false }
        }
    }
    func reloadQuotes(includeClosed: Bool = false) async {
        guard !isFetching, !sleeping, !watchlist.ids.isEmpty else { return }
        isFetching = true
        let generation = providerGeneration
        defer { if providerGeneration == generation { isFetching = false } }
        let requested = watchlist.ids.filter { includeClosed || MarketClock.isTrading($0, at: clock()) }
        guard !requested.isEmpty else { return }
        do {
            let result = try await marketClient.quotes(ids: requested)
            guard !Task.isCancelled, !sleeping, generation == providerGeneration else { return }
            for id in requested where watchlist.ids.contains(id) {
                guard let quote = result[id] else { missingIDs.insert(id); continue }
                missingIDs.remove(id)
                if let previous = quotes[id], quote.sourceTime < previous.sourceTime { continue }
                quotes[id] = quote
                if let existing = series[id], existing.day != MarketClock.day(quote.sourceTime, id: id) {
                    series.removeValue(forKey: id)
                    nextMinutePoll[id] = .distantPast
                }
            }
            persistCache()
            lastSuccess = Date()
            quoteError = nil
            failures = 0
        } catch {
            guard !Task.isCancelled, !sleeping, generation == providerGeneration else { return }
            quoteError = error.localizedDescription
            failures = min(failures + 1, 4)
        }
        nextQuotePoll = Date().addingTimeInterval(max(MarketClock.pollingInterval(at: Date(), ids: watchlist.ids), failures == 0 ? 0 : min(60, 5 * pow(2, Double(failures)))))
    }
    private func cancelMinutes() {
        minuteTask?.cancel()
        minuteTask = nil
        loadingMinutes = false
        loadingMinuteIDs = []
    }
    private func requestMinutes() {
        guard networkEnabled, !sleeping, expanded, indices.detailID == nil, minuteTask == nil else { return }
        initialMinutePending = initialMinutePending.filter { MarketClock.isChartMinute($0, at: clock()) || series[$0]?.day != MarketClock.day(clock(), id: $0) }
        let targets = detailID.map { [$0] } ?? watchlist.visibleIDs
        let due = targets.filter { (MarketClock.isTrading($0, at: clock()) || initialMinutePending.contains($0)) && Date() >= (nextMinutePoll[$0] ?? .distantPast) }
        guard !due.isEmpty else { return }
        loadingMinutes = true
        loadingMinuteIDs = Set(due)
        let client = marketClient
        minuteTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: MinuteFetchResult.self) { group in
                var pending = due.makeIterator()
                for id in due.prefix(6) {
                    _ = pending.next()
                    self.initialMinutePending.remove(id)
                    group.addTask {
                        do { return MinuteFetchResult(id: id, result: .success(try await client.minutes(id: id))) }
                        catch { return MinuteFetchResult(id: id, result: .failure(error)) }
                    }
                }
                for await response in group {
                    let id = response.id
                    let result = response.result
                    guard !Task.isCancelled, !self.sleeping, self.expanded else { group.cancelAll(); break }
                    if self.watchlist.ids.contains(id) {
                        switch result {
                        case .success(let series):
                            if let quote = self.quotes[id], series.day != MarketClock.day(quote.sourceTime, id: id) {
                                self.minuteErrors[id] = "分时日期与报价日期不一致，等待更新"
                            } else {
                                self.series[id] = series
                                self.persistCache()
                                self.minuteErrors.removeValue(forKey: id)
                            }
                        case .failure(let error):
                            self.minuteErrors[id] = "分时更新失败：\(error.localizedDescription)"
                        }
                        self.nextMinutePoll[id] = Date().addingTimeInterval(max(30, MarketClock.pollingInterval(at: Date(), ids: self.watchlist.ids)))
                    }
                    self.loadingMinuteIDs.remove(id)
                    var next = pending.next()
                    while let candidate = next, !MarketClock.isTrading(candidate, at: self.clock()) && !self.initialMinutePending.contains(candidate) { next = pending.next() }
                    if let next {
                        self.initialMinutePending.remove(next)
                        group.addTask {
                            do { return MinuteFetchResult(id: next, result: .success(try await client.minutes(id: next))) }
                            catch { return MinuteFetchResult(id: next, result: .failure(error)) }
                        }
                    }
                }
            }
            guard !Task.isCancelled else { return }
            self.loadingMinutes = false
            self.loadingMinuteIDs = []
            self.minuteTask = nil
        }
    }
}

@MainActor
final class IndexStore: ObservableObject {
    @Published private(set) var securities: [Security]
    @Published private(set) var quotes: [String: QuoteSnapshot] = [:]
    @Published private(set) var series: MinuteSeries?
    @Published private(set) var quoteError: String?
    @Published private(set) var minuteError: String?
    @Published private(set) var persistenceError: String?
    @Published private(set) var currentID: String?
    @Published var detailID: String? { didSet { if oldValue != detailID { minuteTask?.cancel(); minuteTask = nil; series = detailID.flatMap { cachedSeries[$0] }; minuteError = nil; nextMinute = .distantPast } } }
    @Published var hovered = false
    private let clock: () -> Date
    @Published private(set) var closedIDs = Set<String>()
    private let defaults: UserDefaults
    let base: TencentClient
    private var preferred: QuoteProvider = .eastmoney
    private var fallback = true
    private var quoteTask: Task<Void, Never>?
    private var minuteTask: Task<Void, Never>?
    private var nextQuote = Date.distantPast
    private var nextMinute = Date.distantPast
    private var rotated = Date()
    private var generation = UUID()
    private var writable = true
    private var cachedSeries: [String: MinuteSeries] = [:]
    private var initialMinutePending = Set<String>()
    private var bootstrappingQuotes = false
    func bootstrap() {
        initialMinutePending = Set(securities.map(\.id).filter { MarketClock.isChartMinute($0, at: clock()) || cachedSeries[$0]?.day != MarketClock.day(clock(), id: $0) })
        refreshQuotes(includeClosed: true)
    }
    func persistCache() {
        let valid = MarketSnapshot(quotes: quotes, series: cachedSeries).filtered(ids: Set(securities.map(\.id)))
        if let data = try? JSONEncoder().encode(valid), data.count <= 2_000_000 { defaults.set(data, forKey: "indexSnapshot") }
    }
    var current: Security? { securities.first { $0.id == currentID } }
    var detail: Security? { securities.first { $0.id == detailID } }
    private var client: MarketClient { MarketClient(tencent: base, preferred: preferred, fallback: fallback, quoteIDs: Dictionary(uniqueKeysWithValues: securities.compactMap { s in s.quoteID.map { (s.id, $0) } })) }
    init(clock: @escaping () -> Date = Date.init, defaults: UserDefaults, client: TencentClient) {
        self.clock = clock
        self.defaults = defaults; self.base = client
        securities = Array(Security.indexCatalog.prefix(3))
        if let data = defaults.data(forKey: "marketIndices") {
            if let saved = try? JSONDecoder().decode([Security].self, from: data) {
                var seen = Set<String>()
                securities = saved.filter { $0.kind == "指数" && TencentClient.symbol(for: $0.id) != nil && seen.insert($0.id).inserted }.prefix(20).map { $0 }
            } else { writable = false; persistenceError = "指数配置无法读取，原配置已保留。" }
        }
        currentID = securities.first?.id
        if let data = defaults.data(forKey: "indexSnapshot"), data.count <= 2_000_000,
           let snapshot = try? JSONDecoder().decode(MarketSnapshot.self, from: data) {
            let valid = snapshot.filtered(ids: Set(securities.map(\.id)))
            quotes = valid.quotes; cachedSeries = valid.series
        }
    }
    func configure(preferred: QuoteProvider, fallback: Bool) {
        guard self.preferred != preferred || self.fallback != fallback else { return }
        self.preferred = preferred; self.fallback = fallback
        suspend(); quoteError = nil; minuteError = nil
    }
    func suspend() {
        generation = UUID(); quoteTask?.cancel(); quoteTask = nil; bootstrappingQuotes = false; minuteTask?.cancel(); minuteTask = nil
        nextQuote = .distantPast; nextMinute = .distantPast; rotated = Date()
    }
    func tick(visible: Bool, now: Date = Date()) {
        guard visible else { if !bootstrappingQuotes && (quoteTask != nil || minuteTask != nil) { suspend() }; return }
        if !hovered && detailID == nil && now.timeIntervalSince(rotated) >= 4, !securities.isEmpty {
            let current = securities.firstIndex { $0.id == currentID } ?? -1
            currentID = securities[(current + 1) % securities.count].id; rotated = now
        }
        let closed = Set(securities.map(\.id).filter { !MarketClock.isTrading($0, at: clock()) })
        if closed != closedIDs { closedIDs = closed; nextQuote = .distantPast; nextMinute = .distantPast }
        if closed.count == securities.count && !bootstrappingQuotes { quoteTask?.cancel(); quoteTask = nil }
        if now >= nextQuote && quoteTask == nil && !securities.isEmpty { refreshQuotes() }
        if detailID != nil && now >= nextMinute && minuteTask == nil { refreshMinutes() }
    }
    func add(_ security: Security) {
        guard security.kind == "指数", securities.count < 20, !securities.contains(where: { $0.id == security.id }) else { return }
        securities.append(security); if currentID == nil { currentID = security.id }; save(); nextQuote = .distantPast
    }
    func remove(_ id: String) {
        securities.removeAll { $0.id == id }; quotes.removeValue(forKey: id); cachedSeries.removeValue(forKey: id); persistCache()
        if currentID == id { currentID = securities.first?.id }
        if detailID == id { detailID = nil }
        save()
    }
    func reorder(_ id: String, to target: String) {
        guard let from = securities.firstIndex(where: { $0.id == id }), let to = securities.firstIndex(where: { $0.id == target }), from != to else { return }
        securities.insert(securities.remove(at: from), at: to); save()
    }
    func top(_ id: String) { if let first = securities.first { reorder(id, to: first.id) } }
    private func save() {
        guard writable else { return }
        if let data = try? JSONEncoder().encode(securities) { defaults.set(data, forKey: "marketIndices") }
    }
    private func refreshQuotes(includeClosed: Bool = false) {
        let requested = securities.map(\.id).filter { includeClosed || MarketClock.isTrading($0, at: clock()) }, source = client, token = generation
        guard !requested.isEmpty, quoteTask == nil else { return }
        bootstrappingQuotes = includeClosed
        quoteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await source.quotes(ids: requested)
                guard !Task.isCancelled, token == self.generation else { return }
                for id in requested where self.securities.contains(where: { $0.id == id }) {
                    if let q = result[id], self.quotes[id].map({ q.sourceTime >= $0.sourceTime }) ?? true { self.quotes[id] = q }
                }
                self.quoteError = requested.allSatisfy { result[$0] != nil } ? nil : "部分指数暂无新报价"
            } catch { guard !Task.isCancelled, token == self.generation else { return }; self.quoteError = "指数更新失败：" + error.localizedDescription }
            self.persistCache()
            self.nextQuote = Date().addingTimeInterval(self.quoteError == nil ? MarketClock.pollingInterval(at: Date(), ids: requested) : 60)
            self.quoteTask = nil; self.bootstrappingQuotes = false
        }
    }
    private func refreshMinutes() {
        initialMinutePending = initialMinutePending.filter { MarketClock.isChartMinute($0, at: clock()) || cachedSeries[$0]?.day != MarketClock.day(clock(), id: $0) }
        guard let id = detailID, MarketClock.isTrading(id, at: clock()) || initialMinutePending.contains(id) else { return }
        initialMinutePending.remove(id)
        let source = client, token = generation
        minuteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await source.minutes(id: id)
                guard !Task.isCancelled, token == self.generation, self.detailID == id else { return }
                if let quote = self.quotes[id], data.day != MarketClock.day(quote.sourceTime, id: id) { self.minuteError = "分时日期与报价不一致，等待更新" }
                else { self.series = data; self.cachedSeries[id] = data; self.persistCache(); self.minuteError = nil }
            } catch { guard !Task.isCancelled, token == self.generation, self.detailID == id else { return }; self.minuteError = "分时暂不可用：" + error.localizedDescription }
            self.nextMinute = Date().addingTimeInterval(30); self.minuteTask = nil
        }
    }
}
