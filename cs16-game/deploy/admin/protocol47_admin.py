#!/usr/bin/env python3
"""Protocol 47 admin service.

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
            series = [dict(row) for row in self.db.execute(
                "select cast(ts / 300 as integer) * 300 bucket, avg(players) players, avg(tick_rate) tick_rate, "
                "max(physics_ms) physics_ms, avg(cpu_pct) cpu_pct, max(rss_mb) rss_mb, avg(net_in_kbps) net_in_kbps, "
                "avg(net_out_kbps) net_out_kbps from perf where ts >= ? group by bucket order by bucket", (now - 86400,))]
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


# -- HTML ----------------------------------------------------------------
def esc(value):
    return html.escape("" if value is None else str(value))


def when(ts):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)) if ts else ""


def duration(seconds):
    seconds = int(seconds or 0)
    return f"{seconds // 3600}h {seconds % 3600 // 60:02d}m" if seconds >= 3600 else f"{seconds // 60}m {seconds % 60:02d}s"


def kd(kills, deaths):
    return f"{kills or 0}/{deaths or 0}"


def short_tag(tag):
    return f'<a href="player?tag={esc(tag)}"><code>{esc(tag[:8])}</code></a>' if tag else "&mdash;"


def address(session):
    value = session.get("address") or ""
    if session.get("transport") == "ws" and value in LOCAL_ADDRESSES:
        return '<span class="dim">after disconnect</span>' if not session.get("left") else '<span class="dim">unmatched</span>'
    return esc(value) + place(session.get("location"))


def place(label):
    return f'<br><span class="dim">{esc(label)}</span>' if label else ""


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Protocol 47 admin</title>
<meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="refresh" content="15">
<style>
footer {{ margin-top: 32px; font-size: 12px; color: #7d786e; }}
.ok {{ color: #7fd18b; }} .bad {{ color: #ff7a6b; font-weight: 600; }}
.charts {{ display: flex; flex-wrap: wrap; gap: 18px; }} .chart {{ font-size: 12px; }}
pre {{ font-size: 11px; white-space: pre-wrap; color: #c8c2b6; margin: 6px 0; }} summary {{ cursor: pointer; }}
body {{ font: 14px/1.45 system-ui, sans-serif; margin: 24px; background: #15171a; color: #e6e1d6; }}
h1 {{ font-size: 20px; margin: 0 0 4px; }} h2 {{ font-size: 16px; margin: 28px 0 8px; color: #f0b54a; }}
table {{ border-collapse: collapse; width: 100%; }} th, td {{ text-align: left; padding: 5px 10px; border-bottom: 1px solid #2c3036; }}
th {{ color: #a8a296; font-weight: 600; }} code {{ color: #9fd3ff; }} a {{ color: #9fd3ff; }}
.dim {{ color: #7d786e; }} .T {{ color: #ff8f70; }} .CT {{ color: #8fb6ff; }} .tiles span {{ margin-right: 22px; }}
</style></head><body><h1>Protocol 47 admin</h1><div class="dim">{subtitle}</div>{body}
<footer>IP geolocation by <a href="https://db-ip.com">DB-IP</a> (CC BY 4.0); approximate, city level.</footer></body></html>"""


def number(value, digits=0, suffix=""):
    return "&mdash;" if value is None else f"{value:.{digits}f}{suffix}"


def sparkline(values, color, label, unit="", digits=0, floor=None):
    """Inline SVG line chart for the last 24 h (one value per 5 minutes)."""
    width, height = 240, 48
    points = [v for v in values if v is not None]
    if not points:
        return f'<div class="chart"><div class="dim">{esc(label)}: no data yet</div></div>'
    low = min(points) if floor is None else min(floor, min(points))
    high = max(points)
    span = (high - low) or 1.0
    step = width / max(1, len(values) - 1)
    path, pen = [], "M"
    for index, value in enumerate(values):
        if value is None:
            pen = "M"
            continue
        y = height - 2 - (value - low) / span * (height - 4)
        path.append(f"{pen}{index * step:.1f},{y:.1f}")
        pen = "L"
    current = points[-1]
    return (f'<div class="chart"><div>{esc(label)} <b>{number(current, digits, unit)}</b> '
            f'<span class="dim">max {number(high, digits, unit)}</span></div>'
            f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
            f'<path d="{" ".join(path)}" fill="none" stroke="{color}" stroke-width="1.5"/></svg></div>')


