[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [long]$WindowHandle,
    [int]$ProcessId = 0,
    [int]$IntervalMs = 100
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class MiaomiaoCanvasHost {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
}
"@

$handle = [IntPtr]::new($WindowHandle)
$delay = [Math]::Max(50, $IntervalMs)
while ($true) {
    if (-not [MiaomiaoCanvasHost]::IsWindow($handle) -or
        ($ProcessId -gt 0 -and $null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))) {
        Write-Output '{"state":"closed"}'
        break
    }
    if ([MiaomiaoCanvasHost]::IsIconic($handle)) {
        Write-Output '{"state":"hidden"}'
    }
    else {
        $rect = New-Object MiaomiaoCanvasHost+RECT
        if ([MiaomiaoCanvasHost]::GetWindowRect($handle, [ref]$rect)) {
            [ordered]@{
                state = "visible"
                left = $rect.Left
                top = $rect.Top
                right = $rect.Right
                bottom = $rect.Bottom
            } | ConvertTo-Json -Compress | Write-Output
        }
    }
    Start-Sleep -Milliseconds $delay
}
