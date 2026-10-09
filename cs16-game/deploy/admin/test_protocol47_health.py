"""Tests for protocol47_health.py and the dashboard's health section."""
import json
import tempfile
import time
import unittest
from pathlib import Path

import protocol47_admin as admin
import protocol47_health as health

NOW = 1_790_000_000.0


def entry(seconds, message, source="protocol47-server.x86_64", cursor=None):
    return {"__REALTIME_TIMESTAMP": str(int(seconds * 1_000_000)), "MESSAGE": message,
            "SYSLOG_IDENTIFIER": source, "__CURSOR": cursor or f"c{seconds}"}


# Taken from the Oct 9 production crash and its debug-build diagnosis.
JOURNAL = [
    entry(NOW, "Started protocol47.service - Protocol 47 dedicated Dust2 server.", "systemd"),
    entry(NOW + 1, "SCRIPT ERROR: Trying to cast a freed object."),
    entry(NOW + 1, "          at: BotCombatController._advance_tactics_from_perception (res://scripts/bot_controller.gd:237)"),
    entry(NOW + 1, "          GDScript backtrace (most recent call first):"),
    entry(NOW + 1, "              [0] _advance_tactics_from_perception (res://scripts/bot_controller.gd:237)"),
    entry(NOW + 1, "              [1] gather_command (res://scripts/bot_controller.gd:172)"),
    entry(NOW + 2, "SCRIPT ERROR: Trying to cast a freed object."),
    entry(NOW + 2, "          at: BotCombatController._advance_tactics_from_perception (res://scripts/bot_controller.gd:237)"),
    entry(NOW + 3, 'ERROR: Condition "ready_state != STATE_OPEN" is true. Returning: FAILED'),
    entry(NOW + 3, "   at: _send (modules/websocket/wsl_peer.cpp:788)"),
    entry(NOW + 4, "Protocol 47 dedicated server listening on UDP 27447"),
    entry(NOW + 5, "protocol47.service: Main process exited, code=dumped, status=11/SEGV", "systemd"),
    entry(NOW + 5, "protocol47.service: Failed with result 'core-dump'.", "systemd"),
    entry(NOW + 8, "protocol47.service: Scheduled restart job, restart counter is at 1.", "systemd"),
    entry(NOW + 8.5, "Stopping protocol47.service - Protocol 47 dedicated Dust2 server...", "systemd"),
    entry(NOW + 8.6, "Stopped protocol47.service - Protocol 47 dedicated Dust2 server.", "systemd"),
    {"__REALTIME_TIMESTAMP": str(int((NOW + 9) * 1_000_000)), "MESSAGE": list(b"SCRIPT ERROR: bytes \xff message"),
     "SYSLOG_IDENTIFIER": "protocol47-server.x86_64", "__CURSOR": "last"},
]


class JournalParsingTest(unittest.TestCase):
    def test_lifecycle_and_grouped_errors(self):
        records = list(health.parse_game_journal(JOURNAL))
        lifecycle = [r for kind, r in records if kind == "lifecycle"]
        errors = [r for kind, r in records if kind == "error"]
        self.assertEqual([r["kind"] for r in lifecycle], ["start", "crash", "restart", "stop"])
        self.assertEqual(lifecycle[1]["detail"], "code=dumped, status=11/SEGV")
        freed = [e for e in errors if "freed object" in e["message"]]
        self.assertEqual(len(freed), 2)
        self.assertEqual(freed[0]["fingerprint"], freed[1]["fingerprint"], "repeats group together")
        self.assertIn("bot_controller.gd:237", freed[0]["location"])
        self.assertIn("gather_command", freed[0]["backtrace"])
        engine = next(e for e in errors if e["kind"] == "engine")
        self.assertIn("wsl_peer.cpp", engine["location"])
        self.assertTrue(any("bytes" in e["message"] for e in errors), "byte-array messages decode")


