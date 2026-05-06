@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_DIR%fork-gitlab.ps1" -Action create-mr-quick -Branch "%~1" -Target "%~2"
endlocal
