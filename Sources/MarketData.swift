import Foundation
import CoreFoundation

struct Security: Identifiable, Sendable, Codable {
    let id: String
    let name: String
    let initials: String
    var code: String { String(id.dropFirst(3)) }
    var quoteID: String? = nil
    var kind: String = "股票"
    var exchange: String { ["SH": "上交所", "SZ": "深交所", "BJ": "北交所", "HK": "港交所", "US": "美股"][String(id.prefix(2))] ?? "未知市场" }
    var currency: String { id.hasPrefix("US.") ? "USD" : id.hasPrefix("HK.") ? "HKD" : "CNY" }
    static func zone(for id: String) -> TimeZone { TimeZone(identifier: id.hasPrefix("US.") ? "America/New_York" : id.hasPrefix("HK.") ? "Asia/Hong_Kong" : "Asia/Shanghai")! }
    static func isDomesticETF(_ id: String) -> Bool { ["SH.51", "SH.56", "SH.58", "SZ.15"].contains { id.hasPrefix($0) } }

    static let indexCatalog: [Security] = [
        .init(id: "SH.000001", name: "上证指数", initials: "szzs", quoteID: "1.000001", kind: "指数"),
        .init(id: "SZ.399001", name: "深证成指", initials: "szcz", quoteID: "0.399001", kind: "指数"),
        .init(id: "SZ.399006", name: "创业板指", initials: "cybz", quoteID: "0.399006", kind: "指数"),
        .init(id: "SH.000300", name: "沪深300", initials: "hs300", quoteID: "1.000300", kind: "指数"),
        .init(id: "SH.000016", name: "上证50", initials: "sz50", quoteID: "1.000016", kind: "指数"),
        .init(id: "SH.000905", name: "中证500", initials: "zz500", quoteID: "1.000905", kind: "指数"),
        .init(id: "SH.000852", name: "中证1000", initials: "zz1000", quoteID: "1.000852", kind: "指数"),
        .init(id: "BJ.899050", name: "北证50", initials: "bz50", quoteID: "0.899050", kind: "指数"),
        .init(id: "HK.HSI", name: "恒生指数", initials: "hszs", kind: "指数"),
        .init(id: "HK.HSTECH", name: "恒生科技", initials: "hskj", kind: "指数"),
        .init(id: "HK.HSCEI", name: "恒生国企", initials: "hsgq", kind: "指数"),
        .init(id: "US..IXIC", name: "纳斯达克", initials: "nsdk", kind: "指数"),
        .init(id: "US..INX", name: "标普500", initials: "bp500 spx", kind: "指数"),
        .init(id: "US..DJI", name: "道琼斯", initials: "dqs", kind: "指数")
    ]
    static let catalog: [Security] = [
        .init(id: "SH.600519", name: "贵州茅台", initials: "gzmt"),
        .init(id: "SZ.300750", name: "宁德时代", initials: "ndsd"),
        .init(id: "SH.600036", name: "招商银行", initials: "zsyh"),
        .init(id: "SZ.002594", name: "比亚迪", initials: "byd"),
        .init(id: "SZ.000858", name: "五粮液", initials: "wly"),
        .init(id: "SH.601318", name: "中国平安", initials: "zgpa"),
        .init(id: "SH.600900", name: "长江电力", initials: "cjdl"),
        .init(id: "SZ.000333", name: "美的集团", initials: "mdjt"),
        .init(id: "SH.601012", name: "隆基绿能", initials: "ljln"),
        .init(id: "SH.688981", name: "中芯国际", initials: "zxgj"),
        .init(id: "SH.600030", name: "中信证券", initials: "zxzq"),
        .init(id: "SZ.002415", name: "海康威视", initials: "hkws")
    ]
}

