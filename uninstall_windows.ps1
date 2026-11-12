$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$SelfUrl = 'https://raw.githubusercontent.com/khoahocdrive/dowbload_40GB_course_drive/main/uninstall_windows.ps1'
$Dir = Join-Path $env:ProgramData 'tm'

$IsAdmin = $false
try {
  $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
  $IsAdmin = ($env:USER -eq 'root')
}
if (-not $IsAdmin) {
  if ($PSCommandPath) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" skip"
  } else {
    $f = Join-Path $env:TEMP 'uninstall_tm.ps1'
    try { Invoke-WebRequest -Uri $SelfUrl -OutFile $f -UseBasicParsing } catch {}
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$f`" skip"
  }
  exit
}

try { Stop-ScheduledTask -TaskName 'TraffmonetizerResume' } catch {}
try { Unregister-ScheduledTask -TaskName 'TraffmonetizerResume' -Confirm:$false } catch {}
& wsl.exe --terminate tm-linux *> $null
& wsl.exe -d tm-linux -u root -- sh -c 'pkill -f /opt/tm/cli; pkill -f dockerd; true' *> $null
& wsl.exe --unregister tm-linux *> $null
Remove-Item $Dir -Recurse -Force
Remove-Item (Join-Path $env:UserProfile '.wslconfig') -Force
Write-Host 'HOAN TAT xoa sach. WSL van con giu lai (de cai lai nhanh).'
Write-Host 'Neu muon xoa luon WSL: chay lenh  wsl --uninstall'
if ($args -notcontains 'skip') { Start-Sleep -Seconds 15 }
