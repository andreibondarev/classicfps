# Protocol 47 dedicated server

The production service runs the Dust2-only Linux export as the unprivileged
`protocol47` user. Desktop clients connect on UDP 27447. Browser clients cannot
send UDP, so the server also accepts WebSockets on 27448, bound to localhost
only; Caddy serves the browser build over HTTPS and forwards `wss://<domain>/ws`
to it. Desktop and browser players share the same match.
An empty server waits for its first player, and restores its initial 5v5 bot
roster after the final player disconnects.

Build and validate locally (from `cs16-game/`):

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

Build locally (from `cs16-game/`), which also writes `.br`/`.gz` copies of the
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
is online, recent sessions (name, team, length, K/D, transport, IP, browser)
and per-player totals. It is read-only.

- The game server writes `/var/lib/protocol47/events.jsonl` and `status.json`
  when started with `--admin-log=` (see `protocol47.service`).
- `deploy/admin/protocol47_admin.py` (Python standard library) runs as the
  `p47admin` user (`protocol47-admin.service`), stores data in
  `/var/lib/protocol47-admin/admin.db` and listens on 127.0.0.1:8090.
- Browser players reach the game through Caddy, so the game only sees
  127.0.0.1; the service recovers their IP from Caddy's JSON access log (in the
  journal) once a session ends. IPs and user agents are erased after 30 days.
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

Tests: `cd deploy/admin && python3 -m unittest test_protocol47_admin`.
