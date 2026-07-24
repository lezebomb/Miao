[CmdletBinding()]
param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,System.Windows.Forms

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$petRoot = Join-Path $projectRoot "pet\miaomiao"
$manifestPath = Join-Path $petRoot "behavior.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing $manifestPath. Run scripts/build_action_assets.py first."
}

$behavior = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json

foreach ($actionProperty in $behavior.actions.PSObject.Properties) {
    $action = $actionProperty.Value
    if ($action.frames.Count -lt 1) {
        throw "Action $($actionProperty.Name) has no frames."
    }
    if ($null -ne $action.PSObject.Properties["frameDurationsMs"] -and
        $action.frameDurationsMs.Count -ne $action.frames.Count) {
        throw "Action $($actionProperty.Name) has mismatched frameDurationsMs."
    }
    foreach ($relativePath in $action.frames) {
        $path = Join-Path $petRoot ([string]$relativePath -replace "/", "\")
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing frame for $($actionProperty.Name): $path"
        }
    }
}

if ($CheckOnly) {
    $hoverChoices = @($behavior.events.petOrHover.random) -join ", "
    $idleSpecials = @($behavior.events.idle.random | ForEach-Object { $_.action }) -join ", "
    Write-Host "Interactive Miaomiao validation passed."
    Write-Host "Hover/pet random choices: $hoverChoices"
    Write-Host "Idle special actions: $idleSpecials"
    exit 0
}

$window = New-Object System.Windows.Window
$window.Title = "妙妙"
$window.Width = [double]$behavior.cell.width
$window.Height = [double]$behavior.cell.height
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.Left = [System.Windows.SystemParameters]::WorkArea.Right - $window.Width - 24
$window.Top = [System.Windows.SystemParameters]::WorkArea.Bottom - $window.Height - 24

$image = New-Object System.Windows.Controls.Image
$image.Width = $window.Width
$image.Height = $window.Height
$image.Stretch = [System.Windows.Media.Stretch]::None
$window.Content = $image

$script:currentAction = "idle"
$script:frameIndex = 0
$script:completedCycles = 0
$script:nextFrameAt = [DateTime]::UtcNow
$script:hoverArmed = $true
$script:lastPetTriggerAt = [DateTime]::MinValue
$script:isDragging = $false
$script:dragMoved = $false
$script:lastCursor = $null
$script:nextIdleSpecialAt = [DateTime]::UtcNow.AddMilliseconds((Get-Random -Minimum 35000 -Maximum 65001))
$script:imageCache = @{}

function Resolve-Action([string]$name) {
    $action = $behavior.actions.PSObject.Properties[$name].Value
    if ($null -eq $action) {
        throw "Unknown action: $name"
    }
    return $action
}

