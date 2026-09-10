#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache Sources/MarketData.swift Tests/LiveSmoke.swift -o .build/live-smoke
.build/live-smoke
