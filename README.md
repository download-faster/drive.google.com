# tm-install — cài Traffmonetizer 1 lệnh

Tự động chạy Traffmonetizer trên Windows **chỉ với 1 lệnh**, hoàn toàn ẩn, siêu nhẹ:
**không Docker Desktop, không Docker Engine, không cần virtualization (VT-x/AMD-V)**.

Kiến trúc: distro Alpine nhỏ (3.65MB) import vào WSL ở chế độ **WSL1** (dịch syscall, không cần
máy ảo — chạy được cả trên máy ảo VirtualBox/VMware không bật nested VT-x) và chạy **binary
Linux chính thức của Traffmonetizer** (1.4MB) trực tiếp bên trong.

## Cách dùng

### Windows — chạy trong PowerShell, chỉ 1 lệnh duy nhất
```
irm https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1 | iex
```
(Lưu ý: lệnh này chỉ chạy trong PowerShell, không chạy trong CMD. Khi được hỏi email nhập xong Enter,
gõ gì cũng được; sau đó màn hình im lặng — toàn bộ cài đặt chạy ngầm. Tự xin quyền Admin qua UAC.)

Xóa sạch để cài lại:
```
irm https://raw.githubusercontent.com/khoahocdrive/tm-install/main/uninstall_windows.ps1 | iex
```

### Linux
```
curl -fsSL https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_linux.sh | sudo bash
```

### macOS
```
curl -fsSL https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_macos.sh | bash
```

## Windows: kiến trúc (v3)

- KHÔNG Docker Desktop, KHÔNG Docker Engine, KHÔNG cần bật virtualization trong BIOS
- Distro `tm-linux` (Alpine minirootfs) import thủ công ở chế độ **WSL1**:
  - không xuất hiện trong Start Menu, danh sách app hay recent apps
  - không cần VT-x/AMD-V → chạy được trên VM không có nested virtualization
  - RAM chiếm ~10-20MB (WSL1 không chạy máy ảo)
- Chạy binary chính thức `cli` của Traffmonetizer (tải từ repo này, 1.4MB) trực tiếp trong distro
- Task ẩn `TraffmonetizerResume` (wscript + guard.vbs) chạy lúc đăng nhập, giữ client sống 24/7,
  tự khởi động lại nếu client chết (vòng lặp guard + RestartCount + trigger lặp 30 phút + trigger hàng ngày)
- Icon "Linux" trong File Explorer bị ẩn qua registry
- Log client: `C:\ProgramData\tm\install.log` và trong distro: `/var/lib/tm/client.log`

## Kiểm tra sau khi cài (Windows)

```
notepad C:\ProgramData\tm\install.log          # log cai dat
wsl -d tm-linux -u root -- tail -n 20 /var/lib/tm/client.log   # log client
wsl -d tm-linux -u root -- /opt/tm/cli status --token <TOKEN>
```

## Lưu ý

- Nếu máy là **Windows chạy trong VirtualBox/VMware** mà chưa từng bật nested virtualization:
  script vẫn cài được bình thường nhờ chế độ WSL1 (không cần bật gì thêm ở BIOS/máy chủ).
- Muốn chuyển distro sang WSL2 (nếu máy có virtualization): `wsl --set-version tm-linux 2`
- Traffmonetizer chỉ chấp nhận IP nhà dân dụng — **tắt VPN/WARP** trước khi chạy, không thì client
  sẽ connecting → disconnected lặp vô hạn (xem `/var/lib/tm/client.log`).
- Watchtower cũ không còn cần thiết (không dùng Docker). Binary cập nhật bằng cách chạy lại lệnh cài.
