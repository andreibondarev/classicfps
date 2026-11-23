"""Moderation for the Classic FPS admin service: chat log, kicks, bans, mutes.

The admin acts here; the game enforces. Every change rewrites the moderation
file the game watches (game/scripts/moderation.gd, --moderation=PATH):
  {"bans":  [{"tag", "address", "until", "reason"}],
   "mutes": [{"tag", "until", "reason"}],
   "kicks": [{"id", "peer", "tag", "reason", "ts"}]}
Bans match the player's persistent ID (client tag) or IP address; mutes match
the ID and silence both chat and voice; until 0 is permanent. The game reports
what it enforced (kick_enforced / ban_enforced) and every chat line, including
blocked ones, through the admin log.
"""
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import time
from pathlib import Path

SCHEMA = """
create table if not exists chat(
  id integer primary key, ts real, peer integer, tag text, name text, team text,
  team_only integer, text text, blocked integer);
create index if not exists chat_tag on chat(tag);
create table if not exists sanctions(
  id integer primary key, kind text, tag text, address text, name text, reason text,
  created real, until real, lifted real);
create table if not exists kicks(
  id integer primary key, ts real, peer integer, tag text, name text, reason text, enforced real);
create table if not exists audit(id integer primary key, ts real, action text, target text, detail text);
"""
TAG = re.compile(r"^[0-9a-f]{32}$")
# A kick only needs to stay in the file until the game has seen it.
KICK_WINDOW = 120.0
MAX_REASON = 80
DURATIONS = [(3600, "1 hour"), (86400, "1 day"), (7 * 86400, "7 days"), (30 * 86400, "30 days"), (0, "Permanent")]


def clean_reason(value):
    text = " ".join(str(value or "").split())
    return "".join(ch for ch in text if ch.isprintable())[:MAX_REASON]


def valid_address(value):
    try:
        return str(ipaddress.ip_address(str(value or "").strip()))
    except ValueError:
        return ""


