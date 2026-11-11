# tm-install — cài Traffmonetizer 1 lệnh

Tự động cài Docker **trong WSL** (không dùng Docker Desktop) và chạy container Traffmonetizer. Chạy ngầm hoàn toàn, màn hình chỉ hiện chỗ nhập email + `Hello`.

## Cách dùng

### Windows (PowerShell hoặc CMD)
```
powershell -c "irm https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1 | iex"
```

### Linux
```
curl -fsSL https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_linux.sh | sudo bash
```

### macOS
```
curl -fsSL https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_macos.sh | bash
```

## Windows: kiến trúc mới (gọn và ẩn)

- KHÔNG cài Docker Desktop (tiết kiệm ~595MB download + ~2GB ổ đĩa + ~800MB RAM)
- Dùng Docker Engine bên trong một distro WSL import thủ công (`tm-linux`, Alpine) — distro import **không xuất hiện** trong Start Menu, danh sách app hay recent apps
- WSL bị giới hạn 1GB RAM / 2 CPU / 0 swap qua `.wslconfig`
- Task `TraffmonetizerResume` chạy ẩn lúc đăng nhập để tự khởi động Docker + container
- watchtower mặc định TẮT (bật lại: đặt biến môi trường `TM_WATCHTOWER=true` trước khi chạy)

## Kiểm tra sau khi cài (Windows)

```
wsl -d tm-linux -u root -- docker logs tm
notepad C:\ProgramData\tm\install.log
```

## Lưu ý

- Traffmonetizer chỉ chấp nhận IP nhà dân dụng — **tắt VPN/WARP** trước khi chạy, không thì container sẽ connecting → disconnected lặp vô hạn.
- Sau khi cài xong, nên tạo file `.wslconfig` (script tự tạo nếu chưa có) để giữ máy nhẹ.
