"""Port Bridge: bounded-memory, bidirectional TCP forwarding (Python 3.10+)."""
import asyncio
import contextlib
import ipaddress
import json
import os
from pathlib import Path
import socket
import tempfile
import time
from dataclasses import asdict, dataclass, field


@dataclass(frozen=True)
class Rule:
    id: str
    name: str
    listen_host: str = "0.0.0.0"
    listen_port: int = 10808
    target_host: str = ""
    target_port: int = 10808
    auto_start: bool = False

    def validate(self):
        if not isinstance(self.id, str) or not self.id:
            raise ValueError("规则 ID 无效")
        if not isinstance(self.name, str) or not self.name.strip():
            raise ValueError("请输入规则名称")
        try:
            ipaddress.ip_address(self.listen_host)
        except ValueError:
            raise ValueError("监听地址必须是 IP，例如 0.0.0.0、127.0.0.1 或 ::") from None
        if (not isinstance(self.target_host, str) or not self.target_host
                or any(c.isspace() for c in self.target_host)
                or any(c in self.target_host for c in "/[]")):
            raise ValueError("目标地址请只填 IP 或主机名，不含协议、端口或方括号")
        for port in (self.listen_port, self.target_port):
            if type(port) is not int or not 1 <= port <= 65535:
                raise ValueError("端口必须是 1–65535 的整数")
        if type(self.auto_start) is not bool:
            raise ValueError("自动启动选项无效")
        if self.listen_port == self.target_port:
            try:
                target = ipaddress.ip_address(self.target_host)
            except ValueError:
                target = None
            local = ipaddress.ip_address(self.listen_host)
            if (target and (target == local or (local.is_unspecified and target.is_loopback))) or (
                    self.target_host.lower() == "localhost" and (local.is_loopback or local.is_unspecified)):
                raise ValueError("目标指向当前监听端口，会形成转发循环")
        return self


def endpoint(host, port):
    return f"[{host}]:{port}" if ":" in host else f"{host}:{port}"


