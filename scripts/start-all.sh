#!/usr/bin/env bash
# 常驻 supervisor：HUD daemon + iTerm 失焦检测，任一挂掉 5s 内重启。
# 由 LaunchAgent com.ww.focus-hud 托管（KeepAlive）。
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/iterm-focus-hud"
HUD="$SUPPORT/focus-hud"
SCRIPT="$SUPPORT/focus_monitor.py"

[[ -x "$HUD" ]] || { echo "focus-hud: $HUD missing" >&2; exit 1; }
[[ -f "$SCRIPT" ]] || { echo "focus-hud: $SCRIPT missing" >&2; exit 1; }

PY=""
for d in "$HOME/Library/Application Support/iTerm2/iterm2env/versions"/*/bin/python3; do
    if "$d" -c "import iterm2" >/dev/null 2>&1; then
        PY="$d"
        break
    fi
done
if [[ -z "$PY" ]]; then
    echo "focus-hud: iTerm python runtime not found" >&2
    exit 1
fi

"$HUD" &
HUD_PID=$!
"$PY" "$SCRIPT" &
MON_PID=$!

cleanup() {
    kill "$HUD_PID" "$MON_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

while true; do
    if ! kill -0 "$HUD_PID" 2>/dev/null; then
        "$HUD" &
        HUD_PID=$!
    fi
    if ! kill -0 "$MON_PID" 2>/dev/null; then
        "$PY" "$SCRIPT" &
        MON_PID=$!
    fi
    sleep 5
done
