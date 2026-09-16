import Foundation

@main
struct StoreTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("watchlist.json")
        let suite = "NotchStocksTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let store = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: file, defaults: defaults, startTimer: false)
        assert(store.quotes.isEmpty, "Never seed fabricated prices before a network response")
        let online = Security(id: "SH.600000", name: "浦发银行", initials: "pfyh")
        store.add(online)
        store.add(online)
        assert(store.watchlist.ids.first == online.id)
        store.moveToTop("SZ.300750")
        let onlineRestored = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: file, defaults: defaults, startTimer: false)
        assert(onlineRestored.watchlist.ids.first == "SZ.300750", "Top ordering must persist")
        assert(onlineRestored.stocks.contains { $0.id == online.id && $0.name == online.name })
        assert(onlineRestored.watchlist.ids.filter { $0 == online.id }.count == 1)
        assert(store.createGroup("一组") && store.createGroup("二组"))
        let groups = store.watchlist.groups.map(\.id)
        store.chooseGroup(groups[0])
        store.add(online, groupIDs: Set(groups))
        assert(groups.allSatisfy { store.watchlist.memberships[$0, default: []].contains(online.id) })
        let count = store.watchlist.ids.count
        store.add(online, groupIDs: [groups[1]])
        assert(!store.watchlist.visibleIDs.contains(online.id) && store.watchlist.ids.count == count)
        let multiRestored = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: file, defaults: defaults, startTimer: false)
        assert(multiRestored.watchlist.memberships[groups[1], default: []].contains(online.id))
        store.add(online, groupIDs: [])
        assert(store.watchlist.ids.contains(online.id) && groups.allSatisfy { !store.watchlist.memberships[$0, default: []].contains(online.id) })
        store.chooseGroup(nil)
        let added = Security.catalog[4]
        store.add(added)
        store.select(added.id)
        store.move(added.id, by: -1)
        let restored = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: file, defaults: defaults, startTimer: false)
        assert(restored.watchlist.ids == store.watchlist.ids)
        store.openOverview()
        assert(store.expanded && store.detailID == nil, "First-level panel must show all stocks")
        store.openDetail("SH.600519")
        assert(store.detailID == "SH.600519" && store.current?.id == added.id, "Detail navigation must not mutate the ticker selection")
        store.backToOverview()
        assert(store.expanded && store.detailID == nil)
        store.openDetail("SH.600519")
        store.remove("SH.600519")
        assert(store.detailID == nil, "Removing displayed security must return to overview")
        store.openDetail("missing")
        assert(store.detailID == nil)
        store.pinned = true
        var unpinEvents = 0
        let observer = store.$pinned.dropFirst().sink { if !$0 { unpinEvents += 1 } }
        store.collapse(); store.collapse()
        assert(unpinEvents == 1 && !store.expanded && store.detailID == nil)
        withExtendedLifetime(observer) {}
        // Floating-panel removal must detach the security from the active group only.
        store.add(online, groupIDs: Set(groups))
        store.chooseGroup(groups[0])
        store.openDetail(online.id)
        store.removeFromCurrentGroup(online.id)
        assert(store.detailID == nil, "Removing the displayed security must return to overview")
        assert(store.watchlist.ids.contains(online.id), "Floating panel removal must keep the security in the watchlist")
        assert(!store.watchlist.visibleIDs.contains(online.id), "Floating panel removal must leave the active group")
        assert(groups.dropFirst().allSatisfy { store.watchlist.memberships[$0, default: []].contains(online.id) }, "Other groups must keep the security")
        store.chooseGroup(groups[1])
        assert(store.visibleStocks.map(\.id) == [online.id])
        store.removeFromCurrentGroup(online.id)
        assert(store.watchlist.ids.contains(online.id) && store.watchlist.visibleIDs.isEmpty)
        store.chooseGroup(nil)
        assert(store.watchlist.ids.contains(online.id), "Removal from a group must keep the security listed everywhere")
        store.removeFromCurrentGroup(online.id)
        assert(!store.watchlist.ids.contains(online.id), "Removal without an active group must delete the security")
        for id in store.watchlist.ids { store.remove(id) }
        assert(StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: file, defaults: defaults, startTimer: false).stocks.isEmpty)
        let bad = Data("unreadable user file".utf8)
        try bad.write(to: file)
        let corrupt = StockStore(clock: { MarketClock.date("20260910100000")! }, fileURL: file, defaults: defaults, startTimer: false)
        corrupt.add(added)
        let preserved = try Data(contentsOf: file)
        assert(corrupt.persistenceError != nil && preserved == bad)
        print("PASS: no synthetic prices, two-level navigation, selection isolation, deletion, collapse, floating group removal, persistence")
    }
}
