# Setup-ApplicationDiscovery.ps1 - Configure application discovery and management workflows

<#
.SYNOPSIS
    Configure application discovery and management workflows for Windows Melody Recovery.

.DESCRIPTION
    This script provides functionality to:
    - Discover unmanaged applications not tracked by package managers
    - Document application installation methods and sources
    - Create and manage user-editable application and game lists
    - Configure application installation/uninstallation decision workflows

.PARAMETER DiscoveryMode
    Mode for application discovery: 'Full', 'Quick', 'Manual'

.PARAMETER OutputFormat
    Output format for application lists: 'JSON', 'CSV', 'YAML'

.PARAMETER UserListPath
    Path to user-editable application list file

.PARAMETER CreateUserLists
    Create user-editable application and game lists

.PARAMETER DocumentInstallation
    Document installation methods for discovered applications

.EXAMPLE
    Setup-ApplicationDiscovery -DiscoveryMode Full -CreateUserLists

.EXAMPLE
    Setup-ApplicationDiscovery -DocumentInstallation -OutputFormat CSV

.NOTES
    Requires administrative privileges for full system application discovery.
    Part of Windows Melody Recovery module.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Full', 'Quick', 'Manual')]
    [string]$DiscoveryMode = 'Quick',

    [Parameter(Mandatory=$false)]
    [ValidateSet('JSON', 'CSV', 'YAML')]
    [string]$OutputFormat = 'JSON',

    [Parameter(Mandatory=$false)]
    [string]$UserListPath = $null,

    [Parameter(Mandatory=$false)]
    [switch]$CreateUserLists,

    [Parameter(Mandatory=$false)]
    [switch]$DocumentInstallation
)

# Import required modules and functions
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Split-Path -Parent (Split-Path -Parent $scriptPath)

# Load core utilities
$coreUtilitiesPath = Join-Path $modulePath "Private\Core\WindowsMelodyRecovery.Core.ps1"
if (Test-Path $coreUtilitiesPath) {
    . $coreUtilitiesPath
} else {
    Write-Warning "Core utilities not found at: $coreUtilitiesPath"
}

# Load environment configuration
$loadEnvPath = Join-Path $modulePath "Private\scripts\Import-Environment.ps1"
if (Test-Path $loadEnvPath) {
    . $loadEnvPath
} else {
    Write-Warning "Load environment script not found at: $loadEnvPath"
}

