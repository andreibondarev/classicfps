#!/usr/bin/env python3
"""Classic FPS admin service.

Ingests the dedicated server's admin log (events.jsonl + status.json, written
by game/scripts/admin_log.gd) and Caddy's JSON access log into SQLite, and
serves a small read-only dashboard on 127.0.0.1. Caddy exposes it at /admin
behind basic auth. Standard library only.

Browser players reach the game through Caddy, so the game only sees
127.0.0.1 for them. Caddy logs each /ws connection when it closes (end time +
duration + client IP); a finished browser session is matched to the Caddy
entry with the same end time and length. IP addresses and user agents are
kept for --retention-days (30) and then erased; play statistics are kept.
"""
import argparse
import html
import ipaddress
import json
import mmap
import os
import struct
import sqlite3
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import protocol47_health as health

SCHEMA = """
create table if not exists meta(key text primary key, value text);
create table if not exists sessions(
  id integer primary key, peer integer, tag text, name text, team text, actor text,
  transport text, address text, user_agent text, connected real, left real,
  seconds real, kills integer default 0, deaths integer default 0);
create index if not exists sessions_open on sessions(peer, left);
create index if not exists sessions_tag on sessions(tag);
create table if not exists names(tag text, name text, first_seen real, last_seen real, primary key(tag, name));
create table if not exists rounds(id integer primary key, ts real, winner text, t_score integer, ct_score integer);
create table if not exists matches(id integer primary key, ts real, t_score integer, ct_score integer);
create table if not exists geo(ip text primary key, label text, looked_up real);
create table if not exists server_events(id integer primary key, ts real, kind text, detail text, unique(ts, kind));
create table if not exists errors(
  fingerprint text primary key, kind text, message text, location text, backtrace text,
  count integer default 0, first_seen real, last_seen real);
create table if not exists perf(
  ts real primary key, players integer, tick_rate real, target_tick_rate real, physics_ms real, process_ms real,
  cpu_pct real, rss_mb real, load1 real, mem_used_pct real, disk_used_pct real, net_in_kbps real, net_out_kbps real);
create table if not exists ws_connections(
  id integer primary key, ended real, duration real, ip text, user_agent text, session integer,
  unique(ended, ip));
"""
LOCAL_ADDRESSES = ("127.0.0.1", "::1", "")
MATCH_TOLERANCE = 3.0
PERF_RETENTION = 7 * 86400
EVENT_RETENTION = 30 * 86400


