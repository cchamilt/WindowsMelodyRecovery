# Setup-ConfigurationSelection.ps1 - Configure setup script selection and execution planning

<#
.SYNOPSIS
    Configure setup script selection and execution planning for Windows Melody Recovery.

.DESCRIPTION
    This script provides functionality to:
    - Discover and categorize available setup scripts
    - Create and manage configuration profiles for different system types
    - Interactive, automatic, and profile-based script selection
    - Create organized execution plans with dependencies and phases

.PARAMETER ProfileName
    Name of the configuration profile to use or create

.PARAMETER SetupScripts
    Array of specific setup scripts to include

.PARAMETER ConfigurationMode
    Mode for configuration selection: 'Interactive', 'Automatic', 'Profile'

.PARAMETER OutputPath
    Path to save configuration profiles and execution plans

.PARAMETER CreateProfile
    Create a new configuration profile

.EXAMPLE
    Setup-ConfigurationSelection -ProfileName "Developer" -ConfigurationMode Interactive

.EXAMPLE
    Setup-ConfigurationSelection -ProfileName "Gamer" -ConfigurationMode Automatic -CreateProfile

.NOTES
    Requires module initialization before use.
    Part of Windows Melody Recovery module.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProfileName = "Default",

    [Parameter(Mandatory = $false)]
    [string[]]$SetupScripts = @(),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Automatic', 'Profile')]
    [string]$ConfigurationMode = 'Interactive',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $null,

    [Parameter(Mandatory = $false)]
    [switch]$CreateProfile
)

# Import required modules
Import-Module WindowsMelodyRecovery -ErrorAction Stop

function Initialize-ConfigurationSelection {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProfileName = "Default",

        [Parameter(Mandatory = $false)]
        [string[]]$SetupScripts = @(),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Interactive', 'Automatic', 'Profile')]
        [string]$ConfigurationMode = 'Interactive',

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $null,

        [Parameter(Mandatory = $false)]
        [switch]$CreateProfile
    )

    begin {
        Write-Information -MessageData "Setting up Configuration Selection and Setup Script Management..." -InformationAction Continue

        # Get module configuration
        try {
            $config = Get-WindowsMelodyRecovery
            if (-not $config.IsInitialized) {
                throw "Module not initialized. Please run Initialize-WindowsMelodyRecovery first."
            }
            $backupRoot = $config.BackupRoot
            $machineName = $config.MachineName
        }
        catch {
            Write-Warning "Module configuration not available. Using defaults."
            $backupRoot = "$env:USERPROFILE\WindowsMelodyRecovery"
            $machineName = $env:COMPUTERNAME
        }

        # Set up output paths
        if (-not $OutputPath) {
            $OutputPath = Join-Path $backupRoot $machineName "ConfigurationProfiles"
        }

        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        # Discover available setup scripts
        $setupScriptsPath = Join-Path $modulePath "Private\setup"
        $availableScripts = Get-AvailableSetupScripts -SetupPath $setupScriptsPath
    }

    process {
        try {
            # Step 1: Load or create configuration profile
            Write-Information -MessageData "Step 1: Managing configuration profile '$ProfileName'..." -InformationAction Continue

            if ($CreateProfile -or -not (Test-ConfigurationProfile -ProfileName $ProfileName -OutputPath $OutputPath)) {
                $configProfile = New-ConfigurationProfile -ProfileName $ProfileName -OutputPath $OutputPath -AvailableScripts $availableScripts
            }
            else {
                $configProfile = Get-ConfigurationProfile -ProfileName $ProfileName -OutputPath $OutputPath
            }

            # Step 2: Configure setup scripts based on mode
            Write-Information -MessageData "Step 2: Configuring setup scripts in $ConfigurationMode mode..." -InformationAction Continue

            switch ($ConfigurationMode) {
                'Interactive' {
                    $selectedScripts = Invoke-InteractiveScriptSelection -AvailableScripts $availableScripts -CurrentProfile $configProfile
                }
                'Automatic' {
                    $selectedScripts = Invoke-AutomaticScriptSelection -AvailableScripts $availableScripts
                }
                'Profile' {
                    $selectedScripts = Get-ProfileScriptSelection -Profile $configProfile
                }
            }

            # Step 3: Update configuration profile
            if ($selectedScripts) {
                Write-Information -MessageData "Step 3: Updating configuration profile..." -InformationAction Continue
                $configProfile.setup_scripts = $selectedScripts
                $configProfile.last_modified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

                Save-ConfigurationProfile -Profile $configProfile -ProfileName $ProfileName -OutputPath $OutputPath
            }

            # Step 4: Create execution plan
            Write-Information -MessageData "Step 4: Creating setup execution plan..." -InformationAction Continue
            $executionPlan = New-SetupExecutionPlan -Profile $configProfile -AvailableScripts $availableScripts

            if ($executionPlan) {
                $planPath = Join-Path $OutputPath "$ProfileName-execution-plan.json"
                Save-ExecutionPlan -ExecutionPlan $executionPlan -Path $planPath
            }

            Write-Information -MessageData "Configuration selection setup completed successfully!" -InformationAction Continue
            Write-Verbose -Message "Profile: $ProfileName"
            Write-Verbose -Message "Selected Scripts: $($selectedScripts.Count)"
            Write-Verbose -Message "Output Path: $OutputPath"

            return $true

        }
        catch {
            Write-Error "Failed to setup configuration selection: $_"
            return $false
        }
    }
}

