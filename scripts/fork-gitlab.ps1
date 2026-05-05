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
    [ValidateSet('create-mr', 'create-mr-pick', 'open-repo', 'open-branch', 'configure-token')]
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
# Config: store / retrieve the GitLab Personal Access Token
# ---------------------------------------------------------------------------
$script:configFile = Join-Path $env:LOCALAPPDATA 'Fork-GitLab\config.json'

function Get-StoredToken {
    if (Test-Path $script:configFile) {
        try {
            $cfg = Get-Content $script:configFile -Raw | ConvertFrom-Json
            if ($cfg.PSObject.Properties['token']) { return $cfg.token }
        } catch { }
    }
    return $null
}

function Save-StoredToken {
    param([string]$Token)
    $favs = Get-FavoriteBranches
    @{ token = $Token; favorites = @($favs) } | ConvertTo-Json | Set-Content $script:configFile -Encoding UTF8
}

function Get-FavoriteBranches {
    if (Test-Path $script:configFile) {
        try {
            $cfg = Get-Content $script:configFile -Raw | ConvertFrom-Json
            if ($cfg.PSObject.Properties['favorites']) {
                return [string[]]@($cfg.favorites | Where-Object { $_ })
            }
        } catch { }
    }
    return [string[]]@()
}

function Save-FavoriteBranches {
    param([string[]]$Favorites)
    $token = Get-StoredToken
    if ($null -eq $token) { $token = '' }
    @{ token = $token; favorites = @($Favorites) } | ConvertTo-Json | Set-Content $script:configFile -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Show a dialog to enter / update the GitLab Personal Access Token
# ---------------------------------------------------------------------------
function Show-TokenDialog {
    param([string]$CurrentToken = '')
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    [xml]$txaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="GitLab - Personal Access Token"
        Width="480" Height="210"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Topmost="True">
    <Grid Margin="20,16,20,16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="12"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="6"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" TextWrapping="Wrap"
                   Text="Enter your GitLab Personal Access Token (api scope required). It is stored locally on this machine only."/>
        <TextBlock Grid.Row="2" Text="Personal Access Token:" FontWeight="SemiBold"/>
        <TextBox Name="TokenBox" Grid.Row="4" Height="26"
                 VerticalContentAlignment="Center" Padding="4,0"
                 BorderBrush="#ABADB3" BorderThickness="1"/>
        <TextBlock Grid.Row="5" FontSize="11" Foreground="#555"
                   Text="Create one at: GitLab > Settings > Access Tokens  (select api scope)"
                   Margin="0,4,0,0"/>
        <StackPanel Grid.Row="7" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="OkBtn" Content="Save" MinWidth="80" Height="28"
                    Padding="8,0" Margin="0,0,8,0" IsDefault="True"/>
            <Button Name="CancelBtn" Content="Cancel"
                    Width="70" Height="28" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@
    $treader         = [System.Xml.XmlNodeReader]::new($txaml)
    $script:tkWin    = [System.Windows.Markup.XamlReader]::Load($treader)
    $script:tkBox    = $script:tkWin.FindName('TokenBox')
    $tOkBtn          = $script:tkWin.FindName('OkBtn')

    if (-not [string]::IsNullOrWhiteSpace($CurrentToken)) {
        $script:tkBox.Text = $CurrentToken
    }

    $script:tkResult = $null
    $tOkBtn.Add_Click({
        $script:tkResult = $script:tkBox.Text.Trim()
        $script:tkWin.DialogResult = $true
    })
    $script:tkWin.Add_Loaded({ $script:tkBox.Focus() | Out-Null ; $script:tkBox.SelectAll() })

    if ($script:tkWin.ShowDialog()) { return $script:tkResult }
    return $null
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
        # Strip 'origin/' prefix for remote branches (leave other slashes intact e.g. feature/my-branch)
        $Branch = $Branch -replace '^origin/', ''
        $r = Get-GitLabRemote
        $enc = [Uri]::EscapeDataString($Branch)
        Start-Process "https://$($r.Host)/$($r.Path)/-/tree/$enc"
    }

    'create-mr-pick' {
        $logPath = Join-Path $env:TEMP 'forkgit-debug.log'
        "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] create-mr-pick started. Branch='$Branch'" | Set-Content $logPath -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($Branch)) {
            Show-Error "Branch name was not supplied. Please right-click a local branch and choose GitLab > Create MR."
            exit 1
        }
        # Strip 'origin/' prefix for remote branches (leave other slashes intact e.g. feature/my-branch)
        $Branch = $Branch -replace '^origin/', ''
        "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Branch after strip='$Branch'" | Add-Content $logPath -Encoding UTF8

        $r = Get-GitLabRemote
        "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Remote: Host=$($r.Host) Path=$($r.Path)" | Add-Content $logPath -Encoding UTF8
        $allBranches = @(
            & git branch -a --format='%(refname:short)' 2>$null |
            Where-Object { $_ -notmatch 'HEAD' } |
            ForEach-Object { $_ -replace '^origin/', '' } |
            Where-Object { $_ -ne $Branch } |
            Sort-Object -Unique
        )

        if ($allBranches.Count -eq 0) {
            Show-Error "No other branches found to merge into."
            exit 1
        }
        "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Branches found: $($allBranches.Count)" | Add-Content $logPath -Encoding UTF8
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase

        [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="GitLab - Create Merge Request"
        Width="460" Height="480"
        MinHeight="400"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        Topmost="True">
    <Grid Margin="20,16,20,16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="6"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="8"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="4"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="6"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="6"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="10"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Source branch label -->
        <StackPanel Grid.Row="0" Orientation="Horizontal">
            <TextBlock Text="From:  " FontWeight="SemiBold" VerticalAlignment="Center"/>
            <TextBlock Name="SourceLabel" FontFamily="Consolas" VerticalAlignment="Center"
                       Foreground="#0078D4" TextTrimming="CharacterEllipsis"/>
        </StackPanel>

        <!-- MR Title -->
        <TextBlock Grid.Row="2" Text="Title:" FontWeight="SemiBold"/>
        <TextBox Name="TitleBox" Grid.Row="4" Height="26"
                 VerticalContentAlignment="Center" Padding="4,0"
                 BorderBrush="#ABADB3" BorderThickness="1"/>

        <!-- Draft checkbox -->
        <CheckBox Name="DraftCheck" Grid.Row="6"
                  Content="Mark as draft" IsChecked="False"
                  VerticalContentAlignment="Center"/>

        <!-- Delete source branch checkbox -->
        <CheckBox Name="DeleteBranchCheck" Grid.Row="8"
                  Content="Delete source branch when merge request is accepted" IsChecked="False"
                  VerticalContentAlignment="Center"/>

        <!-- Target label + search box -->
        <TextBlock Grid.Row="10" Text="Merge into:" FontWeight="SemiBold"/>
        <Grid Grid.Row="12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox Name="SearchBox" Grid.Column="0" Height="26"
                     VerticalContentAlignment="Center" Padding="4,0"
                     BorderBrush="#ABADB3" BorderThickness="1,1,0,1"/>
            <Border Grid.Column="1" Width="26" Height="26"
                    Background="#F0F0F0" BorderBrush="#ABADB3" BorderThickness="1">
                <TextBlock Text="&#x1F50D;" HorizontalAlignment="Center"
                           VerticalAlignment="Center" FontSize="13"/>
            </Border>
            <Button Name="FavBtn" Grid.Column="2" Width="30" Height="26"
                    Content="&#x2606;" FontSize="15" Padding="0" Margin="4,0,0,0"
                    ToolTip="Toggle favourite (max 6)" Background="Transparent"
                    BorderBrush="#ABADB3" BorderThickness="1"
                    Focusable="False" IsTabStop="False"/>
        </Grid>

        <!-- Filtered branch list -->
        <ListBox Name="BranchList" Grid.Row="14"
                 BorderBrush="#ABADB3" BorderThickness="1"
                 ScrollViewer.VerticalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="12"/>

        <!-- Buttons -->
        <StackPanel Grid.Row="16" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="OkBtn" Content="Create MR"
                    MinWidth="120" Height="28" Padding="8,0" Margin="0,0,8,0" IsDefault="True"/>
            <Button Name="CancelBtn" Content="Cancel"
                    Width="70" Height="28" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@
        $reader           = [System.Xml.XmlNodeReader]::new($xaml)
        $script:mrWin     = [System.Windows.Markup.XamlReader]::Load($reader)
        $script:list      = $script:mrWin.FindName('BranchList')
        $script:search    = $script:mrWin.FindName('SearchBox')
        $script:titleBox  = $script:mrWin.FindName('TitleBox')
        $script:draftChk        = $script:mrWin.FindName('DraftCheck')
        $script:deleteBranchChk  = $script:mrWin.FindName('DeleteBranchCheck')
        $script:favBtn           = $script:mrWin.FindName('FavBtn')
        $okBtn                   = $script:mrWin.FindName('OkBtn')

        $script:mrWin.FindName('SourceLabel').Text = $Branch
        $script:allBranches = $allBranches

        # Helper: strip '★ ' prefix to get the real branch name
        function Get-BranchName {
            param([string]$Item)
            $star = [char]0x2605
            return $Item -replace "^$star ", ''
        }

        # Helper: build the standard MR title from source + current target selection
        function Get-MrTitle {
            $raw    = if ($script:list.SelectedItem) { $script:list.SelectedItem } else { '...' }
            $target = Get-BranchName $raw
            return "From $Branch into $target"
        }

        $script:titleBox.Text = Get-MrTitle
        # Track whether the user has manually edited the title
        $script:titleEdited = $false
        $script:titleBox.Add_TextChanged({
            # Only mark as edited if the change wasn't triggered by our own code
            if (-not $script:updatingTitle) { $script:titleEdited = $true }
        })

        # Draft checkbox: toggle 'Draft: ' prefix on the title
        $script:draftChk.Add_Checked({
            $script:updatingTitle = $true
            $t = $script:titleBox.Text
            if ($t -notlike 'Draft: *') { $script:titleBox.Text = "Draft: $t" }
            $script:updatingTitle = $false
        })
        $script:draftChk.Add_Unchecked({
            $script:updatingTitle = $true
            $script:titleBox.Text = $script:titleBox.Text -replace '^Draft:\s*', ''
            $script:updatingTitle = $false
        })

        # Helper: rebuild the ListBox with only matching branches
        function Update-List {
            param([string]$Filter)
            $prevReal = if ($script:list.SelectedItem) { Get-BranchName $script:list.SelectedItem } else { $null }
            $script:list.Items.Clear()
            $all = if ([string]::IsNullOrWhiteSpace($Filter)) {
                $script:allBranches
            } else {
                $script:allBranches | Where-Object { $_ -like "*$Filter*" }
            }
            $favSet  = [string[]]@($script:favs)
            $favs    = @($all | Where-Object { $favSet -contains $_ })
            $nonFavs = @($all | Where-Object { $favSet -notcontains $_ })
            foreach ($b in $favs)    { [void]$script:list.Items.Add("$([char]0x2605) $b") }
            foreach ($b in $nonFavs) { [void]$script:list.Items.Add($b) }
            # Restore selection by real name
            if ($prevReal) {
                $match = $script:list.Items | Where-Object { (Get-BranchName $_) -eq $prevReal } | Select-Object -First 1
                if ($match) { $script:list.SelectedItem = $match; return }
            }
            if ($script:list.Items.Count -gt 0) { $script:list.SelectedIndex = 0 }
        }

        # Helper: update the ★ button to reflect current selection's fav state
        function Update-FavBtn {
            $real = $script:lastRealBranch
            if (-not $real) { $script:favBtn.Content = [char]0x2606; $script:favBtn.IsEnabled = $false; return }
            $script:favBtn.IsEnabled = $true
            $script:favBtn.Content = if ($script:favs -contains $real) { [char]0x2605 } else { [char]0x2606 }
            if (-not ($script:favs -contains $real)) {
                $script:favBtn.IsEnabled = (@($script:favs).Count -lt 6)
            }
        }

        $script:selectedTarget  = $null
        $script:updatingTitle   = $false
        $script:lastRealBranch  = $null
        $script:favs            = [string[]]@(Get-FavoriteBranches)

        # Seed list; pre-select preferred default
        Update-List ''
        $preferred = @('main', 'master', 'develop') |
                     Where-Object { $allBranches -contains $_ } |
                     Select-Object -First 1
        if ($preferred) {
            $prefItem = $script:list.Items | Where-Object { (Get-BranchName $_) -eq $preferred } | Select-Object -First 1
            if ($prefItem) { $script:list.SelectedItem = $prefItem }
        }
        $sel = $script:list.SelectedItem
        $script:lastRealBranch = if ($sel) { Get-BranchName $sel } else { $null }
        Update-FavBtn

        # Store function refs as script-scoped variables so event handlers can call them
        $script:fnUpdateList   = ${function:Update-List}
        $script:fnUpdateFavBtn = ${function:Update-FavBtn}
        $script:fnGetBranch    = ${function:Get-BranchName}
        $script:fnSaveFavs     = ${function:Save-FavoriteBranches}
        $script:fnGetMrTitle   = ${function:Get-MrTitle}

        # Filter as user types
        $script:search.Add_TextChanged({
            & $script:fnUpdateList $script:search.Text
        })

        # When selection changes, update the title automatically (unless user edited it)
        $script:list.Add_SelectionChanged({
            $sel = $script:list.SelectedItem
            $script:lastRealBranch = if ($sel) { & $script:fnGetBranch $sel } else { $null }
            & $script:fnUpdateFavBtn
            if (-not $script:titleEdited) {
                $script:updatingTitle = $true
                $script:titleBox.Text = & $script:fnGetMrTitle
                $script:updatingTitle = $false
            }
        })

        # Allow selecting from list with keyboard / double-click
        $script:list.Add_MouseDoubleClick({
            if ($script:list.SelectedItem) {
                $okBtn.RaiseEvent(
                    [System.Windows.RoutedEventArgs]::new(
                        [System.Windows.Controls.Button]::ClickEvent))
            }
        })

        # Toggle favourite on the selected branch
        $script:favBtn.Add_Click({
            $favLog = Join-Path $env:TEMP 'forkgit-debug.log'
            try {
                $real = $script:lastRealBranch
                if (-not $real) {
                    $real = if ($script:list.SelectedItem) { & $script:fnGetBranch $script:list.SelectedItem } else { $null }
                }
                "FAV CLICK: real='$real' favs='$($script:favs -join ',')'" | Add-Content $favLog -Encoding UTF8
                if (-not $real) { return }
                if ($script:favs -contains $real) {
                    $script:favs = [string[]]@($script:favs | Where-Object { $_ -ne $real })
                } else {
                    if (@($script:favs).Count -lt 6) {
                        $script:favs = [string[]](@($script:favs) + $real)
                    }
                }
                & $script:fnSaveFavs $script:favs
                & $script:fnUpdateList $script:search.Text
                & $script:fnUpdateFavBtn
                "FAV DONE: favs='$($script:favs -join ',')'" | Add-Content $favLog -Encoding UTF8
            } catch {
                "FAV ERROR: $_" | Add-Content $favLog -Encoding UTF8
            }
        })

        $script:selectedTarget = $null
        $okBtn.Add_Click({
            if ($script:list.SelectedItem) {
                $script:selectedTarget     = & $script:fnGetBranch $script:list.SelectedItem
                $script:mrWin.DialogResult = $true
            }
        })

        # Focus the title box on open so user can edit it immediately
        $script:mrWin.Add_Loaded({ $script:titleBox.Focus() | Out-Null ; $script:titleBox.SelectAll() })

        $result = $script:mrWin.ShowDialog()
        "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] ShowDialog result='$result' selectedTarget='$script:selectedTarget'" | Add-Content $logPath -Encoding UTF8

        if ($result -and -not [string]::IsNullOrWhiteSpace($script:selectedTarget)) {
            # Ensure we have a token — prompt if missing
            $token = Get-StoredToken
            if ([string]::IsNullOrWhiteSpace($token)) {
                $token = Show-TokenDialog
                if ([string]::IsNullOrWhiteSpace($token)) { exit 0 }
                Save-StoredToken $token
            }

            $title        = $script:titleBox.Text.Trim()
            $removeSource = [bool]($script:deleteBranchChk.IsChecked)
            $encodedPath  = [Uri]::EscapeDataString($r.Path)
            $apiUrl       = "https://$($r.Host)/api/v4/projects/$encodedPath/merge_requests"
            $body         = @{
                source_branch        = $Branch
                target_branch        = $script:selectedTarget
                title                = $title
                remove_source_branch = $removeSource
            } | ConvertTo-Json

            $maxAttempts = 3
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                $success = $false
                try {
                    $mr = Invoke-RestMethod -Method POST -Uri $apiUrl `
                        -Headers @{ 'PRIVATE-TOKEN' = $token } `
                        -Body $body -ContentType 'application/json'
                    # Log success for troubleshooting
                    $logPath = Join-Path $env:TEMP 'forkgit-debug.log'
                    "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] SUCCESS`nURL: $apiUrl`nMR iid: $($mr.iid)`nweb_url: $($mr.web_url)`nstate: $($mr.state)" |
                        Set-Content $logPath -Encoding UTF8
                    if (-not [string]::IsNullOrWhiteSpace($mr.web_url)) {
                        # Copy "Title\nURL" to clipboard
                        "$($mr.title)`n$($mr.web_url)" | Set-Clipboard
                        Start-Process $mr.web_url
                    } else {
                        Show-Error "Merge request created but could not get its URL.`nCheck: $apiUrl"
                    }
                    $success = $true
                } catch {
                    $statusCode = 0
                    $errMsg     = $_.Exception.Message
                    $rawBody    = ''
                    if ($_.Exception.Response) {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                        try {
                            $stream  = $_.Exception.Response.GetResponseStream()
                            $rawBody = [System.IO.StreamReader]::new($stream).ReadToEnd()
                            $errObj  = $rawBody | ConvertFrom-Json
                            if ($errObj.PSObject.Properties['message']) {
                                $m = $errObj.message
                                if ($m -is [string]) {
                                    $errMsg = $m
                                } elseif ($m -is [System.Management.Automation.PSCustomObject]) {
                                    $errMsg = ($m.PSObject.Properties.Value | ForEach-Object { $_ -join ', ' }) -join '; '
                                } else {
                                    $errMsg = ($m | Out-String).Trim()
                                }
                            } elseif ($errObj.PSObject.Properties['error']) {
                                $errMsg = $errObj.error
                            } elseif ($errObj.PSObject.Properties['errors']) {
                                $errMsg = ($errObj.errors | Out-String).Trim()
                            } else {
                                $errMsg = $rawBody
                            }
                        } catch { $errMsg = $rawBody }
                    }
                    # Write debug log for troubleshooting
                    $logPath = Join-Path $env:TEMP 'forkgit-debug.log'
                    "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] HTTP $statusCode`nURL: $apiUrl`nBody: $body`nResponse: $rawBody" |
                        Set-Content $logPath -Encoding UTF8
                    if ($statusCode -eq 401) {
                        Save-StoredToken ''
                        $token = Show-TokenDialog -CurrentToken ''
                        if ([string]::IsNullOrWhiteSpace($token)) { break }
                        Save-StoredToken $token
                        # loop will retry with new token
                    } else {
                        Show-Error "Failed to create merge request (HTTP $statusCode):`n$errMsg"
                        break
                    }
                }
                if ($success) { break }
            }
        }
    }

    'configure-token' {
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase
        $current = Get-StoredToken
        if ($null -eq $current) { $current = '' }
        $newToken = Show-TokenDialog -CurrentToken $current
        if ($null -ne $newToken) {
            Save-StoredToken $newToken
            if ([string]::IsNullOrWhiteSpace($newToken)) {
                [System.Windows.MessageBox]::Show(
                    'Token cleared.',
                    'ForkGit – GitLab',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
            } else {
                [System.Windows.MessageBox]::Show(
                    'Token saved successfully.',
                    'ForkGit – GitLab',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                ) | Out-Null
            }
        }
    }
}
