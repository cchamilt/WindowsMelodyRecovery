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
                                        if ($child.Text -match '\[X\]') { $selected += $child.Tag.name }
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
                                        if ($child.Text -match '\[X\]') { $selected += $child.Tag.name }
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

        # Create Main Content Frame
        $mainFrame = [Terminal.Gui.FrameView]::new("Components")
        $mainFrame.X = 0
        $mainFrame.Y = 1 # Position below the menu bar
        $mainFrame.Width = [Terminal.Gui.Dim]::Fill()
        $mainFrame.Height = [Terminal.Gui.Dim]::Fill() - 1 # Leave space for status bar
        $window.Add($mainFrame)

        # Get component names from the template files
        $templatePath = Join-Path $PSScriptRoot '..\\Templates\\System'
        $componentFiles = Get-ChildItem -Path $templatePath -Filter *.yaml
        $componentNames = $componentFiles | ForEach-Object { $_.BaseName }

        # Create a container for the component list and the content view
        $listPane = [Terminal.Gui.FrameView]::new("Components")
        $listPane.Width = [Terminal.Gui.Dim]::Percent(30)
        $listPane.Height = [Terminal.Gui.Dim]::Fill()

        $contentPane = [Terminal.Gui.FrameView]::new("Content")
        $contentPane.X = [Terminal.Gui.Pos]::Right($listPane)
        $contentPane.Width = [Terminal.Gui.Dim]::Fill()
        $contentPane.Height = [Terminal.Gui.Dim]::Fill()

        # Create a ListView for the components
        $componentList = [Terminal.Gui.ListView]::new($componentNames)
        $componentList.Width = [Terminal.Gui.Dim]::Fill()
        $componentList.Height = [Terminal.Gui.Dim]::Fill()
        $componentList.AllowsMarking = $true # Allows checking items

        # Create a TextView for the file content
        $contentView = [Terminal.Gui.TextView]::new()
        $contentView.Width = [Terminal.Gui.Dim]::Fill()
        $contentView.Height = [Terminal.Gui.Dim]::Fill()
        $contentView.ReadOnly = $true

        $componentList.add_SelectedItemChanged(
            {
                param($listArgs)
                if ($null -ne $listArgs.Value) {
                    $selectedComponent = $listArgs.Value.ToString()
                    $filePath = Join-Path $templatePath "$selectedComponent.yaml"
                    if (Test-Path $filePath) {
                        $contentView.Text = [System.IO.File]::ReadAllText($filePath)
                    }
                }
            }
        )

        $listPane.Add($componentList)
        $contentPane.Add($contentView)
        $mainFrame.Add($listPane, $contentPane)

        # Create Status Bar
        $statusBar = [Terminal.Gui.StatusBar]::new(@(
                [Terminal.Gui.StatusItem]::new([Terminal.Gui.Key]::CtrlMask -bor [Terminal.Gui.Key]::Q, "~^Q~ Quit", { [Terminal.Gui.Application]::RequestStop() })
            ))
        $top.Add($statusBar)

        # Load configuration
        $moduleRoot = (Get-Module WindowsMelodyRecovery.TUI).ModuleBase
        $configPath = Join-Path $moduleRoot '..\\Config\\scripts-config.json'
        if (-not (Test-Path $configPath)) {
            $configPath = Join-Path $moduleRoot '..\\Templates\\scripts-config.json'
        }
        $scriptsConfig = Get-Content $configPath -Raw | ConvertFrom-Json

        # Build tree structure
        $tree = New-Object Terminal.Gui.TreeView
        $tree.Width = [Terminal.Gui.Dim]::Fill()
        $tree.Height = [Terminal.Gui.Dim]::Fill()
        $tree.TreeBuilder = {
            param($node)
            $children = @()
            return $children
        } # Custom builder if needed, but perhaps build manually

        # Categories
        $categoryNodes = @{}
        foreach ($category in ($scriptsConfig.categories | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) {
            $categoryNode = [PSCustomObject]@{ Text = $category; Children = @() }
            $categoryNodes[$category] = $categoryNode
            $tree.AddObject($categoryNode)
        }

        # Add items to categories (using backup as example, or combine)
        foreach ($item in $scriptsConfig.backup.enabled) {
            $cat = $item.category
            if ($categoryNodes.ContainsKey($cat)) {
                $itemNode = [PSCustomObject]@{ Text = "$($item.name) $(if($item.enabled){'[X]'}else{'[ ]'})"; Tag = $item; Children = @() }
                $categoryNodes[$cat].Children += $itemNode
            }
        }
        # Similarly for restore and setup if needed

        # Toggle enabled on select or key
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

        $tree.add_SelectedObjectChanged({
                param($treeArgs)
                if ($treeArgs.NewValue -and $treeArgs.NewValue.Tag) {
                    $contentView.Text = $treeArgs.NewValue.Tag.description
                }
                else {
                    $contentView.Text = ''
                }
            })

        # Replace componentList with tree
        $listPane.Add($tree)

        # Add Save menu
        $menu.MenuItems[0].Children.Add(
            [Terminal.Gui.MenuItem]::new("_Save Config", "", {
                    $json = $scriptsConfig | ConvertTo-Json -Depth 10
                    Set-Content -Path (Join-Path $moduleRoot '..\\Config\\scripts-config.json') -Value $json
                    [Terminal.Gui.MessageBox]::Query('Save', 'Configuration saved.', 'OK')
                })
        )

        # Update actions to use actual calls
        # For backup:
        # Collect enabled from config, but since TUI edits in memory, perhaps save first or pass list
        # For now, mock with message, but add call to Backup-WindowsMelodyRecovery -Components $selectedItems

        # Replace mainFrame content with TabView
        $tabView = New-Object Terminal.Gui.TabView
        $tabView.Width = [Terminal.Gui.Dim]::Fill()
        $tabView.Height = [Terminal.Gui.Dim]::Fill()

        # Tab 1: Components (existing)
        $componentsTab = New-Object Terminal.Gui.Tab
        $componentsTab.Title = 'Components'
        $componentsTab.View = $mainFrame  # Reuse existing, but mainFrame is FrameView, adjust
        # Actually, move listPane and contentPane into a new FrameView for tab
        $componentsFrame = New-Object Terminal.Gui.FrameView 'Components'
        $componentsFrame.Add($listPane, $contentPane)
        $componentsTab.View = $componentsFrame
        $tabView.AddTab($componentsTab, $true)

        # Tab 2: Initialization Wizard
        $initTab = New-Object Terminal.Gui.Tab
        $initTab.Title = 'Initialization'
        $initFrame = New-Object Terminal.Gui.FrameView 'Setup Wizard'

        # Step 1: Basic Configuration
        $stepLabel = New-Object Terminal.Gui.Label -ArgumentList 1,1,'Step 1: Basic Configuration'
        $initFrame.Add($stepLabel)

        # Backup Root
        $backupLabel = New-Object Terminal.Gui.Label -ArgumentList 1,3,'Backup Root:'
        $backupField = New-Object Terminal.Gui.TextField -ArgumentList 15,3,40,($script:Config.BackupRoot ?? '')
        $browseBtn = New-Object Terminal.Gui.Button -ArgumentList 57,3,'Browse...'
        $browseBtn.add_Clicked({
            # Simple file dialog simulation - in real implementation use OpenFileDialog
            $dialog = [Terminal.Gui.MessageBox]::Query('Browse', 'Enter backup path:', 'OK', 'Cancel')
            if ($dialog -eq 0) {
                # In real implementation, show file browser
                $backupField.Text = 'C:\Backups\WindowsMelodyRecovery'
            }
        })
        $initFrame.Add($backupLabel, $backupField, $browseBtn)

        # Machine Name
        $machineLabel = New-Object Terminal.Gui.Label -ArgumentList 1,5,'Machine Name:'
        $machineField = New-Object Terminal.Gui.TextField -ArgumentList 15,5,40,($script:Config.MachineName ?? $env:COMPUTERNAME)
        $initFrame.Add($machineLabel, $machineField)

        # Cloud Provider
        $cloudLabel = New-Object Terminal.Gui.Label -ArgumentList 1,7,'Cloud Provider:'
        $cloudCombo = New-Object Terminal.Gui.ComboBox -ArgumentList 15,7,40,@('None', 'OneDrive', 'OneDrive for Business', 'Google Drive', 'Dropbox', 'Custom')
        $cloudCombo.SelectedItem = $script:Config.CloudProvider ?? 'None'
        $autoDetectBtn = New-Object Terminal.Gui.Button -ArgumentList 57,7,'Auto-Detect'
        $autoDetectBtn.add_Clicked({
            # Auto-detect cloud providers
            $detected = @()
            if (Test-Path "$env:USERPROFILE\OneDrive") { $detected += 'OneDrive' }
            if (Test-Path "$env:USERPROFILE\OneDrive - *") { $detected += 'OneDrive for Business' }
            if (Test-Path "$env:USERPROFILE\Google Drive") { $detected += 'Google Drive' }
            if (Test-Path "$env:USERPROFILE\Dropbox") { $detected += 'Dropbox' }

            if ($detected.Count -gt 0) {
                $cloudCombo.SelectedItem = $detected[0]
                [Terminal.Gui.MessageBox]::Query('Detected', "Found: $($detected -join ', ')", 'OK')
            } else {
                [Terminal.Gui.MessageBox]::Query('Not Found', 'No cloud providers detected', 'OK')
            }
        })
        $initFrame.Add($cloudLabel, $cloudCombo, $autoDetectBtn)

        # Step 2: Advanced Configuration (collapsible)
        $advancedLabel = New-Object Terminal.Gui.Label -ArgumentList 1,9,'Step 2: Advanced Configuration (Optional)'
        $initFrame.Add($advancedLabel)

        # Email Settings
        $emailLabel = New-Object Terminal.Gui.Label -ArgumentList 1,11,'Email Notifications:'
        $emailField = New-Object Terminal.Gui.TextField -ArgumentList 20,11,35,($script:Config.EmailSettings.ToAddress ?? '')
        $emailCheck = New-Object Terminal.Gui.CheckBox -ArgumentList 57,11,'Enable'
        $emailCheck.Checked = $script:Config.NotificationSettings.EnableEmail
        $initFrame.Add($emailLabel, $emailField, $emailCheck)

        # Retention Days
        $retentionLabel = New-Object Terminal.Gui.Label -ArgumentList 1,13,'Retention (Days):'
        $retentionField = New-Object Terminal.Gui.TextField -ArgumentList 20,13,10,($script:Config.BackupSettings.RetentionDays.ToString())
        $initFrame.Add($retentionLabel, $retentionField)

        # Wizard Navigation
        $saveBtn = New-Object Terminal.Gui.Button -ArgumentList 1,16,'Save & Initialize'
        $saveBtn.add_Clicked({
            # Validate and save configuration
            $errors = @()

            if ([string]::IsNullOrWhiteSpace($backupField.Text)) {
                $errors += 'Backup Root is required'
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

            # Persist configuration
            try {
                Set-WindowsMelodyRecovery -BackupRoot $script:Config.BackupRoot -CloudProvider $script:Config.CloudProvider -MachineName $script:Config.MachineName
                $script:Config.IsInitialized = $true
                [Terminal.Gui.MessageBox]::Query('Success', 'Configuration saved and module initialized!', 'OK')
            } catch {
                [Terminal.Gui.MessageBox]::ErrorQuery('Error', "Failed to save configuration: $($_.Exception.Message)", 'OK')
            }
        })

        $testBtn = New-Object Terminal.Gui.Button -ArgumentList 20,16,'Test Configuration'
        $testBtn.add_Clicked({
            # Test backup path, cloud connectivity, etc.
            $results = @()

            if (Test-Path $backupField.Text) {
                $results += "✓ Backup path accessible"
            } else {
                $results += "✗ Backup path not found"
            }

            if ($cloudCombo.SelectedItem -ne 'None') {
                # Test cloud path based on selection
                $cloudPath = switch ($cloudCombo.SelectedItem) {
                    'OneDrive' { "$env:USERPROFILE\OneDrive" }
                    'Google Drive' { "$env:USERPROFILE\Google Drive" }
                    'Dropbox' { "$env:USERPROFILE\Dropbox" }
                    default { $null }
                }

                if ($cloudPath -and (Test-Path $cloudPath)) {
                    $results += "✓ Cloud provider accessible"
                } else {
                    $results += "✗ Cloud provider not accessible"
                }
            }

            [Terminal.Gui.MessageBox]::Query('Test Results', ($results -join "`n"), 'OK')
        })

        $resetBtn = New-Object Terminal.Gui.Button -ArgumentList 40,16,'Reset to Defaults'
        $resetBtn.add_Clicked({
            $backupField.Text = "C:\Backups\WindowsMelodyRecovery"
            $machineField.Text = $env:COMPUTERNAME
            $cloudCombo.SelectedItem = 'None'
            $emailField.Text = ''
            $emailCheck.Checked = $false
            $retentionField.Text = '30'
        })

        $initFrame.Add($saveBtn, $testBtn, $resetBtn)
        $initTab.View = $initFrame
        $tabView.AddTab($initTab, $false)

        # Tab 3: Status
        $statusTab = New-Object Terminal.Gui.Tab
        $statusTab.Title = 'Status'
        $statusFrame = New-Object Terminal.Gui.FrameView 'System Status'
        $statusText = New-Object Terminal.Gui.TextView
        $statusText.Text = "Module Initialized: $($script:Config.IsInitialized)
Last Backup: $(try { Get-Content (Join-Path $script:Config.LoggingSettings.Path 'last_backup.log') } catch { 'N/A' })
Machine: $($script:Config.MachineName)
Cloud: $($script:Config.CloudProvider)"
        $statusFrame.Add($statusText)
        $statusTab.View = $statusFrame
        $tabView.AddTab($statusTab, $false)
        $window.Add($tabView)

        # Update tree to include restore/setup
        foreach ($item in $scriptsConfig.restore.enabled + $scriptsConfig.setup.enabled) {
            $cat = $item.category
            if ($categoryNodes.ContainsKey($cat)) {
                $itemNode = [PSCustomObject]@{ Text = "$($item.name) ($(if($item.function.StartsWith('Restore')){'Restore'}else{'Setup'})) $(if($item.enabled){'[X]'}else{'[ ]'})"; Tag = $item; Children = @() }
                $categoryNodes[$cat].Children += $itemNode
            }
        }
        $tree.RefreshObject($true)

        # Add update check
        $repo = 'yourusername/WindowsMelodyRecovery'  # Update with actual
        try {
            $latest = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
            if ($latest.tag_name -gt $script:Config.ModuleVersion) {
                [Terminal.Gui.MessageBox]::Query('Update Available', "New version $($latest.tag_name) available!", 'OK')
            }
        }
        catch {
            Write-Verbose "Update check failed: $_.Exception.Message"
        }

        # Systray (Windows only)
        if ($PSVersionTable.OS -like '*Windows*') {
            Add-Type -AssemblyName System.Windows.Forms
            $tray = New-Object System.Windows.Forms.NotifyIcon
            $tray.Icon = [System.Drawing.SystemIcons]::Information
            $tray.Text = 'WMR TUI'
            $tray.Visible = $true
            $tray.add_Click({ Show-WmrTui })
            # Note: This keeps the process running; perhaps in a separate function
        }

        # Enhance error handling, e.g., around config load
        try { $scriptsConfig = ... } catch { [Terminal.Gui.MessageBox]::ErrorQuery('Error', 'Failed to load config: ' + $_.Exception.Message, 'OK') }

        # Add the window to the application's top-level view and run it
        $top.Add($window)
        [Terminal.Gui.Application]::Run()
    }
    catch {
        Write-Error "Failed to start the TUI. Error: $_"
    }
    finally {
        # Ensure the application is properly shut down
        [Terminal.Gui.Application]::Shutdown()
    }
}

Export-ModuleMember -Function Show-WmrTui
