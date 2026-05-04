#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the ForkGit GitLab integration from the Fork Git client.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installDir  = Join-Path $env:LOCALAPPDATA 'Fork-GitLab'
$forkCmdFile = Join-Path $env:LOCALAPPDATA 'Fork\custom-commands.json'

Write-Host ''
Write-Host '  ForkGit — uninstaller' -ForegroundColor Cyan
Write-Host ''

# Remove installed scripts
if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
    Write-Host "  ✔  Removed $installDir"
}
else {
    Write-Host '  –  Install directory not found, skipping.'
}

# Remove GitLab/* entries from Fork's custom-commands.json
if (Test-Path $forkCmdFile) {
    $raw = Get-Content $forkCmdFile -Raw -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $commands = @($raw | ConvertFrom-Json | Where-Object { $_.name -notlike 'GitLab/*' })
        $commands | ConvertTo-Json -Depth 10 | Set-Content $forkCmdFile -Encoding UTF8
        Write-Host "  ✔  Removed GitLab commands from $forkCmdFile"
    }
}
else {
    Write-Host '  –  Fork custom-commands.json not found, nothing to clean.'
}

Write-Host ''
Write-Host '  Done. Restart Fork to apply changes.' -ForegroundColor Green
Write-Host ''
