param([string]$Stage, [string]$Cfg)
# start a packaged folder via its CherryTree.exe launcher, bare PATH, given (isolated) profile; print PID
$base = (Join-Path $env:TEMP 'ct-test')
$env:PATH = 'C:\Windows\System32;C:\Windows'
$env:APPDATA = "$base\$Cfg"   # settings: %APPDATA%\CherryTree
$env:DBUS_SESSION_BUS_ADDRESS = "tcp:host=127.0.0.1,port=9"  # run on its own, never hand files to an open CherryTree
$sw = [Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath "$Stage\CherryTree.exe" -ArgumentList @("`"$base\Demo Notes.ctd`"")
$p = $null
while ($sw.Elapsed.TotalSeconds -lt 120) {
  $p = Get-Process cherrytree -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Stage\*" } | Select-Object -First 1
  if ($p) { $p.Refresh(); if ($p.MainWindowHandle -ne 0) { break } }
  Start-Sleep -Milliseconds 200
}
if ($p -and $p.MainWindowHandle -ne 0) { "WINDOW after {0:N1}s PID={1} title={2}" -f $sw.Elapsed.TotalSeconds, $p.Id, $p.MainWindowTitle } else { "NO WINDOW" }
