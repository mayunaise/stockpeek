#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache Sources/Watchlist.swift Tests/ModelTests.swift -o .build/model-tests
.build/model-tests
swiftc -module-cache-path .build/module-cache Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Tests/StoreTests.swift -o .build/store-tests
.build/store-tests

swiftc -module-cache-path .build/module-cache Sources/MarketData.swift Tests/MarketDataTests.swift -o .build/market-tests
.build/market-tests
swiftc -module-cache-path .build/module-cache Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Tests/NetworkTests.swift -o .build/network-tests
.build/network-tests

swiftc -O -module-cache-path .build/module-cache Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Tests/OverviewSeriesTests.swift -o .build/overview-tests
.build/overview-tests

swiftc -O -module-cache-path .build/module-cache Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Tests/ProviderTests.swift -o .build/provider-tests
.build/provider-tests

swiftc -O -module-cache-path .build/module-cache Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Tests/GlobalTests.swift -o .build/global-tests
.build/global-tests

swiftc -O -module-cache-path .build/module-cache Sources/Watchlist.swift Sources/MarketData.swift Sources/StockStore.swift Tests/IndexTests.swift -o .build/index-tests
.build/index-tests
