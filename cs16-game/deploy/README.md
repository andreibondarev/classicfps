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

Requires a domain whose DNS A record points at the droplet; Caddy obtains the
TLS certificate automatically.

Build locally (from `cs16-game/`), which also writes `.br`/`.gz` copies of the
large files (the Brotli package is roughly 43 MB instead of 218 MB):

```bash
npm run game:build:web
```

On the droplet:

```bash
sudo apt install caddy
sudo mkdir -p /opt/protocol47/web
# copy game/builds/web/* to /opt/protocol47/web/
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
echo 'PROTOCOL47_DOMAIN=play.example.com' | sudo tee /etc/default/caddy
sudo systemctl restart caddy
```

The firewall must also admit TCP 80 (certificate issuance and redirect) and
TCP 443. Keep 27448 closed: the service binds it to 127.0.0.1. Players open
`https://<domain>/` and join automatically; `?offline` plays against bots
locally and `?server=wss://...` joins a different server.