function Get-AvailableSetupScript {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SetupPath
    )

    try {
        $scripts = @()
        $scriptFiles = Get-ChildItem -Path $SetupPath -Filter "setup-*.ps1" -ErrorAction SilentlyContinue

        foreach ($file in $scriptFiles) {
            $scriptInfo = @{
                Name          = $file.BaseName
                FileName      = $file.Name
                FullPath      = $file.FullName
                Description   = ""
                Category      = "Unknown"
                Dependencies  = @()
                RequiresAdmin = $false
                Parameters    = @()
            }

            # Parse script header for metadata
            $content = Get-Content $file.FullName -First 50 -ErrorAction SilentlyContinue
            if ($content) {
                # Extract description from comment block
                $descriptionMatch = $content | Select-String -Pattern "^\s*#\s*(.+)" | Select-Object -First 1
                if ($descriptionMatch) {
                    $scriptInfo.Description = $descriptionMatch.Matches[0].Groups[1].Value.Trim()
                }

                # Check for admin requirements
                if ($content -match "Administrator|Elevated|Admin") {
                    $scriptInfo.RequiresAdmin = $true
                }

                # Determine category based on script name
                $scriptInfo.Category = Get-SetupScriptCategory -ScriptName $file.BaseName
            }

            $scripts += $scriptInfo
        }

        return $scripts

    }
    catch {
        Write-Warning "Failed to get available setup scripts: $_"
        return @()
    }
}

function Get-SetupScriptCategory {
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    # Categorize scripts based on naming patterns
    switch -Regex ($ScriptName) {
        "Initialize-WSL" { return "Development" }
        "Initialize-PackageManagers" { return "System" }
        "setup-customprofiles" { return "System" }
        "setup-defender" { return "Security" }
        "setup-.*-games" { return "Gaming" }
        "setup-steam" { return "Gaming" }
        "setup-epic" { return "Gaming" }
        "setup-gog" { return "Gaming" }
        "setup-ea" { return "Gaming" }
        "Initialize-Chezmoi" { return "Development" }
        "Remove-Bloat" { return "System" }
        "Initialize-RestorePoints" { return "System" }
        "setup-keepassxc" { return "Security" }
        "Initialize-WSL-fonts" { return "Development" }
        default { return "Other" }
    }
}

function Test-ConfigurationProfile {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    try {
        $profilePath = Join-Path $OutputPath "$ProfileName-profile.json"
        return Test-Path $profilePath
    }
    catch {
        return $false
    }
}

