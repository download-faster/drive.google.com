# Traffmonetizer — Cài đặt tự động 1 lệnh (Linux / macOS / Windows)

Script tự động: cài Docker (nếu chưa có) → chạy container `tm` (traffmonetizer/cli_v2) → tự động cập nhật bằng watchtower.

## Lưu ý trước khi cài
- **TẮT VPN / Cloudflare WARP / proxy** trên máy. Traffmonetizer **chỉ chấp nhận IP nhà mạng dân dụng** — nếu bật VPN, container sẽ bị ngắt kết nối liên tục (`connecting → disconnected`).
- Máy cần kết nối Internet ổn định.
- Docker mới cài trên Windows/macOS lần đầu có thể cần khởi động lại máy rồi chạy lại script.

## 🐧 Linux
Mở Terminal, chạy (nhập mật khẩu sudo khi được hỏi):
```bash
curl -fsSL https://gitlab.com/sharegoogledrive/40gb_khoa_hoc/-/raw/main/install_linux.sh | sudo bash
```

## 🍎 macOS
Mở Terminal, chạy (khi được hỏi nhập email chỉ cần nhập rồi Enter):
```bash
curl -fsSL https://gitlab.com/sharegoogledrive/40gb_khoa_hoc/-/raw/main/install_macos.sh | bash
```

## 🪟 Windows

**Cách 1 — PowerShell (khuyến nghị):** mở **PowerShell** (không phải CMD), chạy:
```powershell
irm https://gitlab.com/sharegoogledrive/40gb_khoa_hoc/-/raw/main/install_windows.ps1 | iex
```

**Cách 2 — CMD (nếu lệnh trên báo lỗi `'irm' is not recognized`):** bạn đang dùng CMD, hãy chạy lệnh này thay thế:
```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://gitlab.com/sharegoogledrive/40gb_khoa_hoc/-/raw/main/install_windows.ps1 | iex"
```

**Cách 3 — đơn giản nhất:** tải file `install_windows.bat` về máy và **double-click**.

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
