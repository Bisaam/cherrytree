# "another PC" test: unzip a release into an empty folder, start it via the top-level CherryTree.exe
# launcher with a bare Windows PATH and an empty profile, open the demo notebook, time it, then stop
# the process it started (by PID; -KeepOpen leaves it running and prints the PID).
param([Parameter(Mandatory)][string]$Zip, [string]$Doc, [switch]$KeepOpen)
if (-not $Doc) { $Doc = Join-Path $PSScriptRoot "Demo Notes.ctd" }
$base = Join-Path $env:TEMP "ct-test"
$dest = "$base\portable-fresh"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $base | Out-Null
Copy-Item $Doc "$base\Demo Notes.ctd"
$sw = [Diagnostics.Stopwatch]::StartNew()
Expand-Archive -Path $Zip -DestinationPath $dest
"UNZIP {0:N1}s" -f $sw.Elapsed.TotalSeconds
$app = Get-ChildItem $dest -Directory | Select-Object -First 1
"TOP-LEVEL: " + ((Get-ChildItem $app.FullName | ForEach-Object Name) -join ', ')
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
$env:XDG_CONFIG_HOME = "$base\cfg-portable-fresh"
$env:DBUS_SESSION_BUS_ADDRESS = "tcp:host=127.0.0.1,port=9"  # run on its own, never hand files to an open CherryTree
if (Test-Path $env:XDG_CONFIG_HOME) { Remove-Item -Recurse -Force $env:XDG_CONFIG_HOME }
$sw.Restart()
Start-Process -FilePath "$($app.FullName)\CherryTree.exe" -ArgumentList @("`"$base\Demo Notes.ctd`"")
$p = $null
while ($sw.Elapsed.TotalSeconds -lt 180) {
  $p = Get-Process cherrytree -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dest\*" } | Select-Object -First 1
  if ($p) { $p.Refresh(); if ($p.MainWindowHandle -ne 0) { break } }
  Start-Sleep -Milliseconds 200
}
if (-not $p -or $p.MainWindowHandle -eq 0) { "NO WINDOW after {0:N1}s" -f $sw.Elapsed.TotalSeconds; exit 2 }
"WINDOW after {0:N1}s PID={1} title={2}" -f $sw.Elapsed.TotalSeconds, $p.Id, $p.MainWindowTitle
Start-Sleep -Seconds 2
$seeded = Get-Content "$env:XDG_CONFIG_HOME\cherrytree-kali\config.cfg" -ErrorAction SilentlyContinue | Select-String -SimpleMatch "rt_style_scheme=Kali-Dark"
"KALI CONFIG SEEDED: " + [bool]$seeded
if ($KeepOpen) { return }
Stop-Process -Id $p.Id -Force
Start-Sleep -Seconds 2
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
"CLEANED: " + (-not (Test-Path $base))
