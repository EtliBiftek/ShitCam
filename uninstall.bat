@echo off
rem ShitCam uninstaller - removes PATH entry and installed files.
setlocal
set "DEST=%LOCALAPPDATA%\ShitCam"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = '%DEST%';" ^
  "$p = [Environment]::GetEnvironmentVariable('Path','User');" ^
  "$np = (($p -split ';') | Where-Object { $_ -ine '' -and $_ -ine $d }) -join ';';" ^
  "[Environment]::SetEnvironmentVariable('Path', $np, 'User')"
if errorlevel 1 (
  echo ERROR: PATH update failed.
  exit /b 1
)

if exist "%DEST%" rmdir /S /Q "%DEST%"
echo Uninstalled. Restart terminals to refresh PATH.
endlocal
exit /b 0
