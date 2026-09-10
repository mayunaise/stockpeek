import SwiftUI
import Charts
import AppKit

enum PanelMetrics {
    static let width: CGFloat = 300
    static let height: CGFloat = 430
    static let radius: CGFloat = 20
}

private let accent = Color(red: 0.65, green: 0.79, blue: 0.98)

func priceText(_ value: Double, precision: Int = 2) -> String {
    value.formatted(.number.precision(.fractionLength(precision)))
}
func changeText(_ value: Double) -> String { String(format: "%+.2f%%", value) }
func trendColor(_ change: Double, redUp: Bool) -> Color {
    if change == 0 { return .secondary }
    return (change > 0) == redUp ? Color(red: 1, green: 0.39, blue: 0.42) : Color(red: 0.30, green: 0.82, blue: 0.64)
}

struct GlassShell: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    let radius: CGFloat
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

struct OverlayView: View {
    @ObservedObject var store: StockStore
    var openManager: () -> Void
    var openSearch: () -> Void
    var openIndices: () -> Void
    @ObservedObject private var indices: IndexStore
    init(store: StockStore, openManager: @escaping () -> Void, openSearch: @escaping () -> Void, openIndices: @escaping () -> Void) {
        self.store = store; self.indices = store.indices
        self.openManager = openManager; self.openSearch = openSearch; self.openIndices = openIndices
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if store.detailID != nil || indices.detailID != nil {
                    Button { store.backToOverview() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("返回全部自选").help("返回全部自选")
                }
                if store.detailID == nil && indices.detailID == nil { GroupSelector(store: store).font(.system(size: 13, weight: .semibold)) }
                else { Text(indices.detailID == nil ? "个股详情" : "指数详情").font(.system(size: 14, weight: .semibold)) }
                if store.detailID == nil && indices.detailID == nil { Text("\(store.visibleStocks.count)").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                Button(action: openSearch) { Image(systemName: "plus") }
                    .accessibilityLabel("添加自选").help("添加自选")
                Button { store.requestRefresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isFetching).accessibilityLabel("刷新行情").help("刷新行情")
                Button { store.pinned.toggle() } label: { Image(systemName: store.pinned ? "pin.fill" : "pin") }
                    .foregroundStyle(store.pinned ? accent : .secondary)
                    .accessibilityLabel(store.pinned ? "取消固定" : "固定面板")
            }.buttonStyle(.plain).padding(.horizontal, 18).frame(height: 44)
            IndexTickerView(indices: indices, redUp: store.redUp, manage: openIndices) { id in
                store.backToOverview(); indices.detailID = id; indices.tick(visible: true)
            }
            if let security = indices.detail {
                IndexDetailView(indices: indices, security: security, redUp: store.redUp)
            } else if let security = store.detail {
                detailPage(security)
            } else {
                overview
            }
            HStack(spacing: 6) {
                Circle().fill(store.quoteError == nil ? accent : .orange).frame(width: 5, height: 5)
                Text(store.connectionLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(store.quoteError ?? "报价来源：\(store.connectionLabel)；实际延迟以源时间为准")
                Spacer()
                Button("管理自选", action: openManager).font(.system(size: 10)).foregroundStyle(accent)
            }.buttonStyle(.plain).padding(.horizontal, 18).frame(height: 35)
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .background(Color(red: 0.055, green: 0.065, blue: 0.08).opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .modifier(GlassShell(radius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.radius)).foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark).preferredColorScheme(.dark)
    }

    private var overview: some View {
        VStack(spacing: 0) {
            if store.visibleStocks.isEmpty {
                EmptyWatchlistView(store: store, compact: true, add: openSearch)
            } else {
                HStack(spacing: 8) { Text("证券").frame(width: 88, alignment: .leading); Text("分时").frame(width: 64); Text("最新价 / 涨跌幅").frame(maxWidth: .infinity, alignment: .trailing) }
                    .font(.system(size: 9)).foregroundStyle(.tertiary).padding(.horizontal, 20).frame(height: 28)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.visibleStocks) { security in
                            Button { store.openDetail(security.id) } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ScrollingSecurityName(name: security.name).frame(height: 17).help(security.name)
                                        Text("\(security.code) · \(store.status(for: security.id))")
                                            .font(.system(size: 9)).foregroundStyle(store.needsAttention(security.id) ? .orange : .secondary)
                                    }
                                    .frame(width: 88, alignment: .leading)
                                    .lineLimit(1)
                                    if let quote = store.quotes[security.id], let series = store.series[security.id], series.day == MarketClock.day(quote.sourceTime, id: security.id) {
                                        Sparkline(quote: quote, series: series, color: trendColor(quote.change, redUp: store.redUp), compact: true)
                                            .frame(width: 64, height: 32)
                                            .opacity(store.minuteErrors[security.id] == nil ? 1 : 0.45)
                                            .overlay(alignment: .topTrailing) {
                                                if store.minuteErrors[security.id] != nil {
                                                    Image(systemName: "exclamationmark.circle").font(.system(size: 8)).foregroundStyle(.orange)
                                                }
                                            }
                                            .help(store.minuteErrors[security.id] ?? "当日分时 · \(series.source.title)")
                                    } else {
                                        Text(store.loadingMinuteIDs.contains(security.id) ? "加载中" : "—")
                                            .font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 64, height: 32)
                                            .help(store.minuteErrors[security.id] ?? "等待分时数据")
                                    }
                                    VStack(alignment: .trailing, spacing: 5) {
                                        if let quote = store.quotes[security.id] {
                                            Text(priceText(quote.price, precision: quote.precision)).font(.system(size: 13, weight: .medium))
                                            Text(changeText(quote.change)).font(.system(size: 11))
                                                .foregroundStyle(trendColor(quote.change, redUp: store.redUp))
                                        } else { Text("—").foregroundStyle(.secondary) }
                                    }.monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                                }.padding(.horizontal, 12).frame(height: 55).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .background(store.current?.id == security.id ? .white.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("\(security.name)，\(store.quotes[security.id].map { priceText($0.price) + "，" + changeText($0.change) } ?? "暂无行情")，查看详情")
                        }
                    }.padding(.horizontal, 8)
                }
            }
        }.frame(maxHeight: .infinity)
    }

    @ViewBuilder private func detailPage(_ security: Security) -> some View {
        if let quote = store.quotes[security.id] {
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(security.name).font(.system(size: 16, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text("\(security.code) · \(security.exchange)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(priceText(quote.price, precision: quote.precision)).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(quote.currency).font(.system(size: 9)).foregroundStyle(.tertiary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(changeText(quote.change)).font(.system(size: 13, weight: .medium))
                        Text(String(format: "%+.2f", quote.amount)).font(.system(size: 10))
                    }.foregroundStyle(trendColor(quote.change, redUp: store.redUp)).monospacedDigit()
                }
                Text("\(MarketClock.isTrading(security.id) ? "" : "休市中 · ")\(MarketClock.string(quote.sourceTime, format: "MM-dd HH:mm:ss z", zone: Security.zone(for: security.id))) · \(quote.source.title)")
                    .help(store.status(for: security.id))
                    .font(.system(size: 9)).foregroundStyle(store.needsAttention(security.id) ? .orange : .secondary)
                if let series = store.series[security.id], series.day == MarketClock.day(quote.sourceTime, id: security.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Sparkline(quote: quote, series: series, color: trendColor(quote.change, redUp: store.redUp))
                        Text(!MarketClock.isTrading(security.id) ? "休市中 · 分时 · \(series.source.title)" : "分时 · \(series.source.title)").font(.system(size: 8)).foregroundStyle(.tertiary)
                    }.frame(height: 105)
                } else {
                    VStack(spacing: 8) {
                        if store.loadingMinutes { ProgressView().controlSize(.small) }
                        Text(!MarketClock.isTrading(security.id) ? "休市中 · 暂无缓存分时" : store.minuteError ?? (store.loadingMinutes ? "加载分时…" : "暂无分时数据"))
                            .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).frame(height: 105)
                }
                HStack(alignment: .top, spacing: 6) {
                    metric("今开", quote.open, precision: quote.precision, previousClose: quote.previousClose)
                    metric("最高", quote.high, precision: quote.precision, previousClose: quote.previousClose)
                    metric("最低", quote.low, precision: quote.precision, previousClose: quote.previousClose)
                    metric("昨收", quote.previousClose, precision: quote.precision)
                }
                HStack {
                    Text("成交量 \(quote.volumeLots.map { $0.formatted(.number.precision(.fractionLength(0))) + " " + quote.volumeUnit } ?? "—")")
                    Spacer()
                    Text("成交额 \(quote.turnoverWan.map { priceText($0 / 10000) + " 亿" } ?? "—")")
                }.font(.system(size: 9)).foregroundStyle(.secondary)
                if let error = store.minuteError, store.series[security.id] != nil {
                    Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .topLeading)
            }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 12) {
                Text(security.name).font(.headline)
                Text(!MarketClock.isTrading(security.id) ? "休市中 · 暂无缓存报价" : store.quoteError ?? "尚未收到这只股票的有效报价")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重试") { store.requestRefresh() }.buttonStyle(.glass)
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func metric(_ title: String, _ value: Double?, precision: Int, previousClose: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value.map { priceText($0, precision: precision) } ?? "—").font(.system(size: 11, weight: .medium)).monospacedDigit()
            if let previousClose, previousClose > 0 {
                let change = value.map { ($0 / previousClose - 1) * 100 }
                Text(change.map(changeText) ?? "—")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(change.map { trendColor($0, redUp: store.redUp) } ?? .secondary)
            } else {
                Text("—").font(.system(size: 9)).hidden()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Sparkline: View {
    let quote: QuoteSnapshot
    let series: MinuteSeries
    let color: Color
    var compact = false
    var body: some View {
        let minimum = min(series.points.map(\.price).min() ?? quote.price, quote.previousClose)
        let maximum = max(series.points.map(\.price).max() ?? quote.price, quote.previousClose)
        let padding = max((maximum - minimum) * 0.15, 0.01)
        let axis = TradingTimeAxis(id: quote.id)
        let segments = segmentedPoints
        Chart {
            RuleMark(y: .value("昨收", quote.previousClose))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(.white.opacity(0.25))
            ForEach(segments, id: \.point.id) { item in
                LineMark(x: .value("交易分钟", axis.position(item.point.time)), y: .value("价格", item.point.price), series: .value("连续区间", item.segment))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
            }

        }
        .chartYScale(domain: (minimum - padding)...(maximum + padding))
        .chartXScale(domain: 0...axis.duration, range: .plotDimension(startPadding: compact ? 0 : 16, endPadding: compact ? 0 : 16))
        .chartXAxis {
            AxisMarks(values: compact ? [] : axis.ticks) { value in
                AxisTick(length: 3).foregroundStyle(.white.opacity(0.2))
                AxisValueLabel(anchor: .top) { if let minute = value.as(Double.self) { Text(axis.label(minute)).font(.system(size: 8)) } }
            }
        }
        .chartYAxis(.hidden).chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(series.day) 分时走势，当前价格 \(priceText(quote.price, precision: quote.precision))，涨跌幅 \(changeText(quote.change))")
    }
    private var segmentedPoints: [(point: QuotePoint, segment: Int)] {
        var segment = 0
        return series.points.enumerated().map { index, point in
            if index > 0, TradingTimeAxis(id: quote.id).position(point.time) - TradingTimeAxis(id: quote.id).position(series.points[index - 1].time) > 1.5 { segment += 1 }
            return (point, segment)
        }
    }
}

struct ManagerView: View {
    @ObservedObject var store: StockStore
    var showOverlay: () -> Void
    @State private var query = ""
    @State private var page = "watchlist"
    @State private var editingGroups = false
    @State private var results: [Security] = []
    @State private var searchError: String?
    @State private var loadingSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 170)
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if page == "watchlist" { watchlistPage } else { settingsPage }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.075, green: 0.08, blue: 0.095))
        }
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
        .frame(minWidth: 780, minHeight: 570)
        .sheet(isPresented: $store.showingSearch) { searchSheet }
        .sheet(isPresented: $editingGroups) { GroupEditor(store: store) }
        .sheet(isPresented: $store.showingIndices) { IndexEditor(indices: store.indices) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "waveform.path").font(.system(size: 27, weight: .light)).foregroundStyle(accent)
                    .frame(width: 44, height: 44).modifier(GlassShell(radius: 14))
                Text("StockPeek").font(.system(size: 16, weight: .semibold))
                Text("抬眼之间，关注所选。") .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.top, 12)
            VStack(spacing: 6) {
                navButton("自选股票", icon: "square.stack.3d.up", value: "watchlist")
                navButton("偏好设置", icon: "slider.horizontal.3", value: "settings")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { Circle().fill(store.quoteError == nil ? accent : .orange).frame(width: 5, height: 5); Text(store.connectionLabel).font(.system(size: 9, weight: .medium)) }
                Text("本地运行 · Apple Silicon").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text("v0.2.0").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }.padding(20)
    }
    private func navButton(_ title: String, icon: String, value: String) -> some View {
        Button { page = value } label: {
            HStack(spacing: 9) { Image(systemName: icon).frame(width: 16); Text(title); Spacer() }
                .font(.system(size: 12, weight: page == value ? .medium : .regular))
                .padding(10).background(page == value ? .white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).foregroundStyle(page == value ? .primary : .secondary)
    }
    private var watchlistPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    GroupSelector(store: store).font(.system(size: 23, weight: .semibold))
                    Text(store.visibleStocks.isEmpty ? "为关注的行情留一个位置" : "\(store.visibleStocks.count) 只股票 · 每 \(Int(store.interval)) 秒轮播")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.showingIndices = true } label: { Label("指数", systemImage: "chart.line.uptrend.xyaxis") }.buttonStyle(.glass)
                Button { editingGroups = true } label: { Label("管理分组", systemImage: "folder") }.buttonStyle(.glass)
                Button { store.showingSearch = true } label: { Label("添加股票", systemImage: "plus").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(.glass).controlSize(.large)
            }
            if !store.visibleStocks.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.rays").font(.system(size: 21, weight: .light)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("行情，常驻菜单栏").font(.system(size: 12, weight: .medium))
                    Text("悬停查看全部自选，点击股票查看分时与详情。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("显示", action: showOverlay).font(.system(size: 11)).buttonStyle(.glass)
            }.padding(15).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            HStack { Text("证券 / 市场"); Spacer(); Text("最新价 / 涨跌幅").padding(.trailing, 96) }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            }
            if store.visibleStocks.isEmpty {
                EmptyWatchlistView(store: store, compact: false) { store.showingSearch = true }
                    .background(.white.opacity(0.015), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.045), lineWidth: 1))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.visibleStocks) { security in stockRow(security) }
                    }
                }
            }
            if let error = store.quoteError { Text("行情连接失败：" + error).font(.caption).foregroundStyle(.orange) }
            if let error = store.persistenceError { Text(error).font(.caption).foregroundStyle(.orange) }
            if !store.visibleStocks.isEmpty {
            HStack {
                Text("拖动调整顺序 · 新增默认置顶").font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
                Button(store.paused ? "继续轮播" : "暂停轮播") { store.paused.toggle() }
                    .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            }
        }
    }
    private func stockRow(_ security: Security) -> some View {
        let quote = store.quotes[security.id]
        let selected = store.watchlist.selectedID == security.id
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary).accessibilityHidden(true)
            Button {
                store.select(security.id)
                showOverlay()
                store.openDetail(security.id)
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2).fill(selected ? accent : .white.opacity(0.1)).frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(security.name).font(.system(size: 13, weight: .medium))
                        Text("\(security.code)  \(security.exchange) · \(security.kind)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let quote {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(priceText(quote.price, precision: quote.precision)).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                            Text((store.needsAttention(security.id) || !MarketClock.isTrading(security.id)) ? store.status(for: security.id) : changeText(quote.change)).font(.system(size: 10)).foregroundStyle(store.needsAttention(security.id) ? .orange : trendColor(quote.change, redUp: store.redUp))
                        }.monospacedDigit()
                    } else { Text("—").foregroundStyle(.secondary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.watchlist.groups) { group in
                        Button { store.toggleMembership(security.id, groupID: group.id) } label: {
                            Label(group.name, systemImage: store.watchlist.memberships[group.id, default: []].contains(security.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    Button("管理分组") { editingGroups = true }
                } label: { Image(systemName: "folder") }.menuStyle(.borderlessButton).fixedSize().help("调整所属分组").accessibilityLabel("分组\(security.name)")
                Button { store.moveToTop(security.id) } label: { Image(systemName: "arrow.up.to.line") }.help("置顶").accessibilityLabel("置顶\(security.name)").disabled(store.watchlist.ids.first == security.id)
                Button { store.remove(security.id) } label: { Image(systemName: "minus.circle") }.help("移除自选").accessibilityLabel("移除\(security.name)")
            }.font(.system(size: 10)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.leading, 8)
        }.padding(.horizontal, 12).padding(.vertical, 13)
            .background(selected ? .white.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .modifier(ReorderableRow(id: security.id, category: "stock", label: security.name) { store.reorderStock($0, to: security.id) })
    }

    private var searchSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("添加自选").font(.title2.bold()); Spacer(); Button("完成") { store.showingSearch = false }.buttonStyle(.glass) }
            TextField("搜索名称、代码或美股代码", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
            Text("股票 / ETF · 沪深北、港股、美股").font(.caption).foregroundStyle(.secondary)
            Text("点击添加后可勾选多个分组").font(.caption).foregroundStyle(.secondary)
            if loadingSearch { ProgressView("搜索中…").controlSize(.small) }
            if let searchError { Text(searchError).font(.caption).foregroundStyle(.orange) }
            if store.watchlist.ids.count >= WatchlistState.maximumCount { Text("自选最多 \(WatchlistState.maximumCount) 只，请先移除部分股票。").font(.caption).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(results) { security in
                        SearchSecurityRow(store: store, security: security)
                    }
                    if results.isEmpty && !loadingSearch && searchError == nil { Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "输入名称、代码或拼音开始搜索。" : "没有匹配结果，试试完整股票代码。") .foregroundStyle(.secondary).padding() }
                }
            }
        }.padding(26).frame(width: 440, height: 450).preferredColorScheme(.dark)
        .onAppear { searchFocused = true }
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            results = []; searchError = nil; loadingSearch = !term.isEmpty
            guard !term.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                let found = try await TencentClient().search(term)
                try Task.checkCancellation()
                results = found
                loadingSearch = false
            } catch {
                guard !Task.isCancelled else { return }
                loadingSearch = false
                searchError = "搜索失败，请修改关键词重试：" + error.localizedDescription
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("偏好设置").font(.system(size: 25, weight: .semibold))
            Text("让行情适应你的工作节奏。") .font(.system(size: 11)).foregroundStyle(.secondary)
            Form {
                Section("显示") {
                    Picker("轮播间隔", selection: $store.interval) {
                        ForEach([3.0, 4.0, 6.0, 10.0], id: \.self) { value in Text("\(Int(value)) 秒").tag(value) }
                    }
                    Toggle("红涨绿跌", isOn: $store.redUp)
                    Toggle("减少动态效果", isOn: $store.reduceMotion)
                }
                Section("行为") {
                    Toggle("暂停轮播", isOn: $store.paused)
                    Toggle("菜单栏仅显示图标", isOn: $store.hidden)
                    Toggle("尝试在全屏应用中显示", isOn: $store.showFullscreen)
                }
                Section("行情连接") {
                    Picker("优先数据源", selection: $store.preferredProvider) {
                        ForEach(QuoteProvider.allCases) { provider in Text(provider.title).tag(provider) }
                    }
                    Toggle("失败时使用备用源", isOn: $store.fallbackEnabled)
                    LabeledContent("备用源", value: store.preferredProvider.alternate.title)
                    LabeledContent("当前报价", value: store.connectionLabel)
                    LabeledContent("同花顺 iFinD", value: "待授权 · 暂未接入")
                    LabeledContent("Wind", value: "待授权 · 暂未接入")
                    LabeledContent("证券搜索", value: "东方财富 / 腾讯 · 多市场")
                    LabeledContent("更新频率", value: "报价约 5 秒 · 分时约 30 秒")
                    Text("美股分时使用腾讯；东方财富优先时请开启备用源。公开接口可能延迟或中断，请以源时间为准。非活跃时段降低刷新频率。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }
    }
}

extension NSScreen {
    var displayID: String { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName }
}

struct GroupSelector: View {
    @ObservedObject var store: StockStore
    var body: some View {
        Menu {
            Button("全部") { store.chooseGroup(nil) }
            ForEach(store.watchlist.groups) { group in
                Button(group.name) { store.chooseGroup(group.id) }
            }
        } label: { Text(store.groupTitle).lineLimit(1) }
        .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("切换分组：" + store.groupTitle)
    }
}

struct GroupEditor: View {
    @ObservedObject var store: StockStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editingID: String?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("管理分组").font(.title2.bold()); Spacer(); Button("完成") { dismiss() }.buttonStyle(.glass) }
            HStack {
                TextField(editingID == nil ? "新分组名称" : "修改分组名称", text: $name).textFieldStyle(.roundedBorder)
                Button(editingID == nil ? "创建" : "保存") {
                    let succeeded = editingID.map { store.renameGroup($0, name: name) } ?? store.createGroup(name)
                    if succeeded { name = ""; editingID = nil; error = nil }
                    else { error = "名称须为 1–20 字，不能重复或使用“全部”。" }
                }.buttonStyle(.glass)
                if editingID != nil { Button("取消") { editingID = nil; name = ""; error = nil } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.watchlist.groups) { group in
                        HStack {
                            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary).accessibilityHidden(true)
                            Text(group.name).lineLimit(1).help(group.name); Spacer()
                            Text("\(store.watchlist.memberships[group.id, default: []].count) 只").foregroundStyle(.secondary)
                            Button { store.moveGroupToTop(group.id) } label: { Image(systemName: "arrow.up.to.line") }
                                .help("置顶").accessibilityLabel("置顶分组" + group.name).disabled(store.watchlist.groups.first?.id == group.id)
                            Button { editingID = group.id; name = group.name; error = nil } label: { Image(systemName: "pencil") }.accessibilityLabel("重命名" + group.name)
                            Button { store.deleteGroup(group.id); if editingID == group.id { editingID = nil; name = "" } } label: { Image(systemName: "trash") }.accessibilityLabel("删除分组" + group.name)
                        }.buttonStyle(.plain).padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .modifier(ReorderableRow(id: group.id, category: "group", label: group.name) { store.reorderGroup($0, to: group.id) })
                    }
                    if store.watchlist.groups.isEmpty { Text("创建分组，按主题整理自选。").foregroundStyle(.secondary).padding() }
                }
            }
            Text("拖动或置顶调整分组顺序，“全部”固定在首位。证券可加入多个分组；删除分组不会删除证券。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 440, height: 380).preferredColorScheme(.dark)
    }
}

