#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc HUD/Sources/FocusHUD/PanelManager.swift HUD/Sources/FocusHUD/Paths.swift tests/HUDContentViewTests.swift -o "$test_dir/test-hud-click"
"$test_dir/test-hud-click"