class HostSamplerTest(unittest.TestCase):
    def setUp(self):
        self.proc = Path(tempfile.mkdtemp(prefix="p47-proc-"))
        (self.proc / "42").mkdir()
        (self.proc / "42" / "status").write_text("Name:\tserver\nThreads:\t7\nVmRSS:\t  204800 kB\n")
        (self.proc / "loadavg").write_text("0.42 0.30 0.20 1/123 4567\n")
        (self.proc / "meminfo").write_text("MemTotal:  4000000 kB\nMemAvailable: 3000000 kB\n")
        (self.proc / "uptime").write_text("5000.0 9000.0\n")
        (self.proc / "net").mkdir()

    def write_counters(self, cpu_ticks, rx, tx):
        # comm may contain spaces and parentheses; fields after ")" start at state.
        (self.proc / "42" / "stat").write_text(
            "42 (protocol47 (server)) S 1 2 3 4 5 6 7 8 9 10 " + f"{cpu_ticks} 0 " + "0 " * 30 + "\n")
        (self.proc / "net" / "dev").write_text(
            "Inter-|   Receive\n face |bytes\n"
            f"    lo: 999 0 0 0 0 0 0 0 999 0 0 0 0 0 0 0\n"
            f"  eth0: {rx} 0 0 0 0 0 0 0 {tx} 0 0 0 0 0 0 0\n")

    def test_rates_from_two_samples(self):
        sampler = health.HostSampler(proc_root=str(self.proc), disk_path=str(self.proc))
        sampler.clock_ticks = 100
        self.write_counters(1000, 0, 0)
        first = sampler.sample(42, NOW)
        self.assertIsNone(first["cpu_pct"], "a rate needs two readings")
        self.assertAlmostEqual(first["rss_mb"], 200.0)
        self.assertAlmostEqual(first["mem_used_pct"], 25.0)
        self.write_counters(1250, 125_000, 250_000)
        second = sampler.sample(42, NOW + 5)
        self.assertAlmostEqual(second["cpu_pct"], 50.0)  # 250 ticks over 5 s at 100 Hz
        self.assertAlmostEqual(second["net_in_kbps"], 200.0)
        self.assertAlmostEqual(second["net_out_kbps"], 400.0)
        self.assertEqual(second["threads"], 7)


class HealthDashboardTest(unittest.TestCase):
    def test_store_ingests_samples_and_renders(self):
        directory = Path(tempfile.mkdtemp(prefix="p47-health-"))
        store = admin.Store(str(directory / "admin.db"), directory / "events.jsonl", 30)
        store.read_game_journal = lambda cursor, since=None: (JOURNAL if not cursor else [], "last")  # noqa: ARG005
        store.read_service_state = lambda: {"MainPID": 0, "ActiveState": "active", "NRestarts": 1, "uptime": 3725.0}
        (directory / "status.json").write_text(json.dumps({
            "ts": time.time(), "players": [{"peer": 1, "name": "A"}],
            "server": {"tick_rate": 99.7, "target_tick_rate": 100, "physics_ms": 7.7, "process_ms": 0.1}}))
        store.ingest_game_journal()
        store.ingest_game_journal()  # cursor: nothing re-ingested
        store.sample_health()
        data = store.health()
        self.assertEqual(data["crashes_24h"], 0, "the sample crash is outside the last 24 h")
        self.assertEqual(data["crashes_7d"], 0)
        freed = next(e for e in data["errors"] if "freed object" in e["message"])
        self.assertEqual(freed["count"], 2)
        self.assertEqual(data["latest"]["tick_rate"], 99.7)
        self.assertEqual(data["uptime"], 3725.0)
        page = admin.render_health(store)
        self.assertIn('class="active">Health', page, "the Health tab is selected")
        self.assertIn("Trying to cast a freed object", page)
        self.assertIn("up 1h 02m", page)
        self.assertIn("99.7", page)
        overview = admin.render_overview(store)
        self.assertIn("Live match", overview)
        self.assertIn("Server online", overview)


if __name__ == "__main__":
    unittest.main()
