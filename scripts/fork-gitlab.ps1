#Requires -Version 5.1
<#
.SYNOPSIS
    ForkGit – GitLab actions launcher.

.PARAMETER Action
    Which action to run:
      create-mr     Open the GitLab "New Merge Request" page for the branch
      open-repo     Open the repository root page on GitLab
      open-branch   Open the branch page on GitLab

.PARAMETER Branch
    The branch name (required for create-mr and open-branch).
    Fork passes this automatically via the custom-command argument.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('create-mr', 'open-repo', 'open-branch')]
    [string]$Action,

    [string]$Branch = ''
)

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Helper: show an error dialog
# ---------------------------------------------------------------------------
function Show-Error {
    param([string]$Message)
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show(
        $Message,
        'ForkGit – GitLab',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
}

# ---------------------------------------------------------------------------
# Helper: read + parse the origin remote URL
#   Returns a hashtable: @{ Host=...; NamespacedProject=... }
# ---------------------------------------------------------------------------
function Get-GitLabRemote {
    $raw = (& git remote get-url origin 2>&1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        Show-Error "Could not read the 'origin' remote URL.`n`nMake sure the repository has a remote named 'origin' pointing to GitLab."
        exit 1
    }
    $url = $raw.Trim()

    if ($url -match '^https?://([^/]+)/(.+?)(?:\.git)?\s*$') {
        return @{ Host = $Matches[1]; Path = $Matches[2] }
    }
    if ($url -match '^git@([^:]+):(.+?)(?:\.git)?\s*$') {
        return @{ Host = $Matches[1]; Path = $Matches[2] }
    }

    Show-Error "Cannot parse remote URL:`n$url`n`nExpected:`n  https://gitlab.com/ns/project.git`n  git@gitlab.com:ns/project.git"
    exit 1
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
switch ($Action) {

    'create-mr' {
        if ([string]::IsNullOrWhiteSpace($Branch)) {
            Show-Error "Branch name was not supplied. Please right-click a local branch and choose GitLab > Create Merge Request."
            exit 1
        }
        $r = Get-GitLabRemote
        $enc = [Uri]::EscapeDataString($Branch)
        $url = "https://$($r.Host)/$($r.Path)/-/merge_requests/new" +
               "?merge_request%5Bsource_branch%5D=$enc"
        Start-Process $url
    }

    'open-repo' {
        $r = Get-GitLabRemote
        Start-Process "https://$($r.Host)/$($r.Path)"
    }

    'open-branch' {
        if ([string]::IsNullOrWhiteSpace($Branch)) {
            Show-Error "Branch name was not supplied. Please right-click a local branch and choose GitLab > Open Branch on GitLab."
            exit 1
        }
        $r = Get-GitLabRemote
        $enc = [Uri]::EscapeDataString($Branch)
        Start-Process "https://$($r.Host)/$($r.Path)/-/tree/$enc"
    }
}
