#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -O -module-cache-path .build/module-cache Sources/MarketData.swift Tests/GlobalLiveSmoke.swift -o .build/global-live-smoke
.build/global-live-smoke