function New-ConfigurationProfile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [array]$AvailableScripts
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would create configuration profile '$ProfileName' in $OutputPath"
        return @{}
    }

    try {
        $configProfile = @{
            metadata          = @{
                name          = $ProfileName
                description   = "Configuration profile for $ProfileName system setup"
                version       = "1.0"
                created       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                last_modified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            system_type       = $ProfileName
            setup_scripts     = @()
            preferences       = @{
                auto_approve_essential = $true
                prompt_for_optional    = $true
                skip_dangerous         = $false
                backup_before_changes  = $true
            }
            script_categories = @{
                system      = @()
                security    = @()
                development = @()
                gaming      = @()
                other       = @()
            }
        }

        # Set default scripts based on profile type
        switch ($ProfileName) {
            "Developer" {
                $configProfile.setup_scripts = @("Initialize-WSL", "Initialize-PackageManagers", "Initialize-Chezmoi", "setup-customprofiles")
                $configProfile.script_categories.development = @("Initialize-WSL", "Initialize-Chezmoi", "Initialize-WSL-fonts")
                $configProfile.script_categories.system = @("Initialize-PackageManagers", "setup-customprofiles")
            }
            "Gamer" {
                $configProfile.setup_scripts = @("setup-steam-games", "setup-epic-games", "setup-gog-games", "setup-ea-games")
                $configProfile.script_categories.gaming = @("setup-steam-games", "setup-epic-games", "setup-gog-games", "setup-ea-games")
                $configProfile.script_categories.system = @("Initialize-PackageManagers")
            }
            "Security" {
                $configProfile.setup_scripts = @("setup-defender", "setup-keepassxc", "Remove-Bloat")
                $configProfile.script_categories.security = @("setup-defender", "setup-keepassxc")
                $configProfile.script_categories.system = @("Remove-Bloat", "Initialize-RestorePoints")
            }
            "Minimal" {
                $configProfile.setup_scripts = @("Initialize-PackageManagers", "setup-customprofiles")
                $configProfile.script_categories.system = @("Initialize-PackageManagers", "setup-customprofiles")
            }
            "Default" {
                $configProfile.setup_scripts = @("Initialize-PackageManagers", "setup-customprofiles", "setup-defender")
                $configProfile.script_categories.system = @("Initialize-PackageManagers", "setup-customprofiles")
                $configProfile.script_categories.security = @("setup-defender")
            }
        }

        return $configProfile

    }
    catch {
        Write-Warning "Failed to create configuration profile: $_"
        return @{}
    }
}

function Save-ConfigurationProfile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Profile,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $profilePath = Join-Path $OutputPath "$ProfileName-profile.json"

    if ($PSCmdlet.ShouldProcess($profilePath, "Save configuration profile")) {
        try {
            $Profile | ConvertTo-Json -Depth 10 | Out-File -FilePath $profilePath -Encoding UTF8
            Write-Information -MessageData "Configuration profile saved: $profilePath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save configuration profile: $_"
        }
    }
}

function Get-ConfigurationProfile {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable], [System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    try {
        $profilePath = Join-Path $OutputPath "$ProfileName-profile.json"
        if (Test-Path $profilePath) {
            $profileContent = Get-Content $profilePath -Raw | ConvertFrom-Json
            return $profileContent
        }
        else {
            return $null
        }
    }
    catch {
        Write-Warning "Failed to get configuration profile: $_"
        return $null
    }
}

function Invoke-InteractiveScriptSelection {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$AvailableScripts,

        [Parameter(Mandatory = $false)]
        [hashtable]$CurrentProfile = @{}
    )

    try {
        $selectedScripts = @()

        Write-Information -MessageData "`nAvailable Setup Scripts:" -InformationAction Continue
        Write-Information -MessageData "========================" -InformationAction Continue

        for ($i = 0; $i -lt $AvailableScripts.Count; $i++) {
            $script = $AvailableScripts[$i]
            $isSelected = $CurrentProfile.setup_scripts -contains $script.Name
            $status = if ($isSelected) { "[X]" } else { "[ ]" }

            Write-Information -MessageData "$($i + 1). $status $($script.Name)"  -InformationAction Continue-ForegroundColor White
            Write-Verbose -Message "   Category: $($script.Category)"
            Write-Verbose -Message "   Description: $($script.Description)"
            if ($script.RequiresAdmin) {
                Write-Warning -Message "   Requires Admin: Yes"
            }
            Write-Information -MessageData "" -InformationAction Continue
        }

        Write-Information -MessageData "Enter script numbers to toggle selection (e.g., 1,3,5) or 'all' for all scripts:" -InformationAction Continue
        $userInput = Read-Host

        if ($userInput -eq 'all') {
            $selectedScripts = $AvailableScripts.Name
        }
        else {
            $indices = $userInput -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
            $selectedScripts = $AvailableScripts[$indices].Name
        }

        return $selectedScripts

    }
    catch {
        Write-Warning "Failed to perform interactive script selection: $_"
        return @()
    }
}

