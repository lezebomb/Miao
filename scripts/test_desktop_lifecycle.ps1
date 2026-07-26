[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
if (-not ("MiaomiaoLifecycleNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class MiaomiaoLifecycleNative {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);
}
"@
}

function Find-VisibleWindowForProcess([int]$processId) {
    $handles = New-Object System.Collections.Generic.List[long]
    [MiaomiaoLifecycleNative]::EnumWindows({
        param($windowHandle, $state)
        $ownerProcessId = 0
        [void][MiaomiaoLifecycleNative]::GetWindowThreadProcessId(
            $windowHandle,
            [ref]$ownerProcessId
        )
        if ($ownerProcessId -eq $processId -and
            [MiaomiaoLifecycleNative]::IsWindowVisible($windowHandle)) {
            $handles.Add($windowHandle.ToInt64())
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    if ($handles.Count -eq 0) {
        return [IntPtr]::Zero
    }
    return [IntPtr]::new($handles[0])
}

function Get-Rect([IntPtr]$windowHandle) {
    $rect = New-Object MiaomiaoLifecycleNative+RECT
    if (-not [MiaomiaoLifecycleNative]::GetWindowRect($windowHandle, [ref]$rect)) {
        throw "GetWindowRect failed for handle $windowHandle."
    }
    return $rect
}

function Wait-Until([scriptblock]$condition, [int]$timeoutMs, [string]$failure) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMs)
    do {
        [System.Windows.Forms.Application]::DoEvents()
        if (& $condition) {
            return
        }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    throw $failure
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$desktopLauncher = Join-Path $projectRoot "launch-miaomiao-desktop.ps1"
$hostWindow = New-Object System.Windows.Forms.Form
$hostWindow.Text = "Codex Lifecycle Test Host"
$hostWindow.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$hostWindow.SetBounds(100, 100, 700, 500)
$hostWindow.Show()
[System.Windows.Forms.Application]::DoEvents()

$hostHandle = $hostWindow.Handle
$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $desktopLauncher,
    "-FollowCodex",
    "-CodexWindowHandle", $hostHandle.ToInt64(),
    "-CodexProcessId", $PID
)
$petProcess = Start-Process -FilePath "powershell.exe" `
    -ArgumentList $arguments `
    -PassThru `
    -WindowStyle Hidden

try {
    $script:petHandle = [IntPtr]::Zero
    Wait-Until {
        $script:petHandle = Find-VisibleWindowForProcess $petProcess.Id
        $script:petHandle -ne [IntPtr]::Zero
    } 5000 "Miaomiao window did not appear."

    Start-Sleep -Milliseconds 400
    $before = Get-Rect $script:petHandle
    $hostBefore = Get-Rect $hostHandle
    $hostWindow.SetBounds(220, 180, 700, 500)
    [System.Windows.Forms.Application]::DoEvents()
    $hostAfter = Get-Rect $hostHandle
    $expectedDx = $hostAfter.Left - $hostBefore.Left
    $expectedDy = $hostAfter.Top - $hostBefore.Top
    Wait-Until {
        $after = Get-Rect $script:petHandle
        [Math]::Abs(($after.Left - $before.Left) - $expectedDx) -le 8 -and
        [Math]::Abs(($after.Top - $before.Top) - $expectedDy) -le 8
    } 3000 "Miaomiao did not follow the host move."

    $hostWindow.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    [System.Windows.Forms.Application]::DoEvents()
    Wait-Until {
        -not [MiaomiaoLifecycleNative]::IsWindowVisible($script:petHandle)
    } 3000 "Miaomiao did not hide when the host was minimized."

    $hostWindow.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $hostWindow.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Wait-Until {
        -not [MiaomiaoLifecycleNative]::IsIconic($hostHandle)
    } 3000 "The temporary host did not restore."
    Wait-Until {
        [MiaomiaoLifecycleNative]::IsWindowVisible($script:petHandle)
    } 3000 "Miaomiao did not show when the host was restored."

    $hostWindow.Close()
    [System.Windows.Forms.Application]::DoEvents()
    Wait-Until {
        $petProcess.Refresh()
        $petProcess.HasExited
    } 3000 "Miaomiao did not exit when the host window closed."

    Write-Host "Desktop lifecycle integration passed: follow, minimize, restore, close."
}
finally {
    if (-not $hostWindow.IsDisposed) {
        $hostWindow.Close()
    }
    $petProcess.Refresh()
    if (-not $petProcess.HasExited) {
        Stop-Process -Id $petProcess.Id -Force
        $petProcess.WaitForExit()
    }
}