struct QuoteSnapshot: Codable, Sendable {
    let id: String
    let name: String
    let price: Double
    let previousClose: Double
    let open: Double?
    let high: Double?
    let low: Double?
    let volumeLots: Double?
    let turnoverWan: Double?
    let sourceTime: Date
    var currency: String { id.hasPrefix("US.") ? "USD" : id.hasPrefix("HK.") ? "HKD" : "CNY" }
    var volumeUnit: String { id.hasPrefix("HK.") || id.hasPrefix("US.") ? "股" : "手" }
    var precision: Int { Security.isDomesticETF(id) || id.hasPrefix("HK.") ? 3 : 2 }
    var change: Double { (price / previousClose - 1) * 100 }
    var source: QuoteProvider = .tencent
    var amount: Double { price - previousClose }
}

struct QuotePoint: Codable, Identifiable, Sendable {
    var id: Date { time }
    let time: Date
    let price: Double
}
struct MinuteSeries: Codable, Sendable {
    let day: String
    let points: [QuotePoint]
    var source: QuoteProvider = .tencent
    var zoneIdentifier: String = "Asia/Shanghai"
    var zone: TimeZone { TimeZone(identifier: zoneIdentifier)! }
}

enum MarketClock {
    static let zone = TimeZone(identifier: "Asia/Shanghai")!
    static func date(_ value: String, format: String = "yyyyMMddHHmmss", zone: TimeZone = zone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    static func string(_ date: Date, format: String, zone: TimeZone = zone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func day(_ date: Date, id: String = "") -> String { string(date, format: "yyyyMMdd", zone: Security.zone(for: id)) }
    static func timestamp(_ date: Date) -> String { string(date, format: "MM-dd HH:mm:ss") }
    static func isChartMinute(_ id: String, at date: Date) -> Bool {
        guard !id.hasPrefix("HK."), !id.hasPrefix("US.") else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Security.zone(for: id)
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
        return seconds <= 15 * 3600
    }
    static func isTrading(_ id: String, at date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Security.zone(for: id)
        let parts = calendar.dateComponents([.weekday, .hour, .minute, .second], from: date)
        guard (2...6).contains(parts.weekday ?? 0) else { return false }
        let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        if id.hasPrefix("US.") { return seconds >= 34200 && seconds < 57600 }
        let morningClose = id.hasPrefix("HK.") ? 43200 : 41400
        let close = id.hasPrefix("HK.") ? 58200 : 54000
        return (seconds >= 34200 && seconds < morningClose) || (seconds >= 46800 && seconds < close)
    }
    static func pollingInterval(at date: Date, ids: [String] = []) -> TimeInterval {
        for prefix in ["HK.", "US."] where ids.contains(where: { $0.hasPrefix(prefix) }) {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = Security.zone(for: prefix)
            let c = local.dateComponents([.weekday, .hour, .minute], from: date)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if (2...6).contains(c.weekday ?? 0) && (prefix == "US." ? (565...970).contains(m) : ((555...725).contains(m) || (775...970).contains(m))) { return 5 }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Weekday time windows are only a request-saving heuristic, not a holiday calendar.
        return (2...6).contains(parts.weekday ?? 0) && ((555...695).contains(minutes) || (775...905).contains(minutes)) ? 5 : 60
    }
}

enum MarketDataError: LocalizedError {
    case invalidSymbol, invalidResponse, unavailableMinutes, http(Int)
    var errorDescription: String? {
        switch self {
        case .unavailableMinutes: return "当前数据源暂不支持美股分时，请开启备用源或选择腾讯财经"
        case .invalidSymbol: return "不支持的证券代码"
        case .invalidResponse: return "行情源未返回有效数据"
        case .http(let code): return "行情请求失败（HTTP \(code)）"
        }
    }
}

struct TencentClient: Sendable {
    let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: configuration)
        }
    }
    static func symbol(for id: String) -> String? {
        if ["HK.HSI", "HK.HSTECH", "HK.HSCEI", "US..DJI", "US..IXIC", "US..INX"].contains(id) { return String(id.prefix(2)).lowercased() + id.dropFirst(3) }
        guard id.range(of: #"^((SH|SZ|BJ)\.[0-9]{6}|HK\.[0-9]{5}|US\.[A-Z][A-Z0-9.\-]{0,19})$"#, options: .regularExpression) != nil else { return nil }
        return String(id.prefix(2)).lowercased() + id.dropFirst(3)
    }
    func search(_ query: String) async throws -> [Security] {
        var url = URLComponents(string: "https://searchapi.eastmoney.com/api/suggest/get")!
        url.queryItems = [URLQueryItem(name: "input", value: query), URLQueryItem(name: "type", value: "14"), URLQueryItem(name: "count", value: "30")]
        do {
            let found = try Self.parseGlobalSearch(try await fetch(url.url!))
            if !found.isEmpty { return found }
        } catch { try Task.checkCancellation() }
        url = URLComponents(string: "https://smartbox.gtimg.cn/s3/")!
        url.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "t", value: "all")]
        return try Self.parseSearch(try await fetch(url.url!))
    }
    func searchIndices(_ query: String) async throws -> [Security] {
        var url = URLComponents(string: "https://searchapi.eastmoney.com/api/suggest/get")!
        url.queryItems = [.init(name: "input", value: query), .init(name: "type", value: "14"), .init(name: "count", value: "30")]
        let data = try await fetch(url.url!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let table = root["QuotationCodeTable"] as? [String: Any], table["Status"] as? Int == 0 else { throw MarketDataError.invalidResponse }
        if table["Data"] is NSNull { return [] }
        guard let rows = table["Data"] as? [[String: Any]] else { throw MarketDataError.invalidResponse }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard row["SecurityTypeName"] as? String == "指数", let code = row["Code"] as? String,
                  let name = row["Name"] as? String, let market = row["MktNum"] as? String else { return nil }
            if let known = Security.indexCatalog.first(where: { $0.name == name || ($0.code == code && $0.id.hasPrefix("HK.")) || ($0.id == "US..INX" && code == "SPX") }) {
                guard seen.insert(known.id).inserted else { return nil }; return known
            }
            guard ["0", "1"].contains(market), row["Classify"] as? String == "Index" else { return nil }
            let id = (market == "1" ? "SH." : code.hasPrefix("899") ? "BJ." : "SZ.") + code
            guard Self.symbol(for: id) != nil, seen.insert(id).inserted else { return nil }
            return Security(id: id, name: name, initials: row["PinYin"] as? String ?? "", quoteID: market + "." + code, kind: "指数")
        }
    }
    static func parseGlobalSearch(_ data: Data) throws -> [Security] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let table = root["QuotationCodeTable"] as? [String: Any], table["Status"] as? Int == 0 else { throw MarketDataError.invalidResponse }
        if table["Data"] is NSNull { return [] }
        guard let rows = table["Data"] as? [[String: Any]] else { throw MarketDataError.invalidResponse }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let code = row["Code"] as? String, let name = row["Name"] as? String, let quoteID = row["QuoteID"] as? String,
                  let market = row["MktNum"] as? String, let classify = row["Classify"] as? String else { return nil }
            let prefix: String
            let kind = name.uppercased().contains("ETF") ? "ETF" : "股票"
            switch classify {
            case "AStock": guard ["0", "1"].contains(market) else { return nil }; prefix = market == "1" ? "SH" : "SZ"
            case "NEEQ": guard row["SecurityTypeName"] as? String == "京A", market == "0" else { return nil }; prefix = "BJ"
            case "HK": guard market == "116", row["SecurityType"] as? String == "19" || kind == "ETF" else { return nil }; prefix = "HK"
            case "UsStock": guard ["105", "106", "107"].contains(market), row["TypeUS"] as? String == "1" || (row["TypeUS"] as? String == "5" && kind == "ETF") else { return nil }; prefix = "US"
            case "Fund": guard ["0", "1"].contains(market), kind == "ETF" else { return nil }; prefix = market == "1" ? "SH" : "SZ"
            default: return nil
            }
            let id = prefix + "." + code.uppercased()
            guard Self.symbol(for: id) != nil, quoteID == market + "." + code, seen.insert(id).inserted else { return nil }
            return Security(id: id, name: name, initials: row["PinYin"] as? String ?? "", quoteID: quoteID, kind: kind)
        }
    }
    static func parseSearch(_ data: Data) throws -> [Security] {
        guard let text = String(data: data, encoding: .utf8),
              let first = text.firstIndex(of: "\""), let last = text.lastIndex(of: "\""), first < last,
              let payload = String(text[first...last]).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: payload) else { throw MarketDataError.invalidResponse }
        if decoded == "N" || decoded.isEmpty { return [] }
        var seen = Set<String>()
        return decoded.components(separatedBy: "^").compactMap { row in
            let fields = row.components(separatedBy: "~")
            guard fields.count >= 5, ["GP-A", "GP", "ETF"].contains(fields[4]) else { return nil }
            let id = fields[0].uppercased() + "." + fields[1].uppercased()
            guard Self.symbol(for: id) != nil, !fields[2].isEmpty, seen.insert(id).inserted else { return nil }
            return Security(id: id, name: fields[2], initials: fields[3], kind: fields[4] == "ETF" ? "ETF" : "股票")
        }
    }
    func quotes(ids: [String]) async throws -> [String: QuoteSnapshot] {
        guard !ids.isEmpty else { return [:] }
        let symbols = ids.compactMap(Self.symbol).map { symbol in
            symbol.hasPrefix("hk") && symbol.dropFirst(2).allSatisfy(\.isNumber) ? "r_" + symbol : symbol
        }
        guard symbols.count == ids.count, ids.count <= 50 else { throw MarketDataError.invalidSymbol }
        let data = try await fetch(URL(string: "https://qt.gtimg.cn/q=" + symbols.joined(separator: ","))!)
        return try Self.parseQuotes(data, requested: ids)
    }
    func minutes(id: String) async throws -> MinuteSeries {
        guard let symbol = Self.symbol(for: id) else { throw MarketDataError.invalidSymbol }
        let endpoint = id.hasPrefix("HK.") ? "hkMinute" : id.hasPrefix("US.") ? "usMinute" : "minute"
        let data = try await fetch(URL(string: "https://web.ifzq.gtimg.cn/appstock/app/" + endpoint + "/query?code=" + symbol)!)
        return try Self.parseMinutes(data, id: id)
    }
    fileprivate func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("StockPeek/0.2", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MarketDataError.invalidResponse }
        guard response.statusCode == 200 else { throw MarketDataError.http(response.statusCode) }
        guard data.count <= 2_000_000 else { throw MarketDataError.invalidResponse }
        return data
    }
    static func parseQuotes(_ data: Data, requested: [String]) throws -> [String: QuoteSnapshot] {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: encoding) else { throw MarketDataError.invalidResponse }
        let expression = try NSRegularExpression(pattern: #"v_((?:r_hk|sh|sz|bj|hk|us)[A-Za-z0-9.\-]+)="([^"\r\n]*)""#)
        let source = text as NSString
        let wanted = Set(requested)
        var quotes: [String: QuoteSnapshot] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let rawSymbol = source.substring(with: match.range(at: 1))
            let symbol = rawSymbol.hasPrefix("r_hk") ? String(rawSymbol.dropFirst(2)) : rawSymbol
            let id = String(symbol.prefix(2)).uppercased() + "." + symbol.dropFirst(2).uppercased()
            guard wanted.contains(id) else { continue }
            let fields = source.substring(with: match.range(at: 2)).components(separatedBy: "~")
            let us = id.hasPrefix("US.")
            let hk = id.hasPrefix("HK.")
            let code = String(id.dropFirst(3))
            guard fields.count > 37, fields[2] == code || (us && fields[2].hasPrefix(code + ".")),
                  let price = positive(fields[3]), let close = positive(fields[4]),
                  let time = MarketClock.date(fields[30], format: us ? "yyyy-MM-dd HH:mm:ss" : hk ? "yyyy/MM/dd HH:mm:ss" : "yyyyMMddHHmmss", zone: Security.zone(for: id)) else { continue }
            if let existing = quotes[id], existing.sourceTime > time { continue }
            quotes[id] = QuoteSnapshot(id: id, name: fields[1], price: price, previousClose: close,
                open: positive(fields[5]), high: positive(fields[33]), low: positive(fields[34]),
                volumeLots: nonnegative(fields[6]), turnoverWan: nonnegative(fields[37]).map { us || hk ? $0 / 10000 : $0 }, sourceTime: time)
        }
        guard !quotes.isEmpty else { throw MarketDataError.invalidResponse }
        return quotes
    }
    private static func positive(_ text: String) -> Double? {
        guard let n = Double(text), n.isFinite, n > 0 else { return nil }
        return n
    }
    private static func nonnegative(_ text: String) -> Double? {
        guard let n = Double(text), n.isFinite, n >= 0 else { return nil }
        return n
    }
    static func parseMinutes(_ data: Data, id: String) throws -> MinuteSeries {
        struct Response: Decodable {
            struct Node: Decodable {
                struct Payload: Decodable { let date: String; let data: [String] }
                let data: Payload
            }
            let code: Int
            let data: [String: Node]
        }
        guard let symbol = symbol(for: id) else { throw MarketDataError.invalidSymbol }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.code == 0, let payload = result.data[symbol]?.data,
              MarketClock.date(payload.date, format: "yyyyMMdd") != nil else { throw MarketDataError.invalidResponse }
        var points: [Date: Double] = [:]
        for line in payload.data.prefix(500) {
            let fields = line.split(separator: " ")
            guard fields.count >= 2, fields[0].count == 4,
                  let time = MarketClock.date(payload.date + fields[0] + "00", zone: Security.zone(for: id)),
                  let price = positive(String(fields[1])) else { continue }
            guard MarketClock.isChartMinute(id, at: time) else { continue }
            points[time] = price
        }
        guard !points.isEmpty else { throw MarketDataError.invalidResponse }
        return MinuteSeries(day: payload.date, points: points.map { QuotePoint(time: $0.key, price: $0.value) }.sorted { $0.time < $1.time }, zoneIdentifier: Security.zone(for: id).identifier)
    }
}

