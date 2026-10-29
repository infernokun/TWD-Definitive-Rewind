# Screenshots the game window once a second during the screenshot tour (see README.md) and files each
# shot under the scene the tour log says is on screen:
#   <Out>\S4\E<ep>\<step> <label>\<HHmmss>.jpg   plus <Out>\index.csv
# The tour log is the "TWDRewind - Tour Log" string in prefs.prop (read from a copy, never written).
# Only the lines after the latest "begin|" (the current episode's tour) count. Frames between a
# "load" line and the next "start" (a scene loading) are skipped. Stops after "done|4", when the game
# closes, or after MaxMinutes.
# Start it before or while the game runs and leave the game window in front: a fullscreen game
# minimizes itself when another window takes the focus (the script brings it back, but those frames
# are lost).
param(
    [string]$Out = (Join-Path (Get-Location) "captures"),
    [string]$Prefs = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Telltale Games\The Walking Dead Definitive\prefs.prop"),
    [int]$MaxMinutes = 100
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
[Win]::SetProcessDPIAware() | Out-Null

$tmp = Join-Path $env:TEMP "twdr_prefs_capture.prop"
$latin1 = [Text.Encoding]::GetEncoding(28591)
function Read-AllTourLines {
    if (-not (Test-Path $Prefs)) { return @() }
    Copy-Item $Prefs $tmp -Force
    $txt = $latin1.GetString([IO.File]::ReadAllBytes($tmp))
    @([regex]::Matches($txt, '(?m)(?<![a-z])(begin|start|load|done)\|[ -~]*') | ForEach-Object { $_.Value })
}
# The log keeps earlier runs, so only the lines written since this script started count.
$baseline = @(Read-AllTourLines).Count
# Tour lines of the current episode's tour: those after the last "begin|" line.
function Read-TourLines {
    $all = @(Read-AllTourLines)
    if ($all.Count -le $baseline) { return @() }
    $all = @($all[$baseline..($all.Count - 1)])
    $b = -1
    for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -like 'begin|*') { $b = $i } }
    if ($b -lt 0 -or $b -ge $all.Count - 1) { return @() }
    $all[($b + 1)..($all.Count - 1)]
}
function Safe([string]$s) { ($s -replace '[\\/:*?"<>|]', '-').Trim() }

New-Item -ItemType Directory -Force $Out | Out-Null
$index = Join-Path $Out "index.csv"
if (-not (Test-Path $index)) { "time,episode,step,label,file" | Set-Content $index -Encoding utf8 }

$started = Get-Date
$seenGame = $false
$focused = $false
$shots = 0
$current = $null                          # @{ ep; step; label } of the scene on screen
$lastWhy = $null
while (((Get-Date) - $started).TotalMinutes -lt $MaxMinutes) {
    $tick = Get-Date
    $proc = Get-Process WDC -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        if ($seenGame) { Write-Output "game closed"; break }
        Start-Sleep -Milliseconds 1000; continue
    }
    $seenGame = $true
    $new = @(Read-TourLines)
    $last = if ($new.Count) { $new[-1] } else { $null }
    if (@($new | Where-Object { $_ -match '^done\|4\|' }).Count) { Write-Output "tour finished"; break }
    if ($last -match '^start\|(\d+)\|(\d+)\|([^|]*)\|') {
        $current = @{ ep = [int]$Matches[1]; step = [int]$Matches[2]; label = $Matches[3] }
    } else {
        $current = $null                  # loading, or the tour hasn't started yet
    }
    $h = $proc.MainWindowHandle
    # Why this frame is skipped (logged when it changes): a fullscreen game minimizes itself when
    # another window takes the focus, so it is brought back.
    $why = if (-not $current) { "no scene (loading or no tour yet)" }
           elseif ($h -eq [IntPtr]::Zero) { "no game window" }
           elseif ([Win]::IsIconic($h)) { "game minimized" }
           else { "" }
    if ($why -ne $lastWhy) { Write-Output ("{0}  {1}" -f (Get-Date).ToString("HH:mm:ss"), $(if ($why) { "skipping: $why" } else { "capturing" })); $lastWhy = $why }
    if ($why -eq "game minimized") { [Win]::ShowWindow($h, 9) | Out-Null; [Win]::SetForegroundWindow($h) | Out-Null }
    if (-not $why) {
        if (-not $focused) { [Win]::SetForegroundWindow($h) | Out-Null; $focused = $true; Start-Sleep -Milliseconds 300 }
        $r = New-Object Win+RECT
        [Win]::GetClientRect($h, [ref]$r) | Out-Null
        $p = New-Object Win+POINT
        [Win]::ClientToScreen($h, [ref]$p) | Out-Null
        $w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
        if ($w -gt 0 -and $hgt -gt 0) {
            $dir = Join-Path $Out ("S4\E{0}\{1:00} {2}" -f $current.ep, $current.step, (Safe $current.label))
            New-Item -ItemType Directory -Force $dir | Out-Null
            $file = Join-Path $dir ((Get-Date).ToString("HHmmss") + ".jpg")
            $bmp = New-Object System.Drawing.Bitmap $w, $hgt
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($p.X, $p.Y, 0, 0, (New-Object System.Drawing.Size $w, $hgt))
            $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $g.Dispose(); $bmp.Dispose()
            $shots++
            ('{0},{1},{2},"{3}","{4}"' -f (Get-Date).ToString("s"), $current.ep, $current.step, $current.label, $file) | Add-Content $index -Encoding utf8
        }
    }
    $wait = 1000 - [int]((Get-Date) - $tick).TotalMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
}
Write-Output ("{0} screenshots in {1:N0} minutes" -f $shots, ((Get-Date) - $started).TotalMinutes)
Get-ChildItem (Join-Path $Out "S4") -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Parent.Name -like 'E*' } |
    ForEach-Object { "{0}\{1}: {2}" -f $_.Parent.Name, $_.Name, (Get-ChildItem $_.FullName -File).Count }
