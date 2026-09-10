import Foundation

@main struct GlobalTests {
    @MainActor static func main() async throws {
        func data(_ name: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/" + name)) }
        let ids = ["SH.510300", "BJ.920002", "HK.00700", "US.AAPL"]
        let quotes = try TencentClient.parseQuotes(data("global-quotes-gb18030.txt"), requested: ids)
        precondition(quotes.count == 4)
        precondition(quotes["SH.510300"]!.price == 4.623 && quotes["SH.510300"]!.precision == 3)
        precondition(quotes["HK.00700"]!.currency == "HKD" && quotes["HK.00700"]!.volumeUnit == "股")
        precondition(abs(quotes["HK.00700"]!.turnoverWan! - 466877.4281082) < 0.0001)
        let us = quotes["US.AAPL"]!
        precondition(us.currency == "USD" && us.volumeLots == 65639962)
        precondition(MarketClock.string(us.sourceTime, format: "yyyy-MM-dd HH:mm", zone: TimeZone(secondsFromGMT: 0)!) == "2026-09-09 20:00")
        for (id, file) in [("US.AAPL", "us-minutes.json"), ("HK.00700", "hk-minutes.json"), ("BJ.920002", "bj-minutes.json")] {
            let series = try TencentClient.parseMinutes(data(file), id: id)
            precondition(series.points.count > 100)
            precondition(series.day == MarketClock.day(quotes[id]!.sourceTime, id: id))
            precondition(MarketClock.string(series.points.first!.time, format: "HH:mm", zone: series.zone) == "09:30")
        }
        let apple = try TencentClient.parseGlobalSearch(data("search-us.json"))
        precondition(apple.count == 2 && apple[0].id == "US.AAPL" && apple[0].quoteID == "105.AAPL", "Exclude debt and derivatives")
        let etf = try TencentClient.parseGlobalSearch(data("search-etf.json"))
        precondition(etf[0].kind == "ETF" && etf[0].id == "SH.510300")
        let spy = try TencentClient.parseGlobalSearch(data("search-us-etf.json"))
        precondition(spy.contains { $0.id == "US.SPY" && $0.quoteID == "107.SPY" && $0.kind == "ETF" })
        let bjSearch = try TencentClient.parseGlobalSearch(data("search-bj.json"))
        let hkSearch = try TencentClient.parseGlobalSearch(data("search-hk.json"))
        let usID = try MarketClient.eastmoneyID("US.AAPL", supplied: "105.AAPL")
        let bjID = try MarketClient.eastmoneyID("BJ.920002")
        let hkID = try MarketClient.eastmoneyID("HK.00700")
        precondition(bjSearch[0].id == "BJ.920002" && hkSearch.contains { $0.id == "HK.00700" })
        precondition(usID == "105.AAPL" && bjID == "0.920002" && hkID == "116.00700")
        precondition(TencentClient.symbol(for: "US.AAPL&x=1") == nil)
        let winter = MarketClock.date("20261201150000", zone: TimeZone(secondsFromGMT: 0)!)!
        precondition(MarketClock.pollingInterval(at: winter, ids: ["US.AAPL"]) == 5)
        var watchlist = WatchlistState(ids: ids)
        precondition(watchlist.createGroup("ETF"))
        precondition(!watchlist.createGroup("ETF") && !watchlist.createGroup("全部"))
        let group = watchlist.groups[0].id
        watchlist.toggleMembership("SH.510300", groupID: group)
        watchlist.activeGroupID = group
        precondition(watchlist.visibleIDs == ["SH.510300"])
        watchlist.advance(paused: false)
        precondition(watchlist.selectedID == "SH.510300")
        precondition(watchlist.add("US.SPY"))
        precondition(watchlist.visibleIDs == ["US.SPY", "SH.510300"])
        precondition(watchlist.renameGroup(group, name: "指数ETF"))
        watchlist.quoteIDs["US.SPY"] = "107.SPY"
        let restored = try JSONDecoder().decode(WatchlistState.self, from: JSONEncoder().encode(watchlist))
        precondition(restored.visibleIDs == watchlist.visibleIDs && restored.groups[0].name == "指数ETF" && restored.quoteIDs["US.SPY"] == "107.SPY")
        precondition(watchlist.createGroup("美股") && watchlist.createGroup("港股"))
        let second = watchlist.groups[1].id
        let third = watchlist.groups[2].id
        watchlist.moveGroupToTop(third)
        precondition(watchlist.groups.map(\.id) == [third, group, second])
        watchlist.moveGroup(third, by: 1)
        watchlist.moveGroup(second, by: -1)
        precondition(watchlist.groups.map(\.id) == [group, second, third])
        watchlist.moveGroup(group, by: -1)
        watchlist.moveGroup(third, by: 1)
        watchlist.moveGroupToTop("missing")
        precondition(watchlist.activeGroupID == group && watchlist.visibleIDs == ["US.SPY", "SH.510300"])
        let reordered = try JSONDecoder().decode(WatchlistState.self, from: JSONEncoder().encode(watchlist))
        precondition(reordered.groups.map(\.id) == [group, second, third])
        watchlist.reorderGroup(third, to: group)
        precondition(watchlist.groups.map(\.id) == [third, group, second])
        watchlist.reorderGroup(third, to: second)
        precondition(watchlist.groups.map(\.id) == [group, second, third])
        let before = watchlist.ids
        watchlist.reorderStock("SH.510300", to: "US.SPY")
        precondition(watchlist.visibleIDs == ["SH.510300", "US.SPY"])
        precondition(watchlist.ids.enumerated().allSatisfy { index, id in ["SH.510300", "US.SPY"].contains(id) || before[index] == id })
        let reorderedIDs = watchlist.ids
        watchlist.reorderStock("missing", to: "US.SPY")
        watchlist.reorderStock("US.SPY", to: "US.SPY")
        precondition(watchlist.ids == reorderedIDs && watchlist.activeGroupID == group)
        let dragRestored = try JSONDecoder().decode(WatchlistState.self, from: JSONEncoder().encode(watchlist))
        precondition(dragRestored.ids == reorderedIDs && dragRestored.groups.map(\.id) == [group, second, third])
        watchlist.deleteGroup(second); watchlist.deleteGroup(third)
        watchlist.deleteGroup(group)
        precondition(watchlist.ids.count == 5 && watchlist.activeGroupID == nil && watchlist.groups.isEmpty)
        let old = try JSONDecoder().decode(WatchlistState.self, from: Data(#"{"ids":["SH.600519"],"names":{}}"#.utf8))
        precondition(old.groups.isEmpty && old.visibleIDs == ["SH.600519"])
        print("PASS: global quote/search/minute fixtures, currency/units, US timezone, ETF precision, group migration/CRUD/filter/persistence")
    }
}
