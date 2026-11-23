"""Tests for protocol47_moderation.py and the admin's moderation forms."""
import json
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

import protocol47_admin as admin

ALICE = "a" * 32
BOB = "b" * 32


class ModerationTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="p47-moderation-"))
        self.events = self.dir / "events.jsonl"
        now = time.time()
        self.events.write_text("".join(json.dumps(event) + "\n" for event in [
            {"type": "game_start", "ts": now - 60},
            {"type": "connect", "peer": 7, "transport": "ws", "address": "198.51.100.7", "port": 1, "ts": now - 50},
            {"type": "identify", "peer": 7, "tag": ALICE, "ts": now - 49},
            {"type": "name", "peer": 7, "name": "Alice", "ts": now - 49},
            {"type": "chat", "peer": 7, "tag": ALICE, "name": "Alice", "team": "T", "team_only": False,
             "text": "<b>gg</b>", "blocked": False, "ts": now - 40},
            {"type": "chat", "peer": 7, "tag": ALICE, "name": "Alice", "team": "T", "team_only": True,
             "text": "rush b", "blocked": True, "ts": now - 30},
        ]))
        self.file = self.dir / "moderation" / "moderation.json"
        self.file.parent.mkdir()
        self.store = admin.Store(str(self.dir / "admin.db"), self.events, 30, moderation=str(self.file))
        self.store.read_game_journal = lambda cursor, since=None: ([], cursor)  # noqa: ARG005
        self.store.read_service_state = lambda: {}
        self.store.ingest_events()
        (self.dir / "status.json").write_text(json.dumps({
            "ts": time.time(), "map": "de_dust2", "players": [
                {"peer": 7, "tag": ALICE, "name": "Alice", "team": "T", "alive": True, "kills": 0, "deaths": 0,
                 "transport": "ws", "address": "198.51.100.7", "connected": time.time() - 50}]}))

    def game_file(self):
        return json.loads(self.file.read_text())

    def test_chat_is_logged_with_blocked_lines(self):
        chat = self.store.moderation.chat()
        self.assertEqual([(c["text"], c["blocked"], c["team_only"]) for c in chat],
                         [("rush b", 1, 1), ("<b>gg</b>", 0, 0)])
        page = admin.render_chat(self.store)
        self.assertIn("&lt;b&gt;gg&lt;/b&gt;", page, "chat text is HTML-escaped")
        self.assertIn("muted, not delivered", page)

    def test_sanctions_kicks_and_the_game_file(self):
        self.store.moderate({"action": "kick", "peer": "7", "tag": ALICE, "name": "Alice", "reason": "afk"})
        self.store.moderate({"action": "mute", "tag": ALICE, "name": "Alice", "reason": "spam", "duration": "3600"})
        self.store.moderate({"action": "ban", "tag": BOB, "address": "203.0.113.9", "name": "Bob",
                             "reason": "wall\nhack\x07", "duration": "0"})
        data = self.game_file()
        self.assertEqual([(k["peer"], k["tag"], k["reason"]) for k in data["kicks"]], [(7, ALICE, "afk")])
        self.assertEqual([(m["tag"], m["reason"]) for m in data["mutes"]], [(ALICE, "spam")])
        self.assertEqual([(b["tag"], b["address"], b["until"], b["reason"]) for b in data["bans"]],
                         [(BOB, "203.0.113.9", 0, "wall hack")], "reasons are single-line and printable")
        # The game reports the kick; old kicks and expired sanctions leave the file.
        kick_id = data["kicks"][0]["id"]
        with self.events.open("a") as handle:
            handle.write(json.dumps({"type": "kick_enforced", "kick": kick_id, "peer": 7, "ts": time.time()}) + "\n")
        self.store.ingest_events()
        self.assertIsNotNone(self.store.db.execute("select enforced from kicks").fetchone()["enforced"])
        later = time.time() + 2 * 3600
        self.store.moderation.write_file(now=later)
        data = self.game_file()
        self.assertEqual((data["kicks"], data["mutes"]), ([], []), "kick window and 1-hour mute have passed")
        self.assertEqual(len(data["bans"]), 1, "the permanent ban stays")
        ban = self.store.moderation.active("ban")[0]
        self.store.moderate({"action": "lift", "id": str(ban["id"])})
        self.assertEqual(self.game_file()["bans"], [])
        actions = [a["action"] for a in self.store.moderation.audit_log()]
        self.assertEqual(actions, ["lift ban", "ban", "mute", "kick"])

    def test_invalid_requests(self):
        for form, message in [
            ({"action": "ban", "tag": "", "address": "", "duration": "3600"}, "needs"),
            ({"action": "ban", "tag": "xyz", "duration": "3600"}, "32 hex"),
            ({"action": "ban", "address": "999.1.1.1", "duration": "3600"}, "not an IP"),
            ({"action": "ban", "address": "127.0.0.1", "duration": "3600"}, "loopback"),
            ({"action": "ban", "tag": BOB, "duration": "5"}, "duration"),
            ({"action": "mute", "address": "203.0.113.9", "duration": "3600"}, "player ID"),
            ({"action": "explode"}, "unknown"),
        ]:
            with self.assertRaisesRegex(ValueError, message):
                self.store.moderate(form)

    def test_forms_over_http_need_the_token_and_same_origin(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), admin.make_handler(self.store))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{server.server_address[1]}"

        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None

        opener = urllib.request.build_opener(NoRedirect)

        def post(fields, origin=None):
            request = urllib.request.Request(base + "/moderate", data=urllib.parse.urlencode(fields).encode())
            if origin:
                request.add_header("Origin", origin)
            try:
                response = opener.open(request)
                return response.status, response.headers.get("Location")
            except urllib.error.HTTPError as error:
                return error.code, error.headers.get("Location")

        try:
            ban = {"action": "ban", "tag": BOB, "duration": "86400", "back": "moderation"}
            self.assertEqual(post(ban)[0], 403, "no token")
            ban["csrf"] = self.store.moderation.csrf
            self.assertEqual(post(ban, origin="https://evil.example")[0], 403, "cross-site")
            self.assertEqual(post(ban, origin=base), (303, "moderation"))
            self.assertEqual(post({**ban, "back": "https://evil.example/"}), (303, "./"), "open redirects refused")
            self.assertEqual(post({**ban, "tag": "nope"})[0], 400)
            self.assertEqual(len(self.game_file()["bans"]), 2)
            overview = urllib.request.urlopen(base + "/").read().decode()
            self.assertIn(">Kick</button>", overview, "live players get a kick button")
            self.assertIn(self.store.moderation.csrf, overview)
            moderation = urllib.request.urlopen(base + "/moderation").read().decode()
            self.assertIn("Active bans", moderation)
            self.assertIn(">Lift</button>", moderation)
            player = urllib.request.urlopen(base + "/player?tag=" + ALICE).read().decode()
            self.assertIn("rush b", player, "the player page shows their chat")
        finally:
            server.shutdown()


if __name__ == "__main__":
    unittest.main()