function Invoke-AutomaticScriptSelection {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$AvailableScripts
    )

    try {
        $selectedScripts = @()
        $systemInfo = Get-SystemInformation

        # Always include essential system scripts
        $selectedScripts += "Initialize-PackageManagers"
        $selectedScripts += "setup-customprofiles"

        # Add scripts based on detected software/features
        if ($systemInfo.HasWSL) {
            $selectedScripts += "Initialize-WSL"
            $selectedScripts += "Initialize-WSL-fonts"
        }

        if ($systemInfo.HasGit) {
            $selectedScripts += "Initialize-Chezmoi"
        }

        if ($systemInfo.HasSteam) {
            $selectedScripts += "setup-steam-games"
        }

        if ($systemInfo.HasEpicGames) {
            $selectedScripts += "setup-epic-games"
        }

        if ($systemInfo.HasGOG) {
            $selectedScripts += "setup-gog-games"
        }

        # Security scripts for all systems
        $selectedScripts += "setup-defender"

        # Remove duplicates and ensure scripts exist
        $selectedScripts = $selectedScripts | Sort-Object -Unique
        $availableNames = $AvailableScripts.Name
        $selectedScripts = $selectedScripts | Where-Object { $availableNames -contains $_ }

        Write-Information -MessageData "Automatically selected $($selectedScripts.Count) scripts based on system detection" -InformationAction Continue

        return $selectedScripts

    }
    catch {
        Write-Warning "Failed to perform automatic script selection: $_"
        return @()
    }
}

function Get-ProfileScriptSelection {
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Profile
    )

    try {
        return $Profile.setup_scripts
    }
    catch {
        Write-Warning "Failed to get profile script selection: $_"
        return @()
    }
}

function Get-SystemInformation {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param()

    try {
        $systemInfo = @{
            HasWSL           = $false
            HasGit           = $false
            HasSteam         = $false
            HasEpicGames     = $false
            HasGOG           = $false
            HasDockerDesktop = $false
            HasVisualStudio  = $false
            HasVSCode        = $false
        }

        # Check for WSL
        try {
            $wslResult = wsl --list --quiet 2>$null
            $systemInfo.HasWSL = $LASTEXITCODE -eq 0
        }
        catch {
            # WSL not installed or not available
            $systemInfo.HasWSL = $false
        }

        # Check for Git
        try {
            git --version 2>$null | Out-Null
            $systemInfo.HasGit = $LASTEXITCODE -eq 0
        }
        catch {
            # Git not installed or not available
            $systemInfo.HasGit = $false
        }

        # Check for Steam
        $steamPath = "${env:ProgramFiles(x86)}\Steam\steam.exe"
        $systemInfo.HasSteam = Test-Path $steamPath

        # Check for Epic Games
        $epicPath = "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"
        $systemInfo.HasEpicGames = Test-Path $epicPath

        # Check for GOG Galaxy
        $gogPath = "${env:ProgramFiles(x86)}\GOG Galaxy\GalaxyClient.exe"
        $systemInfo.HasGOG = Test-Path $gogPath

        # Check for Docker Desktop
        $dockerPath = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
        $systemInfo.HasDockerDesktop = Test-Path $dockerPath

        # Check for Visual Studio
        $vsPath = "${env:ProgramFiles}\Microsoft Visual Studio"
        $systemInfo.HasVisualStudio = Test-Path $vsPath

        # Check for VS Code
        $vscodePath = "${env:ProgramFiles}\Microsoft VS Code\Code.exe"
        $systemInfo.HasVSCode = Test-Path $vscodePath

        return $systemInfo

    }
    catch {
        Write-Warning "Failed to get system information: $_"
        return @{}
    }
}

