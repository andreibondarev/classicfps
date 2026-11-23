#!/bin/sh
# Refresh DB-IP's free City Lite database (CC BY 4.0, https://db-ip.com) used
# by protocol47_admin.py for approximate IP locations. The admin service
# reopens the file when it changes. Run monthly (protocol47-geoip.timer).
set -eu
target="${1:-/var/lib/protocol47-admin/dbip-city-lite.mmdb}"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
for month in "$(date -u +%Y-%m)" "$(date -u -d "$(date -u +%Y-%m-01) -1 month" +%Y-%m)"; do
  if curl -fsSL --max-time 600 -o "$work/db.mmdb.gz" "https://download.db-ip.com/free/dbip-city-lite-$month.mmdb.gz"; then
    gunzip -f "$work/db.mmdb.gz"
    # Refuse anything that is not a MaxMind DB before replacing the old file.
    if grep -q "MaxMind.com" "$work/db.mmdb"; then
      install -m 640 "$work/db.mmdb" "$target.new"
      mv -f "$target.new" "$target"
      echo "Installed DB-IP City Lite $month"
      exit 0
    fi
  fi
done
echo "No DB-IP City Lite download available" >&2
exit 1
