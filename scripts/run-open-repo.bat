@echo off
:: ForkGit - GitLab launcher: Open Repository on GitLab
set "SCRIPT_DIR=%~dp0"
powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden ^
    -File "%SCRIPT_DIR%fork-gitlab.ps1" ^
    -Action open-repo
