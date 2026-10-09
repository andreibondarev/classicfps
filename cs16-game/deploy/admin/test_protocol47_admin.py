"""Tests for protocol47_admin.py (python3 -m unittest, standard library only)."""
import json
import os
import tempfile
import threading
import time
import unittest
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

import protocol47_admin as admin

T0 = 1_790_000_000.0


def write_events(path: Path, events):
    path.write_text("".join(json.dumps(event) + "\n" for event in events))


class AdminStoreTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="p47-admin-test-"))
        self.events = self.dir / "events.jsonl"
        write_events(self.events, [
            {"type": "game_start", "map": "de_dust2", "ts": T0},
            {"type": "connect", "peer": 11, "transport": "ws", "address": "127.0.0.1", "port": 5000, "ts": T0 + 10},
            {"type": "name", "peer": 11, "name": "Alice", "ts": T0 + 10.1},
            {"type": "identify", "peer": 11, "tag": "a" * 32, "ts": T0 + 11},
            {"type": "team", "peer": 11, "actor": "remote_human_1", "team": "T", "ts": T0 + 15},
            {"type": "connect", "peer": 22, "transport": "udp", "address": "203.0.113.9", "port": 27005, "ts": T0 + 20},
            {"type": "identify", "peer": 22, "tag": "b" * 32, "ts": T0 + 21},
            {"type": "name", "peer": 22, "name": "Bob", "ts": T0 + 21.5},
            {"type": "round_end", "winner": "T", "t_score": 1, "ct_score": 0, "ts": T0 + 100},
            {"type": "leave", "peer": 11, "tag": "a" * 32, "name": "Alice", "team": "T", "kills": 3, "deaths": 1,
             "seconds": 190.0, "ts": T0 + 200},
            {"type": "match_end", "t_score": 16, "ct_score": 9, "ts": T0 + 300},
        ])
        self.store = admin.Store(str(self.dir / "admin.db"), self.events, retention_days=30)

    def test_sessions_names_and_browser_address_matching(self):
        self.assertEqual(self.store.ingest_events(), 11)
        # Caddy logs the browser's /ws connection when it closes.
        self.store.ingest_access_lines([json.dumps({
            "ts": T0 + 200.4, "duration": 190.2, "logger": "http.log.access",
            "request": {"uri": "/ws", "client_ip": "198.51.100.7", "headers": {"User-Agent": ["Firefox/146"]}}}),
            json.dumps({"ts": T0 + 50, "request": {"uri": "/index.pck"}}), "not json"])
        self.store.match_browser_addresses()
        sessions = {s["name"]: s for s in self.store.sessions()}
        alice, bob = sessions["Alice"], sessions["Bob"]
        self.assertEqual((alice["address"], alice["user_agent"]), ("198.51.100.7", "Firefox/146"))
        self.assertEqual((alice["kills"], alice["deaths"], alice["team"], alice["seconds"]), (3, 1, "T", 190.0))
        self.assertIsNone(bob["left"], "Bob is still online")
        self.assertEqual(bob["address"], "203.0.113.9", "desktop players keep their UDP address")
        players = {p["tag"]: p for p in self.store.players()}
        self.assertEqual(players["a" * 32]["names"], ["Alice"])
        self.assertEqual(players["a" * 32]["last_address"], "198.51.100.7")
        totals = self.store.totals()
        self.assertEqual((totals["players"], totals["sessions"], totals["rounds"], totals["matches"]), (2, 2, 1, 1))

    def test_incremental_ingest_and_restart_closes_open_sessions(self):
        self.store.ingest_events()
        with self.events.open("a") as handle:
            handle.write(json.dumps({"type": "game_start", "ts": T0 + 400}) + "\n")
            handle.write('{"type": "connect", "peer": 33')  # partial line: not yet complete
        self.assertEqual(self.store.ingest_events(), 1)
        bob = next(s for s in self.store.sessions() if s["name"] == "Bob")
        self.assertEqual(bob["left"], T0 + 400, "a game restart closes sessions left open")
        with self.events.open("a") as handle:
            handle.write(', "transport": "udp", "address": "192.0.2.4", "ts": %s}\n' % (T0 + 401))
        self.assertEqual(self.store.ingest_events(), 1, "the completed line is ingested once")

    def test_retention_erases_addresses_but_keeps_stats(self):
        self.store.ingest_events()
        self.store.retention = 0
        self.store.apply_retention()
        alice = next(s for s in self.store.sessions() if s["name"] == "Alice")
        self.assertIsNone(alice["address"])
        self.assertEqual(alice["kills"], 3)

    def test_dashboard_and_api_over_http(self):
        self.store.ingest_events()
        (self.dir / "status.json").write_text(json.dumps({
            "ts": time.time(), "map": "de_dust2", "round": 3, "phase": "live", "t_score": 2, "ct_score": 0, "bots": 9,
            "players": [{"peer": 22, "tag": "b" * 32, "name": "<Bob>", "team": "CT", "alive": True, "kills": 1,
                         "deaths": 0, "transport": "udp", "address": "203.0.113.9", "connected": time.time() - 60}]}))
        server = ThreadingHTTPServer(("127.0.0.1", 0), admin.make_handler(self.store))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            page = urllib.request.urlopen(base + "/").read().decode()
            self.assertIn("&lt;Bob&gt;", page, "names are HTML-escaped")
            self.assertIn("round 3", page)
            self.assertIn("Alice", page)
            player = urllib.request.urlopen(base + "/player?tag=" + "a" * 32).read().decode()
            self.assertIn("Alice", player)
            for tab in ("players", "sessions", "health"):
                html_page = urllib.request.urlopen(f"{base}/{tab}").read().decode()
                self.assertIn(f'href="{tab}" class="active"', html_page, f"{tab} tab renders and is selected")
            live = json.loads(urllib.request.urlopen(base + "/api/live").read())
            self.assertTrue(live["online"])
            self.assertEqual(len(json.loads(urllib.request.urlopen(base + "/api/sessions").read())), 2)
        finally:
            server.shutdown()


