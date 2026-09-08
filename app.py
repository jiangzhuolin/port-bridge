#!/usr/bin/env python3
"""Port Bridge desktop application. Run: python3 app.py"""
import asyncio
from datetime import datetime
from pathlib import Path
import queue
import sys
import threading
import tkinter as tk
from tkinter import messagebox, ttk
import uuid

from bridge import Config, Engine, Rule, endpoint
from desktop import autostart_path, config_home, set_autostart

VERSION = "1.0.0"


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
                    self.events.put({"type": "status", "id": rule.id, "state": "启动失败"})
                    self.events.put({"type": "log", "name": rule.name, "message": str(exc)})
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
        self.title("编辑转发规则" if rule else "添加转发规则")
        self.resizable(False, False)
        self.transient(parent)
        self.result = None
        self.rule = rule
        self.configure(bg="#f4f7fb")
        box = ttk.Frame(self, padding=24)
        box.pack(fill="both", expand=True)
        ttk.Label(box, text="监听 Ubuntu，连接目标", style="Section.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        ttk.Label(box, text="目标填写 Windows 的可达 IP；地址中不要填写协议。",
                  style="Muted.TLabel").grid(row=1, column=0, columnspan=2, sticky="w", pady=(0, 18))
        values = rule or Rule(uuid.uuid4().hex, "Windows 代理")
        self.fields = {}
        entries = []
        for row, (key, label) in enumerate([
            ("name", "规则名称"), ("listen_host", "Ubuntu 监听地址"),
            ("listen_port", "Ubuntu 监听端口"), ("target_host", "目标 IP / 主机名"),
            ("target_port", "目标端口")], 2):
            ttk.Label(box, text=label).grid(row=row, column=0, sticky="w", padx=(0, 20), pady=8)
            variable = tk.StringVar(value=str(getattr(values, key)))
            self.fields[key] = variable
            entry = ttk.Entry(box, textvariable=variable, width=32)
            entry.grid(row=row, column=1, sticky="ew", pady=8)
            entries.append(entry)
        self.auto = tk.BooleanVar(value=values.auto_start)
        ttk.Checkbutton(box, text="软件启动时自动启用这条规则", variable=self.auto).grid(
            row=7, column=0, columnspan=2, sticky="w", pady=(14, 8))
        ttk.Label(box, text="0.0.0.0 监听所有 IPv4 网卡，容器可通过 Ubuntu IP 访问。",
                  style="Muted.TLabel").grid(row=8, column=0, columnspan=2, sticky="w", pady=8)
        self.error = tk.StringVar()
        ttk.Label(box, textvariable=self.error, foreground="#b42318", wraplength=430).grid(
            row=9, column=0, columnspan=2, sticky="w")
        buttons = ttk.Frame(box)
        buttons.grid(row=10, column=0, columnspan=2, sticky="e", pady=(16, 0))
        ttk.Button(buttons, text="取消", command=self.destroy).pack(side="left", padx=8)
        ttk.Button(buttons, text="保存规则", style="Accent.TButton", command=self.save).pack(side="left")
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
                raise ValueError("端口必须是 1–65535 的整数") from None
            self.result = Rule(id=self.rule.id if self.rule else uuid.uuid4().hex,
                               auto_start=self.auto.get(), **values).validate()
        except ValueError as exc:
            self.error.set(str(exc))
            return
        self.destroy()


