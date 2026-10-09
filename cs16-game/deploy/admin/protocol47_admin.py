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
import json
import sqlite3
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

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
create table if not exists ws_connections(
  id integer primary key, ended real, duration real, ip text, user_agent text, session integer,
  unique(ended, ip));
"""
LOCAL_ADDRESSES = ("127.0.0.1", "::1", "")
MATCH_TOLERANCE = 3.0


class Store:
    def __init__(self, path: str, events: Path, retention_days: int):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        self.events = events
        self.status = events.parent / "status.json"
        self.retention = retention_days * 86400
        self.lock = threading.Lock()

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
        self.db.commit()

    def refresh(self):
        with self.lock:
            self.ingest_events()
            self.ingest_journal()
            self.match_browser_addresses()
            self.apply_retention()

    # -- queries ---------------------------------------------------------
    def live(self):
        try:
            status = json.loads(self.status.read_text())
        except (OSError, json.JSONDecodeError):
            return {"online": False, "players": []}
        status["online"] = time.time() - float(status.get("ts", 0)) < 15
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
            return [dict(row) for row in self.db.execute(query, args)]

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
            return players

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
    return esc(value)


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Protocol 47 admin</title>
<meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="refresh" content="15">
<style>
body {{ font: 14px/1.45 system-ui, sans-serif; margin: 24px; background: #15171a; color: #e6e1d6; }}
h1 {{ font-size: 20px; margin: 0 0 4px; }} h2 {{ font-size: 16px; margin: 28px 0 8px; color: #f0b54a; }}
table {{ border-collapse: collapse; width: 100%; }} th, td {{ text-align: left; padding: 5px 10px; border-bottom: 1px solid #2c3036; }}
th {{ color: #a8a296; font-weight: 600; }} code {{ color: #9fd3ff; }} a {{ color: #9fd3ff; }}
.dim {{ color: #7d786e; }} .T {{ color: #ff8f70; }} .CT {{ color: #8fb6ff; }} .tiles span {{ margin-right: 22px; }}
</style></head><body><h1>Protocol 47 admin</h1><div class="dim">{subtitle}</div>{body}</body></html>"""


def render_dashboard(store):
    live = store.live()
    totals = store.totals()
    body = ['<p class="tiles">'
            f'<span>Players seen: <b>{totals["players"] or 0}</b></span>'
            f'<span>Sessions: <b>{totals["sessions"] or 0}</b></span>'
            f'<span>Play time: <b>{duration(totals["seconds"])}</b></span>'
            f'<span>Rounds: <b>{totals["rounds"]}</b></span><span>Matches: <b>{totals["matches"]}</b></span></p>']
    if live.get("online"):
        body.append(f'<h2>Live &middot; {esc(live.get("map"))} &middot; round {esc(live.get("round"))} '
                    f'({esc(live.get("phase"))}) &middot; <span class="T">T {esc(live.get("t_score"))}</span> : '
                    f'<span class="CT">{esc(live.get("ct_score"))} CT</span> &middot; {esc(live.get("bots"))} bots</h2>')
        rows = "".join(
            f'<tr><td>{esc(p["name"])}</td><td class="{esc(p["team"])}">{esc(p["team"])}</td>'
            f'<td>{"alive" if p.get("alive") else "dead"}</td><td>{kd(p["kills"], p["deaths"])}</td>'
            f'<td>{esc(p["transport"])}</td><td>{address(p)}</td>'
            f'<td>{duration(time.time() - float(p.get("connected") or time.time()))}</td><td>{short_tag(p.get("tag", ""))}</td></tr>'
            for p in live.get("players", []))
        body.append('<table><tr><th>Name</th><th>Team</th><th>State</th><th>K/D</th><th>Via</th><th>Address</th>'
                    f'<th>Online</th><th>Player</th></tr>{rows or "<tr><td colspan=8 class=dim>No humans online</td></tr>"}</table>')
    else:
        body.append('<h2>Live</h2><p class="dim">Game server status is not updating.</p>')
    body.append(render_sessions(store.sessions(60), "Recent sessions"))
    players = store.players()
    rows = "".join(
        f'<tr><td>{short_tag(p["tag"])}</td><td>{esc(", ".join(p["names"][:4]))}</td><td>{p["sessions"]}</td>'
        f'<td>{duration(p["seconds"])}</td><td>{kd(p["kills"], p["deaths"])}</td><td>{esc(p["last_address"])}</td>'
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
    parser.add_argument("--once", action="store_true", help="ingest once and exit (for testing)")
    args = parser.parse_args()
    store = Store(args.db, Path(args.events), args.retention_days)
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