class GeoDatabase:
    """Minimal reader for MaxMind DB files (the format DB-IP's free City Lite
    database uses), standard library only, so lookups never leave the server.
    The file is reopened when it changes (monthly updates)."""

    METADATA_MARKER = b"\xab\xcd\xefMaxMind.com"

    def __init__(self, path):
        self.path = Path(path) if path else None
        self.mtime = None
        self.buffer = None

    def _ensure_open(self):
        if self.path is None or not self.path.is_file():
            self.buffer = None
            return False
        mtime = self.path.stat().st_mtime
        if self.buffer is not None and mtime == self.mtime:
            return True
        with self.path.open("rb") as handle:
            self.buffer = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
        self.mtime = mtime
        marker = self.buffer.rfind(self.METADATA_MARKER)
        if marker < 0:
            self.buffer = None
            return False
        self.metadata, _ = self._decode(marker + len(self.METADATA_MARKER), 0)
        self.node_count = int(self.metadata["node_count"])
        self.record_size = int(self.metadata["record_size"])
        self.ip_version = int(self.metadata["ip_version"])
        self.node_bytes = self.record_size * 2 // 8
        self.search_tree_size = self.node_count * self.node_bytes
        self.data_start = self.search_tree_size + 16
        self.ipv4_start = 0
        if self.ip_version == 6:
            node = 0
            for _ in range(96):
                if node >= self.node_count:
                    break
                node = self._record(node, 0)
            self.ipv4_start = node
        return True

    def _record(self, node, bit):
        offset = node * self.node_bytes
        data = self.buffer[offset:offset + self.node_bytes]
        if self.record_size == 24:
            chunk = data[3:6] if bit else data[0:3]
            return int.from_bytes(chunk, "big")
        if self.record_size == 28:
            if bit:
                return ((data[3] & 0x0F) << 24) | int.from_bytes(data[4:7], "big")
            return ((data[3] & 0xF0) << 20) | int.from_bytes(data[0:3], "big")
        if self.record_size == 32:
            return int.from_bytes(data[4:8] if bit else data[0:4], "big")
        raise ValueError(f"unsupported record size {self.record_size}")

    def _decode(self, offset, base):
        control = self.buffer[offset]
        offset += 1
        kind = control >> 5
        if kind == 1:  # pointer
            size = (control >> 3) & 0x3
            low = control & 0x7
            if size == 0:
                pointer = (low << 8) | self.buffer[offset]
            elif size == 1:
                pointer = ((low << 16) | int.from_bytes(self.buffer[offset:offset + 2], "big")) + 2048
            elif size == 2:
                pointer = ((low << 24) | int.from_bytes(self.buffer[offset:offset + 3], "big")) + 526336
            else:
                pointer = int.from_bytes(self.buffer[offset:offset + 4], "big")
            value, _ = self._decode(base + pointer, base)
            return value, offset + size + 1
        if kind == 0:  # extended type
            kind = 7 + self.buffer[offset]
            offset += 1
        size = control & 0x1F
        if size >= 29:
            extra = size - 28
            raw = int.from_bytes(self.buffer[offset:offset + extra], "big")
            offset += extra
            size = {1: 29, 2: 285, 3: 65821}[extra] + raw
        if kind == 2:
            return self.buffer[offset:offset + size].decode("utf-8", "replace"), offset + size
        if kind == 3:
            return struct.unpack(">d", self.buffer[offset:offset + 8])[0], offset + 8
        if kind == 4:
            return bytes(self.buffer[offset:offset + size]), offset + size
        if kind in (5, 6, 9, 10):
            return int.from_bytes(self.buffer[offset:offset + size], "big"), offset + size
        if kind == 7:
            result = {}
            for _ in range(size):
                key, offset = self._decode(offset, base)
                result[key], offset = self._decode(offset, base)
            return result, offset
        if kind == 8:
            return int.from_bytes(self.buffer[offset:offset + size], "big", signed=True), offset + size
        if kind == 11:
            result = []
            for _ in range(size):
                item, offset = self._decode(offset, base)
                result.append(item)
            return result, offset
        if kind == 14:
            return bool(size), offset
        if kind == 15:
            return struct.unpack(">f", self.buffer[offset:offset + 4])[0], offset + 4
        raise ValueError(f"unsupported MaxMind DB type {kind}")

    def lookup(self, ip):
        """The database record for ip, or None."""
        if not self._ensure_open():
            return None
        address = ipaddress.ip_address(ip)
        if address.version == 6 and self.ip_version == 4:
            return None
        node = self.ipv4_start if address.version == 4 else 0
        packed = address.packed
        for index in range(len(packed) * 8):
            if node >= self.node_count:
                break
            bit = (packed[index >> 3] >> (7 - (index & 7))) & 1
            node = self._record(node, bit)
        if node <= self.node_count:
            return None
        offset = node - self.node_count - 16 + self.search_tree_size + 16
        return self._decode(offset, self.data_start)[0]

    @property
    def available(self):
        return self._ensure_open()


def geo_label(record):
    """'City, Region, CC' from a City-database record."""
    if not record:
        return ""
    def name(entry):
        return ((entry or {}).get("names") or {}).get("en", "")
    city = name(record.get("city"))
    subdivisions = record.get("subdivisions") or []
    region = name(subdivisions[0]) if subdivisions else ""
    country = (record.get("country") or {}).get("iso_code", "")
    parts = [part for part in (city, region if region != city else "", country) if part]
    return ", ".join(parts)


