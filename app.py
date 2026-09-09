#!/usr/bin/env python3
"""Port Bridge desktop application. Run: python3 app.py"""
import asyncio
from collections import deque
from datetime import datetime
from pathlib import Path
import queue
import sys
import threading
import uuid

from platform_support import config_directory, runtime_info, system_name, tk_install_hint, VERSION

try:
    import tkinter as tk
    from tkinter import font as tkfont, messagebox, ttk
except ImportError:
    raise SystemExit(tk_install_hint()) from None

from bridge import Config, Engine, Rule, endpoint
from desktop import InstanceLock, autostart_path, set_autostart
from i18n import DEFAULT_LANGUAGE, LANGUAGES, LocalizedError, error_message, error_text, translate
from settings import Settings

def human_bytes(value):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024:
            return f"{value:.1f} {unit}" if unit != "B" else f"{value} B"
        value /= 1024
    return f"{value:.1f} PiB"


class Worker:
    def __init__(self):
        self.events = queue.Queue()
        self.ready = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()
        self.ready.wait()

    def run(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.engine = Engine(self.events.put)
        self.lock = asyncio.Lock()
        self.loop.create_task(self.stats())
        self.ready.set()
        try:
            self.loop.run_forever()
        finally:
            tasks = asyncio.all_tasks(self.loop)
            for task in tasks:
                task.cancel()
            self.loop.run_until_complete(asyncio.gather(*tasks, return_exceptions=True))
            self.loop.run_until_complete(self.loop.shutdown_asyncgens())
            self.loop.close()

    async def stats(self):
        while True:
            await asyncio.sleep(0.5)
            self.events.put({"type": "stats", "data": self.engine.snapshot()})

    def submit(self, action, rule):
        async def execute():
            async with self.lock:
                try:
                    if action == "start":
                        await self.engine.start(rule)
                    else:
                        await self.engine.stop(rule.id)
                except Exception as exc:
                    self.events.put({"type": "status", "id": rule.id, "state": "failed"})
                    self.events.put({"type": "log", "name": rule.name, "message": "{error}",
                                     "values": {"error": error_message(exc)}})
        return asyncio.run_coroutine_threadsafe(execute(), self.loop)

    def close(self):
        async def shutdown():
            async with self.lock:
                await self.engine.stop_all()
            self.loop.call_soon(self.loop.stop)
        asyncio.run_coroutine_threadsafe(shutdown(), self.loop)


class RuleDialog(tk.Toplevel):
    def __init__(self, parent, rule=None):
        super().__init__(parent)
        self.tr = parent.tr
        self.title(self.tr("Edit forwarding rule" if rule else "Add forwarding rule"))
        self.resizable(False, False)
        self.transient(parent)
        self.result = None
        self.rule = rule
        self.configure(bg="#f4f7fb")
        box = ttk.Frame(self, padding=24)
        box.pack(fill="both", expand=True)
        ttk.Label(box, text=self.tr("Listen locally, forward to a target"), style="Section.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        ttk.Label(box, text=self.tr("Enter a reachable target IP or hostname without a protocol prefix."),
                  style="Muted.TLabel", wraplength=490).grid(row=1, column=0, columnspan=2, sticky="w", pady=(0, 18))
        values = rule or Rule(uuid.uuid4().hex, self.tr("New rule"))
        self.fields = {}
        entries = []
        for row, (key, label) in enumerate([
            ("name", "Rule name"), ("listen_host", "Listen address"),
            ("listen_port", "Listen port"), ("target_host", "Target IP / hostname"),
            ("target_port", "Target port")], 2):
            ttk.Label(box, text=self.tr(label)).grid(row=row, column=0, sticky="w", padx=(0, 20), pady=8)
            variable = tk.StringVar(value=str(getattr(values, key)))
            self.fields[key] = variable
            entry = ttk.Entry(box, textvariable=variable, width=32)
            entry.grid(row=row, column=1, sticky="ew", pady=8)
            entries.append(entry)
        self.auto = tk.BooleanVar(value=values.auto_start)
        ttk.Checkbutton(box, text=self.tr("Start this rule when the application opens"), variable=self.auto).grid(
            row=7, column=0, columnspan=2, sticky="w", pady=(14, 8))
        ttk.Label(box, text=self.tr("0.0.0.0 listens on all IPv4 interfaces. Use 127.0.0.1 for local access only."),
                  style="Muted.TLabel", wraplength=490).grid(row=8, column=0, columnspan=2, sticky="w", pady=8)
        self.error = tk.StringVar()
        ttk.Label(box, textvariable=self.error, foreground="#b42318", wraplength=430).grid(
            row=9, column=0, columnspan=2, sticky="w")
        buttons = ttk.Frame(box)
        buttons.grid(row=10, column=0, columnspan=2, sticky="e", pady=(16, 0))
        ttk.Button(buttons, text=self.tr("Cancel"), command=self.destroy).pack(side="left", padx=8)
        ttk.Button(buttons, text=self.tr("Save rule"), style="Accent.TButton", command=self.save).pack(side="left")
        self.bind("<Return>", lambda _: self.save())
        self.bind("<Escape>", lambda _: self.destroy())
        self.update_idletasks()
        x = parent.winfo_rootx() + max(0, (parent.winfo_width() - self.winfo_width()) // 2)
        y = parent.winfo_rooty() + max(0, (parent.winfo_height() - self.winfo_height()) // 2)
        self.geometry(f"+{x}+{y}")
        self.grab_set()
        entries[3 if rule is None else 0].focus_set()

    def save(self):
        try:
            values = {key: variable.get().strip() for key, variable in self.fields.items()}
            try:
                values["listen_port"] = int(values["listen_port"])
                values["target_port"] = int(values["target_port"])
            except ValueError:
                raise LocalizedError("Ports must be integers from 1 to 65535") from None
            self.result = Rule(id=self.rule.id if self.rule else uuid.uuid4().hex,
                               auto_start=self.auto.get(), **values).validate()
        except ValueError as exc:
            self.error.set(error_text(exc, self.master.language))
            return
        self.destroy()


class SettingsDialog(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        self.title(parent.tr("Settings"))
        self.resizable(False, False)
        self.transient(parent)
        box = ttk.Frame(self, padding=24)
        box.pack(fill="both", expand=True)
        ttk.Label(box, text=parent.tr("Language"), style="Section.TLabel").pack(anchor="w")
        self.language = tk.StringVar(value=LANGUAGES[parent.language])
        self.choice = ttk.Combobox(box, textvariable=self.language, values=list(LANGUAGES.values()),
                                   state="readonly", width=30)
        self.choice.pack(fill="x", pady=(12, 16))
        ttk.Label(box, text=parent.tr("Changes apply immediately and are saved for the next launch."),
                  style="Muted.TLabel", wraplength=380).pack(anchor="w")
        info = runtime_info()
        ttk.Label(box, text=parent.tr("Runtime platform"), style="Section.TLabel").pack(anchor="w", pady=(20, 6))
        description = info.get("distribution", {"windows": "Windows", "macos": "macOS"}.get(info["system"], info["system"]))
        ttk.Label(box, text=f"{description}\n{info['architecture']} · Python {info['python']} ({info['bits']}-bit)",
                  style="Muted.TLabel", wraplength=380).pack(anchor="w")
        buttons = ttk.Frame(box)
        buttons.pack(anchor="e", pady=(20, 0))
        ttk.Button(buttons, text=parent.tr("Cancel"), command=self.destroy).pack(side="left", padx=8)
        self.apply_button = ttk.Button(buttons, text=parent.tr("Apply"), style="Accent.TButton", command=self.apply)
        self.apply_button.pack(side="left")
        self.bind("<Escape>", lambda _: self.destroy())
        self.bind("<Return>", lambda _: self.apply())
        self.update_idletasks()
        self.geometry(f"+{parent.winfo_rootx() + (parent.winfo_width() - self.winfo_width()) // 2}"
                      f"+{parent.winfo_rooty() + (parent.winfo_height() - self.winfo_height()) // 2}")
        self.grab_set()
        self.choice.focus_set()

    def apply(self):
        language = next(code for code, label in LANGUAGES.items() if label == self.language.get())
        try:
            self.master.set_language(language)
        except Exception as exc:
            messagebox.showerror(self.master.tr("Unable to save settings"),
                                 error_text(exc, self.master.language), parent=self)
            return
        self.destroy()


class App(tk.Tk):
    def __init__(self, config_path=None):
        super().__init__()
        self.title("Port Bridge")
        self.geometry("1240x800")
        self.minsize(1160, 740)
        self.configure(bg="#f4f7fb")
        self.config_store = Config(config_path or config_directory() / "rules.json")
        self.settings_store = Settings(self.config_store.path.with_name("settings.json"))
        self.language = DEFAULT_LANGUAGE
        self.settings_error = None
        try:
            self.language = self.settings_store.language()
        except Exception as exc:
            self.settings_error = exc
        self.log_records = deque(maxlen=500)
        self.rules = []
        self.states = {}
        self.metrics = {}
        self.closing = False
        self.read_error = None
        try:
            self.rules = self.config_store.load()
        except Exception as exc:
            self.read_error = exc
        self.worker = Worker()
        self.style_ui()
        self.build_ui()
        self.append_log(None, "TCP forwarding is ready. Application protocols are handled by the target service.")
        self.refresh()
        self.protocol("WM_DELETE_WINDOW", self.close)
        if system_name() == "macos":
            self.createcommand("tk::mac::Quit", self.close)
            self.bind("<Command-q>", lambda _: self.close())
        self.poll_id = self.after(100, self.poll)
        if self.read_error:
            self.after(150, lambda: messagebox.showerror(self.tr("Unable to load configuration"), self.tr(
                "Could not read configuration: {error}\n\nThe original file has been preserved. Repair it and restart the application.\n{path}",
                error=self.read_error, path=self.config_store.path), parent=self))
        else:
            for rule in self.rules:
                if rule.auto_start:
                    self.start_rule(rule)

        if self.settings_error:
            self.after(200, lambda: messagebox.showerror(self.tr("Unable to load settings"), self.tr(
                "Could not read settings: {error}\n\nUsing English. The original file has been preserved. Repair it and restart to save preferences.\n{path}",
                error=self.settings_error, path=self.settings_store.path), parent=self))

    def tr(self, message, **values):
        return translate(self.language, message, **values)

    def style_ui(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        available = set(tkfont.families(self))
        preferred = {"windows": ("Microsoft YaHei UI", "Segoe UI"),
                     "macos": ("PingFang SC", "Helvetica Neue"),
                     "linux": ("Noto Sans CJK SC", "Noto Sans", "DejaVu Sans")}.get(system_name(), ())
        family = next((name for name in preferred if name in available), tkfont.nametofont("TkDefaultFont").actual("family"))
        self.font_family = family
        style.configure(".", font=(family, 10), background="#f4f7fb", foreground="#172b43")
        style.configure("Title.TLabel", font=(family, 24, "bold"), foreground="#132a43")
        style.configure("Section.TLabel", font=(family, 12, "bold"))
        style.configure("Muted.TLabel", foreground="#61738a")
        style.configure("TButton", padding=(14, 8), borderwidth=0, background="#e6edf5")
        style.map("TButton", background=[("active", "#d8e4f0")], foreground=[("disabled", "#98a5b4")])
        style.configure("Accent.TButton", background="#176cdd", foreground="white")
        style.map("Accent.TButton", background=[("active", "#1059b9"), ("disabled", "#b3cbea")])
        style.configure("TEntry", padding=7, fieldbackground="white")
        style.configure("Treeview", background="white", fieldbackground="white", rowheight=45,
                        borderwidth=0, font=(family, 10))
        style.configure("Treeview.Heading", background="#eaf0f7", font=(family, 10, "bold"), padding=(8, 12))
        style.map("Treeview", background=[("selected", "#dceaff")], foreground=[("selected", "#123d70")])

    def build_ui(self):
        self.title(self.tr("Port Bridge"))
        base = self.base = ttk.Frame(self, padding=26)
        base.pack(fill="both", expand=True)
        top = ttk.Frame(base)
        top.pack(fill="x")
        ttk.Label(top, text=self.tr("Port Bridge"), style="Title.TLabel").pack(side="left")
        ttk.Label(top, text=f"v{VERSION}", style="Muted.TLabel").pack(side="left", padx=18, pady=(10, 0))
        self.summary = tk.StringVar(value=self.tr("Ready"))
        ttk.Label(top, textvariable=self.summary, foreground="#14795c").pack(side="right")
        ttk.Label(base, text=self.tr("Clients  →  Local listening port  →  Target TCP service"),
                  style="Muted.TLabel").pack(anchor="w", pady=(8, 22))
        toolbar = ttk.Frame(base)
        toolbar.pack(fill="x", pady=(0, 14))
        self.add_button = ttk.Button(toolbar, text=self.tr("＋ Add rule"), style="Accent.TButton", command=self.add_rule)
        self.add_button.pack(side="left")
        self.edit_button = ttk.Button(toolbar, text=self.tr("Edit"), command=self.edit_rule)
        self.edit_button.pack(side="left", padx=(8, 0))
        self.delete_button = ttk.Button(toolbar, text=self.tr("Delete"), command=self.delete_rule)
        self.delete_button.pack(side="left", padx=(8, 0))
        self.settings_button = ttk.Button(toolbar, text=self.tr("Settings"), command=self.open_settings)
        self.settings_button.pack(side="right", padx=(8, 0))
        ttk.Button(toolbar, text=self.tr("Stop all"), command=self.stop_all).pack(side="right")
        ttk.Button(toolbar, text=self.tr("Start all"), command=self.start_all).pack(side="right", padx=8)
        table = ttk.Frame(base)
        table.pack(fill="both", expand=True)
        columns = ("name", "listen", "target", "state", "connections", "traffic", "auto")
        self.table = ttk.Treeview(table, columns=columns, show="headings", selectmode="browse", height=3)
        for key, label, width in zip(columns,
            ("Rule name", "Listen endpoint", "Target endpoint", "Status", "Active", "Sent / received", "Auto-start"),
            (155, 180, 185, 90, 65, 180, 105)):
            self.table.heading(key, text=self.tr(label))
            self.table.column(key, width=width, minwidth=50, stretch=True,
                              anchor="center" if key in ("state", "connections", "auto") else "w")
        scroll = ttk.Scrollbar(table, orient="vertical", command=self.table.yview)
        self.table.configure(yscrollcommand=scroll.set)
        self.table.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        self.table.tag_configure("running", foreground="#137556")
        self.table.tag_configure("error", foreground="#b42318")
        self.table.bind("<<TreeviewSelect>>", lambda _: self.update_controls())
        self.table.bind("<Double-1>", lambda _: self.edit_rule())
        self.empty = ttk.Label(self.table, text=self.tr("No forwarding rules yet\nClick Add rule to configure a listening port and target address."),
                               justify="center", style="Muted.TLabel")
        detail = ttk.Frame(base)
        detail.pack(fill="x", pady=(14, 16))
        self.selection_text = tk.StringVar(value=self.tr("Select a rule to start or stop"))
        ttk.Label(detail, textvariable=self.selection_text, style="Muted.TLabel").pack(side="left")
        self.stop_button = ttk.Button(detail, text=self.tr("Stop selected"), command=self.stop_selected)
        self.stop_button.pack(side="right")
        self.start_button = ttk.Button(detail, text=self.tr("Start selected"), style="Accent.TButton", command=self.start_selected)
        self.start_button.pack(side="right", padx=8)
        log_header = ttk.Frame(base)
        log_header.pack(fill="x", pady=(2, 8))
        ttk.Label(log_header, text=self.tr("Activity log"), style="Section.TLabel").pack(side="left")
        ttk.Button(log_header, text=self.tr("Clear"), command=self.clear_logs).pack(side="right")
        log_frame = ttk.Frame(base)
        log_frame.pack(fill="x")
        self.logs = tk.Text(log_frame, height=4, font=(self.font_family, 10), bg="#14273e", fg="#dce9f6", relief="flat",
                            padx=12, pady=12, wrap="word", state="disabled")
        log_scroll = ttk.Scrollbar(log_frame, command=self.logs.yview)
        self.logs.configure(yscrollcommand=log_scroll.set)
        self.logs.pack(side="left", fill="x", expand=True)
        log_scroll.pack(side="right", fill="y")
        foot = ttk.Frame(base)
        foot.pack(fill="x", pady=(18, 0))
        self.autostart = tk.BooleanVar(value=autostart_path().exists())
        self.autostart_check = ttk.Checkbutton(foot, text=self.tr("Open at desktop login"), variable=self.autostart,
                                              command=self.toggle_autostart)
        self.autostart_check.pack(side="left")
        if system_name() not in ("windows", "macos", "linux"):
            self.autostart_check.state(["disabled"])
        ttk.Label(foot, text=self.tr("Forwarding continues while minimized; exiting stops all rules."), style="Muted.TLabel").pack(side="right")
        self.render_logs()

    def refresh(self):
        selected = self.table.selection()
        current = set(self.table.get_children())
        for rule in self.rules:
            metric = self.metrics.get(rule.id, {})
            state = self.states.get(rule.id, "stopped")
            values = (rule.name, endpoint(rule.listen_host, rule.listen_port), endpoint(rule.target_host, rule.target_port),
                      self.tr(state), metric.get("connections", 0),
                      f"{human_bytes(metric.get('up', 0))} / {human_bytes(metric.get('down', 0))}",
                      self.tr("Yes" if rule.auto_start else "No"))
            tag = "running" if state == "running" else "error" if state == "failed" else ""
            if rule.id in current:
                self.table.item(rule.id, values=values, tags=(tag,))
                current.remove(rule.id)
            else:
                self.table.insert("", "end", iid=rule.id, values=values, tags=(tag,))
        for key in current:
            self.table.delete(key)
        if selected and self.table.exists(selected[0]):
            self.table.selection_set(selected)
        if self.rules:
            self.empty.place_forget()
        else:
            self.empty.place(relx=0.5, rely=0.5, anchor="center")
        running = sum(self.states.get(rule.id) == "running" for rule in self.rules)
        connections = sum(item.get("connections", 0) for item in self.metrics.values())
        self.summary.set(self.tr("{running} / {count} running    ·    Connections: {connections}",
                                 running=running, count=len(self.rules), connections=connections))
        self.update_controls()

    def selected(self):
        ids = self.table.selection()
        return next((rule for rule in self.rules if ids and rule.id == ids[0]), None)

    def update_controls(self):
        rule = self.selected()
        state = self.states.get(rule.id, "stopped") if rule else ""
        busy = state in ("running", "starting", "stopping")
        editable = bool(rule and not busy and not self.read_error)
        for button, enabled in ((self.edit_button, editable), (self.delete_button, editable),
                                (self.start_button, bool(rule and not busy and not self.read_error)),
                                (self.stop_button, state == "running"),
                                (self.add_button, not self.read_error)):
            button.state(["!disabled" if enabled else "disabled"])
        if rule:
            metric = self.metrics.get(rule.id, {})
            self.selection_text.set(self.tr("{name}  ·  Connections: {total} total / Errors: {errors}",
                                            name=rule.name, total=metric.get("total", 0), errors=metric.get("errors", 0)))
        else:
            self.selection_text.set(self.tr("Select a rule to start or stop. Stop a running rule before editing."))

    def persist(self, rules):
        if self.read_error:
            return False
        try:
            self.config_store.save(rules)
        except Exception as exc:
            messagebox.showerror(self.tr("Unable to save"), error_text(exc, self.language), parent=self)
            return False
        self.rules = rules
        self.refresh()
        return True

    def add_rule(self):
        if self.read_error:
            return
        dialog = RuleDialog(self)
        self.wait_window(dialog)
        if dialog.result and self.persist(self.rules + [dialog.result]):
            self.table.selection_set(dialog.result.id)
            self.append_log(dialog.result.name, "Rule saved. Click Start selected to begin forwarding.")

    def edit_rule(self):
        rule = self.selected()
        if not rule or self.states.get(rule.id) in ("running", "starting", "stopping") or self.read_error:
            return
        dialog = RuleDialog(self, rule)
        self.wait_window(dialog)
        if dialog.result:
            self.persist([dialog.result if item.id == rule.id else item for item in self.rules])

    def delete_rule(self):
        rule = self.selected()
        if not rule or self.states.get(rule.id) in ("running", "starting", "stopping"):
            return
        if self.persist([item for item in self.rules if item.id != rule.id]):
            self.states.pop(rule.id, None)
            self.metrics.pop(rule.id, None)
            self.refresh()

    def start_rule(self, rule):
        if self.closing or self.read_error or self.states.get(rule.id) in ("running", "starting", "stopping"):
            return
        self.states[rule.id] = "starting"
        self.metrics.pop(rule.id, None)
        self.worker.submit("start", rule)
        self.refresh()

    def start_selected(self):
        if self.selected():
            self.start_rule(self.selected())

    def start_all(self):
        for rule in self.rules:
            self.start_rule(rule)

    def stop_rule(self, rule):
        if self.states.get(rule.id) not in ("running", "starting"):
            return
        self.states[rule.id] = "stopping"
        self.worker.submit("stop", rule)
        self.refresh()

    def stop_selected(self):
        if self.selected():
            self.stop_rule(self.selected())

    def stop_all(self):
        for rule in self.rules:
            self.stop_rule(rule)

    def append_log(self, name, message, **values):
        self.log_records.append((datetime.now().strftime("%H:%M:%S"), name, message, values))
        self.render_logs()

    def render_logs(self):
        self.logs.configure(state="normal")
        self.logs.delete("1.0", "end")
        lines = []
        for timestamp, name, message, values in self.log_records:
            label = name if name is not None else self.tr("Application")
            lines.append(f"{timestamp}  [{label}] {self.tr(message, **values)}\n")
        self.logs.insert("end", "".join(lines))
        self.logs.see("end")
        self.logs.configure(state="disabled")

    def clear_logs(self):
        self.log_records.clear()
        self.render_logs()

    def open_settings(self):
        dialog = SettingsDialog(self)
        self.wait_window(dialog)

    def set_language(self, language):
        # Save first: a failed write must not silently change the displayed preference.
        self.settings_store.save_language(language)
        if language == self.language:
            return
        selected = self.table.selection()
        scroll = self.table.yview()
        self.language = language
        self.base.destroy()
        self.build_ui()
        self.refresh()
        if selected and self.table.exists(selected[0]):
            self.table.selection_set(selected)
        self.table.yview_moveto(scroll[0])
        self.update_controls()

    def poll(self):
        self.poll_id = None
        changed = False
        for _ in range(300):
            try:
                event = self.worker.events.get_nowait()
            except queue.Empty:
                break
            if event["type"] == "status":
                self.states[event["id"]] = event["state"]
                if event["state"] == "stopped" and event["id"] in self.metrics:
                    self.metrics[event["id"]]["connections"] = 0
                changed = True
            elif event["type"] == "log":
                self.append_log(event.get("name"), event["message"], **event.get("values", {}))
            elif event["type"] == "stats":
                self.metrics.update(event["data"])
                changed = True
        if changed:
            self.refresh()
        if not self.closing:
            self.poll_id = self.after(100, self.poll)

    def toggle_autostart(self):
        try:
            set_autostart(self.autostart.get(), Path(__file__).resolve())
        except Exception as exc:
            self.autostart.set(not self.autostart.get())
            messagebox.showerror(self.tr("Unable to set autostart"), error_text(exc, self.language), parent=self)

    def close(self):
        if self.closing:
            return
        self.closing = True
        if self.poll_id is not None:
            self.after_cancel(self.poll_id)
            self.poll_id = None
        self.withdraw()
        self.worker.close()
        self.after(50, self.finish_close)

    def finish_close(self):
        if self.worker.thread.is_alive():
            self.after(50, self.finish_close)
        else:
            self.destroy()


def main():
    import argparse
    import json
    import tempfile
    parser = argparse.ArgumentParser(description="Port Bridge desktop TCP forwarding")
    parser.add_argument("--platform-info", action="store_true", help="Print OS and Python runtime architecture as JSON")
    parser.add_argument("--smoke-test", action="store_true", help="Open and close an isolated test window")
    args = parser.parse_args()
    if args.platform_info:
        print(json.dumps(runtime_info(), indent=2))
        return
    if args.smoke_test:
        with tempfile.TemporaryDirectory(prefix="port-bridge-smoke-") as folder:
            app = App(Path(folder) / "rules.json")
            app.after(500, app.close)
            app.mainloop()
        return
    folder = config_directory()
    lock = InstanceLock(folder / "app.lock")
    if not lock.acquire():
        root = tk.Tk()
        root.withdraw()
        try:
            language = Settings(folder / "settings.json").language()
        except Exception:
            language = DEFAULT_LANGUAGE
        messagebox.showinfo(translate(language, "Port Bridge is already running"),
                            translate(language, "The application is already open. Find its window in the taskbar."), parent=root)
        root.destroy()
        return
    try:
        App().mainloop()
    finally:
        lock.close()


if __name__ == "__main__":
    main()
