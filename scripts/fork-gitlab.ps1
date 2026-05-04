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
    [ValidateSet('create-mr', 'create-mr-pick', 'open-repo', 'open-branch')]
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

    'create-mr-pick' {
        if ([string]::IsNullOrWhiteSpace($Branch)) {
            Show-Error "Branch name was not supplied. Please right-click a local branch and choose GitLab > Create MR."
            exit 1
        }
        $r = Get-GitLabRemote

        # Collect all branch names (local + remote), excluding HEAD and the source branch
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

        # Build WPF picker dialog with search filter
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
            </Grid.ColumnDefinitions>
            <TextBox Name="SearchBox" Grid.Column="0" Height="26"
                     VerticalContentAlignment="Center" Padding="4,0"
                     BorderBrush="#ABADB3" BorderThickness="1,1,0,1"/>
            <Border Grid.Column="1" Width="26" Height="26"
                    Background="#F0F0F0" BorderBrush="#ABADB3" BorderThickness="1">
                <TextBlock Text="&#x1F50D;" HorizontalAlignment="Center"
                           VerticalAlignment="Center" FontSize="13"/>
            </Border>
        </Grid>

        <!-- Filtered branch list -->
        <ListBox Name="BranchList" Grid.Row="14"
                 BorderBrush="#ABADB3" BorderThickness="1"
                 ScrollViewer.VerticalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="12"/>

        <!-- Buttons -->
        <StackPanel Grid.Row="16" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="OkBtn" Content="Open in GitLab"
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
        $script:draftChk       = $script:mrWin.FindName('DraftCheck')
        $script:deleteBranchChk = $script:mrWin.FindName('DeleteBranchCheck')
        $okBtn                 = $script:mrWin.FindName('OkBtn')

        $script:mrWin.FindName('SourceLabel').Text = $Branch
        $script:allBranches = $allBranches

        # Helper: build the standard MR title from source + current target selection
        function Get-MrTitle {
            $target = if ($script:list.SelectedItem) { $script:list.SelectedItem } else { '...' }
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
            $script:list.Items.Clear()
            $matches = if ([string]::IsNullOrWhiteSpace($Filter)) {
                $script:allBranches
            } else {
                $script:allBranches | Where-Object { $_ -like "*$Filter*" }
            }
            foreach ($b in $matches) { [void]$script:list.Items.Add($b) }
            if ($script:list.Items.Count -gt 0) {
                $script:list.SelectedIndex = 0
            }
        }

        # Seed list; pre-select preferred default
        Update-List ''
        $preferred = @('main', 'master', 'develop') |
                     Where-Object { $allBranches -contains $_ } |
                     Select-Object -First 1
        if ($preferred) { $script:list.SelectedItem = $preferred }

        # Filter as user types
        $script:search.Add_TextChanged({
            Update-List $script:search.Text
        })

        # When selection changes, update the title automatically (unless user edited it)
        $script:list.Add_SelectionChanged({
            if (-not $script:titleEdited) {
                $script:updatingTitle = $true
                $script:titleBox.Text = Get-MrTitle
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

        $script:selectedTarget = $null
        $script:updatingTitle  = $false
        $okBtn.Add_Click({
            if ($script:list.SelectedItem) {
                $script:selectedTarget       = $script:list.SelectedItem
                $script:mrWin.DialogResult   = $true
            }
        })

        # Focus the title box on open so user can edit it immediately
        $script:mrWin.Add_Loaded({ $script:titleBox.Focus() | Out-Null ; $script:titleBox.SelectAll() })

        $result = $script:mrWin.ShowDialog()

        if ($result -and -not [string]::IsNullOrWhiteSpace($script:selectedTarget)) {
            $encSource = [Uri]::EscapeDataString($Branch)
            $encTarget = [Uri]::EscapeDataString($script:selectedTarget)
            $encTitle  = [Uri]::EscapeDataString($script:titleBox.Text.Trim())
            $wip       = if ($script:draftChk.IsChecked) { 1 } else { 0 }
            $delBranch = if ($script:deleteBranchChk.IsChecked) { 1 } else { 0 }
            $url = "https://$($r.Host)/$($r.Path)/-/merge_requests/new" +
                   "?merge_request%5Bsource_branch%5D=$encSource" +
                   "&merge_request%5Btarget_branch%5D=$encTarget" +
                   "&merge_request%5Btitle%5D=$encTitle" +
                   "&merge_request%5Bwip%5D=$wip" +
                   "&merge_request%5Bforce_remove_source_branch%5D=$delBranch"
            Start-Process $url
        }
    }
}
