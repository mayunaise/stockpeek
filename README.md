<div align="center">
  <img src="Assets/AppIcon.png" width="112" alt="StockPeek waveform app icon">
  <h1>StockPeek</h1>
  <p><strong>Your watchlist, a glance away.</strong></p>
  <p>A compact, native macOS menu bar app for stocks, ETFs, and market indices.</p>
  <p>macOS 26+ · Apple Silicon · SwiftUI · Preview</p>
  <p><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a></p>
  <p><a href="https://github.com/mayunaise/stockpeek/releases">Download</a> · <a href="#preview">Preview</a> · <a href="#features">Features</a> · <a href="#build-and-test">Build</a></p>
</div>

StockPeek keeps prices in a small menu bar ticker. Hover to scan your watchlist and its intraday charts, then click a security to explore the details. A dark, translucent interface keeps the focus on the numbers.

Built with SwiftUI, AppKit, and Charts, with no third-party runtime dependencies. The current app interface is in Simplified Chinese; both English and Chinese documentation are available.

## Preview

<table>
  <tr><th>Watchlist at a glance</th><th>Quotes in detail</th></tr>
  <tr>
    <td align="center"><img src="Assets/previews/overview.svg" width="300" alt="Floating watchlist with index carousel, prices, and intraday charts"></td>
    <td align="center"><img src="Assets/previews/detail.svg" width="300" alt="ETF detail panel with intraday chart and open, high, and low percentage changes"></td>
  </tr>
</table>

<p align="center"><img src="Assets/previews/watchlist.svg" width="820" alt="StockPeek management window with watchlist, grouping, and sorting controls"></p>

Interface illustrations based on the app layout, using fictional securities and prices. These are not live screenshots or investment recommendations. The app currently displays Chinese labels; English labels are used here for illustration.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- To build: a Swift toolchain and macOS 26 SDK (Xcode or compatible Command Line Tools)

## Download and run

