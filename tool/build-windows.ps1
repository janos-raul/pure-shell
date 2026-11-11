# Pure-Shell - an open-source SSH client
# Copyright (C) 2026 Janos-Raul
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Windows release and copies it to debug\win_build (gitignored),
# replacing what was there. Run from anywhere:
#
#   pwsh tool/build-windows.ps1            release build, then copy
#   pwsh tool/build-windows.ps1 -Clean     flutter clean first
#   pwsh tool/build-windows.ps1 -DebugBuild  debug build instead of release
#
# The whole folder is the app: pureshell.exe needs the DLLs and data\ next
# to it. The exe is not code-signed.
[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$DebugBuild
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

$mode = if ($DebugBuild) { 'debug' } else { 'release' }
$source = Join-Path $root "build\windows\x64\runner\$((Get-Culture).TextInfo.ToTitleCase($mode))"
$target = Join-Path $root 'debug\win_build'

if ($Clean) {
    Write-Host '== flutter clean'
    flutter clean
    if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }
}

Write-Host "== flutter build windows --$mode"
flutter build windows "--$mode"
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
if (-not (Test-Path (Join-Path $source 'pureshell.exe'))) {
    throw "no pureshell.exe in $source"
}

# Replace the old copy. Never touch anything outside debug\win_build.
if (Test-Path $target) {
    if ((Get-Process pureshell -ErrorAction SilentlyContinue |
         Where-Object { $_.Path -like "$target*" })) {
        throw 'Pure-Shell is running from debug\win_build: close it first'
    }
    Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse

$exe = Get-Item (Join-Path $target 'pureshell.exe')
$size = (Get-ChildItem $target -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ''
Write-Host ("== {0} {1} ({2}) -> {3}" -f $exe.VersionInfo.ProductName,
    $exe.VersionInfo.FileVersion, $mode, $target)
Write-Host ("   {0:N1} MB, {1} files" -f $size,
    (Get-ChildItem $target -Recurse -File).Count)
