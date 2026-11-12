#!/usr/bin/env bash
# uninstall_macos.sh - Go cai Traffmonetizer sach se (kien truc Lima)
# Giu lai: Lima, Homebrew, QEMU (neu co) - chi go phan lien quan TM
# Im lang terminal: chi hoi xac nhan + in 1 dong HOAN TAT cuoi cung
if [ -z "${TM_SKIP_PROMPT:-}" ]; then
  export TM_SKIP_PROMPT=1
  if { true </dev/tty; } 2>/dev/null; then
    printf 'Go cai Traffmonetizer - nhan Enter de dong y (Ctrl+C de huy): ' >/dev/tty
    read -r _ </dev/tty || true
  fi
fi
for _d in /opt/homebrew/bin /usr/local/bin "$HOME/.lima-bin/bin" /usr/bin /bin /usr/sbin /sbin; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
export PATH
set -u
[ "$(id -u)" -ne 0 ] || { echo "Khong duoc chay voi sudo/root"; exit 1; }

launchctl bootout "gui/$(id -u)/com.khoahocdrive.tm" >/dev/null 2>&1 || launchctl unload -w "$HOME/Library/LaunchAgents/com.khoahocdrive.tm.plist" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/com.khoahocdrive.tm.plist"
pkill -f "$HOME/.tm/guard.sh" 2>/dev/null || true

if command -v limactl >/dev/null 2>&1; then
  limactl stop -f tm-linux >/dev/null 2>&1 || true
  limactl delete -f tm-linux >/dev/null 2>&1 || true
fi

if command -v docker >/dev/null 2>&1; then
  docker rm -f tm watchtower >/dev/null 2>&1 || true
fi

rm -rf "$HOME/.tm"
pkill -f "limactl start tm-linux" 2>/dev/null || true

echo "HOAN TAT: Da go Traffmonetizer sach se. (Lima/QEMU/Homebrew giu nguyen; muon go luon: brew uninstall lima qemu)"
exit 0
