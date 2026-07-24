@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-miaomiao-desktop.ps1"
if errorlevel 1 (
  echo.
  echo Miaomiao launch failed. See the message above.
  pause
)
endlocal
