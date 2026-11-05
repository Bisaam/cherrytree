# Capture only the CherryTree window (PrintWindow, so overlapping windows are not included)
param([string]$Out, [int]$ProcessId = 0, [int]$X = 40, [int]$Y = 40, [int]$Width = 1600, [int]$Height = 900, [switch]$NoResize)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CtWin {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  public struct RECT { public int L, T, R, B; }
}
"@
Add-Type -AssemblyName System.Drawing
if ($ProcessId -gt 0) { $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue } else { $p = Get-Process cherrytree -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
if (-not $p) { Write-Output "NO_WINDOW"; exit 2 }
$h = $p.MainWindowHandle
Write-Output ("TITLE=" + $p.MainWindowTitle)
if (-not $NoResize) { [CtWin]::ShowWindow($h, 9) | Out-Null; [CtWin]::SetWindowPos($h, [IntPtr]::Zero, $X, $Y, $Width, $Height, 0x0004) | Out-Null; Start-Sleep -Milliseconds 1500 }
$style = [CtWin]::GetWindowLong($h, -16); $ex = [CtWin]::GetWindowLong($h, -20)
Write-Output ("STYLE=0x{0:X8} EXSTYLE=0x{1:X8} MINIMIZEBOX={2} SYSMENU={3} CAPTION={4} LAYERED={5}" -f $style, $ex, [bool]($style -band 0x20000), [bool]($style -band 0x80000), (($style -band 0xC00000) -eq 0xC00000), [bool]($ex -band 0x80000))
$r = New-Object CtWin+RECT; [CtWin]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $hh)
$g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
[CtWin]::PrintWindow($h, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc); $g.Dispose(); $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output ("SAVED={0} {1}x{2}" -f $Out, $w, $hh)