private struct ReorderableRow: ViewModifier {
    let id: String
    let category: String
    let label: String
    let move: (String) -> Void
    @State private var targeted = false
    private var prefix: String { "stockpeek:" + category + ":" }
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .draggable(prefix + id) { Text(label).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) }
            .dropDestination(for: String.self) { items, _ in
                guard items.count == 1, let payload = items.first, payload.hasPrefix(prefix) else { return false }
                let source = String(payload.dropFirst(prefix.count))
                guard source != id else { return false }
                move(source)
                return true
            } isTargeted: { targeted = $0 }
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(targeted ? 0.8 : 0), lineWidth: 1).allowsHitTesting(false))
            .help("拖动以排序")
    }
}

private struct SearchSecurityRow: View {
    @ObservedObject var store: StockStore
    let security: Security
    @State private var choosingGroups = false
    private var added: Bool { store.watchlist.ids.contains(security.id) }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(security.name).font(.body.weight(.medium))
                Text("\(security.code) · \(security.exchange) · \(security.kind) · \(security.currency)").font(.caption).foregroundStyle(.secondary)
                if added { Text("已在自选中").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Button(added ? "分组" : "添加") { choosingGroups = true }
                .disabled(!added && store.watchlist.ids.count >= WatchlistState.maximumCount).buttonStyle(.glass)
                .accessibilityLabel((added ? "设置分组" : "添加") + security.name)
                .popover(isPresented: $choosingGroups) {
                    SecurityGroupChoices(store: store, security: security) { choosingGroups = false }
                }
        }
    }
}

