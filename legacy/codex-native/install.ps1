$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $projectRoot "pet\miaomiao"
$destination = Join-Path $env:USERPROFILE ".codex\pets\miaomiao"

if (-not (Test-Path -LiteralPath (Join-Path $source "pet.json"))) {
    throw "Missing pet.json under $source"
}
if (-not (Test-Path -LiteralPath (Join-Path $source "spritesheet.webp"))) {
    throw "Missing spritesheet.webp under $source"
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source "pet.json") -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $source "spritesheet.webp") -Destination $destination -Force

Write-Host "Miaomiao installed at $destination"
Write-Host "Open Codex Settings > Pets, select Refresh, then choose Miaomiao."
Write-Host "If it is still missing with a WSL backend, quit Codex completely and run launch-codex-miaomiao.cmd."
