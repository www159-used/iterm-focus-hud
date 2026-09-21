#!/usr/bin/env python3
"""同步独立窗口焦点与遮罩，并接收指定窗口的激活请求。"""

import asyncio
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


async def overlay_state(app):
    focused = app.current_terminal_window if app.app_active else None
    windows = []
    for window in list(app.windows):
        if focused and window.window_id == focused.window_id:
            continue
        try:
            frame = await window.async_get_frame()
            if frame.size.width > 0 and frame.size.height > 0:
                windows.append({
                    "windowID": window.window_id,
                    "frame": [frame.origin.x, frame.origin.y,
                              frame.size.width, frame.size.height],
                })
        except Exception as err:
            print(f"focus-hud: get frame failed: {err}", file=sys.stderr)
    return {"cmd": "show", "windows": windows,
            "subtle": bool(app.app_active)}


async def main(connection):
    app = await iterm2.async_get_app(connection)
    click_path = os.path.join(os.path.dirname(SOCKET_PATH), "activate.sock")

    async def activate(reader, writer):
        try:
            message = json.loads(await asyncio.wait_for(reader.readline(), 1.0))
            window = app.get_window_by_id(message.get("windowID"))
            if window is not None:
                await window.async_activate()
                await app.async_activate(raise_all_windows=False)
        except Exception as err:
            print(f"focus-hud: activate failed: {err}", file=sys.stderr)
        finally:
            writer.close()

    try:
        os.unlink(click_path)
    except FileNotFoundError:
        pass
    server = await asyncio.start_unix_server(activate, path=click_path)
    os.chmod(click_path, 0o600)
    try:
        # App subscribes to focus/layout notifications. Periodic snapshots also
        # cover geometry changes and restore state after the HUD restarts.
        while True:
            await app.async_refresh_focus()
            send(await overlay_state(app))
            await asyncio.sleep(0.2)
    finally:
        server.close()
        await server.wait_closed()
        os.unlink(click_path)


if __name__ == "__main__":
    iterm2.run_forever(main)
