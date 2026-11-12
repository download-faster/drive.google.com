#!/usr/bin/env bash
# uninstall_linux.sh - Go cai Traffmonetizer sach se (binary truc tiep + systemd)
# Im lang terminal: chi in 1 dong HOAN TAT cuoi cung
set -u
[ "$(uname -s)" = "Linux" ] || { echo "Chi chay tren Linux"; exit 1; }
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { echo "LOI: can quyen root (sudo)"; exit 2; }
  exec sudo bash "$0" "$@"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now tm >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/tm.service
  systemctl daemon-reload >/dev/null 2>&1 || true
else
  rc-service tm stop >/dev/null 2>&1 || true
  rc-update delete tm default >/dev/null 2>&1 || true
  rm -f /etc/init.d/tm /usr/local/bin/tm-run.sh
fi
pkill -f '/opt/tm/cli start' 2>/dev/null || true

rm -rf /opt/tm /var/lib/tm /etc/tm
if id tm >/dev/null 2>&1; then userdel tm 2>/dev/null || true; fi

if command -v docker >/dev/null 2>&1; then
  docker rm -f tm watchtower >/dev/null 2>&1 || true
fi

echo "HOAN TAT: Da go Traffmonetizer sach se."
exit 0