function Setup-ApplicationDiscovery {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Full', 'Quick', 'Manual')]
        [string]$DiscoveryMode = 'Quick',

        [Parameter(Mandatory=$false)]
        [ValidateSet('JSON', 'CSV', 'YAML')]
        [string]$OutputFormat = 'JSON',

        [Parameter(Mandatory=$false)]
        [string]$UserListPath = $null,

        [Parameter(Mandatory=$false)]
        [switch]$CreateUserLists,

        [Parameter(Mandatory=$false)]
        [switch]$DocumentInstallation
    )

    begin {
        Write-Information -MessageData "Setting up Application Discovery and Management..." -InformationAction Continue

        # Check if running as administrator for full discovery
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

        if ($DiscoveryMode -eq 'Full' -and -not $isAdmin) {
            Write-Warning "Full discovery mode requires administrator privileges. Switching to Quick mode."
            $DiscoveryMode = 'Quick'
        }

        # Get module configuration
        try {
            $config = Get-WindowsMelodyRecovery
            if (-not $config.IsInitialized) {
                throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
            }
            $backupRoot = $config.BackupRoot
            $machineName = $config.MachineName
        } catch {
            Write-Warning "Module configuration not available. Using defaults."
            $backupRoot = "$env:USERPROFILE\WindowsMelodyRecovery"
            $machineName = $env:COMPUTERNAME
        }

        # Set up output paths
        $outputPath = Join-Path $backupRoot $machineName "ApplicationDiscovery"
        if (-not (Test-Path $outputPath)) {
            New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
        }

        if (-not $UserListPath) {
            $UserListPath = Join-Path $outputPath "user-editable-apps.$($OutputFormat.ToLower())"
        }
    }

    process {
        try {
            # Step 1: Discover unmanaged applications
            Write-Information -MessageData "Step 1: Discovering unmanaged applications..." -InformationAction Continue
            $unmanagedApps = Invoke-UnmanagedApplicationDiscovery -Mode $DiscoveryMode

            if ($unmanagedApps) {
                Write-Information -MessageData "Found $($unmanagedApps.Count) unmanaged applications" -InformationAction Continue

                # Save unmanaged applications list
                $unmanagedPath = Join-Path $outputPath "unmanaged-applications.$($OutputFormat.ToLower())"
                Save-ApplicationList -Applications $unmanagedApps -Path $unmanagedPath -Format $OutputFormat
            } else {
                Write-Warning -Message "No unmanaged applications found or discovery was skipped"
            }

            # Step 2: Document installation methods
            if ($DocumentInstallation) {
                Write-Information -MessageData "Step 2: Documenting installation methods..." -InformationAction Continue
                $installationDocs = New-InstallationDocumentation -Applications $unmanagedApps

                if ($installationDocs) {
                    $docsPath = Join-Path $outputPath "installation-documentation.$($OutputFormat.ToLower())"
                    Save-InstallationDocumentation -Documentation $installationDocs -Path $docsPath -Format $OutputFormat
                    Write-Information -MessageData "Installation documentation saved to: $docsPath" -InformationAction Continue
                }
            }

            # Step 3: Create user-editable lists
            if ($CreateUserLists) {
                Write-Information -MessageData "Step 3: Creating user-editable application lists..." -InformationAction Continue
                New-UserEditableApplicationLists -OutputPath $outputPath -Format $OutputFormat
            }

            # Step 4: Configure decision workflows
            Write-Information -MessageData "Step 4: Configuring application management workflows..." -InformationAction Continue
            Initialize-ApplicationDecisionWorkflows -OutputPath $outputPath

            Write-Information -MessageData "Application discovery and management setup completed successfully!" -InformationAction Continue
            return $true

        } catch {
            Write-Error "Failed to setup application discovery: $_"
            return $false
        }
    }
}

function Invoke-UnmanagedApplicationDiscovery {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Full', 'Quick', 'Manual')]
        [string]$Mode
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would discover unmanaged applications in $Mode mode"
        return @()
    }

    try {
        # Use existing analyze-unmanaged.ps1 script
        $analyzeScript = Join-Path $PSScriptRoot "..\backup\analyze-unmanaged.ps1"
        if (Test-Path $analyzeScript) {
            Write-Verbose -Message "Running unmanaged application analysis..."
            $result = & $analyzeScript -WhatIf:$WhatIfPreference
            return $result
        } else {
            Write-Warning "Analyze-unmanaged script not found at: $analyzeScript"
            return @()
        }
    } catch {
        Write-Warning "Failed to run unmanaged application discovery: $_"
        return @()
    }
}

function Save-ApplicationList {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Applications,

        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [ValidateSet('JSON', 'CSV', 'YAML')]
        [string]$Format
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would save $($Applications.Count) applications to $Path in $Format format"
        return
    }

    try {
        switch ($Format) {
            'JSON' {
                $Applications | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
            }
            'CSV' {
                $Applications | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
            }
            'YAML' {
                # Simple YAML output for applications
                $yamlContent = "applications:`n"
                foreach ($app in $Applications) {
                    $yamlContent += "  - name: `"$($app.Name)`"`n"
                    $yamlContent += "    version: `"$($app.Version)`"`n"
                    $yamlContent += "    publisher: `"$($app.Publisher)`"`n"
                    $yamlContent += "    source: `"$($app.Source)`"`n"
                    $yamlContent += "    priority: `"$($app.Priority)`"`n"
                    $yamlContent += "    category: `"$($app.Category)`"`n"
                }
                $yamlContent | Out-File -FilePath $Path -Encoding UTF8
            }
        }
        Write-Information -MessageData "Application list saved to: $Path" -InformationAction Continue
    } catch {
        Write-Warning "Failed to save application list: $_"
    }
}