class Store:
    def __init__(self, path: str, events: Path, retention_days: int, geoip: str = ""):
        self.geo = GeoDatabase(geoip)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        self.events = events
        self.status = events.parent / "status.json"
        self.retention = retention_days * 86400
        self.lock = threading.Lock()
        # Health sources (replaceable in tests).
        self.sampler = health.HostSampler()
        self.read_game_journal = health.read_game_journal
        self.read_service_state = health.service_state
        self.service = {}

    # -- meta ------------------------------------------------------------
    def _meta(self, key, default=""):
        row = self.db.execute("select value from meta where key=?", (key,)).fetchone()
        return row["value"] if row else default

    def _set_meta(self, key, value):
        self.db.execute("insert into meta(key, value) values(?, ?) on conflict(key) do update set value=excluded.value",
                        (key, str(value)))

    # -- game events -----------------------------------------------------
    def ingest_events(self):
        if not self.events.is_file():
            return 0
        size = self.events.stat().st_size
        offset = int(self._meta("events_offset", "0"))
        if size < offset:  # file was replaced or truncated
            offset = 0
        count = 0
        with self.events.open("rb") as handle:
            handle.seek(offset)
            for raw in handle:
                if not raw.endswith(b"\n"):
                    break  # partial line still being written
                offset += len(raw)
                try:
                    event = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                self._apply(event)
                count += 1
        self._set_meta("events_offset", offset)
        self.db.commit()
        return count

    def _open_session(self, peer):
        return self.db.execute("select * from sessions where peer=? and left is null order by id desc limit 1",
                               (peer,)).fetchone()

    def _remember_name(self, tag, name, ts):
        if tag and name:
            self.db.execute(
                "insert into names(tag, name, first_seen, last_seen) values(?, ?, ?, ?) "
                "on conflict(tag, name) do update set last_seen=excluded.last_seen", (tag, name, ts, ts))

    def _apply(self, event):
        kind = event.get("type")
        ts = float(event.get("ts", time.time()))
        peer = event.get("peer")
        if kind == "game_start":
            # A restart or scene rebuild ends any session left open.
            self.db.execute("update sessions set left=?, seconds=?-connected where left is null", (ts, ts))
        elif kind == "connect":
            self.db.execute("insert into sessions(peer, transport, address, connected) values(?, ?, ?, ?)",
                            (peer, event.get("transport", ""), event.get("address", ""), ts))
        elif kind in ("name", "identify", "team"):
            session = self._open_session(peer)
            if session is None:
                return
            column = {"name": "name", "identify": "tag", "team": "team"}[kind]
            value = event.get({"identify": "tag"}.get(kind, kind), "")
            self.db.execute(f"update sessions set {column}=? where id=?", (value, session["id"]))
            if kind == "team":
                self.db.execute("update sessions set actor=? where id=?", (event.get("actor", ""), session["id"]))
            refreshed = self._open_session(peer)
            self._remember_name(refreshed["tag"], refreshed["name"], ts)
        elif kind == "leave":
            session = self._open_session(peer)
            if session is None:
                return
            self.db.execute(
                "update sessions set left=?, seconds=?, kills=?, deaths=?, name=coalesce(nullif(?, ''), name), "
                "tag=coalesce(nullif(?, ''), tag), team=coalesce(nullif(?, ''), team) where id=?",
                (ts, event.get("seconds", ts - session["connected"]), event.get("kills", 0), event.get("deaths", 0),
                 event.get("name", ""), event.get("tag", ""), event.get("team", ""), session["id"]))
            self._remember_name(event.get("tag", "") or session["tag"], event.get("name", "") or session["name"], ts)
        elif kind == "round_end":
            self.db.execute("insert into rounds(ts, winner, t_score, ct_score) values(?, ?, ?, ?)",
                            (ts, event.get("winner", ""), event.get("t_score", 0), event.get("ct_score", 0)))
        elif kind == "match_end":
            self.db.execute("insert into matches(ts, t_score, ct_score) values(?, ?, ?)",
                            (ts, event.get("t_score", 0), event.get("ct_score", 0)))

    # -- Caddy access log -------------------------------------------------
    def ingest_access_lines(self, lines):
        count = 0
        for line in lines:
            try:
                entry = json.loads(line)
            except (json.JSONDecodeError, TypeError):
                continue
            request = entry.get("request") or {}
            if request.get("uri") != "/ws" or "ts" not in entry:
                continue
            agent = (request.get("headers") or {}).get("User-Agent") or [""]
            ip = request.get("client_ip") or request.get("remote_ip") or ""
            self.db.execute("insert or ignore into ws_connections(ended, duration, ip, user_agent) values(?, ?, ?, ?)",
                            (float(entry["ts"]), float(entry.get("duration", 0)), ip, agent[0]))
            count += 1
        self.db.commit()
        return count

    def ingest_journal(self):
        since = float(self._meta("journal_since", str(time.time() - 3600)))
        try:
            output = subprocess.run(
                ["journalctl", "-u", "caddy", "-o", "cat", "--no-pager", f"--since=@{int(since) - 5}"],
                capture_output=True, text=True, timeout=30).stdout
        except (OSError, subprocess.SubprocessError):
            return 0
        count = self.ingest_access_lines(output.splitlines())
        self._set_meta("journal_since", time.time())
        self.db.commit()
        return count

    def match_browser_addresses(self):
        sessions = self.db.execute(
            "select id, connected, left from sessions where transport='ws' and left is not null "
            f"and coalesce(address, '') in ({','.join('?' * len(LOCAL_ADDRESSES))})", LOCAL_ADDRESSES).fetchall()
        for session in sessions:
            length = session["left"] - session["connected"]
            match = self.db.execute(
                "select id, ip, user_agent from ws_connections where session is null and abs(ended - ?) <= ? "
                "and abs(duration - ?) <= ? order by abs(ended - ?) limit 1",
                (session["left"], MATCH_TOLERANCE, length, MATCH_TOLERANCE, session["left"])).fetchone()
            if match:
                self.db.execute("update sessions set address=?, user_agent=? where id=?",
                                (match["ip"], match["user_agent"], session["id"]))
                self.db.execute("update ws_connections set session=? where id=?", (session["id"], match["id"]))
        self.db.commit()

    def apply_retention(self):
        cutoff = time.time() - self.retention
        self.db.execute("update sessions set address=null, user_agent=null where connected < ?", (cutoff,))
        self.db.execute("delete from ws_connections where ended < ?", (cutoff,))
        self.db.execute("delete from geo where looked_up < ?", (cutoff,))
        self.db.commit()

    def location(self, ip):
        """Approximate 'City, Region, CC' for an IP (cached; '' when unknown)."""
        if not ip or ip in LOCAL_ADDRESSES:
            return ""
        try:
            address = ipaddress.ip_address(ip)
        except ValueError:
            return ""
        if address.is_private or address.is_loopback or address.is_link_local:
            return "local network"
        row = self.db.execute("select label from geo where ip=?", (ip,)).fetchone()
        if row is not None:
            return row["label"]
        if not self.geo.available:
            return ""
        try:
            label = geo_label(self.geo.lookup(ip))
        except (ValueError, IndexError, KeyError, struct.error):
            label = ""
        self.db.execute("insert or replace into geo(ip, label, looked_up) values(?, ?, ?)", (ip, label, time.time()))
        self.db.commit()
        return label

    def _with_location(self, rows, field="address"):
        for row in rows:
            row["location"] = self.location(row.get(field) or "")
        return rows

    # -- server health ---------------------------------------------------
    def ingest_game_journal(self):
        cursor = self._meta("game_journal_cursor", "")
        entries, cursor = self.read_game_journal(cursor, since=None if cursor else time.time() - 7 * 86400)
        count = 0
        for kind, record in health.parse_game_journal(entries):
            count += 1
            if kind == "lifecycle":
                self.db.execute("insert or ignore into server_events(ts, kind, detail) values(?, ?, ?)",
                                (record["ts"], record["kind"], record["detail"]))
            else:
                self.db.execute(
                    "insert into errors(fingerprint, kind, message, location, backtrace, count, first_seen, last_seen) "
                    "values(?, ?, ?, ?, ?, 1, ?, ?) on conflict(fingerprint) do update set count=count+1, "
                    "last_seen=excluded.last_seen, backtrace=coalesce(nullif(excluded.backtrace, ''), backtrace)",
                    (record["fingerprint"], record["kind"], record["message"], record["location"],
                     record["backtrace"], record["ts"], record["ts"]))
        if cursor:
            self._set_meta("game_journal_cursor", cursor)
        self.db.commit()
        return count

    def sample_health(self, now=None):
        now = time.time() if now is None else now
        self.service = self.read_service_state() or {}
        status = self._read_status()
        server = status.get("server") or {}
        fresh = now - float(status.get("ts", 0)) < 15
        sample = self.sampler.sample(int(self.service.get("MainPID") or 0), now)
        self.db.execute(
            "insert or replace into perf values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (now, len(status.get("players", [])) if fresh else None,
             server.get("tick_rate") if fresh else None, server.get("target_tick_rate"),
             server.get("physics_ms") if fresh else None, server.get("process_ms") if fresh else None,
             sample["cpu_pct"], sample["rss_mb"], sample["load1"], sample["mem_used_pct"],
             sample["disk_used_pct"], sample["net_in_kbps"], sample["net_out_kbps"]))
        self.db.execute("delete from perf where ts < ?", (now - PERF_RETENTION,))
        self.db.execute("delete from server_events where ts < ?", (now - EVENT_RETENTION,))
        self.db.execute("delete from errors where last_seen < ?", (now - EVENT_RETENTION,))
        self.db.commit()
        return sample

    def _read_status(self):
        try:
            return json.loads(self.status.read_text())
        except (OSError, json.JSONDecodeError):
            return {}

    def health(self, now=None):
        now = time.time() if now is None else now
        with self.lock:
            crashes = lambda seconds: self.db.execute(  # noqa: E731
                "select count(*) n from server_events where kind='crash' and ts >= ?", (now - seconds,)).fetchone()["n"]
            latest = self.db.execute("select * from perf order by ts desc limit 1").fetchone()
            # 24 h in 5-minute buckets, averaged (maxima for the stress metrics).
            rows = [dict(row) for row in self.db.execute(
                "select cast(ts / 300 as integer) * 300 bucket, avg(players) players, avg(tick_rate) tick_rate, "
                "max(physics_ms) physics_ms, avg(cpu_pct) cpu_pct, max(rss_mb) rss_mb, avg(net_in_kbps) net_in_kbps, "
                "avg(net_out_kbps) net_out_kbps from perf where ts >= ? group by bucket order by bucket", (now - 86400,))]
            # A fixed 24-hour axis: one slot per 5 minutes, None where nothing was sampled.
            by_bucket = {row["bucket"]: row for row in rows}
            last = int(now // 300) * 300
            series = [by_bucket.get(bucket, {"bucket": bucket, "players": None, "tick_rate": None, "physics_ms": None,
                                             "cpu_pct": None, "rss_mb": None, "net_in_kbps": None, "net_out_kbps": None})
                      for bucket in range(last - 287 * 300, last + 300, 300)]
            events = [dict(row) for row in self.db.execute(
                "select * from server_events order by ts desc limit 20")]
            errors = [dict(row) for row in self.db.execute(
                "select * from errors order by last_seen desc limit 30")]
        state = dict(self.service)
        uptime = state.get("uptime")
        return {"state": state, "uptime": uptime, "crashes_24h": crashes(86400), "crashes_7d": crashes(7 * 86400),
                "latest": dict(latest) if latest else {}, "series": series, "events": events, "errors": errors}

    def refresh(self):
        with self.lock:
            self.ingest_events()
            self.ingest_journal()
            self.match_browser_addresses()
            self.apply_retention()
            self.ingest_game_journal()
            self.sample_health()

    # -- queries ---------------------------------------------------------
    def live(self):
        try:
            status = json.loads(self.status.read_text())
        except (OSError, json.JSONDecodeError):
            return {"online": False, "players": []}
        status["online"] = time.time() - float(status.get("ts", 0)) < 15
        with self.lock:
            self._with_location(status.get("players", []))
            for player in status.get("players", []):
                # Earlier sessions from the same install in the last hour = drops/reconnects.
                player["reconnects_1h"] = self.db.execute(
                    "select count(*) n from sessions where tag=? and tag != '' and left is not null and connected >= ?",
                    (player.get("tag", ""), time.time() - 3600)).fetchone()["n"] if player.get("tag") else 0
        return status

    def sessions(self, limit=100, tag=None):
        query = "select * from sessions"
        args = []
        if tag:
            query += " where tag=?"
            args.append(tag)
        query += " order by connected desc limit ?"
        args.append(limit)
        with self.lock:
            return self._with_location([dict(row) for row in self.db.execute(query, args)])

    def players(self, limit=200):
        with self.lock:
            rows = self.db.execute(
                "select tag, count(*) sessions, sum(coalesce(seconds, 0)) seconds, sum(kills) kills, "
                "sum(deaths) deaths, max(connected) last_seen, min(connected) first_seen from sessions "
                "where coalesce(tag, '') != '' group by tag order by last_seen desc limit ?", (limit,)).fetchall()
            players = []
            for row in rows:
                player = dict(row)
                player["names"] = [r["name"] for r in self.db.execute(
                    "select name from names where tag=? order by last_seen desc", (row["tag"],))]
                last = self.db.execute(
                    "select address from sessions where tag=? and coalesce(address, '') not in ('127.0.0.1', '::1', '') "
                    "order by connected desc limit 1", (row["tag"],)).fetchone()
                player["last_address"] = last["address"] if last else ""
                players.append(player)
            return self._with_location(players, "last_address")

    def totals(self):
        with self.lock:
            row = self.db.execute(
                "select count(*) sessions, count(distinct tag) players, sum(coalesce(seconds, 0)) seconds "
                "from sessions").fetchone()
            rounds = self.db.execute("select count(*) n from rounds").fetchone()["n"]
            matches = self.db.execute("select count(*) n from matches").fetchone()["n"]
        return {**dict(row), "rounds": rounds, "matches": matches}


# -- HTML lives in protocol47_pages.py ------------------------------------
from protocol47_pages import (  # noqa: E402
    render_dashboard, render_health, render_overview, render_player, render_players, render_sessions, sparkline,
)


def make_handler(store):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, status, body, content_type):
            data = body.encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            url = urlparse(self.path)
            query = parse_qs(url.query)
            path = url.path.rstrip("/") or "/"
            pages = {"/": render_overview, "/players": render_players, "/sessions": render_sessions,
                     "/health": render_health}
            if path in pages:
                self._send(200, pages[path](store), "text/html; charset=utf-8")
            elif path == "/player":
                self._send(200, render_player(store, (query.get("tag") or [""])[0]), "text/html; charset=utf-8")
            elif path == "/api/live":
                self._send(200, json.dumps(store.live()), "application/json")
            elif path == "/api/sessions":
                self._send(200, json.dumps(store.sessions(500)), "application/json")
            elif path == "/api/health":
                self._send(200, json.dumps(store.health()), "application/json")
            elif path == "/api/players":
                self._send(200, json.dumps(store.players()), "application/json")
            else:
                self._send(404, "not found", "text/plain")

        def log_message(self, format, *args):  # noqa: A002 (base signature)
            pass

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--events", default="/var/lib/protocol47/events.jsonl")
    parser.add_argument("--db", default="/var/lib/protocol47-admin/admin.db")
    parser.add_argument("--listen", default="127.0.0.1:8090")
    parser.add_argument("--interval", type=float, default=5.0)
    parser.add_argument("--retention-days", type=int, default=30)
    parser.add_argument("--geoip", default="/var/lib/protocol47-admin/dbip-city-lite.mmdb",
                        help="DB-IP City Lite (MaxMind DB format); optional")
    parser.add_argument("--once", action="store_true", help="ingest once and exit (for testing)")
    args = parser.parse_args()
    store = Store(args.db, Path(args.events), args.retention_days, args.geoip)
    store.refresh()
    if args.once:
        return

    def refresher():
        while True:
            time.sleep(args.interval)
            try:
                store.refresh()
            except Exception as error:  # keep serving even if one pass fails
                print(f"refresh failed: {error}", flush=True)

    threading.Thread(target=refresher, daemon=True).start()
    host, port = args.listen.rsplit(":", 1)
    ThreadingHTTPServer((host, int(port)), make_handler(store)).serve_forever()


if __name__ == "__main__":
    main()
