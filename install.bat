@echo off
rem ShitCam installer - user-level, no admin needed, idempotent.
setlocal EnableDelayedExpansion
set "DEST=%LOCALAPPDATA%\ShitCam"
set "SRC=%~dp0build\shitcam.exe"

if not exist "%SRC%" (
  echo ERROR: build\shitcam.exe not found. Run: python tools\build.py
  exit /b 1
)
if not exist "%DEST%" mkdir "%DEST%" >nul 2>&1
copy /Y "%SRC%" "%DEST%\shitcam.exe" >nul
if errorlevel 1 (
  echo ERROR: copy failed.
  exit /b 1
)

rem --- idempotent user PATH add via PowerShell (no duplicates, no clobber) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = '%DEST%';" ^
  "$p = [Environment]::GetEnvironmentVariable('Path','User');" ^
  "if ($p -split ';' | Where-Object { $_ -ieq $d }) { exit 0 };" ^
  "$np = ($p.TrimEnd(';') + ';' + $d).TrimStart(';');" ^
  "if ($np.Length -gt 2047) { Write-Host 'WARNING: PATH near setx limit, entry added but verify with: setx'; };" ^
  "[Environment]::SetEnvironmentVariable('Path', $np, 'User')"
if errorlevel 1 (
  echo ERROR: PATH update failed.
  exit /b 1
)

echo Installed to %DEST%
echo Open a NEW terminal and run: shitcam --version
endlocal
exit /b 0