function New-InstallationDocumentation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Applications
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would create installation documentation for $($Applications.Count) applications"
        return @()
    }

    $documentation = @()

    foreach ($app in $Applications) {
        $doc = @{
            Name = $app.Name
            Version = $app.Version
            Publisher = $app.Publisher
            InstallationMethods = @()
            DownloadSources = @()
            InstallationNotes = ""
            ManualSteps = @()
        }

        # Determine likely installation methods based on publisher and name
        if ($app.Publisher -match "Microsoft") {
            $doc.InstallationMethods += "Windows Store"
            $doc.InstallationMethods += "Microsoft Store"
            $doc.DownloadSources += "https://www.microsoft.com"
        }

        # Check for common package managers
        $doc.InstallationMethods += "Manual Download"
        $doc.DownloadSources += "Publisher Website"

        # Add common installation notes
        $doc.InstallationNotes = "Check publisher website for latest version and installation instructions"
        $doc.ManualSteps += "1. Download installer from publisher website"
        $doc.ManualSteps += "2. Run installer with appropriate permissions"
        $doc.ManualSteps += "3. Follow installation wizard"
        $doc.ManualSteps += "4. Verify installation completed successfully"

        $documentation += $doc
    }

    return $documentation
}

function Save-InstallationDocumentation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Documentation,

        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [ValidateSet('JSON', 'CSV', 'YAML')]
        [string]$Format
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would save installation documentation to $Path in $Format format"
        return
    }

    try {
        switch ($Format) {
            'JSON' {
                $Documentation | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
            }
            'CSV' {
                # Flatten documentation for CSV
                $flatDocs = @()
                foreach ($doc in $Documentation) {
                    $flatDoc = @{
                        Name = $doc.Name
                        Version = $doc.Version
                        Publisher = $doc.Publisher
                        InstallationMethods = ($doc.InstallationMethods -join "; ")
                        DownloadSources = ($doc.DownloadSources -join "; ")
                        InstallationNotes = $doc.InstallationNotes
                        ManualSteps = ($doc.ManualSteps -join " | ")
                    }
                    $flatDocs += New-Object PSObject -Property $flatDoc
                }
                $flatDocs | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
            }
            'YAML' {
                $yamlContent = "installation_documentation:`n"
                foreach ($doc in $Documentation) {
                    $yamlContent += "  - name: `"$($doc.Name)`"`n"
                    $yamlContent += "    version: `"$($doc.Version)`"`n"
                    $yamlContent += "    publisher: `"$($doc.Publisher)`"`n"
                    $yamlContent += "    installation_methods:`n"
                    foreach ($method in $doc.InstallationMethods) {
                        $yamlContent += "      - `"$method`"`n"
                    }
                    $yamlContent += "    download_sources:`n"
                    foreach ($source in $doc.DownloadSources) {
                        $yamlContent += "      - `"$source`"`n"
                    }
                    $yamlContent += "    installation_notes: `"$($doc.InstallationNotes)`"`n"
                    $yamlContent += "    manual_steps:`n"
                    foreach ($step in $doc.ManualSteps) {
                        $yamlContent += "      - `"$step`"`n"
                    }
                }
                $yamlContent | Out-File -FilePath $Path -Encoding UTF8
            }
        }
        Write-Information -MessageData "Installation documentation saved to: $Path" -InformationAction Continue
    } catch {
        Write-Warning "Failed to save installation documentation: $_"
    }
}