Download the Apple Silicon DMG from [Releases](https://github.com/mayunaise/stockpeek/releases), open the disk image, and drag **StockPeek.app** to Applications.

This preview is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded builds; building locally is an alternative. Closing the management window leaves the app running in the menu bar.

## Features

### Small footprint, quick access

The menu bar cycles through your selected securities. Long names scroll inside the compact ticker, and the most recent price stays visible when an update is unavailable. Hover opens the watchlist; detail views keep the same compact dimensions.

### Organize your own view of the market

Create groups, add a security to multiple groups with checkboxes, and drag stocks or groups into the order you prefer. Pin-to-top buttons provide a quick shortcut; newly added securities start at the top. Add more securities directly from the floating panel, and remove them there via the detail toolbar button or a row's right-click menu.

### Charts with market context

Scan intraday sparklines beside each security, or open a full detail chart with open/high/low changes relative to the previous close. A separate, customizable index carousel keeps the broader market within reach.

### Capability overview


- Compact menu bar ticker with scrolling long names; configurable rotation and gain/loss colors.
- Hover to open a 300 × 430 pt watchlist with minute charts. Click a security for detailed quotes and charts in the same panel size.
- Up to 500 watchlist entries, drag sorting, pin-to-top, and multiple group memberships.
- Search mainland China, Beijing, Hong Kong, and US stocks and ETFs by name, code, or supported initials.
- Independent index carousel: choose up to 20 supported indices, reorder them, and open their details.
- Price, change, source timestamp, open/high/low prices and percentage changes, previous close, volume, and turnover.
- Exchange-local chart times with New York daylight saving support. Mainland and Hong Kong lunch breaks are compressed on the chart.
- Mainland minute charts stop at 15:00; after-hours trades are excluded.
- Persistent quote and minute-chart snapshots, with one startup quote refresh even outside trading hours.

### Controls

| Action | Result |
| --- | --- |
| Hover over the menu bar ticker | Open the current group's watchlist |
| Click a stock | Open its detail page |
| Minus icon on the detail page, or right-click a listed stock | Remove the stock from the watchlist |
| Pin icon | Keep the floating panel open |
| Move the pointer away | Dismiss an unpinned panel |
| ⌘D while the app is active | Open and pin the watchlist |
| ⌘1 | Open the management window |
| Escape with panel focus | Return to the list, then dismiss |

Opening a stock from the management window does not automatically pin the panel.

## Market data

Eastmoney and Tencent Finance public web endpoints are supported, with configurable preference and fallback. Tencent numeric Hong Kong quotes use the `r_hk` endpoint; minute charts use separate endpoints and may have different delays. iFinD and Wind are **not integrated** and require appropriate authorization.

- Quotes are requested in batches of up to 50, with approximately 5 seconds between completed refresh rounds during active hours.
- Minute charts load on demand, with up to 6 concurrent requests and an approximately 30-second refresh interval.
- Startup restores local snapshots and fetches one quote round. Each minute chart may be fetched once on first display; cached same-day mainland charts are not refreshed after close.
- After startup, regular polling stops outside each market's configured weekday sessions. It resumes automatically when the session opens.
- Session windows: mainland 09:30–11:30 and 13:00–15:00; Hong Kong 09:30–12:00 and 13:00–16:10; US 09:30–16:00 New York time.
- Holiday calendars, half-days, temporary closures, and individual security suspensions are not yet modeled.

Refresh frequency is not a guarantee of real-time data. Endpoints may be delayed, unavailable, or change without notice. Quotes and minute charts retain their actual source and timestamps. No synthetic prices are used as fallback.

These are public web adapters, not licensed commercial market-data feeds. No exchange authorization, uptime guarantee, or data redistribution rights are implied. This preview does not place trades or provide investment advice.

## Build and test

```bash
bash scripts/test.sh
bash scripts/build.sh
open 'build/StockPeek.app'
```

Quit a running instance before launching a newly built app. To create a DMG installer and SHA-256 checksum:

```bash
bash scripts/package-release.sh
```

Optional live checks (these contact public market-data endpoints):

```bash
bash scripts/live-smoke.sh
bash scripts/global-live-smoke.sh
```

## Local storage and privacy

For compatibility with earlier development builds, the internal bundle identifier remains `com.wayne.notchstocks.demo` and the data directory remains `~/Library/Application Support/NotchStocks/`. The user-facing name and executable are **StockPeek**.

| Data | Storage |
| --- | --- |
| Watchlist, groups, ordering | `watchlist.json` in the data directory |
| Latest stock quotes and matching minute charts | `watchlist.market-snapshot.json` in the data directory |
| Preferences, selected indices, index snapshots | macOS UserDefaults for the bundle identifier |

Snapshots overwrite previous contents instead of appending history. Normal stock snapshot writes are throttled to once per 15 seconds; orderly exit flushes pending data. Stock snapshots are limited to 32 MB and index snapshots to 2 MB. Invalid or mismatched cached data is skipped.

The app sends queried security codes and search text to the selected market-data services. It has no application account, analytics SDK, or file-upload feature. Personal storage files, preferences, caches, and compiled artifacts are not included in this repository. The documentation includes interface illustrations with fictional securities.

## Project layout

```text
Sources/    Native app, state, persistence, chart views, market adapters
Tests/      Offline regression tests and small public-response fixtures
Assets/     Waveform app icon and rendering notes
scripts/    Build, test, package, and optional live checks
```

The icon is based on the same waveform symbol used in the app. See [Assets/README.md](Assets/README.md).

## Status

Early preview, version 0.2.0. Multi-display behavior, long-running energy use, and full-screen interactions need further validation. Price alerts, launch at login, order entry, and licensed market feeds are not included.

## Feedback

Report bugs or suggest improvements through [GitHub Issues](https://github.com/mayunaise/stockpeek/issues). For data or chart issues, include the security code, market, source timestamp, macOS version, and steps to reproduce. Remove personal information from any attached screenshots.

See [CHANGELOG.md](CHANGELOG.md) for changes and [release notes](docs/release-notes.md) for the current preview.

## License

StockPeek is licensed under the [MIT License](LICENSE). Commercial use, modification, and distribution are permitted under its terms. This license does not grant rights to third-party market data or services.
