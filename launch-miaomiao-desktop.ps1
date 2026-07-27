[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$FollowCodex,
    [long]$CodexWindowHandle = 0,
    [int]$CodexProcessId = 0
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,System.Windows.Forms

if (-not ("MiaomiaoNativeWindow" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class MiaomiaoNativeWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
}
"@
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$petRoot = Join-Path $projectRoot "pet\miaomiao"
$manifestPath = Join-Path $petRoot "behavior.json"
$configPath = Join-Path $projectRoot "miaomiao.config.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing $manifestPath. Run scripts/build_action_assets.py first."
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Missing $configPath."
}

$behavior = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath | ConvertFrom-Json

function Get-NumberProperty($object, [string]$name, [double]$fallback) {
    $property = $object.PSObject.Properties[$name]
    if ($null -eq $property) {
        return $fallback
    }
    return [double]$property.Value
}

function Get-RandomRange([object[]]$range, [int]$fallbackMinimum, [int]$fallbackMaximum) {
    if ($range.Count -ne 2) {
        return Get-Random -Minimum $fallbackMinimum -Maximum ($fallbackMaximum + 1)
    }
    $minimum = [int]$range[0]
    $maximum = [int]$range[1]
    if ($minimum -gt $maximum) {
        throw "Invalid range: minimum $minimum is greater than maximum $maximum."
    }
    return Get-Random -Minimum $minimum -Maximum ($maximum + 1)
}

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

$durationScale = Get-NumberProperty $config "globalDurationScale" 1.0
$windowScale = Get-NumberProperty $config "windowScale" 1.0
if ($durationScale -le 0) {
    throw "globalDurationScale must be greater than zero."
}
if ($windowScale -le 0) {
    throw "windowScale must be greater than zero."
}

$idlePauseRange = @($config.idlePauseRangeMs)
$hoverDwellMs = [int](Get-NumberProperty $config "hoverDwellMs" 500)
$triggerCooldownMs = [int](Get-NumberProperty $config "triggerCooldownMs" 2000)
$dragThreshold = [int](Get-NumberProperty $config.drag "horizontalThresholdPx" 16)
$dragDominanceRatio = Get-NumberProperty $config.drag "horizontalDominanceRatio" 1.35
$followIntervalMs = [int](Get-NumberProperty $config.codexWindow "followIntervalMs" 100)

if ($CheckOnly) {
    $rollMs = (@($behavior.actions.roll.frameDurationsMs) | Measure-Object -Sum).Sum
    $kneadCycleMs = (@($behavior.actions.knead.frameDurationsMs) | Measure-Object -Sum).Sum
    $kneadOutroMs = (@($behavior.actions."knead-outro".frameDurationsMs) | Measure-Object -Sum).Sum
    $kneadTotalMs = $kneadCycleMs * [int]$behavior.actions.knead.repeatCount + $kneadOutroMs
    $washMs = (@($behavior.actions."wash-face".frameDurationsMs) | Measure-Object -Sum).Sum
    Write-Host "Miaomiao desktop validation passed."
    Write-Host "Config: $configPath"
    Write-Host "globalDurationScale=$durationScale; windowScale=$windowScale"
    Write-Host "roll=${rollMs}ms; knead=${kneadCycleMs}ms x $($behavior.actions.knead.repeatCount) + ${kneadOutroMs}ms return = ${kneadTotalMs}ms; wash-face=${washMs}ms"
    Write-Host "Lifecycle policy: move/resize=follow; minimized=hide; restored=show; closed=exit."
    if ($FollowCodex -and $CodexWindowHandle -ne 0) {
        $handle = [IntPtr]::new($CodexWindowHandle)
        if (-not [MiaomiaoNativeWindow]::IsWindow($handle)) {
            throw "The supplied Codex window handle is not valid."
        }
        Write-Host "Supplied Codex window handle is valid."
    }
    return
}

$createdNew = $false
$singleInstanceMutex = [System.Threading.Mutex]::new(
    $true,
    "Local\MiaomiaoDesktopPet",
    [ref]$createdNew
)
if (-not $createdNew) {
    Write-Host "Miaomiao is already running; a duplicate window was not started."
    $singleInstanceMutex.Dispose()
    return
}

$window = New-Object System.Windows.Window
$window.Title = ([string]([char]0x5999) + [char]0x5999)
$window.Width = [double]$behavior.cell.width * $windowScale
$window.Height = [double]$behavior.cell.height * $windowScale
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.Left = [System.Windows.SystemParameters]::WorkArea.Right - $window.Width - 24
$window.Top = [System.Windows.SystemParameters]::WorkArea.Bottom - $window.Height - 24

$image = New-Object System.Windows.Controls.Image
$image.Width = $window.Width
$image.Height = $window.Height
$image.Stretch = [System.Windows.Media.Stretch]::Uniform
$image.SnapsToDevicePixels = $true
$window.Content = $image

$script:currentAction = "idle"
$script:frameIndex = 0
$script:completedCycles = 0
$script:nextFrameAt = [DateTime]::MaxValue
$script:nextIdleMotionAt = [DateTime]::UtcNow
$script:nextIdleSpecialCheckAt = [DateTime]::UtcNow
$script:hoverArmed = $true
$script:lastPetTriggerAt = [DateTime]::MinValue
$script:isDragging = $false
$script:dragMoved = $false
$script:dragStartCursor = $null
$script:lastCursor = $null
$script:manualFollowDeltaX = 0.0
$script:manualFollowDeltaY = 0.0
$script:imageCache = @{}
$script:codexWasHidden = $false

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
    $duration = if ($null -ne $action.PSObject.Properties["frameDurationsMs"]) {
        [double]$action.frameDurationsMs[$index]
    }
    else {
        [double]$action.frameDurationMs
    }
    return [Math]::Max(16, [int][Math]::Round($duration * $durationScale))
}

