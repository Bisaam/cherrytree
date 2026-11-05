# install -> run app -> uninstall while running (must refuse) -> close app -> uninstall (must remove all)
# NOTE: uses the same per-user registration as a real install (Start-menu shortcut, Apps & features entry,
# file associations): its uninstall step removes those, so only run it on a PC without CherryTree installed.
param([Parameter(Mandatory)][string]$Setup)
$base  = (Join-Path $env:TEMP 'ct-test')
$realAppData = $env:APPDATA
$setup = $Setup
$dir   = "$base\installed"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
$i = Start-Process -FilePath $setup -ArgumentList @('/S', "/D=$dir") -PassThru -Wait
"INSTALL exit=$($i.ExitCode)"

$env:PATH = 'C:\Windows\System32;C:\Windows'
$env:APPDATA = "$base\cfg-installed"   # settings: %APPDATA%\CherryTree
$env:DBUS_SESSION_BUS_ADDRESS = "tcp:host=127.0.0.1,port=9"  # run on its own, never hand files to an open CherryTree
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath "$dir\CherryTree.exe" -PassThru
$app = $null
while ($sw.Elapsed.TotalSeconds -lt 60) { $app = Get-Process cherrytree -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dir\*" } | Select-Object -First 1; if ($app) { $app.Refresh(); if ($app.MainWindowHandle -ne 0) { break } }; Start-Sleep -Milliseconds 200 }
"APP via Start-menu target CherryTree.exe: window after {0:N1}s" -f $sw.Elapsed.TotalSeconds

# uninstall while running: copy the uninstaller out first, like NSIS does normally
Copy-Item "$dir\uninstall.exe" "$base\un-copy.exe" -Force
$u = Start-Process -FilePath "$base\un-copy.exe" -ArgumentList @('/S', "_?=$dir") -PassThru -Wait
"UNINSTALL while running exit=$($u.ExitCode) files-still-there=" + (Test-Path "$dir\ucrt64\bin\cherrytree.exe")

Stop-Process -Id $app.Id -Force
Start-Sleep -Seconds 1
"gdbus from install dir running: " + [bool](Get-Process gdbus -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dir\*" })
$u = Start-Process -FilePath "$base\un-copy.exe" -ArgumentList @('/S', "_?=$dir") -PassThru -Wait
"UNINSTALL after close exit=$($u.ExitCode)"
Start-Sleep -Seconds 1
"AFTER: left=[" + ((Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object Name) -join ',') + "] dir-exists=" + (Test-Path $dir) + " startmenu=" + (Test-Path "$realAppData\Microsoft\Windows\Start Menu\Programs\CherryTree.lnk") + " key=" + (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CherryTree') + " .ctb=" + (Test-Path 'HKCU:\Software\Classes\.ctb')
Remove-Item "$base\un-copy.exe" -Force
