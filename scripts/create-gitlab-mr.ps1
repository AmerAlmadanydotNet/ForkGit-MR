#Requires -Version 5.1
<#
.SYNOPSIS
    Opens the GitLab "New Merge Request" page in the default browser for the
    current branch.

.PARAMETER Branch
    The source branch name. Passed automatically by Fork via the custom command.

.NOTES
    Step 1 — browser-based MR creation (no GitLab token needed).
    The remote URL is read from `git remote get-url origin` in the current
    working directory (Fork sets CWD to the repository root before running
    custom commands).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Branch
)

# ---------------------------------------------------------------------------
# Helper: show a simple error dialog
# ---------------------------------------------------------------------------
function Show-Error {
    param([string]$Message)
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show(
        $Message,
        'GitLab – Create Merge Request',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
}

# ---------------------------------------------------------------------------
# 1. Get the remote URL from git
# ---------------------------------------------------------------------------
$remoteUrl = (& git remote get-url origin 2>&1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
    Show-Error "Could not read the 'origin' remote URL.`n`nMake sure the repository has a remote named 'origin' that points to GitLab."
    exit 1
}
$remoteUrl = $remoteUrl.Trim()

# ---------------------------------------------------------------------------
# 2. Parse host + namespace/project from the remote URL
#    Supported formats:
#      https://gitlab.com/namespace/project.git
#      https://gitlab.com/group/subgroup/project.git
#      git@gitlab.com:namespace/project.git
# ---------------------------------------------------------------------------
$gitlabHost  = $null
$nsProject   = $null

if ($remoteUrl -match '^https?://([^/]+)/(.+?)(?:\.git)?\s*$') {
    $gitlabHost = $Matches[1]
    $nsProject  = $Matches[2]
}
elseif ($remoteUrl -match '^git@([^:]+):(.+?)(?:\.git)?\s*$') {
    $gitlabHost = $Matches[1]
    $nsProject  = $Matches[2]
}
else {
    Show-Error "Cannot parse the remote URL:`n$remoteUrl`n`nExpected:`n  https://gitlab.com/ns/project.git`n  git@gitlab.com:ns/project.git"
    exit 1
}

# ---------------------------------------------------------------------------
# 3. Build the GitLab new-MR URL
#    GitLab's query param: merge_request[source_branch]=<branch>
#    URL-encode both the param name delimiters and the branch name.
# ---------------------------------------------------------------------------
$encodedBranch = [Uri]::EscapeDataString($Branch)
$mrUrl = "https://$gitlabHost/$nsProject/-/merge_requests/new" +
         "?merge_request%5Bsource_branch%5D=$encodedBranch"

# ---------------------------------------------------------------------------
# 4. Open in the default browser
# ---------------------------------------------------------------------------
Start-Process $mrUrl
