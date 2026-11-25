# One-time setup for KoopMMO 0.76 (auto-update + auto-restart). Run it on the server PC with the server STOPPED:
#   irm https://raw.githubusercontent.com/Koopz8/koopmmo-pack/main/server/install-076.ps1 | iex
# It downloads KoopMMO 0.76.0, checks its SHA-1, archives the old jar, installs the new one, and swaps start.bat
# for one that runs koopmmo-launcher.ps1 (your RAM setting is kept; the old start.bat is saved next to it).
$ErrorActionPreference = 'Stop'
$root = 'C:\KoopcraftMMO\koop-mmo-server'
$base = 'https://raw.githubusercontent.com/Koopz8/koopmmo-pack/main/server'
$ver  = '0.76.0'
$want = 'e1f172d026378f6aee7db10f1e5de15f8321e920'
if (-not (Test-Path "$root\plugins")) { throw "No server at $root" }
if (Get-Process java -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" }) { throw 'The server is running. Stop it first (type stop in its window, then close the window).' }

$dl = "$root\update-0.76"
New-Item -ItemType Directory -Force $dl | Out-Null
Invoke-WebRequest "$base/KoopMMO-$ver.jar" -OutFile "$dl\KoopMMO-$ver.jar" -UseBasicParsing
Invoke-WebRequest "$base/koopmmo-launcher.ps1" -OutFile "$dl\koopmmo-launcher.ps1" -UseBasicParsing
$got = (Get-FileHash "$dl\KoopMMO-$ver.jar" -Algorithm SHA1).Hash.ToLower()
if ($got -ne $want) { throw "Jar checksum wrong: $got (wanted $want). Nothing was changed." }

New-Item -ItemType Directory -Force 'C:\KoopcraftMMO\archive\old-jars' | Out-Null
foreach ($old in Get-ChildItem "$root\plugins" -Filter 'KoopMMO-*.jar') {
  Move-Item $old.FullName "C:\KoopcraftMMO\archive\old-jars\$($old.BaseName)-was-installed-on-laptop.jar" -Force
  Write-Host "Archived $($old.Name)"
}
Copy-Item "$dl\KoopMMO-$ver.jar" "$root\plugins\KoopMMO-$ver.jar" -Force
Copy-Item "$dl\koopmmo-launcher.ps1" "$root\koopmmo-launcher.ps1" -Force

# keep the RAM setting from the current start.bat
$ram = '10G'
if (Test-Path "$root\start.bat") {
  $m = Select-String -Path "$root\start.bat" -Pattern '^\s*set\s+(KOOPMMO_)?RAM=(\S+)' | Select-Object -First 1
  if ($m) { $ram = $m.Matches[0].Groups[2].Value }
  if (-not (Test-Path "$root\start.bat.bak-pre076")) { Copy-Item "$root\start.bat" "$root\start.bat.bak-pre076" }
}
$bat = @"
@echo off
title Koop's MMO
cd /d "%~dp0"

rem ---- RAM for the server ----
set KOOPMMO_RAM=$ram

rem Use the Java 21 bundled in the "java" folder. Falls back to your installed java.
set "JAVA=%~dp0java\bin\java.exe"
if not exist "%JAVA%" set "JAVA=java"
"%JAVA%" -version 2>&1 | findstr /r /c:"version .2[1-9]" >nul
if errorlevel 1 (
  echo This server needs Java 21 or newer. Make sure the "java" folder is next to start.bat.
  pause
  exit /b
)
findstr /c:"eula=true" eula.txt >nul 2>&1 || (echo eula=true> eula.txt)

rem KoopMMO 0.76: the launcher installs downloaded updates and starts the server again after a stop or crash.
rem "mmo shutdown" in the console stops it for good. The KoopMMO plugin keeps koopmmo-launcher.ps1 up to date.
if exist "%~dp0koopmmo-launcher.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0koopmmo-launcher.ps1"
  pause
  exit /b
)

rem No launcher: plain loop.
:run
"%JAVA%" -Xms%KOOPMMO_RAM% -Xmx%KOOPMMO_RAM% -XX:+UseG1GC -jar paper-1.21.11.jar nogui
echo Server stopped. Restarting in 10 seconds - close this window to stop for good.
timeout /t 10
goto run
"@
Set-Content -Path "$root\start.bat" -Value $bat -Encoding Ascii

$chk = (Get-FileHash "$root\plugins\KoopMMO-$ver.jar" -Algorithm SHA1).Hash.ToLower()
Write-Host "RESULT: KoopMMO-$ver.jar installed, sha1 $chk $(if ($chk -eq $want) {'(matches)'} else {'(MISMATCH)'}). start.bat now uses the launcher (RAM $ram). Old one: start.bat.bak-pre076"
Write-Host 'Now start the server with start.bat as usual.'
