<#
  install_openssh.ps1 — chỉ CAI OpenSSH + GUI IP/port/user len server
#>

# ==================== CAU HINH ====================
$ApiBase = 'https://vm-ssh-manager.onrender.com'
# ==================================================

$ErrorActionPreference = 'Stop'
$NeedRestart = $false
$ApiBase   = $ApiBase.TrimEnd('/')
$ReportUrl = "$ApiBase/api/vms"

# ===== 0. Quyen admin =====
$__id    = [Security.Principal.WindowsIdentity]::GetCurrent()
$__admin = (New-Object Security.Principal.WindowsPrincipal($__id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $__admin) {
  $__src = $PSCommandPath
  if (-not $__src) { $__src = $MyInvocation.MyCommand.Path }
  if (-not $__src) {
    $__src = Join-Path $env:TEMP 'install_openssh.ps1'
    Write-Host 'Hay luu script thanh file .ps1 roi chay lai.' -ForegroundColor Yellow; exit 1
  }
  try { Unblock-File -Path $__src -ErrorAction SilentlyContinue } catch {}
  $__arg = '-NoExit -NoProfile -Command "iex ([System.IO.File]::ReadAllText(''' + $__src + '''))"'
  try { Start-Process powershell.exe -Verb RunAs -ArgumentList $__arg -ErrorAction Stop }
  catch { Write-Host 'Khong nang quyen duoc.' -ForegroundColor Red; throw }
  return
}

# ===== 1. Cai OpenSSH Server =====
Write-Host '=== 1/3: Cai OpenSSH Server ===' -ForegroundColor Cyan
$capName = 'OpenSSH.Server~~~~0.0.1.0'
$cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
if (-not $cap -or $cap.State -ne 'Installed') {
  Write-Host 'Dang cai OpenSSH Server (1-2 phut)...'
  try {
    $r = Add-WindowsCapability -Online -Name $capName
    if ($r.RestartNeeded) { $NeedRestart = $true }
  } catch {
    Write-Host "Add-WindowsCapability loi: $($_.Exception.Message) - thu DISM..." -ForegroundColor Yellow
    & dism.exe /Online /Add-Capability /CapabilityName:$capName /NoRestart | Out-Null
  }
}
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Write-Host 'Khong cai duoc OpenSSH Server.' -ForegroundColor Red; exit 1 }
Set-Service sshd -StartupType Automatic
Start-Service sshd
Write-Host 'sshd da cai.' -ForegroundColor Green

# ===== 2. Do port/IP =====
Write-Host '=== 2/3: Do port/IP ===' -ForegroundColor Cyan
$sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
$ports = @(22)
$ErrorActionPreference = 'Continue'
$eff = & $sshdExe -T 2>$null
if ($eff) {
  $p = @($eff | Where-Object { $_ -match '^port\s+\d+' } | ForEach-Object { [int]($_ -split '\s+')[1] })
  if ($p.Count -gt 0) { $ports = $p }
}
$ErrorActionPreference = 'Stop'
$sshPort = $ports[0]
Write-Host "  Port: $($ports -join ', ')" -ForegroundColor Green

# Mo firewall
foreach ($p in $ports) {
  $rn = if ($p -eq 22) { 'OpenSSH-Server-In-TCP' } else { "OpenSSH-Server-In-TCP-$p" }
  if (Get-NetFirewallRule -Name $rn -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -Name $rn | Out-Null }
  else { New-NetFirewallRule -Name $rn -DisplayName "OpenSSH Server $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Any | Out-Null }
}

# Lay IP
$validIPs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
$primaryIP = $null
$defRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
if ($defRoute) {
  $primaryIP = (Get-NetIPAddress -InterfaceIndex $defRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1).IPAddress
}
if (-not $primaryIP) { $primaryIP = ($validIPs | Select-Object -First 1).IPAddress }

# ===== 3. Doc public key (tu file .pub tren may, khong co thi de trong) =====
Write-Host '=== 3/3: Bao cao len server ===' -ForegroundColor Cyan
$pubKey = ''
$pubFiles = @(
  (Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'),
  (Join-Path $env:USERPROFILE '.ssh\id_rsa.pub'),
  (Join-Path $env:ProgramData 'ssh\ssh_host_ed25519_key.pub'),
  (Join-Path $env:ProgramData 'ssh\ssh_host_rsa_key.pub')
)
foreach ($f in $pubFiles) {
  if (Test-Path $f) {
    $line = (Get-Content $f -Raw).Trim()
    if ($line -match '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\s+[A-Za-z0-9+/=]+') {
      $pubKey = $line
      Write-Host "  Lay public key tu: $f" -ForegroundColor Gray
      break
    }
  }
}
if (-not $pubKey) { Write-Host '  Khong tim thay file .pub nao -> gui khong co public_key.' -ForegroundColor Yellow }

Write-Host "  IP chinh: $primaryIP | User: $env:USERNAME" -ForegroundColor Green
foreach ($ipObj in $validIPs) { Write-Host "  ssh -p $sshPort $env:USERNAME@$($ipObj.IPAddress)" -ForegroundColor Green }

# Gui len server
$payload = @{
  vm_name    = $env:COMPUTERNAME
  ip_address = "$primaryIP"
  port       = $sshPort
  username   = $env:USERNAME
  public_key = $pubKey
  all_ips    = @($validIPs | ForEach-Object { $_.IPAddress })
} | ConvertTo-Json -Compress

if (-not $primaryIP) { Write-Host '[WARN] Khong co IPv4 -> bo qua bao cao.' -ForegroundColor Yellow; exit 0 }

for ($i = 1; $i -le 3; $i++) {
  try {
    $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $resp = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -UseBasicParsing
    Write-Host "[SUCCESS] $($resp.message)" -ForegroundColor Green
    break
  } catch {
    Write-Host "  Bao cao lan $i/3 that bai: $($_.Exception.Message)" -ForegroundColor Yellow
    if ($i -lt 3) { Start-Sleep -Seconds 5 }
  }
}

if ($NeedRestart) { Write-Host 'Can REBOOT de hoan tat cai OpenSSH.' -ForegroundColor Yellow }
Write-Host 'HOAN TAT.' -ForegroundColor Green