function Resolve-Frame([string]$relativePath) {
    $path = Join-Path $petRoot ($relativePath -replace "/", "\")
    if (-not $script:imageCache.ContainsKey($path)) {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = [Uri]::new($path)
        $bitmap.EndInit()
        $bitmap.Freeze()
        $script:imageCache[$path] = $bitmap
    }
    return $script:imageCache[$path]
}

function Show-CurrentFrame {
    $action = Resolve-Action $script:currentAction
    $framePath = [string]$action.frames[$script:frameIndex]
    $image.Source = Resolve-Frame $framePath
}

function Get-FrameDurationMs($action, [int]$index) {
    if ($null -ne $action.PSObject.Properties["frameDurationsMs"]) {
        return [int]$action.frameDurationsMs[$index]
    }
    return [int]$action.frameDurationMs
}

function Start-Action([string]$name) {
    $script:currentAction = $name
    $script:frameIndex = 0
    $script:completedCycles = 0
    Show-CurrentFrame
    $action = Resolve-Action $name
    $script:nextFrameAt = [DateTime]::UtcNow.AddMilliseconds((Get-FrameDurationMs $action 0))
}

function Start-PetAction {
    $event = $behavior.events.petOrHover
    $now = [DateTime]::UtcNow
    if (($null -eq $event.PSObject.Properties["ignoreWhilePlaying"] -or [bool]$event.ignoreWhilePlaying) -and
        $script:currentAction -ne "idle") {
        return
    }
    $cooldown = if ($null -ne $event.PSObject.Properties["triggerCooldownMs"]) { [int]$event.triggerCooldownMs } else { 900 }
    if (($now - $script:lastPetTriggerAt).TotalMilliseconds -lt $cooldown) {
        return
    }
    $choices = @($event.random)
    $weights = @($event.weights)
    $roll = (Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0
    $cumulative = 0.0
    $choice = $choices[-1]
    for ($index = 0; $index -lt $choices.Count; $index++) {
        $weight = if ($weights.Count -eq $choices.Count) { [double]$weights[$index] } else { 1.0 / $choices.Count }
        $cumulative += $weight
        if ($roll -lt $cumulative) {
            $choice = $choices[$index]
            break
        }
    }
    $script:lastPetTriggerAt = $now
    Start-Action ([string]$choice)
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(16)
$timer.Add_Tick({
    $now = [DateTime]::UtcNow
    if ($script:currentAction -eq "idle" -and -not $script:isDragging -and $now -ge $script:nextIdleSpecialAt) {
        Start-Action "wash-face"
        $script:nextIdleSpecialAt = $now.AddMilliseconds((Get-Random -Minimum 35000 -Maximum 65001))
        return
    }
    if ($now -lt $script:nextFrameAt) {
        return
    }
    $action = Resolve-Action $script:currentAction
    $script:frameIndex++
    if ($script:frameIndex -ge $action.frames.Count) {
        if ([bool]$action.loop) {
            $script:frameIndex = 0
        }
        else {
            $script:completedCycles++
            $repeatCount = if ($null -ne $action.PSObject.Properties["repeatCount"]) { [int]$action.repeatCount } else { 1 }
            if ($script:completedCycles -lt $repeatCount) {
                $script:frameIndex = 0
            }
            else {
                Start-Action "idle"
                return
            }
        }
    }
    Show-CurrentFrame
    $script:nextFrameAt = $now.AddMilliseconds((Get-FrameDurationMs $action $script:frameIndex))
})

$hoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$hoverDwellMs = if ($null -ne $behavior.events.petOrHover.PSObject.Properties["hoverDwellMs"]) {
    [int]$behavior.events.petOrHover.hoverDwellMs
} else { 350 }
$hoverTimer.Interval = [TimeSpan]::FromMilliseconds($hoverDwellMs)
$hoverTimer.Add_Tick({
    $hoverTimer.Stop()
    if ($script:hoverArmed -and -not $script:isDragging -and $window.IsMouseOver) {
        $script:hoverArmed = $false
        Start-PetAction
    }
})

$window.Add_MouseEnter({
    if ($script:hoverArmed -and -not $script:isDragging) {
        $hoverTimer.Stop()
        $hoverTimer.Start()
    }
})

$window.Add_MouseLeave({
    $hoverTimer.Stop()
    if (-not $script:isDragging) {
        $script:hoverArmed = $true
    }
})

$window.Add_MouseLeftButtonDown({
    $hoverTimer.Stop()
    $script:isDragging = $true
    $script:dragMoved = $false
    $script:lastCursor = [System.Windows.Forms.Cursor]::Position
    $window.CaptureMouse() | Out-Null
})

$window.Add_MouseMove({
    if (-not $script:isDragging -or [System.Windows.Input.Mouse]::LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
        return
    }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:lastCursor.X
    $dy = $cursor.Y - $script:lastCursor.Y
    if ([Math]::Abs($dx) + [Math]::Abs($dy) -ge 2) {
        $script:dragMoved = $true
        $window.Left += $dx
        $window.Top += $dy
        $direction = if ($dx -lt 0) { "running-left" } else { "running-right" }
        if ($script:currentAction -ne $direction) {
            Start-Action $direction
        }
        $script:lastCursor = $cursor
    }
})

$window.Add_MouseLeftButtonUp({
    if ($script:isDragging) {
        $window.ReleaseMouseCapture()
        $script:isDragging = $false
        if ($script:dragMoved) {
            Start-Action "idle"
        }
        else {
            Start-Action "idle"
            Start-PetAction
        }
    }
})

$window.Add_MouseRightButtonUp({
    $window.Close()
})

$window.Add_Closed({
    $timer.Stop()
    $hoverTimer.Stop()
})

Start-Action "idle"
$timer.Start()
[void]$window.ShowDialog()
