"""HTML pages for the Protocol 47 admin dashboard (no external assets).

Tabs: Overview (status, live match, key charts, latest sessions), Players,
Sessions, Health (uptime, crashes, charts, events, errors), plus a player
detail page. Every link is relative, because Caddy serves this under /admin/.
"""
import html
import time

LOCAL_ADDRESSES = ("127.0.0.1", "::1", "")
TABS = [("overview", "Overview", "./"), ("players", "Players", "players"),
        ("sessions", "Sessions", "sessions"), ("health", "Health", "health")]

STYLE = """
:root { --bg: #0f1114; --panel: #171a1f; --panel-2: #1d2128; --line: #262b33; --text: #e7e3da;
  --muted: #8d8a83; --accent: #f0b54a; --t: #ff8a68; --ct: #7fb0ff; --ok: #6fd58a; --bad: #ff6b5e;
  --link: #9fd3ff; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
header { position: sticky; top: 0; z-index: 2; background: rgba(15,17,20,.92); backdrop-filter: blur(6px);
  border-bottom: 1px solid var(--line); }
.bar { max-width: 1240px; margin: 0 auto; padding: 14px 20px 0; display: flex; align-items: center; gap: 18px; flex-wrap: wrap; }
.brand { font-weight: 700; font-size: 16px; letter-spacing: .2px; }
.brand span { color: var(--accent); }
.status { margin-left: auto; font-size: 13px; color: var(--muted); display: flex; gap: 10px; align-items: center; }
nav { max-width: 1240px; margin: 0 auto; padding: 8px 20px 0; display: flex; gap: 4px; overflow-x: auto; }
nav a { padding: 9px 14px; color: var(--muted); border-bottom: 2px solid transparent; font-weight: 600; white-space: nowrap; }
nav a.active { color: var(--text); border-bottom-color: var(--accent); text-decoration: none; }
main { max-width: 1240px; margin: 0 auto; padding: 22px 20px 40px; }
.grid { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); margin-bottom: 18px; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px 18px; margin-bottom: 18px; }
.card h2 { margin: 0 0 12px; font-size: 15px; display: flex; align-items: center; gap: 10px; }
.card h2 .sub { color: var(--muted); font-weight: 500; font-size: 13px; }
.tile { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 14px 16px; }
.tile .label { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .6px; }
.tile .value { font-size: 24px; font-weight: 700; margin-top: 2px; }
.tile .hint { color: var(--muted); font-size: 12px; }
.pill { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 12px; font-weight: 600; background: var(--panel-2); }
.pill.ok { color: var(--ok); background: rgba(111,213,138,.12); } .pill.bad { color: var(--bad); background: rgba(255,107,94,.12); }
.team { display: inline-block; min-width: 30px; text-align: center; padding: 1px 7px; border-radius: 6px; font-size: 12px; font-weight: 700; }
.team.T { color: var(--t); background: rgba(255,138,104,.12); } .team.CT { color: var(--ct); background: rgba(127,176,255,.12); }
.team.none { color: var(--muted); background: var(--panel-2); }
.table { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; white-space: nowrap; }
th { color: var(--muted); font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .5px; }
tr:hover td { background: rgba(255,255,255,.02); }
td.wrap { white-space: normal; }
.muted { color: var(--muted); } .bad { color: var(--bad); font-weight: 600; } .ok { color: var(--ok); }
.place { display: block; color: var(--muted); font-size: 12px; }
code { color: var(--link); font-size: 12px; }
.scoreboard { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.score { font-size: 30px; font-weight: 800; }
.score.T { color: var(--t); } .score.CT { color: var(--ct); }
.charts { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); }
.chart { background: var(--panel-2); border-radius: 10px; padding: 12px 14px 8px; }
.chart .head { display: flex; justify-content: space-between; font-size: 13px; }
.chart .head b { font-size: 16px; }
.chart svg { width: 100%; height: 70px; display: block; margin-top: 6px; }
.chart .axis { display: flex; justify-content: space-between; color: var(--muted); font-size: 11px; }
input.search { width: 100%; max-width: 360px; background: var(--panel-2); color: var(--text); border: 1px solid var(--line);
  border-radius: 8px; padding: 8px 12px; margin-bottom: 12px; font: inherit; }
details summary { cursor: pointer; } pre { white-space: pre-wrap; font-size: 12px; color: #c8c2b6; margin: 8px 0 0; }
footer { max-width: 1240px; margin: 0 auto; padding: 0 20px 30px; color: var(--muted); font-size: 12px; }
@media (max-width: 700px) { .scoreboard { grid-template-columns: 1fr; } .status { margin-left: 0; } }
"""