class Config:
    def __init__(self, path):
        self.path = Path(path)

    def load(self):
        if not self.path.exists():
            return []
        data = json.loads(self.path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("rules"), list):
            raise ValueError("不支持的配置格式")
        rules = [Rule(**item).validate() for item in data["rules"]]
        if len({r.id for r in rules}) != len(rules):
            raise ValueError("配置包含重复规则 ID")
        return rules

    def save(self, rules):
        for rule in rules:
            rule.validate()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix=".rules-", dir=self.path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump({"version": 1, "rules": [asdict(r) for r in rules]}, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(name, self.path)
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(name)


@dataclass
class Listener:
    rule: Rule
    server: object = None
    tasks: set = field(default_factory=set)
    writers: set = field(default_factory=set)
    stopping: bool = False
    up: int = 0
    down: int = 0
    total: int = 0
    errors: int = 0
    last_error_log: float = 0


class Engine:
    """All methods and callbacks run on a single asyncio loop."""
    def __init__(self, emit=lambda event: None, connect_timeout=10, max_connections=512):
        self.emit = emit
        self.connect_timeout = connect_timeout
        self.max_connections = max_connections
        self.listeners = {}

    def log(self, rule, message):
        self.emit({"type": "log", "id": rule.id, "name": rule.name, "message": message})

    async def start(self, rule):
        rule.validate()
        if rule.id in self.listeners:
            return
        state = Listener(rule)
        family = socket.AF_INET6 if ":" in rule.listen_host else socket.AF_INET
        try:
            server = await asyncio.start_server(
                lambda reader, writer: self.accept(state, reader, writer),
                rule.listen_host, rule.listen_port, family=family, start_serving=False)
        except OSError as exc:
            self.emit({"type": "status", "id": rule.id, "state": "启动失败"})
            self.log(rule, f"无法监听 {endpoint(rule.listen_host, rule.listen_port)}：{exc}")
            raise
        state.server = server
        self.listeners[rule.id] = state
        try:
            await server.start_serving()
        except BaseException:
            server.close()
            await server.wait_closed()
            self.listeners.pop(rule.id, None)
            raise
        self.emit({"type": "status", "id": rule.id, "state": "运行中"})
        self.log(rule, f"已监听 {endpoint(rule.listen_host, rule.listen_port)} → {endpoint(rule.target_host, rule.target_port)}")

    def accept(self, state, reader, writer):
        if state.stopping or len(state.tasks) >= self.max_connections:
            writer.close()
            return
        state.writers.add(writer)
        task = asyncio.create_task(self.relay(state, reader, writer))
        state.tasks.add(task)
        task.add_done_callback(state.tasks.discard)

    async def relay(self, state, reader, writer):
        upstream = None
        pumps = []
        state.total += 1
        try:
            if state.rule.listen_port == state.rule.target_port:
                # A probe bind identifies local destinations without sending traffic.
                addresses = await asyncio.wait_for(asyncio.get_running_loop().getaddrinfo(
                    state.rule.target_host, state.rule.target_port, type=socket.SOCK_STREAM),
                    timeout=self.connect_timeout)
                for family, kind, proto, _, address in addresses:
                    local = ipaddress.ip_address(state.rule.listen_host)
                    if not local.is_unspecified and str(local) != address[0]:
                        continue
                    with socket.socket(family, kind, proto) as probe:
                        try:
                            probe.bind((address[0], 0))
                        except OSError:
                            continue
                    raise OSError("目标是本机同一监听端口，已阻止转发循环")
            remote_reader, upstream = await asyncio.wait_for(
                asyncio.open_connection(state.rule.target_host, state.rule.target_port),
                timeout=self.connect_timeout)
            state.writers.add(upstream)

            async def copy(source, destination, direction):
                while True:
                    chunk = await source.read(65536)
                    if not chunk:
                        if destination.can_write_eof():
                            destination.write_eof()
                            await destination.drain()
                        return
                    destination.write(chunk)
                    await destination.drain()
                    setattr(state, direction, getattr(state, direction) + len(chunk))

            pumps = [asyncio.create_task(copy(reader, upstream, "up")),
                     asyncio.create_task(copy(remote_reader, writer, "down"))]
            await asyncio.gather(*pumps)
        except (OSError, asyncio.TimeoutError) as exc:
            state.errors += 1
            if time.monotonic() - state.last_error_log >= 1:
                self.log(state.rule, f"连接失败 / 中断：{exc or '连接目标超时'}")
                state.last_error_log = time.monotonic()
        finally:
            for task in pumps:
                task.cancel()
            if pumps:
                await asyncio.gather(*pumps, return_exceptions=True)
            for stream in (upstream, writer):
                if stream:
                    stream.close()
                    state.writers.discard(stream)
            for stream in (upstream, writer):
                if stream:
                    with contextlib.suppress(OSError, asyncio.TimeoutError):
                        await asyncio.wait_for(stream.wait_closed(), timeout=2)

    async def stop(self, rule_id):
        state = self.listeners.get(rule_id)
        if state is None:
            self.emit({"type": "status", "id": rule_id, "state": "已停止"})
            return
        state.stopping = True
        state.server.close()
        # Close accepted transports even if their relay coroutine hasn't started.
        for writer in tuple(state.writers):
            writer.close()
        tasks = list(state.tasks)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await state.server.wait_closed()
        state.writers.clear()
        self.listeners.pop(rule_id, None)
        self.emit({"type": "status", "id": rule_id, "state": "已停止"})
        self.log(state.rule, "已停止监听并关闭现有连接")

    async def stop_all(self):
        for rule_id in list(self.listeners):
            await self.stop(rule_id)

    def snapshot(self):
        return {key: {"connections": len(s.tasks), "up": s.up, "down": s.down,
                      "total": s.total, "errors": s.errors}
                for key, s in self.listeners.items()}
