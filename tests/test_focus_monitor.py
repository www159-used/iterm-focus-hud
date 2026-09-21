import asyncio
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

# Unit tests do not require an iTerm2 installation or a live desktop.
sys.modules.setdefault('iterm2', SimpleNamespace())
spec = importlib.util.spec_from_file_location(
    'focus_monitor', Path(__file__).resolve().parents[1] / 'iterm/focus_monitor.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class Window:
    def __init__(self, window_id):
        self.window_id = window_id
        self.frame = SimpleNamespace(origin=SimpleNamespace(x=0, y=0),
                                     size=SimpleNamespace(width=800, height=600))
        self.activated = False

    async def async_get_frame(self):
        return self.frame

    async def async_activate(self):
        self.activated = True


class FocusTests(unittest.TestCase):
    def setUp(self):
        self.a, self.b = Window('A'), Window('B')
        self.app = SimpleNamespace(app_active=True,
                                   current_terminal_window=self.a,
                                   windows=[self.a, self.b])

    def state(self):
        return asyncio.run(monitor.overlay_state(self.app))

    def test_switch_between_independent_windows(self):
        self.assertEqual(self.state()['windows'][0]['windowID'], 'B')
        self.app.current_terminal_window = self.b
        state = self.state()
        self.assertTrue(state['subtle'])
        self.assertEqual([w['windowID'] for w in state['windows']], ['A'])

    def test_application_blur_shades_all_windows(self):
        self.app.app_active = False
        state = self.state()
        self.assertFalse(state['subtle'])
        self.assertEqual([w['windowID'] for w in state['windows']], ['A', 'B'])

    def test_geometry_and_window_closure(self):
        self.b.frame.origin.x = 200
        self.assertEqual(self.state()['windows'][0]['frame'], [200, 0, 800, 600])
        self.app.windows.remove(self.b)
        self.assertEqual(self.state()['windows'], [])
        self.app.windows.clear()
        self.app.current_terminal_window = None
        self.assertEqual(self.state()['windows'], [])

    def test_activation_socket_targets_clicked_window(self):
        async def check():
            async def get_app(_):
                return self.app

            async def refresh():
                pass

            app_activations = []

            async def activate(**kwargs):
                app_activations.append(kwargs)

            self.app.async_refresh_focus = refresh
            self.app.async_activate = activate
            self.app.get_window_by_id = lambda key: next(
                (w for w in self.app.windows if w.window_id == key), None)
            with tempfile.TemporaryDirectory(prefix='hud-', dir='/tmp') as directory:
                control = str(Path(directory) / 'control.sock')
                click = str(Path(directory) / 'activate.sock')
                with patch.object(monitor.iterm2, 'async_get_app', get_app, create=True), \
                     patch.object(monitor, 'SOCKET_PATH', control), \
                     patch.object(monitor, 'send') as send:
                    task = asyncio.create_task(monitor.main(None))
                    try:
                        for _ in range(100):
                            if Path(click).exists():
                                break
                            await asyncio.sleep(0.01)
                        reader, writer = await asyncio.open_unix_connection(click)
                        writer.write((json.dumps({'windowID': 'B'}) + '\n').encode())
                        await writer.drain()
                        await asyncio.wait_for(reader.read(), 1)
                        writer.close()
                        self.assertTrue(self.b.activated)
                        self.assertFalse(self.a.activated)
                        self.assertEqual(app_activations, [{'raise_all_windows': False}])
                        self.assertTrue(send.called)  # Initial state needs no focus event.
                    finally:
                        task.cancel()
                        try:
                            await task
                        except asyncio.CancelledError:
                            pass
                    self.assertFalse(Path(click).exists())
        asyncio.run(check())


if __name__ == '__main__':
    unittest.main()
