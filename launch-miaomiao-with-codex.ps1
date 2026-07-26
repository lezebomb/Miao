[CmdletBinding()]
param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktopLauncher = Join-Path $projectRoot "launch-miaomiao-desktop.ps1"
$configPath = Join-Path $projectRoot "miaomiao.config.json"

if (-not (Test-Path -LiteralPath $desktopLauncher -PathType Leaf)) {
    throw "Missing desktop runtime: $desktopLauncher"
}

$package = Get-AppxPackage -Name "OpenAI.Codex" |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $package) {
    throw "The native OpenAI Codex Windows app is not installed."
}

$codexExecutable = Join-Path $package.InstallLocation "app\ChatGPT.exe"
if (-not (Test-Path -LiteralPath $codexExecutable -PathType Leaf)) {
    throw "Codex executable not found: $codexExecutable"
}

function Find-CodexMainProcess {
    $candidates = @(
        Get-Process -Name "ChatGPT", "Codex" -ErrorAction SilentlyContinue
    )
    foreach ($candidate in $candidates) {
        try {
            $candidate.Refresh()
            $insidePackage = $candidate.Path.StartsWith(
                $package.InstallLocation,
                [System.StringComparison]::OrdinalIgnoreCase
            )
            if ($insidePackage -and $candidate.MainWindowHandle -ne 0) {
                return $candidate
            }
        }
        catch {
            continue
        }
    }
    return $null
}

if ($CheckOnly) {
    & $desktopLauncher -CheckOnly
    $running = Find-CodexMainProcess
    Write-Host "Codex package version: $($package.Version)"
    Write-Host "Codex executable: $codexExecutable"
    Write-Host "Codex main window: $(if ($null -eq $running) { 'not currently open' } else { 'ready' })"
    Write-Host "Unified native Windows launch validation passed; no WSL variables are used."
    return
}

$codexProcess = Find-CodexMainProcess
if ($null -eq $codexProcess) {
    Write-Host "Starting native Codex for Windows..."
    Start-Process -FilePath $codexExecutable -WorkingDirectory (Split-Path -Parent $codexExecutable) | Out-Null
}
else {
    Write-Host "Codex is already running."
}

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath | ConvertFrom-Json
$timeoutMs = if ($null -ne $config.codexWindow.PSObject.Properties["waitTimeoutMs"]) {
    [int]$config.codexWindow.waitTimeoutMs
}
else {
    60000
}
$deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMs)
while ($null -eq $codexProcess -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 200
    $codexProcess = Find-CodexMainProcess
}
if ($null -eq $codexProcess) {
    throw "Codex started, but its main window did not appear within ${timeoutMs}ms."
}

Write-Host "Starting Miaomiao beside the Codex window..."
& $desktopLauncher `
    -FollowCodex `
    -CodexWindowHandle ([long]$codexProcess.MainWindowHandle) `
    -CodexProcessId ([int]$codexProcess.Id)
