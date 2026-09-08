"""Linux Tk integration test and real-window screenshots under Xvfb."""
import asyncio
from dataclasses import replace
import os
from pathlib import Path
import socket
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
CAPTURES = ROOT / "build" / "gui-tests"
CAPTURES.mkdir(parents=True, exist_ok=True)
from app import App, RuleDialog
from bridge import Config, Rule
from desktop import autostart_path


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def pump(app, condition, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        app.update()
        if condition():
            return
        time.sleep(0.02)
    raise AssertionError("GUI condition timed out")


def capture(app, path):
    from PIL import ImageGrab
    app.update_idletasks()
    x, y = app.winfo_rootx(), app.winfo_rooty()
    ImageGrab.grab(bbox=(x, y, x + app.winfo_width(), y + app.winfo_height()),
                   xdisplay=os.environ["DISPLAY"]).save(path)


with tempfile.TemporaryDirectory(prefix="port-bridge-gui-") as folder:
    os.environ["XDG_CONFIG_HOME"] = folder
    app = App(Path(folder) / "rules.json")
    errors = []
    app.report_callback_exception = lambda *args: errors.append(args)
    app.update()
    assert app.empty.winfo_ismapped()
    app.geometry("1000x740")
    app.update()
    assert app.autostart_check.winfo_rooty() + app.autostart_check.winfo_height() <= app.winfo_rooty() + app.winfo_height()
    capture(app, CAPTURES / "gui-small.png")
    app.geometry("1160x800")
    app.update()
    capture(app, CAPTURES / "gui-empty.png")

    # Exercise the actual add dialog save/validation and parent callback.
    target_port, listen_port, second_port = port(), port(), port()

    def fill_dialog():
        dialog = next(child for child in app.winfo_children() if isinstance(child, RuleDialog))
        dialog.fields["target_host"].set("127.0.0.1")
        dialog.fields["listen_port"].set("bad")
        dialog.save()
        assert dialog.error.get()
        dialog.fields["name"].set("本机回环验证")
        dialog.fields["listen_port"].set(str(listen_port))
        dialog.fields["target_port"].set(str(target_port))
        dialog.auto.set(True)
        capture(dialog, CAPTURES / "gui-dialog.png")
        dialog.save()

    app.after(100, fill_dialog)
    app.add_button.invoke()
    assert len(app.rules) == 1
    rule = app.rules[0]
    assert Config(app.config_store.path).load()[0] == rule

    async def echo(reader, writer):
        try:
            while data := await reader.read(65536):
                writer.write(data)
                await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()

    target = asyncio.run_coroutine_threadsafe(
        asyncio.start_server(echo, "127.0.0.1", target_port), app.worker.loop).result(3)
    app.table.selection_set(rule.id)
    app.update_controls()
    app.start_button.invoke()
    pump(app, lambda: app.states.get(rule.id) == "运行中")
    assert app.edit_button.instate(["disabled"])
    assert app.stop_button.instate(["!disabled"])

    with socket.create_connection(("127.0.0.1", listen_port), timeout=3) as client:
        client.sendall(b"GUI test" * 1000)
        received = bytearray()
        while len(received) < 8000:
            received.extend(client.recv(8000 - len(received)))
        assert received == b"GUI test" * 1000
        pump(app, lambda: app.metrics.get(rule.id, {}).get("up") == 8000)
        capture(app, CAPTURES / "gui-running.png")
        app.stop_button.invoke()
        pump(app, lambda: app.states.get(rule.id) == "已停止")
        assert client.recv(1) == b""

    # Actual edit callback + persisted restart preference.
    def edit_dialog():
        dialog = next(child for child in app.winfo_children() if isinstance(child, RuleDialog))
        dialog.fields["name"].set("回环验证 · 已编辑")
        dialog.save()
    app.after(100, edit_dialog)
    app.edit_button.invoke()
    assert app.rules[0].name.endswith("已编辑")
    app.autostart.set(True)
    app.toggle_autostart()
    assert autostart_path().exists()
    app.autostart.set(False)
    app.toggle_autostart()
    assert not autostart_path().exists()

    async def stop_target():
        target.close()
        await target.wait_closed()
    asyncio.run_coroutine_threadsafe(stop_target(), app.worker.loop).result(3)
    app.close()
    app.mainloop()
    assert not app.worker.thread.is_alive()
    assert not errors, errors

    second = App(Path(folder) / "rules.json")
    pump(second, lambda: second.states.get(rule.id) == "运行中")
    second.table.selection_set(rule.id)
    second.stop_selected()
    pump(second, lambda: second.states.get(rule.id) == "已停止")
    second.delete_rule()
    assert Config(second.config_store.path).load() == []
    second.close()
    second.mainloop()
    assert not second.worker.thread.is_alive()
print("GUI integration passed: add, validate, start, traffic, stop, edit, save/reload, autostart, delete, shutdown")
