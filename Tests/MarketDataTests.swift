import Foundation

@main
struct MarketDataTests {
    static func main() throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/tencent-quotes-gb18030.txt"))
        let quotes = try TencentClient.parseQuotes(raw, requested: ["SH.600519", "SZ.300750", "SH.600036", "SZ.002594"])
        assert(quotes.count == 4)
        let q = quotes["SH.600519"]!
        assert(q.name == "贵州茅台", "GB18030 names must decode correctly")
        assert(q.price == 1285.57 && q.previousClose == 1290.88 && q.open == 1291)
        assert(q.high == 1294.99 && q.low == 1283.01)
        assert(MarketClock.timestamp(q.sourceTime) == "09-10 10:55:12")
        assert(abs(q.change - (-0.411347)) < 0.001)
        let single = try TencentClient.parseQuotes(raw, requested: ["SZ.300750"])
        assert(single.count == 1 && single["SH.600519"] == nil, "Ignore unsolicited symbols")
        do {
            _ = try TencentClient.parseQuotes(Data("v_sh600519=\"1~bad~600519~NaN\";".utf8), requested: ["SH.600519"])
            assertionFailure("Malformed payload must fail, never become a zero price")
        } catch {}
        let bytes = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/tencent-minutes.json"))
        let series = try TencentClient.parseMinutes(bytes, id: "SH.600519")
        assert(series.day == "20260910")
        assert(series.points.first?.price == 1291)
        assert(MarketClock.timestamp(series.points.first!.time) == "09-10 09:30:00")
        assert(series.points.count > 60)
        assert(TencentClient.symbol(for: "SH.600519") == "sh600519")
        assert(TencentClient.symbol(for: "SH.600519&x=1") == nil)
        assert(MarketClock.date("20261310093000") == nil)
        let search = try TencentClient.parseSearch(Data(#"v_hint="sh~600000~\u6d66\u53d1\u94f6\u884c~pfyh~GP-A^us~AAPL~Apple~aapl~GP^sh~600000~duplicate~x~GP-A";"#.utf8))
        assert(search.count == 2 && search[0].name == "浦发银行" && search[0].id == "SH.600000")
        let emptySearch = try TencentClient.parseSearch(Data(#"v_hint="N";"#.utf8))
        assert(emptySearch.isEmpty)
        for (id, close, duration) in [("SH.600519", "113000", 240.0), ("HK.00700", "120000", 330.0)] {
            let axis = TradingTimeAxis(id: id)
            let morning = MarketClock.date("20260910" + close, zone: Security.zone(for: id))!
            let afternoon = MarketClock.date("20260910130000", zone: Security.zone(for: id))!
            precondition(axis.position(morning) == axis.position(afternoon), "Lunch must occupy zero chart width")
            precondition(axis.duration == duration)
            precondition(axis.position(afternoon.addingTimeInterval(60)) == axis.position(morning) + 1)
        }
        let usAxis = TradingTimeAxis(id: "US.AAPL")
        for day in ["20260910", "20260112"] {
            let noon = MarketClock.date(day + "120000", zone: Security.zone(for: "US.AAPL"))!
            precondition(usAxis.position(noon) == 150 && usAxis.position(noon.addingTimeInterval(3600)) == 210)
        }
        for (id, close) in [("SH.600519", "150000"), ("HK.00700", "161000"), ("US.AAPL", "160000")] {
            let end = MarketClock.date("20260910" + close, zone: Security.zone(for: id))!
            precondition(MarketClock.isTrading(id, at: end.addingTimeInterval(-1)))
            precondition(!MarketClock.isTrading(id, at: end))
            precondition(!MarketClock.isTrading(id, at: MarketClock.date("20260912100000", zone: Security.zone(for: id))!))
        }
        precondition(!MarketClock.isTrading("SH.600519", at: MarketClock.date("20260910120000")!))
        for day in ["20260910", "20260112"] {
            let open = MarketClock.date(day + "093000", zone: Security.zone(for: "US.AAPL"))!
            precondition(MarketClock.isTrading("US.AAPL", at: open) && !MarketClock.isTrading("US.AAPL", at: open.addingTimeInterval(-1)))
        }
        let hkLive = try TencentClient.parseQuotes(Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/hk-realtime-quotes-gb18030.txt")), requested: ["HK.07709"])
        precondition(hkLive["HK.07709"]?.price == 44.2)
        precondition(MarketClock.string(hkLive["HK.07709"]!.sourceTime, format: "HH:mm:ss", zone: Security.zone(for: "HK.07709")) == "15:07:59", "Delayed hk quote must not overwrite r_hk quote")
        let afterHours = Data(#"{"code":0,"data":{"sh600519":{"data":{"date":"20260910","data":["1459 100 1","1500 101 2","1501 999 3","1530 999 4"]}}}}"#.utf8)
        let regular = try TencentClient.parseMinutes(afterHours, id: "SH.600519")
        precondition(regular.points.count == 2 && regular.points.last!.price == 101, "A-share charts must exclude post-close trades while keeping 15:00")
        let eastAfterHours = Data(#"{"rc":0,"data":{"code":"600519","market":1,"trends":["2026-09-10 15:00,100,101","2026-09-10 15:01,100,999"]}}"#.utf8)
        let eastRegular = try MarketClient.parseMinutes(eastAfterHours, id: "SH.600519")
        precondition(eastRegular.points.count == 1)
        print("PASS: GB18030, field positions, timestamps, symbol isolation, malformed data, real minute fixture")
    }
}
