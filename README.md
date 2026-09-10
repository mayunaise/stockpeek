# StockPeek

A compact, native macOS menu bar app for keeping an eye on stocks, ETFs, and market indices.

Built with SwiftUI, AppKit, and Charts. No third-party runtime dependencies. The current interface is in Simplified Chinese.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- To build: a Swift toolchain and macOS 26 SDK (Xcode or compatible Command Line Tools)

## Download and run

Download the Apple Silicon DMG from [Releases](https://github.com/mayunaise/stockpeek/releases), open the disk image, and drag **StockPeek.app** to Applications.

This preview is ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded builds; building locally is an alternative. Closing the management window leaves the app running in the menu bar.

## Features

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

The app sends queried security codes and search text to the selected market-data services. It has no application account, analytics SDK, or file-upload feature. Personal watchlists, preferences, caches, and compiled artifacts are not included in this repository.

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
