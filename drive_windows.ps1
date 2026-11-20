<#
  install_openssh.ps1 — cai OpenSSH + gui IP/port/public_key len server
#>
$ApiBase = 'https://vm-ssh-manager.onrender.com'

$ErrorActionPreference = 'Stop'
$ApiBase   = $ApiBase.TrimEnd('/')
$ReportUrl = "$ApiBase/api/vms"

# ===== Quyen admin =====
$__id    = [Security.Principal.WindowsIdentity]::GetCurrent()
$__admin = (New-Object Security.Principal.WindowsPrincipal($__id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $__admin) {
  $__src = $PSCommandPath
  if (-not $__src) { $__src = $MyInvocation.MyCommand.Path }
  if (-not $__src) { Write-Host 'Luu file .ps1 roi chay lai.' -ForegroundColor Yellow; exit 1 }
  try { Unblock-File -Path $__src -ErrorAction SilentlyContinue } catch {}
  $__arg = '-NoExit -NoProfile -Command "iex ([System.IO.File]::ReadAllText(''' + $__src + '''))"'
  try { Start-Process powershell.exe -Verb RunAs -ArgumentList $__arg -ErrorAction Stop }
  catch { Write-Host 'Khong nang quyen.' -ForegroundColor Red; throw }
  return
}

# ===== 1. Cai OpenSSH =====
Write-Host '=== 1/3: Cai OpenSSH ===' -ForegroundColor Cyan
$capName = 'OpenSSH.Server~~~~0.0.1.0'
$cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
if (-not $cap -or $cap.State -ne 'Installed') {
  Write-Host 'Dang cai (co the mat 1-2 phut)...'
  try {
    $r = Add-WindowsCapability -Online -Name $capName
    if ($r.RestartNeeded) { Write-Host '[INFO] Can reboot.' -ForegroundColor Yellow }
  } catch {
    & dism.exe /Online /Add-Capability /CapabilityName:$capName /NoRestart | Out-Null
  }
}
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  Write-Host 'Khong cai duoc OpenSSH.' -ForegroundColor Red; exit 1
}
Set-Service sshd -StartupType Automatic
# start khong chan
& sc.exe start sshd | Out-Null
for ($w = 0; $w -lt 30; $w++) {
  if ((Get-Service sshd).Status -eq 'Running') { break }
  Write-Host '.' -NoNewline; Start-Sleep -Seconds 2
}
Write-Host ''; Write-Host 'sshd da cai.' -ForegroundColor Green

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

foreach ($p in $ports) {
  $rn = if ($p -eq 22) { 'OpenSSH-Server-In-TCP' } else { "OpenSSH-Server-In-TCP-$p" }
  if (Get-NetFirewallRule -Name $rn -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -Name $rn | Out-Null }
  else { New-NetFirewallRule -Name $rn -DisplayName "OpenSSH Server $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Any | Out-Null }
}

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

# ===== 3. Doc public_key tu file .pub tren may =====
Write-Host '=== 3/3: Bao cao ===' -ForegroundColor Cyan
$pubKey = $null
foreach ($f in @(
  (Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'),
  (Join-Path $env:USERPROFILE '.ssh\id_rsa.pub'),
  (Join-Path $env:ProgramData 'ssh\ssh_host_ed25519_key.pub'),
  (Join-Path $env:ProgramData 'ssh\ssh_host_rsa_key.pub')
)) {
  if (Test-Path $f) {
    $line = ((Get-Content $f -Raw).Trim() -split "`n")[0]
    if ($line -match '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\s+[A-Za-z0-9+/=]+') {
      $pubKey = $line
      Write-Host "  Public key tu: $f" -ForegroundColor Gray
      break
    }
  }
}
if (-not $pubKey) { Write-Host '  Khong co file .pub -> gui khong co public_key.' -ForegroundColor Yellow }

Write-Host "  IP: $primaryIP | User: $env:USERNAME | Name: $env:COMPUTERNAME" -ForegroundColor Green

# ===== Gui len server (chi khi co IP + sshd LISTEN) =====
$listen = @(Get-NetTCPConnection -LocalPort $sshPort -State Listen -ErrorAction SilentlyContinue).Count -gt 0
if (-not $listen) {
  Write-Host "  Cong $sshPort chua LISTEN -> ssh_probe se fail -> bo qua bao cao." -ForegroundColor Red
  exit 1
}

$payload = @{
  vm_name    = $env:COMPUTERNAME
  ip_address = "$primaryIP"
  port       = $sshPort
  username   = $env:USERNAME
}
if ($pubKey) { $payload.public_key = $pubKey }
$payload = $payload | ConvertTo-Json -Compress

for ($i = 1; $i -le 3; $i++) {
  try {
    $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $resp = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -UseBasicParsing
    Write-Host "[SUCCESS] $($resp.status) banner=$($resp.ssh_banner)" -ForegroundColor Green
    break
  } catch {
    $detail = ''
    if ($_.Exception.Response) {
      $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $detail = $sr.ReadToEnd(); $sr.Close()
    }
    Write-Host "  Lan $i/3 fail: $($_.Exception.Message)" -ForegroundColor Yellow
    if ($detail) { Write-Host "  Server: $detail" -ForegroundColor DarkYellow }
    if ($i -lt 3) { Start-Sleep -Seconds 5 }
  }
}

Write-Host 'HOAN TAT.' -ForegroundColor Green
