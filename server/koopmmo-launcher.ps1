# KoopMMO launcher. start.bat runs this. The KoopMMO plugin rewrites this file when it changes,
# so put your settings (RAM) in start.bat, not here.
#
# Each time round the loop it:
#   1. installs a new KoopMMO jar waiting in pending-update\ (only if its SHA-1 matches the .sha1 file;
#      the old jar is archived in ..\archive\old-jars), then
#   2. starts the server and waits for it to stop, then
#   3. starts it again after 10 seconds - unless it was stopped with "mmo shutdown".
# If the server keeps dying within 2 minutes of starting it stops trying and waits for Enter.

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root
$ram = if ($env:KOOPMMO_RAM) { $env:KOOPMMO_RAM } else { '4G' }
$serverJar = if ($env:KOOPMMO_SERVER_JAR) { $env:KOOPMMO_SERVER_JAR } else { 'paper-1.21.11.jar' }
$java = Join-Path $root 'java\bin\java.exe'
if (-not (Test-Path $java)) { $java = 'java' }
$pending = Join-Path $root 'pending-update'
$archive = Join-Path (Split-Path $root -Parent) 'archive\old-jars'
$stopFlag = Join-Path $root 'stay-stopped.flag'
New-Item -ItemType Directory -Force (Join-Path $root 'logs') | Out-Null
$logFile = Join-Path $root 'logs\launcher.log'

function Log([string]$m, [string]$color = 'Cyan') {
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  Write-Host $line -ForegroundColor $color
  Add-Content -Path $logFile -Value $line
}

function Sha1([string]$path) { (Get-FileHash $path -Algorithm SHA1).Hash.ToLower() }

function Install-Pending {
  if (-not (Test-Path $pending)) { return }
  $jars = @(Get-ChildItem $pending -Filter 'KoopMMO-*.jar' -File | Sort-Object LastWriteTime -Descending)
  if ($jars.Count -eq 0) { return }
  $new = $jars[0]
  $done = Join-Path $pending 'applied'
  New-Item -ItemType Directory -Force $done | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  if ($jars.Count -gt 1) {
    foreach ($extra in $jars[1..($jars.Count - 1)]) {
      Move-Item $extra.FullName (Join-Path $done "$($extra.Name).skipped-$stamp") -Force
      if (Test-Path "$($extra.FullName).sha1") { Move-Item "$($extra.FullName).sha1" (Join-Path $done "$($extra.Name).sha1.skipped-$stamp") -Force }
    }
  }
  $shaFile = "$($new.FullName).sha1"
  if (-not (Test-Path $shaFile)) {
    Log "Not installing $($new.Name): there's no .sha1 file next to it." 'Red'
    Move-Item $new.FullName (Join-Path $done "$($new.Name).rejected-$stamp") -Force
    return
  }
  $want = ((Get-Content $shaFile -Raw) -replace '[^0-9a-fA-F]', '').ToLower()
  if ($want.Length -ge 40) { $want = $want.Substring(0, 40) }
  $got = Sha1 $new.FullName
  if ($got -ne $want) {
    Log "Not installing $($new.Name): checksum $got doesn't match $want. Keeping the current jar." 'Red'
    Move-Item $new.FullName (Join-Path $done "$($new.Name).rejected-$stamp") -Force
    Move-Item $shaFile (Join-Path $done "$($new.Name).sha1.rejected-$stamp") -Force
    return
  }
  New-Item -ItemType Directory -Force $archive | Out-Null
  $moved = @()
  foreach ($old in @(Get-ChildItem (Join-Path $root 'plugins') -Filter 'KoopMMO-*.jar' -File)) {
    $to = Join-Path $archive "$($old.BaseName)-replaced-$stamp.jar"
    Move-Item $old.FullName $to -Force
    $moved += ,@($to, $old.FullName)
    Log "Archived $($old.Name)"
  }
  $dest = Join-Path $root "plugins\$($new.Name)"
  Copy-Item $new.FullName $dest -Force
  $chk = Sha1 $dest
  if ($chk -ne $want) {
    Log "Copy of $($new.Name) came out wrong ($chk). Putting the old jar back." 'Red'
    Remove-Item $dest -Force -ErrorAction SilentlyContinue
    foreach ($pair in $moved) { Move-Item $pair[0] $pair[1] -Force }
    return
  }
  Move-Item $new.FullName (Join-Path $done "$($new.Name).installed-$stamp") -Force
  Move-Item $shaFile (Join-Path $done "$($new.Name).sha1.installed-$stamp") -Force
  Log "Installed $($new.Name) (sha1 $chk)." 'Green'
}

if (Test-Path $stopFlag) { Remove-Item $stopFlag -Force }
$quickExits = @()
$host.UI.RawUI.WindowTitle = "Koop's MMO"

while ($true) {
  try { Install-Pending } catch { Log "Update step failed: $($_.Exception.Message). Starting with the current jar." 'Red' }
  $env:KOOPMMO_LAUNCHER = '1'
  Log "Starting Koop's MMO ($ram RAM)..." 'Green'
  $started = Get-Date
  $javaArgs = @("-Xms$ram", "-Xmx$ram", '-XX:+UseG1GC', '-XX:+ParallelRefProcEnabled', '-XX:MaxGCPauseMillis=200',
    '-XX:+UnlockExperimentalVMOptions', '-XX:+DisableExplicitGC', '-XX:+AlwaysPreTouch', '-XX:G1NewSizePercent=30',
    '-XX:G1MaxNewSizePercent=40', '-XX:G1HeapRegionSize=8M', '-XX:G1ReservePercent=20', '-XX:G1HeapWastePercent=5',
    '-XX:G1MixedGCCountTarget=4', '-XX:InitiatingHeapOccupancyPercent=15', '-XX:G1MixedGCLiveThresholdPercent=90',
    '-XX:SurvivorRatio=32', '-XX:+PerfDisableSharedMem', '-XX:MaxTenuringThreshold=1', '-jar', $serverJar, 'nogui')
  & $java @javaArgs
  $code = $LASTEXITCODE
  $ran = ((Get-Date) - $started).TotalSeconds

  if (Test-Path $stopFlag) {
    Remove-Item $stopFlag -Force
    Log 'Stopped with "mmo shutdown". Not restarting. Run start.bat to start it again.' 'Yellow'
    break
  }
  if ($ran -lt 120) { $quickExits += Get-Date } else { $quickExits = @() }
  if ($quickExits.Count -ge 4) {
    Log "The server stopped within 2 minutes of starting 4 times in a row (last exit code $code). Not restarting until you press Enter." 'Red'
    Read-Host 'Check logs\latest.log, then press Enter to try again (or close this window)'
    $quickExits = @()
    continue
  }
  Log "Server stopped (exit code $code, ran $([int]$ran)s). Starting again in 10 seconds - close this window to stop for good." 'Yellow'
  Start-Sleep -Seconds 10
}