function Select-WeightedAction([object[]]$entries, [switch]$AllowNoSelection) {
    if ($entries.Count -eq 0) {
        return $null
    }
    $total = 0.0
    foreach ($entry in $entries) {
        $total += [Math]::Max(0.0, [double]$entry.weight)
    }
    if ($total -le 0) {
        return $null
    }
    $roll = if ($AllowNoSelection) {
        (Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0
    }
    else {
        ((Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0) * $total
    }
    if ($AllowNoSelection -and $roll -ge $total) {
        return $null
    }
    $cumulative = 0.0
    foreach ($entry in $entries) {
        $cumulative += [Math]::Max(0.0, [double]$entry.weight)
        if ($roll -lt $cumulative) {
            return [string]$entry.action
        }
    }
    return [string]$entries[-1].action
}

function Start-IdlePause {
    $script:currentAction = "idle"
    $script:frameIndex = 0
    $script:completedCycles = 0
    $script:nextFrameAt = [DateTime]::MaxValue
    $pause = Get-RandomRange $idlePauseRange 3000 6000
    $script:nextIdleMotionAt = [DateTime]::UtcNow.AddMilliseconds($pause * $durationScale)
    Show-CurrentFrame
}

function Start-Action([string]$name) {
    if ($name -eq "idle") {
        Start-IdlePause
        return
    }
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
    if (($now - $script:lastPetTriggerAt).TotalMilliseconds -lt $triggerCooldownMs) {
        return
    }
    $choices = @($event.random)
    $weights = @($event.weights)
    $total = 0.0
    for ($index = 0; $index -lt $choices.Count; $index++) {
        $total += if ($weights.Count -eq $choices.Count) { [Math]::Max(0.0, [double]$weights[$index]) } else { 1.0 }
    }
    if ($total -le 0) {
        return
    }
    $roll = ((Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0) * $total
    $cumulative = 0.0
    $choice = [string]$choices[-1]
    for ($index = 0; $index -lt $choices.Count; $index++) {
        $cumulative += if ($weights.Count -eq $choices.Count) { [Math]::Max(0.0, [double]$weights[$index]) } else { 1.0 }
        if ($roll -lt $cumulative) {
            $choice = [string]$choices[$index]
            break
        }
    }
    $script:lastPetTriggerAt = $now
    Start-Action $choice
}

function Schedule-NextIdleSpecialCheck([DateTime]$from) {
    $range = @($behavior.events.idle.specialCheckIntervalMs)
    $delay = Get-RandomRange $range 30000 60000
    $script:nextIdleSpecialCheckAt = $from.AddMilliseconds($delay * $durationScale)
}

function Get-CodexTargetPosition([MiaomiaoNativeWindow+RECT]$rect) {
    $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($window)
    $left = $rect.Left / $dpi.DpiScaleX
    $top = $rect.Top / $dpi.DpiScaleY
    $right = $rect.Right / $dpi.DpiScaleX
    $bottom = $rect.Bottom / $dpi.DpiScaleY
    $offsetX = Get-NumberProperty $config.codexWindow "offsetX" 16
    $offsetY = Get-NumberProperty $config.codexWindow "offsetY" -16
    $edgePadding = Get-NumberProperty $config.codexWindow "edgePadding" 16
    $placement = [string]$config.codexWindow.placement
    $workArea = [System.Windows.SystemParameters]::WorkArea

    if ($placement -eq "inside-bottom-right") {
        $targetLeft = $right - $window.Width - $edgePadding + $offsetX
        $targetTop = $bottom - $window.Height - $edgePadding + $offsetY
    }
    else {
        $targetLeft = $right + $offsetX
        $targetTop = $bottom - $window.Height + $offsetY
        if (($targetLeft + $window.Width) -gt $workArea.Right) {
            $targetLeft = $right - $window.Width - $edgePadding + $offsetX
        }
    }

    $targetLeft = [Math]::Max($workArea.Left, [Math]::Min($targetLeft, $workArea.Right - $window.Width))
    $targetTop = [Math]::Max($workArea.Top, [Math]::Min($targetTop, $workArea.Bottom - $window.Height))
    return [System.Windows.Point]::new(
        $targetLeft + $script:manualFollowDeltaX,
        $targetTop + $script:manualFollowDeltaY
    )
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(16)
$timer.Add_Tick({
    $now = [DateTime]::UtcNow

    if ($script:currentAction -eq "idle") {
        if (-not $script:isDragging -and $now -ge $script:nextIdleSpecialCheckAt) {
            Schedule-NextIdleSpecialCheck $now
            $special = Select-WeightedAction @($behavior.events.idle.random) -AllowNoSelection
            if ($null -ne $special) {
                Start-Action $special
                return
            }
        }
        if (-not $script:isDragging -and $now -ge $script:nextIdleMotionAt) {
            $micro = Select-WeightedAction @($behavior.events.idle.microActions)
            if ($null -ne $micro) {
                Start-Action $micro
            }
        }
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
                $outro = $action.PSObject.Properties["outroAction"]
                if ($null -ne $outro) {
                    Start-Action ([string]$outro.Value)
                }
                else {
                    Start-IdlePause
                }
                return
            }
        }
    }
    Show-CurrentFrame
    $script:nextFrameAt = $now.AddMilliseconds((Get-FrameDurationMs $action $script:frameIndex))
})

$hoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$hoverTimer.Interval = [TimeSpan]::FromMilliseconds($hoverDwellMs)
$hoverTimer.Add_Tick({
    $hoverTimer.Stop()
    if ($script:hoverArmed -and -not $script:isDragging -and $window.IsMouseOver) {
        $script:hoverArmed = $false
        Start-PetAction
    }
})

$followTimer = New-Object System.Windows.Threading.DispatcherTimer
$followTimer.Interval = [TimeSpan]::FromMilliseconds($followIntervalMs)
$followTimer.Add_Tick({
    if (-not $FollowCodex -or $script:isDragging) {
        return
    }
    $handle = [IntPtr]::new($CodexWindowHandle)
    if (-not [MiaomiaoNativeWindow]::IsWindow($handle)) {
        $window.Close()
        return
    }
    if ($CodexProcessId -gt 0 -and $null -eq (Get-Process -Id $CodexProcessId -ErrorAction SilentlyContinue)) {
        $window.Close()
        return
    }
    if ([MiaomiaoNativeWindow]::IsIconic($handle)) {
        if ($window.IsVisible) {
            $window.Hide()
        }
        $script:codexWasHidden = $true
        return
    }
    if (-not $window.IsVisible) {
        $window.Show()
    }
    $script:codexWasHidden = $false
    $rect = New-Object MiaomiaoNativeWindow+RECT
    if ([MiaomiaoNativeWindow]::GetWindowRect($handle, [ref]$rect)) {
        $target = Get-CodexTargetPosition $rect
        $window.Left = $target.X
        $window.Top = $target.Y
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
    $script:dragStartCursor = [System.Windows.Forms.Cursor]::Position
    $script:lastCursor = $script:dragStartCursor
    $window.CaptureMouse() | Out-Null
})

$window.Add_MouseMove({
    if (-not $script:isDragging -or [System.Windows.Input.Mouse]::LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
        return
    }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:lastCursor.X
    $dy = $cursor.Y - $script:lastCursor.Y
    $totalDx = $cursor.X - $script:dragStartCursor.X
    $totalDy = $cursor.Y - $script:dragStartCursor.Y
    if ([Math]::Abs($totalDx) + [Math]::Abs($totalDy) -ge 2) {
        $script:dragMoved = $true
        $window.Left += $dx
        $window.Top += $dy
        if ($FollowCodex) {
            $script:manualFollowDeltaX += $dx
            $script:manualFollowDeltaY += $dy
        }
        if ([Math]::Abs($totalDx) -ge $dragThreshold -and
            [Math]::Abs($totalDx) -ge ([Math]::Abs($totalDy) * $dragDominanceRatio)) {
            $direction = if ($totalDx -lt 0) { "running-left" } else { "running-right" }
            if ($script:currentAction -ne $direction) {
                Start-Action $direction
            }
        }
        $script:lastCursor = $cursor
    }
})

$window.Add_MouseLeftButtonUp({
    if ($script:isDragging) {
        $window.ReleaseMouseCapture()
        $script:isDragging = $false
        if ($script:dragMoved) {
            Start-IdlePause
        }
        else {
            Start-IdlePause
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
    $followTimer.Stop()
    [System.Windows.Threading.Dispatcher]::ExitAllFrames()
})

try {
    Start-IdlePause
    Schedule-NextIdleSpecialCheck ([DateTime]::UtcNow)
    $timer.Start()
    if ($FollowCodex) {
        if ($CodexWindowHandle -eq 0) {
            throw "FollowCodex requires CodexWindowHandle."
        }
        $followTimer.Start()
    }
    $window.Show()
    [System.Windows.Threading.Dispatcher]::Run()
}
finally {
    if ($createdNew) {
        $singleInstanceMutex.ReleaseMutex()
    }
    $singleInstanceMutex.Dispose()
}