SEARCH_SCRIPT = """<script>
for (const input of document.querySelectorAll('input.search')) {
  input.addEventListener('input', () => {
    const needle = input.value.toLowerCase();
    for (const row of document.querySelectorAll(input.dataset.rows))
      row.style.display = row.textContent.toLowerCase().includes(needle) ? '' : 'none';
  });
}
</script>"""


# -- formatting helpers ------------------------------------------------------
def esc(value):
    return html.escape("" if value is None else str(value))


def when(ts):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts)) if ts else ""


def ago(ts):
    if not ts:
        return ""
    seconds = max(0, time.time() - ts)
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)} min ago"
    if seconds < 86400:
        return f"{int(seconds // 3600)} h ago"
    return f"{int(seconds // 86400)} d ago"


def duration(seconds):
    if seconds is None:
        return "&mdash;"
    seconds = int(seconds)
    if seconds >= 86400:
        return f"{seconds // 86400}d {seconds % 86400 // 3600}h"
    return f"{seconds // 3600}h {seconds % 3600 // 60:02d}m" if seconds >= 3600 else f"{seconds // 60}m {seconds % 60:02d}s"


def number(value, digits=0, suffix=""):
    return "&mdash;" if value is None else f"{value:.{digits}f}{suffix}"


def kd(kills, deaths):
    kills, deaths = kills or 0, deaths or 0
    ratio = f'<span class="muted"> ({kills / deaths:.2f})</span>' if deaths else ""
    return f"{kills} / {deaths}{ratio}"


def team(value):
    value = value or ""
    css = value if value in ("T", "CT") else "none"
    return f'<span class="team {css}">{esc(value if value in ("T", "CT") else "–")}</span>'


def short_tag(tag):
    return f'<a href="player?tag={esc(tag)}"><code>{esc(tag[:8])}</code></a>' if tag else '<span class="muted">&mdash;</span>'


def place(label):
    return f'<span class="place">{esc(label)}</span>' if label else ""


def address(session):
    value = session.get("address") or ""
    if session.get("transport") == "ws" and value in LOCAL_ADDRESSES:
        text = "after disconnect" if not session.get("left") else "unmatched"
        return f'<span class="muted">{text}</span>'
    return esc(value) + place(session.get("location"))


def ping(player):
    rtt = player.get("rtt_ms")
    if rtt is None or rtt < 0:
        return '<span class="muted">&mdash;</span>'
    return f'<span class="{"bad" if rtt > 150 else ("ok" if rtt < 80 else "")}">{rtt:.0f} ms</span>'


# -- charts --------------------------------------------------------------
def sparkline(values, color, label, unit="", digits=0, floor=None, span_label="24 h ago"):
    """Area chart; one value per bucket (None = gap). Width scales to the card."""
    width, height = 600, 70
    points = [v for v in values if v is not None]
    if not points:
        return (f'<div class="chart"><div class="head"><span>{esc(label)}</span><span class="muted">no data yet</span></div>'
                f'<svg viewBox="0 0 {width} {height}" preserveAspectRatio="none"></svg>'
                f'<div class="axis"><span>{esc(span_label)}</span><span>now</span></div></div>')
    low = min(points) if floor is None else min(floor, min(points))
    high = max(points)
    spread = (high - low) or 1.0
    step = width / max(1, len(values) - 1)
    segments, current = [], []
    for index, value in enumerate(values):
        if value is None:
            if current:
                segments.append(current)
            current = []
            continue
        current.append((index * step, height - 3 - (value - low) / spread * (height - 6)))
    if current:
        segments.append(current)
    shapes = []
    for segment in segments:
        if len(segment) == 1:  # a lone bucket: draw a dot
            x, y = segment[0]
            shapes.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3" fill="{color}"/>')
            continue
        line = " ".join(f"{x:.1f},{y:.1f}" for x, y in segment)
        area = f"{segment[0][0]:.1f},{height} {line} {segment[-1][0]:.1f},{height}"
        shapes.append(f'<polygon points="{area}" fill="{color}" fill-opacity="0.12"/>'
                      f'<polyline points="{line}" fill="none" stroke="{color}" stroke-width="2" '
                      f'vector-effect="non-scaling-stroke" stroke-linejoin="round"/>')
    return (f'<div class="chart"><div class="head"><span>{esc(label)}</span>'
            f'<span><b>{number(points[-1], digits, unit)}</b> <span class="muted">max {number(high, digits, unit)}</span></span></div>'
            f'<svg viewBox="0 0 {width} {height}" preserveAspectRatio="none">{"".join(shapes)}</svg>'
            f'<div class="axis"><span>{esc(span_label)}</span><span>now</span></div></div>')


