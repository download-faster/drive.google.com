$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$SelfUrl = 'https://raw.githubusercontent.com/khoahocdrive/tm-install/main/uninstall_windows.ps1'

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  if ($PSCommandPath) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  } else {
    $f = Join-Path $env:TEMP 'uninstall_tm.ps1'
    try { Invoke-WebRequest -Uri $SelfUrl -OutFile $f -UseBasicParsing } catch {}
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$f`""
  }
  exit
}

Write-Host 'Dang xoa sach Thi nghiem Traffmonetizer...'
& wsl.exe --unregister tm-linux 2>$null
Write-Host ' - Da xoa distro tm-linux (bao gom Docker Engine, container tm, du lieu)'
Unregister-ScheduledTask -TaskName 'TraffmonetizerResume' -Confirm:$false
Write-Host ' - Da xoa task tu dong chay khi dang nhap'
Remove-Item (Join-Path $env:ProgramData 'tm') -Recurse -Force
Write-Host ' - Da xoa thu muc C:\ProgramData\tm (script + log)'
Remove-Item (Join-Path $env:UserProfile '.wslconfig') -Force
Write-Host ' - Da xoa file .wslconfig'
Write-Host ''
Write-Host 'HOAN TAT xoa sach. WSL van con giu lai (de cai lai nhanh).'
Write-Host 'Neu muon xoa luon WSL: chay lenh  wsl --uninstall'
Start-Sleep -Seconds 15
