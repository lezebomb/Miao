@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-codex-miaomiao.ps1"
if errorlevel 1 (
  echo.
  echo Launch failed. See the message above.
  pause
)
endlocal
