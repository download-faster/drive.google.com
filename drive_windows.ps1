foreach ($f in @(
  (Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'),
  (Join-Path $env:USERPROFILE '.ssh\id_rsa.pub'),
  (Join-Path $env:ProgramData 'ssh\ssh_host_ed25519_key.pub'),
  (Join-Path $env:ProgramData 'ssh\ssh_host_rsa_key.pub')
)) {
  if (Test-Path $f) {
    $parts = ((Get-Content $f -Raw).Trim() -split '\s+')
    if ($parts.Count -ge 2 -and $parts[0] -match '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))$') {
      $pubKey = $parts[0] + ' ' + $parts[1]     # CHI type + blob, BO comment
      Write-Host "  Public key tu: $f" -ForegroundColor Gray
      break
    }
  }
}