class App(tk.Tk):
    def __init__(self, config_path=None):
        super().__init__()
        self.title("端口桥 · Port Bridge")
        self.geometry("1160x800")
        self.minsize(1000, 740)
        self.configure(bg="#f4f7fb")
        self.config_store = Config(config_path or config_home() / "port-bridge" / "rules.json")
        self.rules = []
        self.states = {}
        self.metrics = {}
        self.closing = False
        self.read_error = None
        try:
            self.rules = self.config_store.load()
        except Exception as exc:
            self.read_error = f"无法读取配置：{exc}\n\n原文件已保留。修复配置后重新打开软件。\n{self.config_store.path}"
        self.worker = Worker()
        self.style_ui()
        self.build_ui()
        self.refresh()
        self.protocol("WM_DELETE_WINDOW", self.close)
        self.poll_id = self.after(100, self.poll)
        if self.read_error:
            self.after(150, lambda: messagebox.showerror("配置读取失败", self.read_error, parent=self))
        else:
            for rule in self.rules:
                if rule.auto_start:
                    self.start_rule(rule)

    def style_ui(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        family = "Noto Sans CJK SC" if sys.platform.startswith("linux") else "Microsoft YaHei UI"
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
        base = ttk.Frame(self, padding=26)
        base.pack(fill="both", expand=True)
        top = ttk.Frame(base)
        top.pack(fill="x")
        ttk.Label(top, text="端口桥", style="Title.TLabel").pack(side="left")
        ttk.Label(top, text=f"PORT BRIDGE  /  {VERSION}", style="Muted.TLabel").pack(side="left", padx=18, pady=(10, 0))
        self.summary = tk.StringVar(value="准备就绪")
        ttk.Label(top, textvariable=self.summary, foreground="#14795c").pack(side="right")
        ttk.Label(base, text="Docker 容器  →  Ubuntu 监听端口  →  Windows / 其他目标",
                  style="Muted.TLabel").pack(anchor="w", pady=(8, 22))
        toolbar = ttk.Frame(base)
        toolbar.pack(fill="x", pady=(0, 14))
        self.add_button = ttk.Button(toolbar, text="＋ 添加规则", style="Accent.TButton", command=self.add_rule)
        self.add_button.pack(side="left")
        self.edit_button = ttk.Button(toolbar, text="编辑", command=self.edit_rule)
        self.edit_button.pack(side="left", padx=(8, 0))
        self.delete_button = ttk.Button(toolbar, text="删除", command=self.delete_rule)
        self.delete_button.pack(side="left", padx=(8, 0))
        ttk.Button(toolbar, text="全部停止", command=self.stop_all).pack(side="right")
        ttk.Button(toolbar, text="全部启动", command=self.start_all).pack(side="right", padx=8)
        table = ttk.Frame(base)
        table.pack(fill="both", expand=True)
        columns = ("name", "listen", "target", "state", "connections", "traffic", "auto")
        self.table = ttk.Treeview(table, columns=columns, show="headings", selectmode="browse", height=3)
        for key, label, width in zip(columns,
            ("规则名称", "Ubuntu 监听", "转发目标", "状态", "连接", "发送 / 接收", "随软件启动"),
            (145, 177, 190, 90, 55, 165, 95)):
            self.table.heading(key, text=label)
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
        self.empty = ttk.Label(self.table, text="还没有转发规则\n点击「添加规则」，设置 Ubuntu 监听端口和 Windows 目标地址。",
                               justify="center", style="Muted.TLabel")
        detail = ttk.Frame(base)
        detail.pack(fill="x", pady=(14, 16))
        self.selection_text = tk.StringVar(value="选择一条规则以启动或停止")
        ttk.Label(detail, textvariable=self.selection_text, style="Muted.TLabel").pack(side="left")
        self.stop_button = ttk.Button(detail, text="停止所选", command=self.stop_selected)
        self.stop_button.pack(side="right")
        self.start_button = ttk.Button(detail, text="启动所选", style="Accent.TButton", command=self.start_selected)
        self.start_button.pack(side="right", padx=8)
        log_header = ttk.Frame(base)
        log_header.pack(fill="x", pady=(2, 8))
        ttk.Label(log_header, text="运行日志", style="Section.TLabel").pack(side="left")
        ttk.Button(log_header, text="清空", command=self.clear_logs).pack(side="right")
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
        self.autostart = tk.BooleanVar(value=autostart_path().exists() if sys.platform.startswith("linux") else False)
        self.autostart_check = ttk.Checkbutton(foot, text="登录 Linux 桌面后自动打开", variable=self.autostart,
                                              command=self.toggle_autostart)
        self.autostart_check.pack(side="left")
        if not sys.platform.startswith("linux"):
            self.autostart_check.state(["disabled"])
        ttk.Label(foot, text="最小化继续转发 · 退出软件停止全部转发", style="Muted.TLabel").pack(side="right")
        self.append_log("软件", "TCP 透明转发已就绪；HTTP / SOCKS5 协议由目标代理提供。")

    def refresh(self):
        selected = self.table.selection()
        current = set(self.table.get_children())
        for rule in self.rules:
            metric = self.metrics.get(rule.id, {})
            state = self.states.get(rule.id, "已停止")
            values = (rule.name, endpoint(rule.listen_host, rule.listen_port), endpoint(rule.target_host, rule.target_port),
                      state, metric.get("connections", 0),
                      f"{human_bytes(metric.get('up', 0))} / {human_bytes(metric.get('down', 0))}",
                      "是" if rule.auto_start else "否")
            tag = "running" if state == "运行中" else "error" if state == "启动失败" else ""
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
        running = sum(self.states.get(rule.id) == "运行中" for rule in self.rules)
        connections = sum(item.get("connections", 0) for item in self.metrics.values())
        self.summary.set(f"{running} / {len(self.rules)} 条运行中    ·    {connections} 个连接")
        self.update_controls()

    def selected(self):
        ids = self.table.selection()
        return next((rule for rule in self.rules if ids and rule.id == ids[0]), None)

    def update_controls(self):
        rule = self.selected()
        state = self.states.get(rule.id, "已停止") if rule else ""
        busy = state in ("运行中", "启动中", "停止中")
        editable = bool(rule and not busy and not self.read_error)
        for button, enabled in ((self.edit_button, editable), (self.delete_button, editable),
                                (self.start_button, bool(rule and not busy and not self.read_error)),
                                (self.stop_button, state == "运行中"),
                                (self.add_button, not self.read_error)):
            button.state(["!disabled" if enabled else "disabled"])
        if rule:
            metric = self.metrics.get(rule.id, {})
            self.selection_text.set(f"{rule.name}  ·  累计 {metric.get('total', 0)} 次连接 / {metric.get('errors', 0)} 次异常")
        else:
            self.selection_text.set("选择一条规则以启动或停止；编辑运行中的规则前请先停止。")

    def persist(self, rules):
        if self.read_error:
            return False
        try:
            self.config_store.save(rules)
        except Exception as exc:
            messagebox.showerror("无法保存", str(exc), parent=self)
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
            self.append_log(dialog.result.name, "规则已保存，点击「启动所选」开始转发。")

    def edit_rule(self):
        rule = self.selected()
        if not rule or self.states.get(rule.id) in ("运行中", "启动中", "停止中") or self.read_error:
            return
        dialog = RuleDialog(self, rule)
        self.wait_window(dialog)
        if dialog.result:
            self.persist([dialog.result if item.id == rule.id else item for item in self.rules])

    def delete_rule(self):
        rule = self.selected()
        if not rule or self.states.get(rule.id) in ("运行中", "启动中", "停止中"):
            return
        if self.persist([item for item in self.rules if item.id != rule.id]):
            self.states.pop(rule.id, None)
            self.metrics.pop(rule.id, None)
            self.refresh()

    def start_rule(self, rule):
        if self.closing or self.read_error or self.states.get(rule.id) in ("运行中", "启动中", "停止中"):
            return
        self.states[rule.id] = "启动中"
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
        if self.states.get(rule.id) not in ("运行中", "启动中"):
            return
        self.states[rule.id] = "停止中"
        self.worker.submit("stop", rule)
        self.refresh()

    def stop_selected(self):
        if self.selected():
            self.stop_rule(self.selected())

    def stop_all(self):
        for rule in self.rules:
            self.stop_rule(rule)

    def append_log(self, name, message):
        self.logs.configure(state="normal")
        self.logs.insert("end", f"{datetime.now():%H:%M:%S}  [{name}] {message}\n")
        line_count = int(self.logs.index("end-1c").split(".")[0])
        if line_count > 500:
            self.logs.delete("1.0", f"{line_count - 500}.0")
        self.logs.see("end")
        self.logs.configure(state="disabled")

    def clear_logs(self):
        self.logs.configure(state="normal")
        self.logs.delete("1.0", "end")
        self.logs.configure(state="disabled")

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
                if event["state"] == "已停止" and event["id"] in self.metrics:
                    self.metrics[event["id"]]["connections"] = 0
                changed = True
            elif event["type"] == "log":
                self.append_log(event.get("name", "软件"), event["message"])
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
            messagebox.showerror("无法设置自动启动", str(exc), parent=self)

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
    lock_file = None
    if sys.platform.startswith("linux"):
        import fcntl
        folder = config_home() / "port-bridge"
        folder.mkdir(parents=True, exist_ok=True)
        lock_file = (folder / "app.lock").open("a")
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("端口桥已运行", "软件已打开，请在任务栏中找到端口桥窗口。", parent=root)
            root.destroy()
            lock_file.close()
            return
    try:
        App().mainloop()
    finally:
        if lock_file:
            lock_file.close()


if __name__ == "__main__":
    main()
