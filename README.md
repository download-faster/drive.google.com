# Traffmonetizer — Cài đặt tự động 1 lệnh (Linux / macOS / Windows)

Script tự động: cài Docker (nếu chưa có) → chạy container `tm` (traffmonetizer/cli_v2) → tự động cập nhật bằng watchtower.
Toàn bộ cài đặt chạy ngầm, không hiện cửa sổ/log — chỉ hiện chỗ nhập email và "Hello".

## Lưu ý trước khi cài
- **TẮT VPN / Cloudflare WARP / proxy** trên máy. Traffmonetizer **chỉ chấp nhận IP nhà mạng dân dụng** — nếu bật VPN, container sẽ bị ngắt kết nối liên tục (`connecting → disconnected`).
- Máy cần kết nối Internet ổn định.
- Docker mới cài trên Windows/macOS lần đầu có thể cần khởi động lại máy rồi chạy lại script.

## 🐧 Linux
Mở Terminal, chạy (nhập mật khẩu sudo khi được hỏi):
```bash
curl -fsSL https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_linux.sh | sudo bash
```

## 🍎 macOS
Mở Terminal, chạy (khi được hỏi nhập email chỉ cần nhập rồi Enter):
```bash
curl -fsSL https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_macos.sh | bash
```

## 🪟 Windows
Mở **PowerShell**, chạy 1 lệnh:
```powershell
irm https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1 | iex
```

Nếu đang trong **CMD**, chạy lệnh này thay thế:
```cmd
powershell -c "irm https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1 | iex"
```

## Kiểm tra đã chạy thành công
```bash
docker logs -f tm        # phải thấy: connected (và giữ nguyên)
```
- Log cài đặt: Linux `/var/log/tm_install.log` — macOS `~/.tm/install.log` — Windows `C:\ProgramData\tm\install.log`
- Xem thiết bị và thu nhập: dashboard traffmonetizer.com

## Gỡ
```bash
docker rm -f tm watchtower
```