function New-UserEditableApplicationLists {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet('JSON', 'CSV', 'YAML')]
        [string]$Format
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would create user-editable application lists in $OutputPath"
        return
    }

    try {
        # Create template for user-editable applications list
        $userAppsTemplate = @{
            metadata = @{
                name = "User Editable Applications"
                description = "User-customizable list of applications to install/manage"
                version = "1.0"
                last_modified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            categories = @{
                essential = @{
                    description = "Essential applications that should always be installed"
                    applications = @()
                }
                productivity = @{
                    description = "Productivity and office applications"
                    applications = @()
                }
                development = @{
                    description = "Development tools and environments"
                    applications = @()
                }
                gaming = @{
                    description = "Gaming platforms and games"
                    applications = @()
                }
                optional = @{
                    description = "Optional applications based on user preference"
                    applications = @()
                }
            }
        }

        # Create template for user-editable games list
        $userGamesTemplate = @{
            metadata = @{
                name = "User Editable Games"
                description = "User-customizable list of games to install/manage"
                version = "1.0"
                last_modified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            platforms = @{
                steam = @{
                    description = "Steam games to install"
                    games = @()
                }
                epic = @{
                    description = "Epic Games Store games to install"
                    games = @()
                }
                gog = @{
                    description = "GOG Galaxy games to install"
                    games = @()
                }
                xbox = @{
                    description = "Xbox Game Pass games to install"
                    games = @()
                }
                other = @{
                    description = "Other games and platforms"
                    games = @()
                }
            }
        }

        # Save templates
        $appsPath = Join-Path $OutputPath "user-editable-apps.$($Format.ToLower())"
        $gamesPath = Join-Path $OutputPath "user-editable-games.$($Format.ToLower())"

        Save-ApplicationList -Applications @($userAppsTemplate) -Path $appsPath -Format $Format
        Save-ApplicationList -Applications @($userGamesTemplate) -Path $gamesPath -Format $Format

        # Create instructions file
        $instructionsPath = Join-Path $OutputPath "user-lists-instructions.txt"
        $instructions = @"
User-Editable Application and Game Lists
========================================

This directory contains user-editable lists for managing applications and games:

Files:
- user-editable-apps.$($Format.ToLower()) - Applications list organized by category
- user-editable-games.$($Format.ToLower()) - Games list organized by platform
- user-lists-instructions.txt - This instructions file

Usage:
1. Edit the JSON/CSV/YAML files to add/remove applications and games
2. Use the Windows Melody Recovery module to install from these lists
3. Categories help organize applications by purpose/priority
4. Platforms help organize games by gaming service

Categories (Applications):
- essential: Must-have applications for basic functionality
- productivity: Office, document, and productivity tools
- development: Programming tools, IDEs, and development environments
- gaming: Gaming platforms and related applications
- optional: Nice-to-have applications based on personal preference

Platforms (Games):
- steam: Steam games (use Steam app ID or name)
- epic: Epic Games Store games
- gog: GOG Galaxy games
- xbox: Xbox Game Pass games
- other: Games from other platforms or standalone games

Tips:
- Keep lists updated as your preferences change
- Use version pinning for critical applications
- Test installations in a safe environment first
- Back up your customized lists regularly
"@

        $instructions | Out-File -FilePath $instructionsPath -Encoding UTF8

        Write-Information -MessageData "User-editable lists created:" -InformationAction Continue
        Write-Verbose -Message "  Applications: $appsPath"
        Write-Verbose -Message "  Games: $gamesPath"
        Write-Verbose -Message "  Instructions: $instructionsPath"

    } catch {
        Write-Warning "Failed to create user-editable lists: $_"
    }
}

function Initialize-ApplicationDecisionWorkflows {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would initialize application decision workflows in $OutputPath"
        return
    }

    try {
        # Create decision workflow configuration
        $workflowConfig = @{
            metadata = @{
                name = "Application Decision Workflows"
                description = "Configuration for application install/uninstall decision logic"
                version = "1.0"
                last_modified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            workflows = @{
                install_decisions = @{
                    description = "Logic for deciding whether to install applications"
                    rules = @(
                        @{
                            name = "Essential Applications"
                            condition = "category -eq 'essential'"
                            action = "install"
                            priority = 1
                        },
                        @{
                            name = "User Approved Applications"
                            condition = "user_approved -eq true"
                            action = "install"
                            priority = 2
                        },
                        @{
                            name = "Optional Applications"
                            condition = "category -eq 'optional'"
                            action = "prompt"
                            priority = 3
                        }
                    )
                }
                uninstall_decisions = @{
                    description = "Logic for deciding whether to uninstall applications"
                    rules = @(
                        @{
                            name = "Bloatware Applications"
                            condition = "category -eq 'bloatware'"
                            action = "uninstall"
                            priority = 1
                        },
                        @{
                            name = "Outdated Applications"
                            condition = "last_used -lt (Get-Date).AddDays(-90)"
                            action = "prompt"
                            priority = 2
                        },
                        @{
                            name = "Unknown Applications"
                            condition = "category -eq 'unknown'"
                            action = "prompt"
                            priority = 3
                        }
                    )
                }
            }
        }

        # Save workflow configuration
        $workflowPath = Join-Path $OutputPath "application-decision-workflows.json"
        $workflowConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $workflowPath -Encoding UTF8

        Write-Information -MessageData "Application decision workflows initialized: $workflowPath" -InformationAction Continue

    } catch {
        Write-Warning "Failed to initialize application decision workflows: $_"
    }
}

function Test-ApplicationDiscoveryStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = $null
    )

    try {
        if (-not $OutputPath) {
            $config = Get-WindowsMelodyRecovery
            $OutputPath = Join-Path $config.BackupRoot $config.MachineName "ApplicationDiscovery"
        }

        $status = @{
            ApplicationDiscoveryConfigured = $false
            UnmanagedAppsDiscovered = $false
            InstallationDocumented = $false
            UserListsCreated = $false
            WorkflowsInitialized = $false
            OutputPath = $OutputPath
        }

        if (Test-Path $OutputPath) {
            $status.ApplicationDiscoveryConfigured = $true

            # Check for unmanaged apps
            $unmanagedFiles = Get-ChildItem -Path $OutputPath -Filter "unmanaged-applications.*" -ErrorAction SilentlyContinue
            $status.UnmanagedAppsDiscovered = $unmanagedFiles.Count -gt 0

            # Check for installation documentation
            $docsFiles = Get-ChildItem -Path $OutputPath -Filter "installation-documentation.*" -ErrorAction SilentlyContinue
            $status.InstallationDocumented = $docsFiles.Count -gt 0

            # Check for user lists
            $userAppsFiles = Get-ChildItem -Path $OutputPath -Filter "user-editable-apps.*" -ErrorAction SilentlyContinue
            $userGamesFiles = Get-ChildItem -Path $OutputPath -Filter "user-editable-games.*" -ErrorAction SilentlyContinue
            $status.UserListsCreated = ($userAppsFiles.Count -gt 0) -and ($userGamesFiles.Count -gt 0)

            # Check for workflows
            $workflowFile = Join-Path $OutputPath "application-decision-workflows.json"
            $status.WorkflowsInitialized = Test-Path $workflowFile
        }

        return $status

    } catch {
        Write-Warning "Failed to check application discovery status: $_"
        return @{
            ApplicationDiscoveryConfigured = $false
            UnmanagedAppsDiscovered = $false
            InstallationDocumented = $false
            UserListsCreated = $false
            WorkflowsInitialized = $false
            OutputPath = $OutputPath
            Error = $_.Exception.Message
        }
    }
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    Setup-ApplicationDiscovery -DiscoveryMode $DiscoveryMode -OutputFormat $OutputFormat -UserListPath $UserListPath -CreateUserLists:$CreateUserLists -DocumentInstallation:$DocumentInstallation
}