enum QuoteProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case eastmoney, tencent
    var id: String { rawValue }
    var title: String { self == .eastmoney ? "东方财富" : "腾讯财经" }
    var alternate: Self { self == .eastmoney ? .tencent : .eastmoney }
}

struct MarketClient: Sendable {
    let tencent: TencentClient
    let preferred: QuoteProvider
    let fallback: Bool
    var quoteIDs: [String: String] = [:]
    func quotes(ids: [String]) async throws -> [String: QuoteSnapshot] {
        if ids.isEmpty { return [:] }
        var combined: [String: QuoteSnapshot] = [:]
        var lastError: Error?
        for start in stride(from: 0, to: ids.count, by: 50) {
            try Task.checkCancellation()
            let batch = Array(ids[start..<min(start + 50, ids.count)])
            do { combined.merge(try await quoteBatch(ids: batch)) { _, latest in latest } }
            catch { try Task.checkCancellation(); lastError = error }
        }
        if combined.isEmpty, let lastError { throw lastError }
        return combined
    }
    private func quoteBatch(ids: [String]) async throws -> [String: QuoteSnapshot] {
        var result: [String: QuoteSnapshot]
        do { result = try await quotes(ids: ids, provider: preferred) }
        catch {
            try Task.checkCancellation()
            guard fallback else { throw error }
            return try await quotes(ids: ids, provider: preferred.alternate)
        }
        let missing = ids.filter { result[$0] == nil }
        if fallback && !missing.isEmpty {
            try Task.checkCancellation()
            if let extra = try? await quotes(ids: missing, provider: preferred.alternate) {
                result.merge(extra) { first, _ in first }
            }
        }
        try Task.checkCancellation()
        return result
    }
    private func quotes(ids: [String], provider: QuoteProvider) async throws -> [String: QuoteSnapshot] {
        if provider == .tencent { return try await tencent.quotes(ids: ids) }
        let codes = ids.compactMap { try? Self.eastmoneyID($0, supplied: quoteIDs[$0]) }.joined(separator: ",")
        guard !codes.isEmpty else { throw MarketDataError.invalidSymbol }
        let data = try await tencent.fetch(URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&secids=\(codes)&fields=f12,f13,f14,f2,f3,f4,f5,f6,f15,f16,f17,f18,f124")!)
        return try Self.parseQuotes(data, requested: ids)
    }
    func minutes(id: String) async throws -> MinuteSeries {
        do { return try await minutes(id: id, provider: preferred) }
        catch {
            try Task.checkCancellation()
            guard fallback else { throw error }
            return try await minutes(id: id, provider: preferred.alternate)
        }
    }
    private func minutes(id: String, provider: QuoteProvider) async throws -> MinuteSeries {
        if provider == .tencent { return try await tencent.minutes(id: id) }
        // Eastmoney US minute timestamps have not been verified; only use the tested Tencent adapter.
        guard !id.hasPrefix("US.") else { throw MarketDataError.unavailableMinutes }
        let code = try Self.eastmoneyID(id, supplied: quoteIDs[id])
        let data = try await tencent.fetch(URL(string: "https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=\(code)&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11&fields2=f51,f52,f53,f54,f55,f56,f57,f58&ndays=1&iscr=0")!)
        return try Self.parseMinutes(data, id: id)
    }
    static func eastmoneyID(_ id: String, supplied: String? = nil) throws -> String {
        guard TencentClient.symbol(for: id) != nil else { throw MarketDataError.invalidSymbol }
        if Security.indexCatalog.contains(where: { $0.id == id && $0.quoteID == nil }) { throw MarketDataError.invalidSymbol }
        if id.hasPrefix("US.") {
            guard let supplied, ["105", "106", "107"].contains(String(supplied.split(separator: ".").first ?? "")), supplied.dropFirst(4) == id.dropFirst(3) else { throw MarketDataError.invalidSymbol }
            return supplied
        }
        return (id.hasPrefix("HK.") ? "116." : id.hasPrefix("SH.") ? "1." : "0.") + id.dropFirst(3)
    }
    static func marketNumberMatches(_ number: Int, id: String) -> Bool {
        switch String(id.prefix(2)) {
        case "SH": return number == 1
        case "SZ", "BJ": return number == 0
        case "HK": return number == 116
        case "US": return [105, 106, 107].contains(number)
        default: return false
        }
    }
    static func parseQuotes(_ data: Data, requested: [String]) throws -> [String: QuoteSnapshot] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["rc"] as? Int == 0,
              let payload = root["data"] as? [String: Any], let rows = payload["diff"] as? [[String: Any]] else { throw MarketDataError.invalidResponse }
        func number(_ row: [String: Any], _ key: String, positive: Bool = false) -> Double? {
            guard let n = row[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                  positive ? n.doubleValue > 0 : n.doubleValue >= 0 else { return nil }
            return n.doubleValue
        }
        var result: [String: QuoteSnapshot] = [:]
        for row in rows {
            guard let code = row["f12"] as? String, let market = row["f13"] as? Int, [0, 1, 105, 106, 107, 116].contains(market) else { continue }
            guard let id = requested.first(where: { String($0.dropFirst(3)) == code.uppercased() && Self.marketNumberMatches(market, id: $0) }) else { continue }
            guard requested.contains(id), let name = row["f14"] as? String,
                  let price = number(row, "f2", positive: true), let close = number(row, "f18", positive: true),
                  let time = number(row, "f124", positive: true), time > 946684800, time <= Date().timeIntervalSince1970 + 300 else { continue }
            result[id] = QuoteSnapshot(id: id, name: name, price: price, previousClose: close,
                open: number(row, "f17", positive: true), high: number(row, "f15", positive: true), low: number(row, "f16", positive: true),
                volumeLots: number(row, "f5"), turnoverWan: number(row, "f6").map { $0 / 10000 },
                sourceTime: Date(timeIntervalSince1970: time), source: .eastmoney)
        }
        guard !result.isEmpty else { throw MarketDataError.invalidResponse }
        return result
    }
    static func parseMinutes(_ data: Data, id: String) throws -> MinuteSeries {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["rc"] as? Int == 0,
              let payload = root["data"] as? [String: Any], let code = payload["code"] as? String,
              let market = payload["market"] as? Int, Self.marketNumberMatches(market, id: id),
              code.uppercased() == String(id.dropFirst(3)),
              let rows = payload["trends"] as? [String], rows.count <= 500 else { throw MarketDataError.invalidResponse }
        var points: [Date: Double] = [:]
        for row in rows {
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, let time = MarketClock.date(String(fields[0]), format: "yyyy-MM-dd HH:mm", zone: Security.zone(for: id)),
                  let price = Double(fields[2]), price.isFinite, price > 0 else { continue }
            guard MarketClock.isChartMinute(id, at: time) else { continue }
            points[time] = price
        }
        let sorted = points.map { QuotePoint(time: $0.key, price: $0.value) }.sorted { $0.time < $1.time }
        guard let last = sorted.last, sorted.allSatisfy({ MarketClock.day($0.time, id: id) == MarketClock.day(last.time, id: id) }) else { throw MarketDataError.invalidResponse }
        return MinuteSeries(day: MarketClock.day(last.time, id: id), points: sorted, source: .eastmoney, zoneIdentifier: Security.zone(for: id).identifier)
    }
}


struct TradingTimeAxis {
    let id: String
    private var isUS: Bool { id.hasPrefix("US.") }
    private var isHK: Bool { id.hasPrefix("HK.") }
    var duration: Double { isUS ? 390 : isHK ? 330 : 240 }
    var breakPosition: Double { isHK ? 150 : 120 }
    var ticks: [Double] { [0, isUS ? 150 : breakPosition, duration] }
    func position(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Security.zone(for: id)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        let elapsed = minutes - 570
        if isUS { return elapsed }
        let lunchStart = isHK ? 720.0 : 690.0
        return elapsed - min(max(minutes - lunchStart, 0), 780 - lunchStart)
    }
    func label(_ value: Double) -> String {
        if value == 0 { return "09:30" }
        if value == duration { return isUS || isHK ? "16:00" : "15:00" }
        return isUS ? "12:00" : isHK ? "12:00/13:00" : "11:30/13:00"
    }
}


struct MarketSnapshot: Codable {
    var quotes: [String: QuoteSnapshot]
    var series: [String: MinuteSeries]
    func filtered(ids: Set<String>) -> MarketSnapshot {
        let validQuotes = quotes.filter { id, q in
            ids.contains(id) && q.id == id && q.price.isFinite && q.price > 0 && q.previousClose.isFinite && q.previousClose > 0
        }
        let validSeries = series.filter { id, s in
            guard let quote = validQuotes[id] else { return false }
            return s.day == MarketClock.day(quote.sourceTime, id: id) && s.zoneIdentifier == Security.zone(for: id).identifier
                && !s.points.isEmpty && s.points.count <= 500
                && s.points.allSatisfy { MarketClock.isChartMinute(id, at: $0.time) && $0.price.isFinite && $0.price > 0 && MarketClock.day($0.time, id: id) == s.day }
        }
        return MarketSnapshot(quotes: validQuotes, series: validSeries)
    }
}