# -- page shell ------------------------------------------------------------
def page(active, title, body, store, refresh=False):
    health = store.health()
    state = health["state"]
    up = state.get("ActiveState") == "active"
    status = (f'<span class="pill {"ok" if up else "bad"}">{"Server online" if up else "Server " + esc(state.get("ActiveState") or "unknown")}</span>'
              f'<span>up {duration(health["uptime"])}</span>'
              + (f'<span class="pill bad">{health["crashes_24h"]} crash{"es" if health["crashes_24h"] != 1 else ""} in 24 h</span>'
                 if health["crashes_24h"] else ""))
    tabs = "".join(f'<a href="{href}" class="{"active" if key == active else ""}">{label}</a>' for key, label, href in TABS)
    meta = '<meta http-equiv="refresh" content="15">' if refresh else ""
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{esc(title)} · Protocol 47 admin</title>'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">{meta}<style>{STYLE}</style></head><body>'
            f'<header><div class="bar"><div class="brand">Protocol 47 <span>admin</span></div>'
            f'<div class="status">{status}</div></div><nav>{tabs}</nav></header>'
            f'<main>{body}</main><footer>Updated {when(time.time())}{" · refreshes every 15 s" if refresh else ""} · '
            f'IP geolocation by <a href="https://db-ip.com">DB-IP</a> (CC BY 4.0), approximate.</footer>'
            f'{SEARCH_SCRIPT}</body></html>')


def tile(label, value, hint="", css=""):
    return (f'<div class="tile"><div class="label">{esc(label)}</div><div class="value {css}">{value}</div>'
            f'<div class="hint">{hint}</div></div>')


# -- sections --------------------------------------------------------------
def live_section(store):
    live = store.live()
    if not live.get("online"):
        return '<div class="card"><h2>Live match</h2><p class="muted">The game server is not reporting status.</p></div>'
    players = live.get("players", [])
    sides = {"T": [], "CT": [], "other": []}
    for player in players:
        sides[player.get("team") if player.get("team") in ("T", "CT") else "other"].append(player)

    def roster(side):
        rows = "".join(
            f'<tr><td>{esc(p.get("name"))}{"" if p.get("alive") else " <span class=muted>(dead)</span>"}</td>'
            f'<td>{kd(p.get("kills"), p.get("deaths"))}</td><td>{ping(p)}</td>'
            f'<td>{esc(p.get("transport"))}</td><td>{address(p)}</td><td>{short_tag(p.get("tag", ""))}</td></tr>'
            for p in sides[side])
        return (f'<div class="table"><table><tr><th>Player</th><th>K / D</th><th>Ping</th><th>Via</th><th>Address</th><th>ID</th></tr>'
                f'{rows or "<tr><td colspan=6 class=muted>No humans</td></tr>"}</table></div>')

    unassigned = ""
    if sides["other"]:
        names = ", ".join(esc(p.get("name")) for p in sides["other"])
        unassigned = f'<p class="muted">Choosing a team: {names}</p>'
    return (f'<div class="card"><h2>Live match <span class="sub">{esc(live.get("map"))} · round {esc(live.get("round"))} · '
            f'{esc(live.get("phase"))} · {esc(live.get("bots"))} bots</span></h2>'
            f'<div class="scoreboard"><div><div class="score T">T {esc(live.get("t_score"))}</div>{roster("T")}</div>'
            f'<div><div class="score CT">CT {esc(live.get("ct_score"))}</div>{roster("CT")}</div></div>{unassigned}</div>')


def sessions_table(sessions, searchable=False):
    rows = "".join(
        f'<tr class="session-row"><td>{when(s["connected"])}<span class="place">{ago(s["connected"])}</span></td>'
        f'<td>{esc(s["name"])}</td><td>{team(s["team"])}</td>'
        f'<td>{duration(s["seconds"]) if s["left"] else "<span class=ok>online</span>"}</td>'
        f'<td>{kd(s["kills"], s["deaths"])}</td><td>{esc(s["transport"])}</td><td>{address(s)}</td>'
        f'<td>{short_tag(s["tag"] or "")}</td><td class="muted">{esc(browser(s["user_agent"]))}</td></tr>'
        for s in sessions)
    search = ('<input class="search" placeholder="Filter by name, IP, place, browser…" data-rows=".session-row">'
              if searchable else "")
    return (f'{search}<div class="table"><table><tr><th>Joined</th><th>Name</th><th>Team</th><th>Length</th><th>K / D</th>'
            f'<th>Via</th><th>Address</th><th>ID</th><th>Browser</th></tr>'
            f'{rows or "<tr><td colspan=9 class=muted>No sessions yet</td></tr>"}</table></div>')


