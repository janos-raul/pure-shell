# Pure-Shell - an open-source SSH client
# Copyright (C) 2026 Janos-Raul
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs the TEST build of Pure-Shell on this PC. Copied by
# tool/build-msix.ps1 into debug\msix\install\ together with Pure-Shell.msix
# and test-cert.cer. Run it from that folder (Windows PowerShell 5 or 7):
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#
# 1. Trusts the test certificate (public part only) in
#    Local Machine > Trusted People. Needs admin: asks once (UAC).
# 2. Installs the package for the current user; the same version already
#    installed is removed first (Windows refuses to reinstall it).
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$msix = Join-Path $here 'Pure-Shell.msix'
$cer = Join-Path $here 'test-cert.cer'
$name = 'PureShell.Test'

if ($Uninstall) {
    $p = Get-AppxPackage $name
    if ($p) { Remove-AppxPackage $p.PackageFullName; Write-Host 'Pure-Shell removed.' }
    else { Write-Host 'Pure-Shell is not installed.' }
    Write-Host 'The test certificate stays trusted; to remove it (as admin):'
    Write-Host "  Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Subject -eq 'CN=Pure-Shell Test' | Remove-Item"
    return
}

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cer
$trusted = Get-ChildItem Cert:\LocalMachine\TrustedPeople |
    Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
if (-not $trusted) {
    Write-Host "Trusting the test certificate ($($cert.Subject)): Windows asks for admin rights."
    $cmd = "Import-Certificate -FilePath '$cer' -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
    Start-Process powershell.exe -Verb RunAs -Wait `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
    $trusted = Get-ChildItem Cert:\LocalMachine\TrustedPeople |
        Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
    if (-not $trusted) { throw 'The certificate was not trusted; nothing installed.' }
}

$old = Get-AppxPackage $name
if ($old) {
    Write-Host "Removing the installed $($old.Version) first."
    Remove-AppxPackage $old.PackageFullName
}
Add-AppxPackage $msix
$p = Get-AppxPackage $name
Write-Host "Installed Pure-Shell $($p.Version). Start it from the Start menu."