private struct SecurityGroupChoices: View {
    @ObservedObject var store: StockStore
    let security: Security
    let close: () -> Void
    @State private var selected: Set<String>
    init(store: StockStore, security: Security, close: @escaping () -> Void) {
        self.store = store; self.security = security; self.close = close
        let existing = store.watchlist.ids.contains(security.id)
        _selected = State(initialValue: existing
            ? Set(store.watchlist.groups.filter { store.watchlist.memberships[$0.id, default: []].contains(security.id) }.map(\.id))
            : Set(store.watchlist.activeGroupID.map { [$0] } ?? []))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(security.name).font(.headline)
            Text("所属分组 · 可多选").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Label("全部自选（始终保留）", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary).font(.caption)
                    ForEach(store.watchlist.groups) { group in
                        Toggle(group.name, isOn: Binding(get: { selected.contains(group.id) }, set: { checked in
                            if checked { selected.insert(group.id) } else { selected.remove(group.id) }
                        })).toggleStyle(.checkbox)
                    }
                    if store.watchlist.groups.isEmpty { Text("暂无分组，可在“管理分组”中创建。").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: min(CGFloat(store.watchlist.groups.count * 30 + 42), 210))
            Text("不勾选分组时，仅保留在全部自选。").font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.watchlist.ids.contains(security.id) ? "保存分组" : "添加自选") {
                    store.add(security, groupIDs: selected); close()
                }.buttonStyle(.glass).keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(width: 280).preferredColorScheme(.dark)
    }
}