def browser(agent):
    agent = agent or ""
    for needle, name in (("Edg/", "Edge"), ("Firefox/", "Firefox"), ("Chrome/", "Chrome"), ("Safari/", "Safari")):
        if needle in agent:
            system = next((s for s in ("Windows", "Mac OS X", "Android", "iPhone", "iPad", "Linux") if s in agent), "")
            return f"{name}{' · ' + system.replace('Mac OS X', 'macOS') if system else ''}"
    return agent[:40]


def charts(series, keys):
    column = lambda key: [row[key] for row in series]  # noqa: E731
    specs = {
        "players": ("#f0b54a", "Players online", "", 0, 0),
        "tick_rate": ("#6fd58a", "Tick rate", "", 1, None),
        "physics_ms": ("#ff8a68", "Physics time (max)", " ms", 1, 0),
        "cpu_pct": ("#9fd3ff", "Game CPU (one core)", "%", 0, 0),
        "rss_mb": ("#c9a0ff", "Game memory", " MB", 0, None),
        "net_out_kbps": ("#7fb0ff", "Droplet upload", " kbit/s", 0, 0),
    }
    return '<div class="charts">' + "".join(
        sparkline(column(key), *specs[key][:2], unit=specs[key][2], digits=specs[key][3], floor=specs[key][4])
        for key in keys) + "</div>"


# -- pages -------------------------------------------------------------------
def render_overview(store):
    health = store.health()
    latest = health["latest"]
    totals = store.totals()
    live = store.live()
    online = len(live.get("players", [])) if live.get("online") else 0
    target = latest.get("target_tick_rate") or 100
    tick = latest.get("tick_rate")
    tiles = ('<div class="grid">'
             + tile("Online now", online, f'{esc(live.get("bots", 0))} bots')
             + tile("Tick rate", number(tick, 1), f"target {number(target)} / s",
                    "bad" if tick is not None and tick < 0.95 * target else "")
             + tile("Game CPU", number(latest.get("cpu_pct"), 0, "%"), "of one core")
             + tile("Players seen", totals["players"] or 0, f'{totals["sessions"] or 0} sessions')
             + tile("Play time", duration(totals["seconds"] or 0), f'{totals["rounds"]} rounds · {totals["matches"]} matches')
             + "</div>")
    recent = sessions_table(store.sessions(8))
    return page("overview", "Overview",
                tiles + live_section(store)
                + f'<div class="card"><h2>Last 24 hours</h2>{charts(health["series"], ["players", "tick_rate", "cpu_pct"])}</div>'
                + f'<div class="card"><h2>Latest sessions <a class="sub" href="sessions">all sessions →</a></h2>{recent}</div>',
                store, refresh=True)


def render_players(store):
    rows = "".join(
        f'<tr class="player-row"><td>{short_tag(p["tag"])}</td><td class="wrap">{esc(", ".join(p["names"][:5]))}</td>'
        f'<td>{p["sessions"]}</td><td>{duration(p["seconds"])}</td><td>{kd(p["kills"], p["deaths"])}</td>'
        f'<td>{esc(p["last_address"])}{place(p.get("location"))}</td>'
        f'<td>{when(p["last_seen"])}<span class="place">{ago(p["last_seen"])}</span></td></tr>' for p in store.players())
    body = ('<div class="card"><h2>Players <span class="sub">grouped by browser install</span></h2>'
            '<input class="search" placeholder="Filter by name, IP, place…" data-rows=".player-row">'
            '<div class="table"><table><tr><th>ID</th><th>Names</th><th>Sessions</th><th>Play time</th><th>K / D</th>'
            f'<th>Last address</th><th>Last seen</th></tr>{rows or "<tr><td colspan=7 class=muted>No players yet</td></tr>"}'
            '</table></div></div>')
    return page("players", "Players", body, store)


def render_sessions(store):
    return page("sessions", "Sessions",
                f'<div class="card"><h2>Sessions <span class="sub">most recent 300</span></h2>'
                f'{sessions_table(store.sessions(300), searchable=True)}</div>', store)