def render_health(store):
    data = store.health()
    state, latest = data["state"], data["latest"]
    active = state.get("ActiveState") == "active"
    status = (f'<span class="{"ok" if active else "bad"}">{esc(state.get("ActiveState") or "unknown")}</span>'
              f' &middot; up {duration(data["uptime"]) if data["uptime"] is not None else "&mdash;"}'
              f' &middot; restarts {state.get("NRestarts", 0)}'
              f' &middot; <span class="{"bad" if data["crashes_24h"] else ""}">crashes 24h: {data["crashes_24h"]}</span>'
              f' &middot; 7d: {data["crashes_7d"]}')
    tick = latest.get("tick_rate")
    target = latest.get("target_tick_rate") or 100
    tiles = (f'<p class="tiles">'
             f'<span>Tick rate <b class="{"bad" if tick is not None and tick < 0.95 * target else ""}">{number(tick, 1)}</b>/{number(target)}</span>'
             f'<span>Physics <b>{number(latest.get("physics_ms"), 2, " ms")}</b> of {number(1000 / target, 0, " ms")}</span>'
             f'<span>CPU <b>{number(latest.get("cpu_pct"), 0, "%")}</b></span>'
             f'<span>Memory <b>{number(latest.get("rss_mb"), 0, " MB")}</b></span>'
             f'<span>Load <b>{number(latest.get("load1"), 2)}</b></span>'
             f'<span>Droplet RAM <b>{number(latest.get("mem_used_pct"), 0, "%")}</b></span>'
             f'<span>Disk <b>{number(latest.get("disk_used_pct"), 0, "%")}</b></span>'
             f'<span>Net <b>{number(latest.get("net_in_kbps"), 0)}</b> in / <b>{number(latest.get("net_out_kbps"), 0)}</b> out kbit/s</span></p>')
    series = data["series"]
    column = lambda key: [row[key] for row in series]  # noqa: E731
    charts = ('<div class="charts">'
              + sparkline(column("players"), "#f0b54a", "Players", floor=0)
              + sparkline(column("tick_rate"), "#7fd18b", "Tick rate", digits=1)
              + sparkline(column("physics_ms"), "#ff8f70", "Physics (max)", " ms", 2, floor=0)
              + sparkline(column("cpu_pct"), "#9fd3ff", "CPU", "%", floor=0)
              + sparkline(column("rss_mb"), "#c9a0ff", "Memory", " MB")
              + sparkline(column("net_out_kbps"), "#8fb6ff", "Net out", " kbit/s", floor=0)
              + '</div><p class="dim">Last 24 hours, 5-minute buckets.</p>')
    events = "".join(
        f'<tr><td>{when(e["ts"])}</td><td class="{"bad" if e["kind"] == "crash" else ""}">{esc(e["kind"])}</td>'
        f'<td class="dim">{esc(e["detail"])}</td></tr>' for e in data["events"])
    errors = "".join(
        f'<tr><td>{esc(e["kind"])}</td><td>{e["count"]}</td><td>{when(e["last_seen"])}</td>'
        f'<td><details><summary>{esc(e["message"][:140])}</summary><div class="dim">{esc(e["location"])}</div>'
        f'<pre>{esc(e["backtrace"])}</pre></details></td></tr>' for e in data["errors"])
    return (f'<h2>Server health</h2><p>{status}</p>{tiles}{charts}'
            '<h2>Server events</h2><table><tr><th>When</th><th>Event</th><th>Detail</th></tr>'
            f'{events or "<tr><td colspan=3 class=dim>None recorded</td></tr>"}</table>'
            '<h2>Errors</h2><table><tr><th>Kind</th><th>Count</th><th>Last seen</th><th>Message</th></tr>'
            f'{errors or "<tr><td colspan=4 class=dim>No errors logged</td></tr>"}</table>')


def quality(player):
    rtt = player.get("rtt_ms")
    loss = player.get("loss")
    rtt_text = "&mdash;" if rtt is None or rtt < 0 else f'<span class="{"bad" if rtt > 150 else ""}">{rtt:.0f} ms</span>'
    loss_text = "n/a" if loss is None or loss < 0 else f"{loss * 100:.1f}%"
    return (f'<td>{rtt_text}</td><td>{loss_text}</td>'
            f'<td>{number(player.get("kbps_in"), 0)} / {number(player.get("kbps_out"), 0)}</td>'
            f'<td class="{"bad" if player.get("reconnects_1h", 0) >= 3 else ""}">{player.get("reconnects_1h", 0)}</td>')


