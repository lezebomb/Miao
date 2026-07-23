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

Write-Host "妙妙已安装到 $destination"
Write-Host "请完全退出并重新打开 Codex，然后在宠物选择器中选择“妙妙”。"
