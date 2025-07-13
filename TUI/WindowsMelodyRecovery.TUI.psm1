<#
.SYNOPSIS
    Displays the main Text User Interface (TUI) for Windows Melody Recovery.
.DESCRIPTION
    Initializes and runs the Terminal.Gui-based user interface, providing an
    interactive way to manage backup and recovery configurations.
.EXAMPLE
    PS C:\> Show-WmrTui
    This command starts the Windows Melody Recovery TUI.
.NOTES
    This function requires the 'Microsoft.PowerShell.ConsoleGuiTools' module.
#>
function Show-WmrTui {
    [CmdletBinding()]
    param()

    try {
        # Import the necessary assembly from the required module
        $module = Get-Module -Name 'Microsoft.PowerShell.ConsoleGuiTools' -ListAvailable
        if ($null -eq $module) {
            throw "Required module 'Microsoft.PowerShell.ConsoleGuiTools' is not installed. Please run: Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools"
        }
        Add-Type -Path (Join-Path $module.ModuleBase 'Terminal.Gui.dll')

        # Initialize the application
        [Terminal.Gui.Application]::Init()

        # Create the top-level window
        $top = [Terminal.Gui.Application]::Top
        $window = [Terminal.Gui.Window]::new()
        $window.Title = "Windows Melody Recovery"

        # Load configuration
        $moduleRoot = (Get-Module WindowsMelodyRecovery.TUI).ModuleBase
        $configPath = Join-Path $moduleRoot '..\Config\scripts-config.json'
        if (-not (Test-Path $configPath)) {
            $configPath = Join-Path $moduleRoot '..\Templates\scripts-config.json'
        }

        try {
            $scriptsConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        }
        catch {
            [Terminal.Gui.MessageBox]::ErrorQuery('Error', 'Failed to load config: ' + $_.Exception.Message, 'OK')
            return
        }

        # Initialize configuration object
        $script:Config = @{
            BackupRoot = 'C:\Backups\WindowsMelodyRecovery'
            MachineName = $env:COMPUTERNAME
            CloudProvider = 'None'
            IsInitialized = $false
            EmailSettings = @{
                ToAddress = ''
            }
            NotificationSettings = @{
                EnableEmail = $false
            }
            BackupSettings = @{
                RetentionDays = 30
                Schedule = 'Weekly'
                EnableScheduled = $false
            }
            LoggingSettings = @{
                Level = 'Information'
                Path = 'logs'
            }
            SharedConfigPath = ''
            UseSharedConfig = $false
            PackageSettings = @{
                EnableVersionPinning = $false
                EnableAutoUpdates = $false
            }
            ModuleVersion = '1.0.0'
        }

        # Create Menu Bar
        $menu = [Terminal.Gui.MenuBar]::new(@(
                [Terminal.Gui.MenuBarItem]::new("_File", @(
                        [Terminal.Gui.MenuItem]::new("_Quit", "Ctrl+Q", { [Terminal.Gui.Application]::RequestStop() })
                    )),
                [Terminal.Gui.MenuBarItem]::new("_Actions", @(
                        [Terminal.Gui.MenuItem]::new("_Backup Selected", "", {
                                $selected = @()
                                foreach ($cat in $categoryNodes.Values) {
                                    foreach ($child in $cat.Children) {
                                        if ($child.Text -match '\[X\]') {
                                            $selected += $child.Tag.name
                                        }
                                    }
                                }
                                if ($selected.Count -gt 0) {
                                    Backup-WindowsMelodyRecovery -Components $selected
                                    [Terminal.Gui.MessageBox]::Query('Backup', 'Backup completed for: ' + ($selected -join ', '), 'OK')
                                }
                            }),
                        [Terminal.Gui.MenuItem]::new("_Restore Selected", "", {
                                $selected = @()
                                foreach ($cat in $categoryNodes.Values) {
                                    foreach ($child in $cat.Children) {
                                        if ($child.Text -match '\[X\]') {
                                            $selected += $child.Tag.name
                                        }
                                    }
                                }
                                if ($selected.Count -gt 0) {
                                    Restore-WindowsMelodyRecovery -Components $selected
                                    [Terminal.Gui.MessageBox]::Query("Restore", "Restoring the following components:`n- $($selected -join "`n- ")", "OK")
                                }
                                else {
                                    [Terminal.Gui.MessageBox]::Query("Restore", "No components selected.", "OK")
                                }
                            })
                    ))
            ))
        $top.Add($menu)

        # Create main content area
        $mainFrame = [Terminal.Gui.FrameView]::new("Components")
        $mainFrame.X = 0
        $mainFrame.Y = 1
        $mainFrame.Width = [Terminal.Gui.Dim]::Fill()
        $mainFrame.Height = [Terminal.Gui.Dim]::Fill(1)

        # Create left pane for component list
        $listPane = [Terminal.Gui.FrameView]::new("Available Components")
        $listPane.X = 0
        $listPane.Y = 0
        $listPane.Width = [Terminal.Gui.Dim]::Percent(50)
        $listPane.Height = [Terminal.Gui.Dim]::Fill()

        # Create right pane for content display
        $contentPane = [Terminal.Gui.FrameView]::new("Configuration")
        $contentPane.X = [Terminal.Gui.Pos]::Percent(50)
        $contentPane.Y = 0
        $contentPane.Width = [Terminal.Gui.Dim]::Percent(50)
        $contentPane.Height = [Terminal.Gui.Dim]::Fill()

        # Create content view
        $contentView = [Terminal.Gui.TextView]::new()
        $contentView.ReadOnly = $true
        $contentView.Width = [Terminal.Gui.Dim]::Fill()
        $contentView.Height = [Terminal.Gui.Dim]::Fill()
        $contentPane.Add($contentView)

        # Build tree structure
        $tree = [Terminal.Gui.TreeView]::new()
        $tree.Width = [Terminal.Gui.Dim]::Fill()
        $tree.Height = [Terminal.Gui.Dim]::Fill()

        # Categories
        $categoryNodes = @{}
        foreach ($category in ($scriptsConfig.categories | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) {
            $categoryNode = [PSCustomObject]@{ Text = $category; Children = @() }
            $categoryNodes[$category] = $categoryNode
            $tree.AddObject($categoryNode)
        }

        # Add items to categories
        foreach ($item in $scriptsConfig.backup.enabled) {
            $cat = $item.category
            if ($categoryNodes.ContainsKey($cat)) {
                $itemNode = [PSCustomObject]@{
                    Text = "$($item.name) $(if($item.enabled){'[X]'}else{'[ ]'})"
                    Tag = $item
                    Children = @()
                }
                $categoryNodes[$cat].Children += $itemNode
            }
        }

        # Add restore/setup items
        foreach ($item in $scriptsConfig.restore.enabled + $scriptsConfig.setup.enabled) {
            $cat = $item.category
            if ($categoryNodes.ContainsKey($cat)) {
                $itemNode = [PSCustomObject]@{
                    Text = "$($item.name) ($(if($item.function.StartsWith('Restore')){'Restore'}else{'Setup'})) $(if($item.enabled){'[X]'}else{'[ ]'})"
                    Tag = $item
                    Children = @()
                }
                $categoryNodes[$cat].Children += $itemNode
            }
        }

        # Toggle enabled on spacebar
        $tree.add_KeyDown({
                if ($_.KeyEvent.Key -eq [Terminal.Gui.Key]::Space) {
                    $selected = $tree.SelectedObject
                    if ($selected.Tag) {
                        $item = $selected.Tag
                        $item.enabled = -not $item.enabled
                        $selected.Text = "$($item.name) $(if($item.enabled){'[X]'}else{'[ ]'})"
                        $tree.RefreshObject($selected, $true)
                    }
                }
            })

        # Update content view on selection
        $tree.add_SelectedObjectChanged({
                param($treeArgs)
                if ($treeArgs.NewValue -and $treeArgs.NewValue.Tag) {
                    $contentView.Text = $treeArgs.NewValue.Tag.description
                }
                else {
                    $contentView.Text = ''
                }
            })

        $listPane.Add($tree)
        $mainFrame.Add($listPane, $contentPane)

        # Create Status Bar
        $statusBar = [Terminal.Gui.StatusBar]::new(@(
                [Terminal.Gui.StatusItem]::new([Terminal.Gui.Key]::CtrlMask -bor [Terminal.Gui.Key]::Q, "~^Q~ Quit", { [Terminal.Gui.Application]::RequestStop() })
            ))
        $top.Add($statusBar)

        # Add Save menu
        $menu.MenuItems[0].Children.Add(
            [Terminal.Gui.MenuItem]::new("_Save Config", "", {
                    $json = $scriptsConfig | ConvertTo-Json -Depth 10
                    Set-Content -Path (Join-Path $moduleRoot '..\Config\scripts-config.json') -Value $json
                    [Terminal.Gui.MessageBox]::Query('Save', 'Configuration saved.', 'OK')
                })
        )

        # Replace mainFrame content with TabView
        $tabView = [Terminal.Gui.TabView]::new()
        $tabView.Width = [Terminal.Gui.Dim]::Fill()
        $tabView.Height = [Terminal.Gui.Dim]::Fill()

        # Tab 1: Components
        $componentsTab = [Terminal.Gui.Tab]::new()
        $componentsTab.Title = 'Components'
        $componentsFrame = [Terminal.Gui.FrameView]::new('Components')
        $componentsFrame.Add($listPane, $contentPane)
        $componentsTab.View = $componentsFrame
        $tabView.AddTab($componentsTab, $true)

        # Tab 2: Initialization Wizard
        $initTab = [Terminal.Gui.Tab]::new()
        $initTab.Title = 'Initialization'
        $initFrame = [Terminal.Gui.FrameView]::new('Setup Wizard')

        # Step 1: Basic Configuration
        $stepLabel = [Terminal.Gui.Label]::new(1, 1, 'Step 1: Basic Configuration')
        $initFrame.Add($stepLabel)

        # Backup Root
        $backupLabel = [Terminal.Gui.Label]::new(1, 3, 'Backup Root:')
        $backupField = [Terminal.Gui.TextField]::new(15, 3, 40, ($script:Config.BackupRoot ?? ''))
        $browseBtn = [Terminal.Gui.Button]::new(57, 3, 'Browse...')
        $browseBtn.add_Clicked({
                $dialog = [Terminal.Gui.MessageBox]::Query('Browse', 'Enter backup path:', 'OK', 'Cancel')
                if ($dialog -eq 0) {
                    $backupField.Text = 'C:\Backups\WindowsMelodyRecovery'
                }
            })
        $initFrame.Add($backupLabel, $backupField, $browseBtn)

        # Machine Name
        $machineLabel = [Terminal.Gui.Label]::new(1, 5, 'Machine Name:')
        $machineField = [Terminal.Gui.TextField]::new(15, 5, 40, ($script:Config.MachineName ?? $env:COMPUTERNAME))
        $initFrame.Add($machineLabel, $machineField)

        # Cloud Provider
        $cloudLabel = [Terminal.Gui.Label]::new(1, 7, 'Cloud Provider:')
        $cloudCombo = [Terminal.Gui.ComboBox]::new(15, 7, 40, @('None', 'OneDrive', 'OneDrive for Business', 'Google Drive', 'Dropbox', 'Custom'))
        $cloudCombo.SelectedItem = $script:Config.CloudProvider ?? 'None'
        $autoDetectBtn = [Terminal.Gui.Button]::new(57, 7, 'Auto-Detect')
        $autoDetectBtn.add_Clicked({
                $detected = @()
                if (Test-Path "$env:USERPROFILE\OneDrive") { $detected += 'OneDrive' }
                if (Test-Path "$env:USERPROFILE\OneDrive - *") { $detected += 'OneDrive for Business' }
                if (Test-Path "$env:USERPROFILE\Google Drive") { $detected += 'Google Drive' }
                if (Test-Path "$env:USERPROFILE\Dropbox") { $detected += 'Dropbox' }

                if ($detected.Count -gt 0) {
                    $cloudCombo.SelectedItem = $detected[0]
                    [Terminal.Gui.MessageBox]::Query('Detected', "Found: $($detected -join ', ')", 'OK')
                }
                else {
                    [Terminal.Gui.MessageBox]::Query('Not Found', 'No cloud providers detected', 'OK')
                }
            })
        $initFrame.Add($cloudLabel, $cloudCombo, $autoDetectBtn)

        # Advanced Configuration
        $advancedLabel = [Terminal.Gui.Label]::new(1, 9, 'Step 2: Advanced Configuration (Optional)')
        $initFrame.Add($advancedLabel)

        # Email Settings
        $emailLabel = [Terminal.Gui.Label]::new(1, 11, 'Email Notifications:')
        $emailField = [Terminal.Gui.TextField]::new(20, 11, 35, ($script:Config.EmailSettings.ToAddress ?? ''))
        $emailCheck = [Terminal.Gui.CheckBox]::new(57, 11, 'Enable')
        $emailCheck.Checked = $script:Config.NotificationSettings.EnableEmail
        $initFrame.Add($emailLabel, $emailField, $emailCheck)

        # Retention Days
        $retentionLabel = [Terminal.Gui.Label]::new(1, 13, 'Retention (Days):')
        $retentionField = [Terminal.Gui.TextField]::new(20, 13, 10, ($script:Config.BackupSettings.RetentionDays.ToString()))
        $initFrame.Add($retentionLabel, $retentionField)

        # Logging Level
        $logLabel = [Terminal.Gui.Label]::new(35, 13, 'Logging Level:')
        $logCombo = [Terminal.Gui.ComboBox]::new(50, 13, 15, @('Error', 'Warning', 'Information', 'Verbose', 'Debug'))
        $logCombo.SelectedItem = $script:Config.LoggingSettings.Level ?? 'Information'
        $initFrame.Add($logLabel, $logCombo)

        # Backup Schedule
        $scheduleLabel = [Terminal.Gui.Label]::new(1, 15, 'Backup Schedule:')
        $scheduleCombo = [Terminal.Gui.ComboBox]::new(20, 15, 20, @('Manual', 'Daily', 'Weekly', 'Monthly'))
        $scheduleCombo.SelectedItem = $script:Config.BackupSettings.Schedule ?? 'Weekly'
        $scheduleCheck = [Terminal.Gui.CheckBox]::new(42, 15, 'Enable Auto-Backup')
        $scheduleCheck.Checked = $script:Config.BackupSettings.EnableScheduled
        $initFrame.Add($scheduleLabel, $scheduleCombo, $scheduleCheck)

        # Shared Configuration
        $sharedLabel = [Terminal.Gui.Label]::new(1, 17, 'Shared Config Path:')
        $sharedField = [Terminal.Gui.TextField]::new(20, 17, 35, ($script:Config.SharedConfigPath ?? ''))
        $sharedCheck = [Terminal.Gui.CheckBox]::new(57, 17, 'Use Shared')
        $sharedCheck.Checked = $script:Config.UseSharedConfig
        $initFrame.Add($sharedLabel, $sharedField, $sharedCheck)

        # Version Pinning
        $versionLabel = [Terminal.Gui.Label]::new(1, 19, 'Version Pinning:')
        $versionCheck = [Terminal.Gui.CheckBox]::new(20, 19, 'Pin Package Versions')
        $versionCheck.Checked = $script:Config.PackageSettings.EnableVersionPinning
        $updateCheck = [Terminal.Gui.CheckBox]::new(42, 19, 'Auto-Update Packages')
        $updateCheck.Checked = $script:Config.PackageSettings.EnableAutoUpdates
        $initFrame.Add($versionLabel, $versionCheck, $updateCheck)

        # Wizard Navigation
        $saveBtn = [Terminal.Gui.Button]::new(1, 22, 'Save & Initialize')
        $saveBtn.add_Clicked({
                $errors = @()

                if ([string]::IsNullOrWhiteSpace($backupField.Text)) {
                    $errors += 'Backup Root is required'
                }

                if ($emailCheck.Checked -and -not [string]::IsNullOrWhiteSpace($emailField.Text)) {
                    if ($emailField.Text -notmatch '^[^@]+@[^@]+\.[^@]+$') {
                        $errors += 'Email address format is invalid'
                    }
                }

                try {
                    $retentionDays = [int]$retentionField.Text
                    if ($retentionDays -le 0 -or $retentionDays -gt 365) {
                        $errors += 'Retention days must be between 1-365'
                    }
                }
                catch {
                    $errors += 'Retention days must be a valid number'
                }

                if ($sharedCheck.Checked -and -not [string]::IsNullOrWhiteSpace($sharedField.Text)) {
                    if (-not (Test-Path $sharedField.Text)) {
                        $errors += 'Shared configuration path does not exist'
                    }
                }

                if ($errors.Count -gt 0) {
                    [Terminal.Gui.MessageBox]::ErrorQuery('Validation Error', ($errors -join "`n"), 'OK')
                    return
                }

                # Update configuration
                $script:Config.BackupRoot = $backupField.Text.ToString()
                $script:Config.MachineName = $machineField.Text.ToString()
                $script:Config.CloudProvider = $cloudCombo.SelectedItem.ToString()
                $script:Config.EmailSettings.ToAddress = $emailField.Text.ToString()
                $script:Config.NotificationSettings.EnableEmail = $emailCheck.Checked
                $script:Config.BackupSettings.RetentionDays = [int]$retentionField.Text.ToString()
                $script:Config.LoggingSettings.Level = $logCombo.SelectedItem.ToString()
                $script:Config.BackupSettings.Schedule = $scheduleCombo.SelectedItem.ToString()
                $script:Config.BackupSettings.EnableScheduled = $scheduleCheck.Checked
                $script:Config.SharedConfigPath = $sharedField.Text.ToString()
                $script:Config.UseSharedConfig = $sharedCheck.Checked
                $script:Config.PackageSettings.EnableVersionPinning = $versionCheck.Checked
                $script:Config.PackageSettings.EnableAutoUpdates = $updateCheck.Checked

                try {
                    Set-WindowsMelodyRecovery -BackupRoot $script:Config.BackupRoot -CloudProvider $script:Config.CloudProvider -MachineName $script:Config.MachineName
                    $script:Config.IsInitialized = $true
                    [Terminal.Gui.MessageBox]::Query('Success', 'Configuration saved and module initialized!', 'OK')
                }
                catch {
                    [Terminal.Gui.MessageBox]::ErrorQuery('Error', "Failed to save configuration: $($_.Exception.Message)", 'OK')
                }
            })

        $testBtn = [Terminal.Gui.Button]::new(20, 22, 'Test Configuration')
        $testBtn.add_Clicked({
                $results = @()

                if (Test-Path $backupField.Text) {
                    $results += "✓ Backup path accessible"
                }
                else {
                    $results += "✗ Backup path not found"
                }

                if ($cloudCombo.SelectedItem -ne 'None') {
                    $cloudPath = switch ($cloudCombo.SelectedItem) {
                        'OneDrive' { "$env:USERPROFILE\OneDrive" }
                        'Google Drive' { "$env:USERPROFILE\Google Drive" }
                        'Dropbox' { "$env:USERPROFILE\Dropbox" }
                        default { $null }
                    }

                    if ($cloudPath -and (Test-Path $cloudPath)) {
                        $results += "✓ Cloud provider accessible"
                    }
                    else {
                        $results += "✗ Cloud provider not accessible"
                    }
                }

                if ($emailCheck.Checked -and -not [string]::IsNullOrWhiteSpace($emailField.Text)) {
                    if ($emailField.Text -match '^[^@]+@[^@]+\.[^@]+$') {
                        $results += "✓ Email address format valid"
                    }
                    else {
                        $results += "✗ Email address format invalid"
                    }
                }

                if ($sharedCheck.Checked -and -not [string]::IsNullOrWhiteSpace($sharedField.Text)) {
                    if (Test-Path $sharedField.Text) {
                        $results += "✓ Shared configuration path accessible"
                    }
                    else {
                        $results += "✗ Shared configuration path not found"
                    }
                }

                try {
                    $retentionDays = [int]$retentionField.Text
                    if ($retentionDays -gt 0 -and $retentionDays -le 365) {
                        $results += "✓ Retention days valid ($retentionDays days)"
                    }
                    else {
                        $results += "✗ Retention days should be between 1-365"
                    }
                }
                catch {
                    $results += "✗ Retention days must be a number"
                }

                $results += "✓ Logging level: $($logCombo.SelectedItem)"

                if ($scheduleCheck.Checked) {
                    $results += "✓ Auto-backup enabled: $($scheduleCombo.SelectedItem)"
                }
                else {
                    $results += "○ Auto-backup disabled"
                }

                [Terminal.Gui.MessageBox]::Query('Test Results', ($results -join "`n"), 'OK')
            })

        $resetBtn = [Terminal.Gui.Button]::new(40, 22, 'Reset to Defaults')
        $resetBtn.add_Clicked({
                $backupField.Text = "C:\Backups\WindowsMelodyRecovery"
                $machineField.Text = $env:COMPUTERNAME
                $cloudCombo.SelectedItem = 'None'
                $emailField.Text = ''
                $emailCheck.Checked = $false
                $retentionField.Text = '30'
                $logCombo.SelectedItem = 'Information'
                $scheduleCombo.SelectedItem = 'Weekly'
                $scheduleCheck.Checked = $false
                $sharedField.Text = ''
                $sharedCheck.Checked = $false
                $versionCheck.Checked = $false
                $updateCheck.Checked = $false
            })

        $initFrame.Add($saveBtn, $testBtn, $resetBtn)
        $initTab.View = $initFrame
        $tabView.AddTab($initTab, $false)

        # Tab 3: Status
        $statusTab = [Terminal.Gui.Tab]::new()
        $statusTab.Title = 'Status'
        $statusFrame = [Terminal.Gui.FrameView]::new('System Status')
        $statusText = [Terminal.Gui.TextView]::new()
        $statusText.ReadOnly = $true
        $statusText.Text = "Module Initialized: $($script:Config.IsInitialized)
Last Backup: $(try { Get-Content (Join-Path $script:Config.LoggingSettings.Path 'last_backup.log') } catch { 'N/A' })
Machine: $($script:Config.MachineName)
Cloud Provider: $($script:Config.CloudProvider)
Backup Root: $($script:Config.BackupRoot)

Advanced Settings:
- Email Notifications: $(if($script:Config.NotificationSettings.EnableEmail){'Enabled'}else{'Disabled'})
- Email Address: $($script:Config.EmailSettings.ToAddress)
- Logging Level: $($script:Config.LoggingSettings.Level)
- Retention Days: $($script:Config.BackupSettings.RetentionDays)
- Auto-Backup: $(if($script:Config.BackupSettings.EnableScheduled){'Enabled'}else{'Disabled'}) ($($script:Config.BackupSettings.Schedule))
- Shared Config: $(if($script:Config.UseSharedConfig){'Enabled'}else{'Disabled'})
- Version Pinning: $(if($script:Config.PackageSettings.EnableVersionPinning){'Enabled'}else{'Disabled'})
- Auto-Updates: $(if($script:Config.PackageSettings.EnableAutoUpdates){'Enabled'}else{'Disabled'})

Module Version: $($script:Config.ModuleVersion ?? 'Unknown')
PowerShell Version: $($PSVersionTable.PSVersion)
Operating System: $($PSVersionTable.OS)"

        $refreshBtn = [Terminal.Gui.Button]::new(1, 1, 'Refresh Status')
        $refreshBtn.add_Clicked({
                $statusText.Text = "Module Initialized: $($script:Config.IsInitialized)
Last Backup: $(try { Get-Content (Join-Path $script:Config.LoggingSettings.Path 'last_backup.log') } catch { 'N/A' })
Machine: $($script:Config.MachineName)
Cloud Provider: $($script:Config.CloudProvider)
Backup Root: $($script:Config.BackupRoot)

Advanced Settings:
- Email Notifications: $(if($script:Config.NotificationSettings.EnableEmail){'Enabled'}else{'Disabled'})
- Email Address: $($script:Config.EmailSettings.ToAddress)
- Logging Level: $($script:Config.LoggingSettings.Level)
- Retention Days: $($script:Config.BackupSettings.RetentionDays)
- Auto-Backup: $(if($script:Config.BackupSettings.EnableScheduled){'Enabled'}else{'Disabled'}) ($($script:Config.BackupSettings.Schedule))
- Shared Config: $(if($script:Config.UseSharedConfig){'Enabled'}else{'Disabled'})
- Version Pinning: $(if($script:Config.PackageSettings.EnableVersionPinning){'Enabled'}else{'Disabled'})
- Auto-Updates: $(if($script:Config.PackageSettings.EnableAutoUpdates){'Enabled'}else{'Disabled'})

Module Version: $($script:Config.ModuleVersion ?? 'Unknown')
PowerShell Version: $($PSVersionTable.PSVersion)
Operating System: $($PSVersionTable.OS)"
            })

        $statusFrame.Add($statusText, $refreshBtn)
        $statusTab.View = $statusFrame
        $tabView.AddTab($statusTab, $false)
        $window.Add($tabView)

        # Refresh tree to show all items
        $tree.RefreshObject($true)

        # Check for updates
        $repo = 'yourusername/WindowsMelodyRecovery'
        try {
            $latest = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
            if ($latest.tag_name -gt $script:Config.ModuleVersion) {
                [Terminal.Gui.MessageBox]::Query('Update Available', "New version $($latest.tag_name) available!", 'OK')
            }
        }
        catch {
            Write-Verbose "Update check failed: $($_.Exception.Message)"
        }

        # System tray (Windows only)
        if ($PSVersionTable.OS -like '*Windows*') {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $tray = [System.Windows.Forms.NotifyIcon]::new()
                $tray.Icon = [System.Drawing.SystemIcons]::Information
                $tray.Text = 'WMR TUI'
                $tray.Visible = $true
                $tray.add_Click({ Show-WmrTui })
            }
            catch {
                Write-Verbose "System tray initialization failed: $($_.Exception.Message)"
            }
        }

        # Add the window to the application's top-level view and run it
        $top.Add($window)
        [Terminal.Gui.Application]::Run()
    }
    catch {
        Write-Error "TUI initialization failed: $($_.Exception.Message)"
        throw
    }
    finally {
        # Cleanup
        try {
            [Terminal.Gui.Application]::Shutdown()
        }
        catch {
            Write-Verbose "TUI shutdown cleanup failed: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Show-WmrTui