def render_dashboard(store):
    live = store.live()
    totals = store.totals()
    body = [render_health(store), '<p class="tiles">'
            f'<span>Players seen: <b>{totals["players"] or 0}</b></span>'
            f'<span>Sessions: <b>{totals["sessions"] or 0}</b></span>'
            f'<span>Play time: <b>{duration(totals["seconds"])}</b></span>'
            f'<span>Rounds: <b>{totals["rounds"]}</b></span><span>Matches: <b>{totals["matches"]}</b></span></p>']
    if live.get("online"):
        body.append(f'<h2>Live &middot; {esc(live.get("map"))} &middot; round {esc(live.get("round"))} '
                    f'({esc(live.get("phase"))}) &middot; <span class="T">T {esc(live.get("t_score"))}</span> : '
                    f'<span class="CT">{esc(live.get("ct_score"))} CT</span> &middot; {esc(live.get("bots"))} bots</h2>')
        rows = "".join(
            f'<tr><td>{esc(p.get("name"))}</td><td class="{esc(p.get("team"))}">{esc(p.get("team"))}</td>'
            f'<td>{"alive" if p.get("alive") else "dead"}</td><td>{kd(p.get("kills"), p.get("deaths"))}</td>'
            f'<td>{esc(p.get("transport"))}</td><td>{address(p)}</td>{quality(p)}'
            f'<td>{duration(time.time() - float(p.get("connected") or time.time()))}</td><td>{short_tag(p.get("tag", ""))}</td></tr>'
            for p in live.get("players", []))
        body.append('<table><tr><th>Name</th><th>Team</th><th>State</th><th>K/D</th><th>Via</th><th>Address</th>'
                    '<th>Ping</th><th>Loss</th><th>kbit/s in / out</th><th>Reconnects 1h</th>'
                    f'<th>Online</th><th>Player</th></tr>{rows or "<tr><td colspan=12 class=dim>No humans online</td></tr>"}</table>')
    else:
        body.append('<h2>Live</h2><p class="dim">Game server status is not updating.</p>')
    body.append(render_sessions(store.sessions(60), "Recent sessions"))
    players = store.players()
    rows = "".join(
        f'<tr><td>{short_tag(p["tag"])}</td><td>{esc(", ".join(p["names"][:4]))}</td><td>{p["sessions"]}</td>'
        f'<td>{duration(p["seconds"])}</td><td>{kd(p["kills"], p["deaths"])}</td><td>{esc(p["last_address"])}{place(p.get("location"))}</td>'
        f'<td>{when(p["last_seen"])}</td></tr>' for p in players)
    body.append('<h2>Players</h2><table><tr><th>Player</th><th>Names</th><th>Sessions</th><th>Time</th><th>K/D</th>'
                f'<th>Last address</th><th>Last seen</th></tr>{rows}</table>')
    return PAGE.format(subtitle=f"Updated {when(time.time())} &middot; refreshes every 15s", body="".join(body))


def render_sessions(sessions, title):
    rows = "".join(
        f'<tr><td>{when(s["connected"])}</td><td>{esc(s["name"])}</td><td class="{esc(s["team"])}">{esc(s["team"] or "")}</td>'
        f'<td>{duration(s["seconds"]) if s["left"] else "online"}</td><td>{kd(s["kills"], s["deaths"])}</td>'
        f'<td>{esc(s["transport"])}</td><td>{address(s)}</td><td>{short_tag(s["tag"] or "")}</td>'
        f'<td class="dim">{esc((s["user_agent"] or "")[:60])}</td></tr>' for s in sessions)
    return (f'<h2>{esc(title)}</h2><table><tr><th>Joined</th><th>Name</th><th>Team</th><th>Length</th><th>K/D</th>'
            f'<th>Via</th><th>Address</th><th>Player</th><th>Browser</th></tr>{rows}</table>')


def render_player(store, tag):
    sessions = store.sessions(500, tag=tag)
    names = sorted({s["name"] for s in sessions if s["name"]})
    body = (f'<p><a href="./">&larr; Dashboard</a></p><h2>Player <code>{esc(tag)}</code></h2>'
            f'<p>Names: {esc(", ".join(names)) or "&mdash;"}</p>' + render_sessions(sessions, "Sessions"))
    return PAGE.format(subtitle="", body=body)


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
            if path == "/":
                self._send(200, render_dashboard(store), "text/html; charset=utf-8")
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
