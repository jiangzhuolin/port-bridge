import asyncio
from dataclasses import replace
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bridge import Config, Engine, Rule


def free_port(host="127.0.0.1", family=socket.AF_INET):
    with socket.socket(family, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        return sock.getsockname()[1]


class ForwardingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events = []
        self.engine = Engine(self.events.append, connect_timeout=0.5)
        self.connections = set()

        async def echo(reader, writer):
            self.connections.add(writer)
            try:
                while chunk := await reader.read(65536):
                    writer.write(chunk)
                    await writer.drain()
            except (OSError, asyncio.CancelledError):
                pass
            finally:
                writer.close()
                self.connections.discard(writer)

        self.echo = echo
        self.target = await asyncio.start_server(echo, "127.0.0.1", 0)
        self.target_port = self.target.sockets[0].getsockname()[1]
        self.rule = Rule("one", "测试规则", "127.0.0.1", free_port(), "127.0.0.1", self.target_port)

    async def asyncTearDown(self):
        await self.engine.stop_all()
        self.target.close()
        await self.target.wait_closed()
        for writer in tuple(self.connections):
            writer.close()
            await writer.wait_closed()

    async def exchange(self, port, payload):
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        try:
            writer.write(payload)
            await writer.drain()
            result = await asyncio.wait_for(reader.readexactly(len(payload)), 8)
            self.assertEqual(result, payload)
        finally:
            writer.close()
            await writer.wait_closed()

    async def test_multiple_rules_concurrent_binary_traffic(self):
        second = replace(self.rule, id="two", listen_port=free_port())
        await self.engine.start(self.rule)
        await self.engine.start(second)
        payload = os.urandom(256 * 1024)
        await asyncio.gather(*(self.exchange(rule.listen_port, payload)
                               for rule in (self.rule, second) for _ in range(8)))
        await asyncio.sleep(0.05)
        for stats in self.engine.snapshot().values():
            self.assertEqual(stats["up"], 8 * len(payload))
            self.assertEqual(stats["down"], 8 * len(payload))
            self.assertEqual(stats["errors"], 0)

    async def test_half_close_allows_delayed_response(self):
        async def respond_after_eof(reader, writer):
            data = await reader.read()
            await asyncio.sleep(0.02)
            writer.write(b"response:" + data)
            await writer.drain()
            writer.close()
            await writer.wait_closed()
        server = await asyncio.start_server(respond_after_eof, "127.0.0.1", 0)
        rule = replace(self.rule, target_port=server.sockets[0].getsockname()[1])
        try:
            await self.engine.start(rule)
            reader, writer = await asyncio.open_connection("127.0.0.1", rule.listen_port)
            writer.write(b"request")
            await writer.drain()
            writer.write_eof()
            self.assertEqual(await asyncio.wait_for(reader.read(), 3), b"response:request")
            writer.close()
            await writer.wait_closed()
        finally:
            server.close()
            await server.wait_closed()

    async def test_bind_conflict_does_not_break_existing_rule(self):
        await self.engine.start(self.rule)
        with self.assertRaises(OSError):
            await self.engine.start(replace(self.rule, id="collision"))
        self.assertNotIn("collision", self.engine.listeners)
        await self.exchange(self.rule.listen_port, b"still works")

    async def test_stop_closes_active_connections_and_releases_port(self):
        await self.engine.start(self.rule)
        reader, writer = await asyncio.open_connection("127.0.0.1", self.rule.listen_port)
        writer.write(b"hello")
        await writer.drain()
        self.assertEqual(await reader.readexactly(5), b"hello")
        state = self.engine.listeners[self.rule.id]
        await self.engine.stop(self.rule.id)
        self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        self.assertFalse(state.tasks)
        self.assertFalse(state.writers)
        writer.close()
        await writer.wait_closed()
        await self.engine.start(self.rule)
        await self.exchange(self.rule.listen_port, b"restarted")

    async def test_offline_target_recovers_without_restart(self):
        port = free_port()
        rule = replace(self.rule, target_port=port)
        await self.engine.start(rule)
        reader, writer = await asyncio.open_connection("127.0.0.1", rule.listen_port)
        self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        writer.close()
        await writer.wait_closed()
        self.assertTrue(any("连接失败" in item.get("message", "") for item in self.events))
        server = await asyncio.start_server(self.echo, "127.0.0.1", port)
        try:
            await self.exchange(rule.listen_port, b"target recovered")
        finally:
            server.close()
            await server.wait_closed()

    async def test_ipv6_listener(self):
        try:
            port = free_port("::1", socket.AF_INET6)
        except OSError:
            self.skipTest("IPv6 not available")
        rule = replace(self.rule, listen_host="::1", listen_port=port)
        await self.engine.start(rule)
        reader, writer = await asyncio.open_connection("::1", port)
        writer.write(b"ipv6")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.readexactly(4), 2), b"ipv6")
        writer.close()
        await writer.wait_closed()

    async def test_self_forward_detected_before_connect(self):
        # Resolve a hostname to a local address to exercise runtime loop protection.
        rule = replace(self.rule, listen_host="0.0.0.0", target_host="self.invalid",
                       target_port=self.rule.listen_port)
        await self.engine.start(rule)
        resolved = [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "",
                     ("127.0.0.1", rule.listen_port))]
        with patch.object(asyncio.get_running_loop(), "getaddrinfo", AsyncMock(return_value=resolved)):
            reader, writer = await asyncio.open_connection("127.0.0.1", rule.listen_port)
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
            writer.close()
            await writer.wait_closed()
        self.assertEqual(self.engine.snapshot()[rule.id]["total"], 1)
        self.assertTrue(any("转发循环" in item.get("message", "") for item in self.events))


class ConfigTests(unittest.TestCase):
    def test_round_trip_unicode_and_saved_autostart(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "nested" / "rules.json"
            store = Config(path)
            rule = Rule("one", "Windows 代理", target_host="192.168.100.1", auto_start=True)
            store.save([rule])
            self.assertEqual(store.load(), [rule])
            store.save([])
            self.assertEqual(store.load(), [])

    def test_corrupted_file_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "rules.json"
            path.write_text("{broken", encoding="utf-8")
            with self.assertRaises(json.JSONDecodeError):
                Config(path).load()
            self.assertEqual(path.read_text(), "{broken")

    def test_validation(self):
        rule = Rule("one", "代理", target_host="192.168.100.1")
        for changes in ({"target_port": 0}, {"listen_port": 65536}, {"target_port": True},
                        {"target_host": "http://example.com"}, {"listen_host": "invalid"},
                        {"target_host": "127.0.0.1"}, {"name": ""}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                replace(rule, **changes).validate()


if __name__ == "__main__":
    unittest.main()
