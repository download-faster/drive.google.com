#!/usr/bin/env bash
# uninstall_linux.sh - Go cai Traffmonetizer sach se (binary truc tiep + systemd)
# Khong ghi log
set -u
[ "$(uname -s)" = "Linux" ] || { echo "Chi chay tren Linux"; exit 1; }
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { echo "LOI: can quyen root (sudo)"; exit 2; }
  exec sudo bash "$0" "$@"
fi

echo "== 1. Tat va xoa dich vu =="
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

echo "== 2. Xoa binary va du lieu =="
rm -rf /opt/tm /var/lib/tm /etc/tm
if id tm >/dev/null 2>&1; then userdel tm 2>/dev/null || true; fi

echo "== 3. Don container Docker kien truc cu (neu co) =="
if command -v docker >/dev/null 2>&1; then
  docker rm -f tm watchtower >/dev/null 2>&1 || true
fi

echo "HOAN TAT: Da go Traffmonetizer sach se (khong con log, binary, dich vu)."
exit 0
