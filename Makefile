SUPPORT := $(HOME)/Library/Application Support/iterm-focus-hud
LAUNCHD := $(HOME)/Library/LaunchAgents/com.ww.focus-hud.plist
BIN     := $(SUPPORT)/focus-hud
IT2ENV  := $(HOME)/Library/Application Support/iTerm2/iterm2env
# 找到一个能 import iterm2 的 iTerm Python
IT2PY   := $(shell for p in "$(IT2ENV)"/versions/*/bin/python3; do [ -x "$$p" ] && "$$p" -c "import iterm2" 2>/dev/null && echo "$$p" && break; done)

.PHONY: build install uninstall status check clean

build:
	cd HUD && swift build -c release

check:
	@if [ -z "$(IT2PY)" ]; then \
		echo "iTerm2 Python Runtime 未就绪"; \
		echo "  → 打开 iTerm2 → Scripts → Install Python Runtime 安装后重新 make install"; \
		exit 1; \
	else \
		echo "iTerm2 Python Runtime OK: $(IT2PY)"; \
	fi

install: build check
	@mkdir -p "$(SUPPORT)"
	cp HUD/.build/release/FocusHUD "$(BIN)"
	chmod +x "$(BIN)"
	cp iterm/focus_monitor.py "$(SUPPORT)/focus_monitor.py"
	cp scripts/start-all.sh "$(SUPPORT)/start-all.sh"
	chmod +x "$(SUPPORT)/start-all.sh"
	cp scripts/com.ww.focus-hud.plist "$(LAUNCHD)"
	launchctl unload "$(LAUNCHD)" 2>/dev/null || true
	launchctl load "$(LAUNCHD)"
	@echo "installed + LaunchAgent loaded"

uninstall:
	launchctl unload "$(LAUNCHD)" 2>/dev/null || true
	rm -f "$(LAUNCHD)" "$(BIN)" "$(SUPPORT)/focus_monitor.py" "$(SUPPORT)/start-all.sh"
	@echo "uninstalled"

status:
	pgrep -lf "$(BIN)" || echo "HUD daemon: NOT running"
	ps aux | grep -i focus_monitor | grep -v grep || echo "monitor: NOT running"
	ls -la "$(SUPPORT)/control.sock" 2>/dev/null || echo "socket: missing"

clean:
	rm -rf dist HUD/.build
