"""Tk integration tests and window captures (Linux/Xvfb or Windows)."""
import asyncio
from dataclasses import replace
import os
from pathlib import Path
import socket
import sys
import tempfile
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
CAPTURES = ROOT / "build" / "gui-tests"
CAPTURES.mkdir(parents=True, exist_ok=True)
from app import App, RuleDialog, SettingsDialog
from bridge import Config, Rule
from desktop import autostart_path
from i18n import LANGUAGES
from settings import Settings


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
    app.update()
    x, y = app.winfo_rootx(), app.winfo_rooty()
    options = {"xdisplay": os.environ["DISPLAY"]} if sys.platform.startswith("linux") else {}
    ImageGrab.grab(bbox=(x, y, x + app.winfo_width(), y + app.winfo_height()), **options).save(path)


def switch_language(app, language):
    def apply_dialog():
        dialog = next(child for child in app.winfo_children() if isinstance(child, SettingsDialog))
        capture(dialog, CAPTURES / f"gui-settings-{app.language}.png")
        dialog.language.set(LANGUAGES[language])
        dialog.apply_button.invoke()
    app.after(100, apply_dialog)
    app.settings_button.invoke()
    assert app.language == language
    assert Settings(app.settings_store.path).language() == language
    app.update()


def check_dialog(app, language):
    dialog = RuleDialog(app)
    dialog.fields["listen_port"].set("bad")
    dialog.save()
    assert dialog.error.get() == app.tr("Ports must be integers from 1 to 65535")
    dialog.fields["listen_port"].set("9000")
    dialog.fields["target_host"].set("http://invalid")
    dialog.save()
    assert dialog.error.get() == app.tr("Enter only a target IP or hostname, without a protocol, port or brackets")
    capture(dialog, CAPTURES / f"gui-dialog-{language}.png")
    dialog.destroy()


with tempfile.TemporaryDirectory(prefix="port-bridge-gui-") as folder:
    os.environ["XDG_CONFIG_HOME"] = folder
    app = App(Path(folder) / "rules.json")
    errors = []
    app.report_callback_exception = lambda *args: errors.append(args)
    app.update()
    assert app.language == "en"
    assert app.settings_button.cget("text") == "Settings"
    assert app.empty.winfo_ismapped()
    app.geometry("1160x740")
    app.update()
    assert app.autostart_check.winfo_rooty() + app.autostart_check.winfo_height() <= app.winfo_rooty() + app.winfo_height()
    capture(app, CAPTURES / "gui-small.png")
    app.geometry("1240x800")
    app.update()
    capture(app, CAPTURES / "gui-empty.png")
    check_dialog(app, "en")
    # Cancel must leave both the display and disk unchanged.
    dialog = SettingsDialog(app)
    dialog.language.set(LANGUAGES["zh_CN"])
    dialog.destroy()
    assert app.language == "en" and not app.settings_store.path.exists()
    # A settings write failure must keep the dialog open and current language intact.
    dialog = SettingsDialog(app)
    dialog.language.set(LANGUAGES["zh_CN"])
    with patch.object(app.settings_store, "save_language", side_effect=PermissionError("read only")), \
            patch("app.messagebox.showerror") as showerror:
        dialog.apply()
        assert showerror.called and dialog.winfo_exists() and app.language == "en"
    dialog.destroy()

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
    pump(app, lambda: app.states.get(rule.id) == "running")
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
        original_rules = app.config_store.path.read_bytes()
        worker = app.worker
        total = app.metrics[rule.id]["total"]
        for language in ("zh_CN", "en", "zh_CN"):
            switch_language(app, language)
            assert app.worker is worker and app.worker.thread.is_alive()
            assert app.selected().id == rule.id
            assert app.table.item(rule.id, "values")[3] == app.tr("running")
            assert app.edit_button.instate(["disabled"]) and app.stop_button.instate(["!disabled"])
            assert app.metrics[rule.id]["total"] == total
            assert app.config_store.path.read_bytes() == original_rules
            assert ("已监听" if language == "zh_CN" else "Listening on") in app.logs.get("1.0", "end")
            client.sendall(b"same connection")
            received = bytearray()
            while len(received) < 15:
                received.extend(client.recv(15 - len(received)))
            assert received == b"same connection"
            capture(app, CAPTURES / f"gui-running-{language}.png")
        check_dialog(app, "zh_CN")
        app.stop_button.invoke()
        pump(app, lambda: app.states.get(rule.id) == "stopped")
        assert client.recv(1) == b""

    # Actual edit callback + persisted restart preference.
    def edit_dialog():
        dialog = next(child for child in app.winfo_children() if isinstance(child, RuleDialog))
        dialog.fields["name"].set("回环验证 · 已编辑")
        dialog.save()
    app.after(100, edit_dialog)
    app.edit_button.invoke()
    assert app.rules[0].name.endswith("已编辑")
    if sys.platform.startswith("linux"):
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
    assert second.language == "zh_CN"
    assert second.settings_button.cget("text") == "设置"
    pump(second, lambda: second.states.get(rule.id) == "running")
    second.table.selection_set(rule.id)
    second.stop_selected()
    pump(second, lambda: second.states.get(rule.id) == "stopped")
    second.delete_rule()
    assert Config(second.config_store.path).load() == []
    second.close()
    second.mainloop()
    assert not second.worker.thread.is_alive()
print("GUI integration passed: bilingual settings, cancel/save failure, live switching without disconnects, "
      "localized validation, preference reload, add/edit/delete, traffic, stop, autostart, shutdown")
