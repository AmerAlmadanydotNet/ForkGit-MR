@echo off
:: ForkGit - GitLab launcher: Create MR (with target branch picker dialog)
:: %~1 = source branch name passed by Fork
set "SCRIPT_DIR=%~dp0"
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden ^
    -File "%SCRIPT_DIR%fork-gitlab.ps1" ^
    -Action create-mr-pick ^
    -Branch "%~1"