function New-SetupExecutionPlan {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Profile,

        [Parameter(Mandatory = $true)]
        [array]$AvailableScripts
    )

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would create setup execution plan for profile '$($Profile.metadata.name)'"
        return @{}
    }

    try {
        $executionPlan = @{
            metadata = @{
                profile_name  = $Profile.metadata.name
                created       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                total_scripts = $Profile.setup_scripts.Count
            }
            phases   = @{
                system       = @{
                    description = "System configuration and essential setup"
                    order       = 1
                    scripts     = @()
                }
                applications = @{
                    description = "Application installation and configuration"
                    order       = 2
                    scripts     = @()
                }
                development  = @{
                    description = "Development environment setup"
                    order       = 3
                    scripts     = @()
                }
                gaming       = @{
                    description = "Gaming platform and game setup"
                    order       = 4
                    scripts     = @()
                }
            }
        }

        # Organize scripts by phase
        foreach ($scriptName in $Profile.setup_scripts) {
            $script = $AvailableScripts | Where-Object { $_.Name -eq $scriptName } | Select-Object -First 1
            if ($script) {
                $scriptInfo = @{
                    name           = $script.Name
                    filename       = $script.FileName
                    description    = $script.Description
                    category       = $script.Category
                    requires_admin = $script.RequiresAdmin
                    dependencies   = $script.Dependencies
                }

                switch ($script.Category) {
                    "System" { $executionPlan.phases.system.scripts += $scriptInfo }
                    "Security" { $executionPlan.phases.system.scripts += $scriptInfo }
                    "Development" { $executionPlan.phases.development.scripts += $scriptInfo }
                    "Gaming" { $executionPlan.phases.gaming.scripts += $scriptInfo }
                    default { $executionPlan.phases.applications.scripts += $scriptInfo }
                }
            }
        }

        return $executionPlan

    }
    catch {
        Write-Warning "Failed to create setup execution plan: $_"
        return @{}
    }
}

function Save-ExecutionPlan {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ExecutionPlan,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($PSCmdlet.ShouldProcess($Path, "Save execution plan")) {
        try {
            $ExecutionPlan | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
            Write-Information -MessageData "Execution plan saved: $Path" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save execution plan: $_"
        }
    }
}

function Test-ConfigurationSelectionStatus {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $null,

        [Parameter(Mandatory = $false)]
        [string]$ProfileName = "Default"
    )

    try {
        if (-not $OutputPath) {
            $config = Get-WindowsMelodyRecovery
            $OutputPath = Join-Path $config.BackupRoot $config.MachineName "ConfigurationProfiles"
        }

        $status = @{
            ConfigurationSelectionConfigured = $false
            ProfileExists                    = $false
            ExecutionPlanExists              = $false
            AvailableScripts                 = 0
            ProfileName                      = $ProfileName
            OutputPath                       = $OutputPath
        }

        if (Test-Path $OutputPath) {
            $status.ConfigurationSelectionConfigured = $true

            # Check for profile
            $profilePath = Join-Path $OutputPath "$ProfileName-profile.json"
            $status.ProfileExists = Test-Path $profilePath

            # Check for execution plan
            $planPath = Join-Path $OutputPath "$ProfileName-execution-plan.json"
            $status.ExecutionPlanExists = Test-Path $planPath

            # Count available scripts
            $setupScriptsPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "Private\setup"
            $scriptFiles = Get-ChildItem -Path $setupScriptsPath -Filter "setup-*.ps1" -ErrorAction SilentlyContinue
            $status.AvailableScripts = $scriptFiles.Count
        }

        return $status

    }
    catch {
        Write-Warning "Failed to check configuration selection status: $_"
        return @{
            ConfigurationSelectionConfigured = $false
            ProfileExists                    = $false
            ExecutionPlanExists              = $false
            AvailableScripts                 = 0
            ProfileName                      = $ProfileName
            OutputPath                       = $OutputPath
            Error                            = $_.Exception.Message
        }
    }
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    Setup-ConfigurationSelection -ProfileName $ProfileName -SetupScripts $SetupScripts -ConfigurationMode $ConfigurationMode -OutputPath $OutputPath -CreateProfile:$CreateProfile
}












