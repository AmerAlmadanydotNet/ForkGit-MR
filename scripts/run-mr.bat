@echo off
:: ForkGit - GitLab launcher: Create Merge Request
:: %~1 = branch name passed by Fork
set "SCRIPT_DIR=%~dp0"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden ^
    -File "%SCRIPT_DIR%fork-gitlab.ps1" ^
    -Action create-mr ^
    -Branch "%~1"
