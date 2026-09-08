#!/usr/bin/env python3
"""iTerm2 失焦检测：应用失焦 -> HUD show；回焦 -> HUD hide。

安装：复制到 ~/Library/Application Support/iTerm2/Scripts/AutoLaunch/focus_monitor.py
协议：往 unix socket 写新行分隔 JSON：{"cmd":"show","frames":[[x,y,w,h],...]} / {"cmd":"hide"}
坐标：AppKit 全局屏幕坐标（左下原点，points），与 HUD NSPanel 直接对齐。
"""

import json
import os
import socket
import sys

import iterm2

SOCKET_PATH = os.path.expanduser(
    "~/Library/Application Support/iterm-focus-hud/control.sock"
)
ITEMS_SOCKET_TIMEOUT = 1.0


def send(payload: dict) -> None:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(ITEMS_SOCKET_TIMEOUT)
            sock.connect(SOCKET_PATH)
            sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    except OSError as err:
        print(f"focus-hud: send failed: {err}", file=sys.stderr)


async def main(connection):
    app = await iterm2.async_get_app(connection)
    shown = False
    monitor = iterm2.FocusMonitor(connection)
    async with monitor:
        while True:
            update = await monitor.async_get_next_update()
            app_active = update.application_active
            if app_active is None:
                continue
            if app_active.application_active:
                if shown:
                    send({"cmd": "hide"})
                    shown = False
            else:
                frames = []
                for window in app.windows:
                    try:
                        frame = await window.async_get_frame()
                        if frame.size.width <= 0 or frame.size.height <= 0:
                            continue
                        frames.append(
                            [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
                        )
                    except Exception as err:  # noqa: BLE001
                        print(f"focus-hud: get frame failed: {err}", file=sys.stderr)
                send({"cmd": "show", "frames": frames})
                shown = True


if __name__ == "__main__":
    iterm2.run_forever(main)
