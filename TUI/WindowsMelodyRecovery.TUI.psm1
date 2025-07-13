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
        # Add fields, e.g., TextField for Backup Root
        $backupLabel = New-Object Terminal.Gui.Label -ArgumentList 0, 0, 'Backup Root:'
        $backupField = New-Object Terminal.Gui.TextField -ArgumentList 15, 0, 50, $script:Config.BackupRoot
        $initFrame.Add($backupLabel, $backupField)
        # Add save button
        $saveBtn = New-Object Terminal.Gui.Button 'Save'
        $saveBtn.add_Clicked({
            $script:Config.BackupRoot = $backupField.Text.ToString()
            # Add more fields as needed, e.g., cloud provider dropdown
            # Persist config, e.g., Export-Config or Set-WindowsMelodyRecovery
            Set-WindowsMelodyRecovery -BackupRoot $script:Config.BackupRoot
            [Terminal.Gui.MessageBox]::Query('Saved', 'Configuration updated.', 'OK')
        })
        $initFrame.Add($saveBtn)
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
        } catch {
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
