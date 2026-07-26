@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-miaomiao-with-codex.ps1"
if errorlevel 1 (
  echo.
  echo Miaomiao and Codex launch failed. See the message above.
  pause
)
endlocal
