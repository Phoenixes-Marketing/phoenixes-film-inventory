@echo off
chcp 65001 >nul
set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

echo Phoenixes Film Inventory - Online Update
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%scripts\update_online_inventory.ps1" %*
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
  echo Update completed. You can close this window.
) else (
  echo Update failed. Please send the error text above to Codex.
)
echo.
pause
exit /b %EXITCODE%
