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
#   pwsh tool/build-msix.ps1 -Store -Rebuild
#                                     the Store package again at the version
#                                     already recorded (not yet uploaded)
#
# Versions: the package version is pubspec's x.y.z with a 4th part 0 (the
# Store requires 0 there); the build number (+10) is dropped, so a Windows
# release must raise at least the patch number. -Store stops with an error
# unless the version is higher than the last Store build, recorded in
# windows/msix-store-version.txt (commit it with the release).
#
# The test certificate is created on first use in windows\packaging\
# (gitignored): test-cert.pfx (private key), test-cert.cer (public part, to
# trust), test-cert.password. Never commit them. Its subject must equal
# msix_config.publisher in pubspec.yaml. How to trust it and install the
# package: docs/windows-build.md.
param([switch]$Store, [switch]$Rebuild)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

$out = Join-Path $root 'debug\msix'
New-Item -ItemType Directory -Force $out | Out-Null

# The package version comes from pubspec's "version" (1.1.1+10 -> 1.1.1.0),
# never from a second, hand-kept number.
$m = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+)\.(\d+)\.(\d+)'
if (-not $m) { throw 'no "version: x.y.z" in pubspec.yaml' }
$g = $m.Matches[0].Groups
$version = "$($g[1].Value).$($g[2].Value).$($g[3].Value).0"
Write-Host "== package version $version (from pubspec)"
if (-not $Store) {
    $installed = Get-AppxPackage PureShell.Test -ErrorAction SilentlyContinue
    if ($installed -and [version]$installed.Version -ge [version]$version) {
        Write-Host ("   note: $($installed.Version) is installed here; install.ps1 " +
            'replaces it (a plain update needs a higher x.y.z)')
    }
}

if ($Store) {
    # Windows and the Store reject a package that is not newer than the one
    # before it, and only x.y.z can carry that (the 4th part must be 0).
    $record = Join-Path $root 'windows\msix-store-version.txt'
    $last = if (Test-Path $record) { (Get-Content $record -Raw).Trim() } else { $null }
    if ($last) {
        $cmp = ([version]$version).CompareTo([version]$last)
        if ($cmp -lt 0 -or ($cmp -eq 0 -and -not $Rebuild)) {
            throw ("package version $version is not higher than the last Store " +
                "build $last ($record). Raise at least the patch number in " +
                "pubspec.yaml (a higher +build alone is not enough), or use " +
                "-Rebuild to build $last again before it is uploaded.")
        }
    }
    Write-Host '== Store variant (not signed locally)'
    dart run msix:create --store --version $version --output-path $out --output-name Pure-Shell-store
    if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }
    Set-Content -Path $record -Value $version -NoNewline
    Write-Host "   recorded $version in windows\msix-store-version.txt (commit it)"
    Write-Host ''
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
dart run msix:create --version $version --certificate-path $pfx --certificate-password $pw `
    --output-path $out --output-name Pure-Shell
if ($LASTEXITCODE -ne 0) { throw 'msix:create failed' }

$msix = Get-Item (Join-Path $out 'Pure-Shell.msix')

# A folder to copy to another PC: package, public certificate, installer.
$bundle = Join-Path $out 'install'
if (Test-Path $bundle) { Remove-Item -LiteralPath $bundle -Recurse -Force }
New-Item -ItemType Directory $bundle | Out-Null
Copy-Item $msix.FullName, $cer $bundle
Copy-Item (Join-Path $PSScriptRoot 'msix-install.ps1') (Join-Path $bundle 'install.ps1')

Write-Host ''
Write-Host ('== {0} ({1:N1} MB)' -f $msix.FullName, ($msix.Length / 1MB))
Write-Host "   to install on any PC: copy $bundle, then run"
Write-Host '   powershell -ExecutionPolicy Bypass -File install.ps1'
