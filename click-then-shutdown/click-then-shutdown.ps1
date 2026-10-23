<#
.SYNOPSIS
    Waits 2 hours 30 minutes, left-clicks once, waits 1 more hour, then shuts down the PC.

.DESCRIPTION
    At the start you point the mouse at the spot to click and press Enter. The script
    then keeps the PC awake (no sleep, screen stays on) until it shuts it down.

    Leave the PC unlocked: a click on the lock screen does not reach your app.
    Press Ctrl+C to cancel while it waits. Once the shutdown warning appears you have
    60 seconds to cancel it with:  shutdown /a

.EXAMPLE
    .\click-then-shutdown.ps1

.EXAMPLE
    # Quick test: click after 10 seconds, shutdown warning 10 seconds later.
    .\click-then-shutdown.ps1 -ClickAfter 0:00:10 -ShutdownAfter 0:00:10
#>
param(
    [timespan]$ClickAfter = '02:30:00',
    [timespan]$ShutdownAfter = '01:00:00'
)

if (-not ('ClickShutdownNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class ClickShutdownNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);

    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint ES_CONTINUOUS = 0x80000000;
    const uint ES_SYSTEM_REQUIRED = 0x00000001;
    const uint ES_DISPLAY_REQUIRED = 0x00000002;

    public static POINT CursorPosition()
    {
        POINT p;
        GetCursorPos(out p);
        return p;
    }

    public static void LeftClick(int x, int y)
    {
        SetCursorPos(x, y);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }

    // Stops Windows from sleeping or turning the screen off while this process runs.
    public static void KeepAwake(bool on)
    {
        SetThreadExecutionState(on ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
    }
}
'@
}

# Times are kept in UTC so a daylight-saving change during the wait cannot shift them.
function Wait-Until([datetime]$UtcTime, [string]$Action) {
    $at = $UtcTime.ToLocalTime().ToString('HH:mm:ss')
    while (($left = $UtcTime - [datetime]::UtcNow) -gt [timespan]::Zero) {
        Write-Host ("`r{0} in {1:hh\:mm\:ss} (at {2})   " -f $Action, $left, $at) -NoNewline
        Start-Sleep -Milliseconds 500
    }
    Write-Host ''
}

Write-Host 'Move the mouse over the spot to click (do not click), then press Enter.'
$null = Read-Host
$target = [ClickShutdownNative]::CursorPosition()

$clickAt = [datetime]::UtcNow + $ClickAfter
$shutdownAt = $clickAt + $ShutdownAfter
Write-Host "Will click at X=$($target.X), Y=$($target.Y) at $($clickAt.ToLocalTime().ToString('HH:mm:ss'))."
Write-Host "Will shut down at $($shutdownAt.ToLocalTime().ToString('HH:mm:ss')) (after a 60-second warning)."
Write-Host 'Keep this window open and the PC unlocked. Press Ctrl+C to cancel.'
Write-Host ''

[ClickShutdownNative]::KeepAwake($true)
try {
    Wait-Until $clickAt 'Clicking'
    [ClickShutdownNative]::LeftClick($target.X, $target.Y)
    Write-Host "Clicked at $(Get-Date -Format 'HH:mm:ss')."

    Wait-Until $shutdownAt 'Shutting down'
    shutdown.exe /s /t 60 /c "Scheduled shutdown. Run 'shutdown /a' to cancel."
    Write-Host 'Shutdown starts in 60 seconds. Run  shutdown /a  to cancel it.'
}
finally {
    [ClickShutdownNative]::KeepAwake($false)
}
