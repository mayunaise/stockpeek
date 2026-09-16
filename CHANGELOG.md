# Changelog

## Unreleased

### Fixed

- Manual refresh fetches current-page quotes and intraday charts once, including closed sessions and index details.

- Fetch a one-time snapshot for newly added indices, including queued additions during closed sessions or while the panel is hidden; allow an initial intraday chart fetch on first detail display.

- Fetch a one-time quote snapshot when adding a watchlist security, including outside trading hours. Queue additions made while another quote request is running.
- Allow newly added securities to load an intraday chart on first display during closed sessions, without enabling regular closed-market polling.

## 0.2.0 — First public preview

- Rename the application to StockPeek while preserving existing local settings.
- Add menu bar rotation, hover watchlists, and individual security detail panels.
- Support mainland, Beijing, Hong Kong, and US equities/ETFs through public market-data adapters.
- Add multi-group membership, drag ordering, and configurable index carousels.
- Add persistent snapshots, session-aware polling, and startup snapshot refresh.
- Align minute chart times, compress lunch breaks, and exclude mainland after-hours points.
- Display open/high/low percentage changes below the chart.
