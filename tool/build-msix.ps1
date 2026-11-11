# Pure-Shell - an open-source SSH client
# Copyright (C) 2026 Janos-Raul
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Windows MSIX package into debug\msix (gitignored).
#
#   pwsh tool/build-msix.ps1          signed with the local TEST certificate,
#                                     for installing on this machine
#   pwsh tool/build-msix.ps1 -Store   unsigned Store variant (Partner Center
#                                     signs it); needs the real identity_name
#                                     and publisher in pubspec.yaml first
#
# The test certificate is created on first use in windows\packaging\
# (gitignored): test-cert.pfx (private key), test-cert.cer (public part, to
# trust), test-cert.password. Never commit them. Its subject must equal
# msix_config.publisher in pubspec.yaml. How to trust it and install the
# package: docs/windows-build.md.
param([switch]$Store)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

$out = Join-Path $root 'debug\msix'
New-Item -ItemType Directory -Force $out | Out-Null

if ($Store) {
    Write-Host '== Store variant (not signed locally)'
    dart run msix:create --store --output-path $out --output-name Pure-Shell-store
    if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }
    Get-Item (Join-Path $out 'Pure-Shell-store.msix') |
        ForEach-Object { '{0} ({1:N1} MB)' -f $_.FullName, ($_.Length / 1MB) }
    return
}

$publisher = (Select-String -Path pubspec.yaml -Pattern '^\s+publisher:\s*(.+)$').
    Matches[0].Groups[1].Value.Trim()
$certDir = Join-Path $root 'windows\packaging'
$pfx = Join-Path $certDir 'test-cert.pfx'
$cer = Join-Path $certDir 'test-cert.cer'
$pwFile = Join-Path $certDir 'test-cert.password'

if (-not (Test-Path $pfx)) {
    Write-Host "== creating the local test certificate ($publisher)"
    New-Item -ItemType Directory -Force $certDir | Out-Null
    $cert = New-SelfSignedCertificate -Type Custom -Subject $publisher `
        -KeyUsage DigitalSignature -FriendlyName 'Pure-Shell TEST (local MSIX only)' `
        -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(2) `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $pw = -join (1..32 | ForEach-Object { $chars[[Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] })
    Set-Content -Path $pwFile -Value $pw -NoNewline
    $secure = ConvertTo-SecureString $pw -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null
    Export-Certificate -Cert $cert -FilePath $cer | Out-Null
    # The .pfx is the only copy of the private key from now on.
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($cert.Thumbprint)"
    Write-Host "   $pfx (+ .cer, .password)"
}
$pw = Get-Content -Path $pwFile -Raw

Write-Host '== building and signing the MSIX (test certificate)'
dart run msix:create --certificate-path $pfx --certificate-password $pw `
    --output-path $out --output-name Pure-Shell
if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }

$msix = Get-Item (Join-Path $out 'Pure-Shell.msix')
Write-Host ''
Write-Host ('== {0} ({1:N1} MB)' -f $msix.FullName, ($msix.Length / 1MB))
Write-Host "   trust once: $cer -> Local Machine > Trusted People (see docs)"
