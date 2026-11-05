# README screenshot: start a packaged folder with a fresh profile (bundled defaults + "Demo Notes.ctd"
# open, tree expanded, no folder in the title), capture its window, stop that process (by PID).
param([Parameter(Mandatory)][string]$Stage, [Parameter(Mandatory)][string]$Out, [string]$Demo)
if (-not $Demo) { $Demo = Join-Path $PSScriptRoot "Demo Notes.ctd" }
$base = Join-Path $env:TEMP "ct-demo-shot"
if (Test-Path $base) { Remove-Item -Recurse -Force $base }
New-Item -ItemType Directory -Force "$base\cfg\CherryTree" | Out-Null
Copy-Item $Demo "$base\Demo Notes.ctd"
$doc = "$base\Demo Notes.ctd"
$cfg = Get-Content -Raw "$Stage\ucrt64\usr\share\cherrytree\data\config-default.cfg"
$cfg = $cfg -replace '(?m)^\[state\]\r?$', "[state]`r`ndoc_0=$($doc -replace '\\','\\')`r`nnodep_0=1:0`r`ncurs_0=0`r`nhpaned_pos=310`r`nwin_is_maximized=true"
$cfg += "`r`n[tree]`r`nrest_exp_coll=1`r`n[misc]`r`nwin_title_doc_dir=false`r`n"
[IO.File]::WriteAllText("$base\cfg\CherryTree\config.cfg", $cfg, (New-Object Text.UTF8Encoding $false))  # no BOM: GKeyFile rejects it
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
$env:APPDATA = "$base\cfg"   # settings: %APPDATA%\CherryTree
# CherryTree is single instance (GApplication over D-Bus): without a reachable session bus it runs on
# its own, so a CherryTree the user has open never receives this test's file
$env:DBUS_SESSION_BUS_ADDRESS = "tcp:host=127.0.0.1,port=9"
Start-Process -FilePath "$Stage\CherryTree.exe" -ArgumentList @("`"$doc`"") | Out-Null
$p = $null; $sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 120) {
  $p = Get-Process cherrytree -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Stage\*" } | Select-Object -First 1
  if ($p) { $p.Refresh(); if ($p.MainWindowHandle -ne 0) { break } }
  Start-Sleep -Milliseconds 200
}
if (-not $p -or $p.MainWindowHandle -eq 0) { "NO WINDOW"; exit 2 }
Start-Sleep -Seconds 3
& "$PSScriptRoot\capture.ps1" -Out $Out -ProcessId $p.Id -NoResize
Stop-Process -Id $p.Id -Force
Start-Sleep -Seconds 1
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
