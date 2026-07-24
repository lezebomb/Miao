[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$SkipSync,
    [string]$WslDistro = "Ubuntu"
)

$ErrorActionPreference = "Stop"

$petDirectory = Join-Path $env:USERPROFILE ".codex\pets\miaomiao"
$manifestPath = Join-Path $petDirectory "pet.json"
$spritesheetPath = Join-Path $petDirectory "spritesheet.webp"
$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePetDirectory = Join-Path $projectDirectory "pet\miaomiao"
$sourceManifestPath = Join-Path $sourcePetDirectory "pet.json"
$sourceSpritesheetPath = Join-Path $sourcePetDirectory "spritesheet.webp"

if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) {
    throw "Project pet manifest is missing: $sourceManifestPath"
}
if (-not (Test-Path -LiteralPath $sourceSpritesheetPath -PathType Leaf)) {
    throw "Project spritesheet is missing: $sourceSpritesheetPath"
}

$package = Get-AppxPackage -Name "OpenAI.Codex" | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $package) {
    throw "The OpenAI Codex Windows app is not installed."
}

$codexExecutable = Join-Path $package.InstallLocation "app\ChatGPT.exe"
if (-not (Test-Path -LiteralPath $codexExecutable -PathType Leaf)) {
    throw "Codex executable not found: $codexExecutable"
}

if (-not (Test-Path -LiteralPath "$env:SystemRoot\System32\wsl.exe" -PathType Leaf)) {
    throw "WSL is not installed. Start Codex normally and refresh the Pets page."
}
$distro = $WslDistro

if (-not $SkipSync) {
    New-Item -ItemType Directory -Path $petDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceManifestPath -Destination $manifestPath -Force
    Copy-Item -LiteralPath $sourceSpritesheetPath -Destination $spritesheetPath -Force

    $sourceManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceManifestPath).Hash
    $installedManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    $sourceSpriteHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceSpritesheetPath).Hash
    $installedSpriteHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $spritesheetPath).Hash
    if (
        $sourceManifestHash -ne $installedManifestHash -or
        $sourceSpriteHash -ne $installedSpriteHash
    ) {
        throw "Miaomiao sync verification failed."
    }
    Write-Host "Synced current project pet into $petDirectory"
    Write-Host "Spritesheet SHA256: $sourceSpriteHash"
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing installed manifest: $manifestPath"
}
if (-not (Test-Path -LiteralPath $spritesheetPath -PathType Leaf)) {
    throw "Missing installed spritesheet: $spritesheetPath"
}

Write-Host "Miaomiao directory: $petDirectory"
Write-Host "Codex version: $($package.Version)"
Write-Host "WSL distribution: $distro"

if ($CheckOnly) {
    Write-Host "Compatibility launch check passed."
    exit 0
}

$runningCodex = Get-Process -Name "ChatGPT" -ErrorAction SilentlyContinue |
    Where-Object {
        try {
            $_.Path.StartsWith($package.InstallLocation, [System.StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $false
        }
    }

if ($runningCodex) {
    throw "Codex is still running. Quit it from the system tray, then run launch-codex-miaomiao.cmd again."
}

# Codex 26.715 may pass a C:\ path to a POSIX file API when the Windows UI
# uses a WSL execution host. This emulates the environment of launching the
# Windows app from WSL, allowing CODEX_HOME to be normalized before pet scan.
$env:WSL_DISTRO_NAME = $distro
$env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex"

$wslEnvEntries = @($env:WSLENV -split ":" | Where-Object { $_ })
if ($wslEnvEntries -notcontains "CODEX_HOME/w") {
    $env:WSLENV = (@($wslEnvEntries) + "CODEX_HOME/w") -join ":"
}

Start-Process -FilePath $codexExecutable -WorkingDirectory (Split-Path -Parent $codexExecutable)
Write-Host "Codex started in Miaomiao compatibility mode. Open Settings > Pets, select Refresh, then choose Miaomiao."