class Moderation:
    """Lives on the Store: same SQLite connection and lock."""

    def __init__(self, store, path):
        self.store = store
        self.db = store.db
        self.path = Path(path) if path else None
        self.db.executescript(SCHEMA)
        secret = store._meta("csrf_secret", "")
        if not secret:
            secret = secrets.token_hex(32)
            store._set_meta("csrf_secret", secret)
            self.db.commit()
        self.csrf = hmac.new(bytes.fromhex(secret), b"protocol47-admin-forms", hashlib.sha256).hexdigest()
        self._written = None

    # -- events from the game ----------------------------------------------
    def apply_event(self, event):
        kind = event.get("type")
        ts = float(event.get("ts", time.time()))
        if kind == "chat":
            self.db.execute(
                "insert into chat(ts, peer, tag, name, team, team_only, text, blocked) values(?, ?, ?, ?, ?, ?, ?, ?)",
                (ts, event.get("peer"), event.get("tag", ""), event.get("name", ""), event.get("team", ""),
                 1 if event.get("team_only") else 0, str(event.get("text", "")), 1 if event.get("blocked") else 0))
            return True
        if kind == "kick_enforced":
            kick_id = str(event.get("kick", ""))
            if kick_id.isdigit():
                self.db.execute("update kicks set enforced=? where id=? and enforced is null", (ts, int(kick_id)))
            return True
        if kind == "ban_enforced":
            self.db.execute("insert into audit(ts, action, target, detail) values(?, ?, ?, ?)",
                            (ts, "ban refused a connection", event.get("tag", ""), clean_reason(event.get("reason"))))
            return True
        return False

    # -- admin actions -----------------------------------------------------
    def _audit(self, action, target, detail=""):
        self.db.execute("insert into audit(ts, action, target, detail) values(?, ?, ?, ?)",
                        (time.time(), action, target, detail))

    def kick(self, peer, tag, name, reason):
        if not TAG.match(tag or "") and not peer:
            raise ValueError("kick needs a connected player")
        reason = clean_reason(reason)
        cursor = self.db.execute("insert into kicks(ts, peer, tag, name, reason) values(?, ?, ?, ?, ?)",
                                 (time.time(), int(peer or 0), tag or "", name or "", reason))
        self._audit("kick", name or tag, reason)
        self.write_file()
        return cursor.lastrowid

    def sanction(self, kind, tag, address, name, reason, seconds):
        if kind not in ("ban", "mute"):
            raise ValueError("unknown sanction")
        tag, address = (tag or "").strip().lower(), (address or "").strip()
        if tag and not TAG.match(tag):
            raise ValueError("a player ID is 32 hex characters")
        if address and kind == "ban":
            address = valid_address(address)
            if not address:
                raise ValueError("that is not an IP address")
        elif kind == "mute":
            address = ""
        if not tag and not address:
            raise ValueError("a ban needs a player ID or an IP address" if kind == "ban" else "a mute needs a player ID")
        if address and ipaddress.ip_address(address).is_loopback:
            raise ValueError("refusing to ban a loopback address (that would ban every browser player)")
        seconds = int(seconds)
        if seconds not in [d for d, _ in DURATIONS]:
            raise ValueError("unknown duration")
        now = time.time()
        reason = clean_reason(reason)
        self.db.execute(
            "insert into sanctions(kind, tag, address, name, reason, created, until) values(?, ?, ?, ?, ?, ?, ?)",
            (kind, tag, address, name or "", reason, now, now + seconds if seconds else 0))
        label = dict(DURATIONS)[seconds].lower()
        self._audit(kind, name or tag or address, f"{label}{': ' + reason if reason else ''}"
                    + (f" (IP {address})" if address else ""))
        self.write_file()

    def lift(self, sanction_id):
        row = self.db.execute("select * from sanctions where id=? and lifted is null", (int(sanction_id),)).fetchone()
        if row is None:
            raise ValueError("no such active ban or mute")
        self.db.execute("update sanctions set lifted=? where id=?", (time.time(), row["id"]))
        self._audit(f"lift {row['kind']}", row["name"] or row["tag"] or row["address"], row["reason"])
        self.write_file()

    # -- the file the game reads -------------------------------------------
    def active(self, kind=None, now=None):
        now = time.time() if now is None else now
        query = "select * from sanctions where lifted is null and (until = 0 or until > ?)"
        args = [now]
        if kind:
            query += " and kind=?"
            args.append(kind)
        return [dict(row) for row in self.db.execute(query + " order by created desc", args)]

    def file_contents(self, now=None):
        now = time.time() if now is None else now
        active = self.active(now=now)
        kicks = self.db.execute("select * from kicks where ts >= ? order by id", (now - KICK_WINDOW,)).fetchall()
        return {
            "bans": [{"tag": s["tag"], "address": s["address"], "until": s["until"], "reason": s["reason"]}
                     for s in active if s["kind"] == "ban"],
            "mutes": [{"tag": s["tag"], "until": s["until"], "reason": s["reason"]}
                      for s in active if s["kind"] == "mute"],
            "kicks": [{"id": str(k["id"]), "peer": k["peer"], "tag": k["tag"], "reason": k["reason"], "ts": k["ts"]}
                      for k in kicks],
        }

    def write_file(self, now=None):
        """Atomically rewrite the moderation file when its contents change."""
        self.db.commit()
        if self.path is None:
            return False
        text = json.dumps(self.file_contents(now), sort_keys=True)
        if text == self._written and self.path.is_file():
            return False
        temporary = self.path.with_name(self.path.name + ".tmp")
        temporary.write_text(text)
        os.chmod(temporary, 0o640)
        os.replace(temporary, self.path)
        self._written = text
        return True

    def apply_retention(self, cutoff):
        self.db.execute("delete from chat where ts < ?", (cutoff,))
        self.db.execute("delete from kicks where ts < ?", (cutoff,))
        # Lifted or expired sanctions keep their record but drop the address.
        self.db.execute("update sanctions set address='' where (lifted is not null and lifted < ?) "
                        "or (until != 0 and until < ?)", (cutoff, cutoff))

    # -- queries for the pages ---------------------------------------------
    def chat(self, limit=300, tag=None):
        query, args = "select * from chat", []
        if tag:
            query += " where tag=?"
            args.append(tag)
        return [dict(row) for row in self.db.execute(query + " order by ts desc limit ?", args + [limit])]

    def audit_log(self, limit=100):
        return [dict(row) for row in self.db.execute("select * from audit order by ts desc limit ?", (limit,))]

    def status_for(self, tag, address=""):
        """Active ban/mute rows that apply to this player (by ID or address)."""
        found = []
        for row in self.active():
            if (tag and row["tag"] == tag) or (address and row["address"] == address):
                found.append(row)
        return found