def render_health(store):
    health = store.health()
    state, latest = health["state"], health["latest"]
    target = latest.get("target_tick_rate") or 100
    tick = latest.get("tick_rate")
    tiles = ('<div class="grid">'
             + tile("Uptime", duration(health["uptime"]), f'restarts {state.get("NRestarts", 0)}')
             + tile("Crashes", health["crashes_24h"], f'{health["crashes_7d"]} in 7 days', "bad" if health["crashes_24h"] else "")
             + tile("Tick rate", number(tick, 1), f"target {number(target)} / s", "bad" if tick is not None and tick < 0.95 * target else "")
             + tile("Physics", number(latest.get("physics_ms"), 1, " ms"), f"budget {number(1000 / target, 0, ' ms')} per tick",
                    "bad" if (latest.get("physics_ms") or 0) > 1000 / target else "")
             + tile("Game CPU", number(latest.get("cpu_pct"), 0, "%"), "of one core")
             + tile("Game memory", number(latest.get("rss_mb"), 0, " MB"), "resident")
             + tile("Droplet", f'{number(latest.get("load1"), 2)}', f'load · RAM {number(latest.get("mem_used_pct"), 0, "%")} · disk {number(latest.get("disk_used_pct"), 0, "%")}')
             + tile("Network", number(latest.get("net_out_kbps"), 0), f'kbit/s out · {number(latest.get("net_in_kbps"), 0)} in')
             + "</div>")
    chart_card = (f'<div class="card"><h2>Last 24 hours <span class="sub">5-minute buckets</span></h2>'
                  f'{charts(health["series"], ["players", "tick_rate", "physics_ms", "cpu_pct", "rss_mb", "net_out_kbps"])}</div>')
    event_rows = "".join(
        f'<tr><td>{when(e["ts"])}<span class="place">{ago(e["ts"])}</span></td>'
        f'<td><span class="pill {"bad" if e["kind"] == "crash" else ""}">{esc(e["kind"])}</span></td>'
        f'<td class="muted wrap">{esc(e["detail"])}</td></tr>' for e in health["events"])
    error_rows = "".join(
        f'<tr><td><span class="pill">{esc(e["kind"])}</span></td><td>{e["count"]}</td>'
        f'<td>{when(e["last_seen"])}<span class="place">{ago(e["last_seen"])}</span></td>'
        f'<td class="wrap"><details><summary>{esc(e["message"][:160])}</summary>'
        f'<div class="muted">{esc(e["location"])}</div><pre>{esc(e["backtrace"])}</pre></details></td></tr>'
        for e in health["errors"])
    body = (tiles + chart_card
            + '<div class="card"><h2>Server events</h2><div class="table"><table><tr><th>When</th><th>Event</th><th>Detail</th></tr>'
            + (event_rows or "<tr><td colspan=3 class=muted>None recorded</td></tr>") + '</table></div></div>'
            + '<div class="card"><h2>Errors <span class="sub">grouped, last 30 days</span></h2><div class="table"><table>'
            + '<tr><th>Kind</th><th>Count</th><th>Last seen</th><th>Message</th></tr>'
            + (error_rows or "<tr><td colspan=4 class=muted>No errors logged</td></tr>") + '</table></div></div>')
    return page("health", "Health", body, store, refresh=True)


def render_player(store, tag):
    sessions = store.sessions(500, tag=tag)
    names = sorted({s["name"] for s in sessions if s["name"]})
    kills = sum(s["kills"] or 0 for s in sessions)
    deaths = sum(s["deaths"] or 0 for s in sessions)
    played = sum(s["seconds"] or 0 for s in sessions)
    tiles = ('<div class="grid">' + tile("Sessions", len(sessions)) + tile("Play time", duration(played))
             + tile("K / D", f"{kills} / {deaths}", f"{kills / deaths:.2f} ratio" if deaths else "")
             + tile("First seen", ago(min((s["connected"] for s in sessions), default=0)) or "&mdash;")
             + "</div>")
    body = (f'<p><a href="players">← Players</a></p><div class="card"><h2>Player <code>{esc(tag)}</code></h2>'
            f'<p>Names used: {esc(", ".join(names)) or "<span class=muted>none</span>"}</p></div>'
            f'{tiles}<div class="card"><h2>Sessions</h2>{sessions_table(sessions)}</div>')
    return page("players", "Player", body, store)


render_dashboard = render_overview