class GeoLocationTest(unittest.TestCase):
    def test_labels(self):
        record = {"city": {"names": {"en": "London"}}, "subdivisions": [{"names": {"en": "England"}}],
                  "country": {"iso_code": "GB"}}
        self.assertEqual(admin.geo_label(record), "London, England, GB")
        self.assertEqual(admin.geo_label({"country": {"iso_code": "US"}}), "US")
        self.assertEqual(admin.geo_label(None), "")

    def test_private_and_unknown_addresses(self):
        directory = Path(tempfile.mkdtemp(prefix="p47-geo-test-"))
        store = admin.Store(str(directory / "admin.db"), directory / "events.jsonl", 30, geoip=str(directory / "absent.mmdb"))
        self.assertEqual(store.location("192.168.1.20"), "local network")
        self.assertEqual(store.location("127.0.0.1"), "")
        self.assertEqual(store.location("not an ip"), "")
        self.assertEqual(store.location("8.8.8.8"), "", "no database: no location, no error")

    @unittest.skipUnless(os.environ.get("P47_GEOIP_DB"), "set P47_GEOIP_DB to a DB-IP City Lite .mmdb")
    def test_real_database_lookup_and_cache(self):
        directory = Path(tempfile.mkdtemp(prefix="p47-geo-test-"))
        store = admin.Store(str(directory / "admin.db"), directory / "events.jsonl", 30, geoip=os.environ["P47_GEOIP_DB"])
        self.assertTrue(store.location("8.8.8.8").endswith(", US"))
        self.assertIn("GB", store.location("81.2.69.142"))
        self.assertRegex(store.location("2001:4860:4860::8888"), r", [A-Z]{2}$", "IPv6 lookups resolve")
        cached = store.db.execute("select count(*) n from geo").fetchone()["n"]
        store.location("8.8.8.8")
        self.assertEqual(store.db.execute("select count(*) n from geo").fetchone()["n"], cached, "lookups are cached")


if __name__ == "__main__":
    unittest.main()
