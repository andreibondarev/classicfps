# Protocol 47 dedicated server

The production service runs the Dust2-only Linux export as the unprivileged
`protocol47` user. It listens on UDP 27447 and does not open a TCP game port.
An empty server waits for its first player, and restores its initial 5v5 bot
roster after the final player disconnects.

Build and validate locally:

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
