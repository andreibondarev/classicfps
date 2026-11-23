# Classic FPS dedicated server

The production service runs the Dust2-only Linux export as the unprivileged
`protocol47` user. Desktop clients connect on UDP 27447. Browser clients cannot
send UDP, so the server also accepts WebSockets on 27448, bound to localhost
only; Caddy serves the browser build over HTTPS and forwards `wss://<domain>/ws`
to it. Desktop and browser players share the same match.
An empty server waits for its first player, and restores its initial 5v5 bot
roster after the final player disconnects.

Build and validate locally (from the repository root):

```bash
npm run game:test:dedicated
npm run game:build:server
```

Install `game/builds/protocol47-server.x86_64` at
`/opt/protocol47/protocol47-server.x86_64`, install
`deploy/protocol47.service` at `/etc/systemd/system/protocol47.service`, then
run:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now protocol47.service
sudo systemctl status protocol47.service
sudo journalctl -u protocol47.service -f
```

The cloud firewall should admit UDP 27447 from players and restrict TCP 22 to
the operator's current IP. Keep the game binary and service file owned by root;
the service only needs write access to `/var/lib/protocol47`.

## Browser play

Requires a domain whose DNS A record points at the droplet (production:
`classicfps.app`, plus `www.classicfps.app`, `cs16.site` and `www.cs16.site`,
which redirect to it; all → 167.71.173.156); Caddy obtains the TLS
certificate automatically. Start Caddy only after the domain resolves, so the
certificate request does not burn Let's Encrypt's failed-validation limit.

Build locally (from the repository root), which also writes `.br`/`.gz` copies of the
large files (the Brotli package is roughly 43 MB instead of 218 MB):

```bash
npm run game:build:web
```

On the droplet:

```bash
sudo apt install caddy
sudo mkdir -p /var/www/protocol47
# copy game/builds/web/* to /var/www/protocol47/
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
# Ubuntu's caddy.service reads no environment file; set the domain in a drop-in.
sudo mkdir -p /etc/systemd/system/caddy.service.d
sudo cp deploy/caddy-protocol47.conf /etc/systemd/system/caddy.service.d/protocol47.conf
sudo systemctl daemon-reload && sudo systemctl restart caddy
```

The firewall must also admit TCP 80 (certificate issuance and redirect) and
TCP 443. Keep 27448 closed: the service binds it to 127.0.0.1. Players open
`https://<domain>/` and join automatically; `?offline` plays against bots
locally and `?server=wss://...` joins a different server.

## Admin dashboard

`https://<domain>/admin/` (user `admin`, password-protected by Caddy) shows who
is online, recent sessions (name, team, length, K/D, transport, IP, browser),
per-player totals, the chat log and moderation.

- The game server writes `/var/lib/protocol47/events.jsonl` and `status.json`
  when started with `--admin-log=` (see `protocol47.service`).
- `deploy/admin/protocol47_admin.py` (Python standard library) runs as the
  `p47admin` user (`protocol47-admin.service`), stores data in
  `/var/lib/protocol47-admin/admin.db` and listens on 127.0.0.1:8090.
- Browser players reach the game through Caddy. Caddy passes the browser's
  address to the game as `/ws?client_ip=` (the game trusts it only on its
  loopback listener); the service also reads Caddy's JSON access log for user
  agents. IPs and user agents are erased after 30 days (active bans keep theirs).
- Players are grouped by a random per-install tag the client sends; it is not
  an account and resets if the player clears site data.

Setup on the droplet (as root):

```bash
useradd --system --no-create-home --shell /usr/sbin/nologin p47admin
usermod -aG protocol47,systemd-journal p47admin
install -D -m 644 deploy/admin/protocol47_admin.py /opt/protocol47-admin/protocol47_admin.py
install -m 644 deploy/protocol47-admin.service /etc/systemd/system/
umask 077; head -c 18 /dev/urandom | base64 | tr -d "/+=" | head -c 20 > /root/protocol47-admin-password
echo "Environment=PROTOCOL47_ADMIN_HASH=$(caddy hash-password --plaintext "$(cat /root/protocol47-admin-password)")" \
  >> /etc/systemd/system/caddy.service.d/protocol47.conf
systemctl daemon-reload && systemctl restart caddy && systemctl enable --now protocol47-admin
```

The **Server health** section shows the game service's state, uptime, restarts
and crashes (from its journal), errors grouped with their GDScript backtraces,
current tick rate / physics time / CPU / memory / droplet load, disk and
network, and 24-hour charts (samples every 5 s, kept 7 days). The live table
adds each player's ping (application-level, every 2 s), packet loss (desktop
UDP only), bandwidth and reconnects in the last hour. JSON: `/admin/api/health`.

### Moderation

Live players have **Kick** and **Mute / Ban** buttons (Overview and player
pages); the **Chat** tab logs every message, including ones a mute blocked; the
**Moderation** tab lists active bans and mutes (with Lift), bans players who are
offline by ID or IP, and keeps an action log.

- Kick disconnects with the admin's reason; the player can rejoin.
- Ban (1 hour to permanent) matches the player's per-install ID and/or IP. A
  banned player is dropped at once and refused on every rejoin with the
  reason. ID bans survive IP changes but not clearing site data; IP bans hit
  everyone behind that address. Loopback can't be banned.
- Mute silences chat and voice for that ID.
- The admin service writes `/var/lib/protocol47/moderation/moderation.json`;
  the game (`--moderation=`, `game/scripts/moderation.gd`) reloads it every
  second and reports what it enforced back through the admin log. Forms carry
  a CSRF token and must come from the same origin (Basic auth alone would let
  another site post to them).

Setup on the droplet (as root), once:

```bash
install -d -o protocol47 -g protocol47 -m 2770 /var/lib/protocol47/moderation
install -m 644 deploy/admin/protocol47_moderation.py /opt/protocol47-admin/
install -m 644 deploy/protocol47.service deploy/protocol47-admin.service /etc/systemd/system/
cp deploy/Caddyfile /etc/caddy/Caddyfile
systemctl daemon-reload && systemctl restart protocol47 protocol47-admin && systemctl reload caddy
```

Tests: `cd deploy/admin && python3 -m unittest` and `node scripts/test-moderation.mjs`
(part of `npm run game:test:dedicated`).
