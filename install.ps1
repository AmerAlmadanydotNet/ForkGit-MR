#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the ForkGit GitLab integration for the Fork Git client.

.DESCRIPTION
    1. Copies launcher scripts to %LOCALAPPDATA%\Fork-GitLab\
    2. Merges the new custom commands into Fork's custom-commands.json
       (%LOCALAPPDATA%\Fork\custom-commands.json)
    3. Prints instructions to restart Fork
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$sourceScripts  = Join-Path $PSScriptRoot 'scripts'
$installDir     = Join-Path $env:LOCALAPPDATA 'Fork-GitLab'
$forkConfigDir  = Join-Path $env:LOCALAPPDATA 'Fork'
$forkCmdFile    = Join-Path $forkConfigDir 'custom-commands.json'

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Icon, [string]$Message)
    Write-Host "  $Icon  $Message"
}

Write-Host ''
Write-Host '  ForkGit — GitLab integration installer' -ForegroundColor Cyan
Write-Host '  ───────────────────────────────────────' -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Create install directory
# ---------------------------------------------------------------------------
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Write-Step '✔' "Created  $installDir"
}
else {
    Write-Step '✔' "Exists   $installDir"
}

# ---------------------------------------------------------------------------
# 2. Copy scripts
# ---------------------------------------------------------------------------
$filesToCopy = @(
    'fork-gitlab.ps1',
    'run-mr.bat',
    'run-open-repo.bat',
    'run-open-branch.bat'
)
foreach ($file in $filesToCopy) {
    $src = Join-Path $sourceScripts $file
    if (-not (Test-Path $src)) {
        Write-Host "  x  Source file not found: $src" -ForegroundColor Red
        exit 1
    }
    Copy-Item -Path $src -Destination (Join-Path $installDir $file) -Force
    Write-Step 'OK' "Copied   $file"
}

# ---------------------------------------------------------------------------
# 3. Build the three custom command entries with absolute bat paths
# ---------------------------------------------------------------------------
$newCommands = @(
    [PSCustomObject]@{
        name       = 'GitLab/Create Merge Request'
        target     = 'ref'
        refTargets = @('localbranch')
        action     = [PSCustomObject]@{
            type        = 'process'
            path        = (Join-Path $installDir 'run-mr.bat')
            args        = '"$name"'
            showOutput  = $false
            waitForExit = $false
        }
    },
    [PSCustomObject]@{
        name   = 'GitLab/Open Repository on GitLab'
        target = 'repository'
        action = [PSCustomObject]@{
            type        = 'process'
            path        = (Join-Path $installDir 'run-open-repo.bat')
            args        = ''
            showOutput  = $false
            waitForExit = $false
        }
    },
    [PSCustomObject]@{
        name       = 'GitLab/Open Branch on GitLab'
        target     = 'ref'
        refTargets = @('localbranch')
        action     = [PSCustomObject]@{
            type        = 'process'
            path        = (Join-Path $installDir 'run-open-branch.bat')
            args        = '"$name"'
            showOutput  = $false
            waitForExit = $false
        }
    }
)

# ---------------------------------------------------------------------------
# 4. Merge with Fork's existing custom-commands.json
# ---------------------------------------------------------------------------
if (-not (Test-Path $forkConfigDir)) {
    New-Item -ItemType Directory -Path $forkConfigDir -Force | Out-Null
}

$commands = @()
if (Test-Path $forkCmdFile) {
    $raw = Get-Content $forkCmdFile -Raw -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $existing = $raw | ConvertFrom-Json
        # Remove any previous GitLab/* commands so we don't duplicate
        $commands = @($existing | Where-Object { $_.name -notlike 'GitLab/*' })
        Write-Step 'OK' "Kept $($commands.Count) existing non-GitLab commands"
    }
}

$commands += $newCommands
$commands | ConvertTo-Json -Depth 10 | Set-Content -Path $forkCmdFile -Encoding UTF8
Write-Step 'OK' "Written $($newCommands.Count) GitLab commands to $forkCmdFile"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  Installation complete!' -ForegroundColor Green
Write-Host ''
Write-Host '  GitLab menu items added to Fork:' -ForegroundColor Yellow
Write-Host '    Right-click a LOCAL BRANCH  ->  GitLab > Create Merge Request'
Write-Host '    Right-click a LOCAL BRANCH  ->  GitLab > Open Branch on GitLab'
Write-Host '    Right-click the REPOSITORY  ->  GitLab > Open Repository on GitLab'
Write-Host ''
Write-Host '  Restart Fork to apply the changes.'
Write-Host ''
