import AppKit
import SwiftUI
import Combine

final class QuotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.dismissPanelLevel() }
}

final class HoverHostingView: NSHostingView<OverlayView> {
    override var isOpaque: Bool { false }
    var hoverHandler: ((Bool) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.cornerRadius = PanelMetrics.radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        focusRingType = .none
    }
    private var region: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let region { removeTrackingArea(region) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        region = area
    }
    override func mouseEntered(with event: NSEvent) { hoverHandler?(true) }
    override func mouseExited(with event: NSEvent) { hoverHandler?(false) }
}

@main
struct StockPeekApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = StockStore()
    private var panel: QuotePanel!
    private var manager: NSWindow?
    private var status: NSStatusItem!
    private let scrollingName = ScrollingNameView()
    private var subscriptions = Set<AnyCancellable>()
    private var trackingMenus = 0
    private var hoverWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var menuOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        panel = QuotePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.title = "StockPeek 行情"
        let hosting = HoverHostingView(rootView: OverlayView(store: store, openManager: { [weak self] in self?.openManager() }, openSearch: { [weak self] in
            guard let self else { return }
            self.collapse()
            self.openManager()
            self.store.showingSearch = true
        }, openIndices: { [weak self] in
            guard let self else { return }
            self.collapse(); self.openManager(); self.store.showingIndices = true
        }))
        hosting.hoverHandler = { [weak self] inside in self?.hover(inside) }
        panel.contentView = hosting
        store.$expanded.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateVisibility() }.store(in: &subscriptions)
        store.$showFullscreen.receive(on: RunLoop.main).sink { [weak self] _ in self?.position() }.store(in: &subscriptions)
        store.$hidden.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateVisibility() }.store(in: &subscriptions)
        store.$pinned.dropFirst().receive(on: RunLoop.main).sink { [weak self] pinned in
            if !pinned { self?.hover(false) }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.position() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.trackingMenus += 1; self?.hoverWork?.cancel() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.trackingMenus = max(0, self.trackingMenus - 1)
                if self.trackingMenus == 0 && self.store.expanded && !self.store.hovered { self.hover(false) }
            }.store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleep() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.sleeping = false
                self?.store.refresh()
                self?.updateVisibility()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleep() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.sleeping = false; self?.updateVisibility() }
        })
        store.$quotes.combineLatest(store.$watchlist, store.$redUp)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &subscriptions)
        store.$quoteError.combineLatest(store.$missingIDs, store.$lastSuccess)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &subscriptions)
        updateVisibility()
        openManager()
    }

    private func configureMenu() {
        status = NSStatusBar.system.statusItem(withLength: 112)
        if let button = status.button {
            scrollingName.frame = button.bounds.insetBy(dx: 6, dy: 0)
            scrollingName.autoresizingMask = [.width, .height]
            button.addSubview(scrollingName)
            button.addTrackingArea(NSTrackingArea(rect: button.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        updateStatusTitle()
        let menu = NSMenu()
        menu.addItem(withTitle: "StockPeek · A 股行情", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for (title, selector, key) in [
            ("管理自选…", #selector(openManager), ""),
            ("查看自选", #selector(showDetails), ""),
            ("暂停 / 继续轮播", #selector(togglePause), ""),
            ("精简图标 / 显示行情", #selector(toggleHidden), "")
        ] {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            item.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出 StockPeek", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.delegate = self
        status.menu = menu

        let appMenu = NSMenu()
        let main = NSMenu()
        let appRoot = NSMenuItem()
        appRoot.submenu = appMenu
        main.addItem(appRoot)
        appMenu.addItem(withTitle: "退出 StockPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "编辑")
        let editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editRoot.submenu = edit
        main.addItem(editRoot)
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let view = NSMenu(title: "窗口")
        let viewRoot = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        viewRoot.submenu = view
        main.addItem(viewRoot)
        let details = view.addItem(withTitle: "查看自选", action: #selector(showDetails), keyEquivalent: "d")
        details.target = self
        let manage = view.addItem(withTitle: "管理自选", action: #selector(openManager), keyEquivalent: "1")
        manage.target = self
        NSApp.mainMenu = main
    }

    @objc func openManager() {
        if manager == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "StockPeek"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 780, height: 600)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: ManagerView(store: store, showOverlay: { [weak self] in
                self?.showPanel(pinned: false)
            }))
            window.center()
            manager = window
        }
        manager?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showDetails() { showPanel(pinned: true) }

    private func showPanel(pinned: Bool) {
        store.hidden = false
        store.openOverview()
        if store.pinned != pinned { store.pinned = pinned }
        position()
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func togglePause() { store.paused.toggle() }
    @objc private func toggleHidden() { store.hidden.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func hover(_ inside: Bool) {
        hoverWork?.cancel()
        store.hovered = inside
        if inside {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.store.hovered, !self.store.sleeping, !self.menuOpen else { return }
                if !self.store.expanded { self.store.openOverview() }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.store.pinned, self.trackingMenus == 0 else { return }
                // Resizing the panel can generate an exit while the cursor is still inside.
                if (self.panel.isVisible && self.panel.frame.contains(NSEvent.mouseLocation)) || self.statusFrame?.contains(NSEvent.mouseLocation) == true { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func dismissPanelLevel() {
        if store.detailID != nil || store.indices.detailID != nil { store.backToOverview() } else { collapse() }
    }

    func collapse() {
        hoverWork?.cancel()
        store.collapse()
    }

    private func sleep() {
        store.sleeping = true
        collapse()
        panel.orderOut(nil)
    }
    private func updateVisibility() {
        updateStatusTitle()
        guard panel != nil else { return }
        if store.sleeping || !store.expanded || menuOpen {
            panel.orderOut(nil)
        } else {
            position()
            panel.orderFrontRegardless()
        }
    }

    private var statusFrame: NSRect? {
        guard let button = status.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func position() {
        guard panel != nil, let screen = status.button?.window?.screen ?? NSScreen.main else { return }
        panel.collectionBehavior = store.showFullscreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces, .fullScreenNone]
        let anchor = statusFrame ?? NSRect(x: screen.visibleFrame.maxX - 220, y: screen.visibleFrame.maxY, width: 220, height: 22)
        let width = PanelMetrics.width
        let x = min(max(anchor.midX - width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
        let height = PanelMetrics.height
        panel.setFrame(NSRect(x: x, y: anchor.minY - height, width: width, height: height), display: true)
    }

    private func updateStatusTitle() {
        guard let button = status?.button else { return }
        scrollingName.isHidden = store.hidden
        if store.hidden {
            status.length = NSStatusItem.squareLength
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "股票行情")
        } else {
            status.length = 112
            button.image = nil
            let name = store.current?.name ?? "＋ 添加自选"
            let value: String
            if let stock = store.current, let quote = store.currentQuote {
                value = (store.needsAttention(stock.id) || !MarketClock.isTrading(stock.id)) ? priceText(quote.price, precision: quote.precision) : changeText(quote.change)
            } else { value = store.current == nil ? "" : "—" }
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            var color = NSColor.labelColor
            if let stock = store.current, let quote = store.currentQuote, !store.needsAttention(stock.id), MarketClock.isTrading(stock.id) {
                color = quote.change == 0 ? .secondaryLabelColor : ((quote.change > 0) == store.redUp ? .systemRed : .systemGreen)
            }
            button.attributedTitle = NSAttributedString(string: "")
            scrollingName.update(name: NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.labelColor]), suffix: NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color]), identity: store.current?.id ?? "")
        }
        if let stock = store.current, let quote = store.currentQuote {
            button.toolTip = "\(stock.name) · \(priceText(quote.price, precision: quote.precision)) \(quote.currency) · \(changeText(quote.change)) · \(MarketClock.string(quote.sourceTime, format: "MM-dd HH:mm:ss z", zone: Security.zone(for: stock.id))) · \(store.status(for: stock.id))"
        } else { button.toolTip = store.current == nil ? "点击添加自选" : "等待行情 · 悬停查看全部自选" }
        button.setAccessibilityLabel(store.current.map { "\($0.name)，悬停查看全部自选，点击打开菜单" } ?? "添加自选股票")
    }

    @objc(mouseEntered:) func statusMouseEntered(_ event: NSEvent) { hover(true) }
    @objc(mouseExited:) func statusMouseExited(_ event: NSEvent) { hover(false) }
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        collapse()
        store.hovered = true
        panel?.orderOut(nil)
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        store.hovered = false
        store.resetRotation()
        updateVisibility()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openManager()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { store.save() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