private struct EmptyWatchlistView: View {
    @ObservedObject var store: StockStore
    let compact: Bool
    let add: () -> Void
    var body: some View {
        VStack(spacing: compact ? 18 : 24) {
            ZStack {
                Circle().fill(RadialGradient(colors: [accent.opacity(0.10), .clear], center: .center, startRadius: 10, endRadius: compact ? 52 : 68))
                    .frame(width: compact ? 108 : 140, height: compact ? 108 : 140)
                Image(systemName: store.watchlist.activeGroupID == nil ? "waveform.path" : "folder")
                    .font(.system(size: compact ? 26 : 34, weight: .ultraLight))
                    .foregroundStyle(accent.opacity(0.9))
                    .frame(width: compact ? 58 : 76, height: compact ? 58 : 76)
                    .modifier(GlassShell(radius: compact ? 18 : 22))
            }.accessibilityHidden(true)
            VStack(spacing: 9) {
                Text(store.watchlist.activeGroupID == nil ? "从第一只自选开始" : "这个分组还没有自选")
                    .font(.system(size: compact ? 14 : 19, weight: .medium))
                Text("添加股票或 ETF，\n把关注的行情放在一起。")
                    .font(.system(size: compact ? 11 : 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(4)
            }
            VStack(spacing: 12) {
                Button(action: add) { Label("添加自选", systemImage: "plus").font(.system(size: compact ? 11 : 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 3) }
                    .buttonStyle(.glass).tint(accent)
                if store.watchlist.activeGroupID != nil && !store.stocks.isEmpty {
                    Button("查看全部自选") { store.chooseGroup(nil) }
                        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }.padding(compact ? 18 : 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IndexTickerView: View {
    @ObservedObject var indices: IndexStore
    let redUp: Bool
    let manage: () -> Void
    let open: (String) -> Void
    var body: some View {
        HStack(spacing: 7) {
            if let index = indices.current {
                Button { open(index.id) } label: {
                    HStack(spacing: 6) {
                        Text(index.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if let quote = indices.quotes[index.id] {
                            if MarketClock.isTrading(index.id) && (indices.quoteError != nil || Date().timeIntervalSince(quote.sourceTime) > 90) {
                                Circle().fill(.orange).frame(width: 4, height: 4)
                            }
                            Text(priceText(quote.price)).monospacedDigit()
                            Text(changeText(quote.change)).monospacedDigit().foregroundStyle(trendColor(quote.change, redUp: redUp))
                        } else { Text(!MarketClock.isTrading(index.id) ? "休市中" : indices.quoteError == nil ? "加载中…" : "暂无报价").foregroundStyle(.secondary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help(indices.quoteError ?? indices.quotes[index.id].map { "\($0.source.title) · \(MarketClock.string($0.sourceTime, format: "MM-dd HH:mm:ss z", zone: Security.zone(for: index.id)))" } ?? "等待指数行情")
            } else {
                Button("选择关注指数", action: manage).buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
            }
            Button(action: manage) { Image(systemName: "slider.horizontal.3").font(.system(size: 9)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("管理指数").accessibilityLabel("管理指数")
        }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 18).frame(height: 26)
            .onHover { indices.hovered = $0 }
    }
}

private struct IndexDetailView: View {
    @ObservedObject var indices: IndexStore
    let security: Security
    let redUp: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(security.name).font(.system(size: 18, weight: .semibold))
            if let quote = indices.quotes[security.id] {
                HStack(alignment: .firstTextBaseline) {
                    Text(priceText(quote.price)).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("点").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(changeText(quote.change)).font(.system(size: 12)).foregroundStyle(trendColor(quote.change, redUp: redUp))
                }
                Text("\(MarketClock.isTrading(security.id) ? "" : "休市中 · ")\(MarketClock.string(quote.sourceTime, format: "MM-dd HH:mm:ss z", zone: Security.zone(for: security.id))) · \(quote.source.title)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                if let series = indices.series, series.day == MarketClock.day(quote.sourceTime, id: security.id) {
                    Sparkline(quote: quote, series: series, color: trendColor(quote.change, redUp: redUp)).frame(height: 110)
                    Text(!MarketClock.isTrading(security.id) ? "休市中 · 分时 · \(series.source.title)" : "分时 · \(series.source.title)").font(.system(size: 9)).foregroundStyle(.secondary)
                } else { Text(!MarketClock.isTrading(security.id) ? "休市中 · 暂无缓存分时" : indices.minuteError ?? "加载分时…").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 110) }
                if let error = indices.quoteError { Text(error).font(.caption2).foregroundStyle(.orange) }
                if let error = indices.minuteError, indices.series != nil { Text(error).font(.caption2).foregroundStyle(.orange) }
            } else { Text(!MarketClock.isTrading(security.id) ? "休市中 · 暂无缓存报价" : indices.quoteError ?? "等待指数行情…").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct IndexEditor: View {
    @ObservedObject var indices: IndexStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var found: [Security] = Security.indexCatalog
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("关注指数").font(.title2.bold()); Spacer(); Button("完成") { dismiss() }.buttonStyle(.glass) }
            Text("每 4 秒轮播 · 悬停暂停 · 拖动排序 · 最多 20 个").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(indices.securities) { index in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Text(index.name); Spacer()
                            Button { indices.top(index.id) } label: { Image(systemName: "arrow.up.to.line") }.disabled(indices.securities.first?.id == index.id).accessibilityLabel("置顶指数" + index.name)
                            Button { indices.remove(index.id) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("移除指数" + index.name)
                        }.font(.system(size: 12)).buttonStyle(.plain).padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .modifier(ReorderableRow(id: index.id, category: "index", label: index.name) { indices.reorder($0, to: index.id) })
                    }
                    if indices.securities.isEmpty { Text("尚未选择指数，请在下方添加。").font(.caption).foregroundStyle(.secondary).padding() }
                }
            }.frame(height: 160)
            Divider()
            TextField("搜索指数名称、代码或拼音", text: $query).textFieldStyle(.roundedBorder)
            if loading { ProgressView().controlSize(.small) }
            if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(found) { index in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(index.name); Text(index.code + " · " + index.exchange).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            let added = indices.securities.contains { $0.id == index.id }
                            Button(added ? "已添加" : "添加") { indices.add(index) }.disabled(added || indices.securities.count >= 20).buttonStyle(.glass).accessibilityLabel((added ? "已添加" : "添加指数") + index.name)
                        }
                    }
                    if found.isEmpty && !loading { Text("未找到支持的指数").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let error = indices.persistenceError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width: 440, height: 510).preferredColorScheme(.dark)
            .task(id: query) {
                let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let local = Security.indexCatalog.filter { term.isEmpty || $0.name.lowercased().contains(term) || $0.code.lowercased().contains(term) || $0.initials.contains(term) }
                found = local; error = nil; loading = !term.isEmpty
                guard !term.isEmpty else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let online = try await indices.base.searchIndices(term)
                    try Task.checkCancellation()
                    let seen = Set(local.map(\.id)); found = local + online.filter { !seen.contains($0.id) }; loading = false
                } catch { guard !Task.isCancelled else { return }; loading = false; self.error = "在线搜索暂不可用，仍可选择常用指数。" }
            }
    }
}

/// Clips only the name; the quote stays stationary and mouse events reach the row/button.
final class ScrollingNameView: NSView {
    var name = NSAttributedString()
    var suffix = NSAttributedString()
    private var identity = ""
    private var started = Date()
    private var timer: Timer?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(name: NSAttributedString, suffix: NSAttributedString = NSAttributedString(), identity: String) {
        if self.identity != identity { self.identity = identity; started = Date() }
        self.name = name; self.suffix = suffix
        setAccessibilityLabel(name.string + " " + suffix.string)
        needsDisplay = true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate(); timer = nil
        if window != nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let trailing = suffix.length == 0 ? 0 : suffix.size().width + 5
        let width = max(0, bounds.width - trailing)
        let overflow = max(0, name.size().width - width)
        let phase = Date().timeIntervalSince(started).truncatingRemainder(dividingBy: 4)
        let progress = min(1, max(0, (phase - 0.7) / 2))
        let offset = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : overflow * progress
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: bounds.height)).addClip()
        name.draw(at: NSPoint(x: -offset, y: (bounds.height - name.size().height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        suffix.draw(at: NSPoint(x: bounds.width - suffix.size().width, y: (bounds.height - suffix.size().height) / 2))
    }
}

private struct ScrollingSecurityName: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> ScrollingNameView { ScrollingNameView() }
    func updateNSView(_ view: ScrollingNameView, context: Context) {
        view.update(name: NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]), identity: name)
    }
}
