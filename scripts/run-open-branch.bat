@echo off
:: ForkGit - GitLab launcher: Open Branch on GitLab
:: %~1 = branch name passed by Fork
set "SCRIPT_DIR=%~dp0"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden ^
    -File "%SCRIPT_DIR%fork-gitlab.ps1" ^
    -Action open-branch ^
    -Branch "%~1"
