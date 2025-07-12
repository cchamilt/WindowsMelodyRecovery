#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Mock Integration for Windows Melody Recovery Testing

.DESCRIPTION
    Integrates enhanced mock infrastructure with existing testing system,
    providing seamless backwards compatibility while enabling advanced
    mock data capabilities.

.NOTES
    This integration layer ensures existing tests continue working while
    providing access to enhanced mock data features.
#>

# Import enhanced mock infrastructure
. (Join-Path $PSScriptRoot "Enhanced-Mock-Infrastructure.ps1")

# Legacy compatibility functions
function Initialize-MockEnvironment {
    <#
    .SYNOPSIS
        Legacy compatibility wrapper for mock environment initialization.
    #>
    param(
        [string]$Environment = "Enhanced"
    )

    Write-Warning -Message "🔗 Initializing mock environment (legacy compatibility)"

    # Use enhanced infrastructure with integration test scope
    Initialize-EnhancedMockInfrastructure -TestType "Integration" -Scope "Standard"

    Write-Information -MessageData "✓ Legacy mock environment initialized with enhanced infrastructure" -InformationAction Continue
}

function Get-MockDataPath {
    <#
    .SYNOPSIS
        Legacy compatibility wrapper for mock data paths.
    #>
    param([string]$DataType)

    $testPaths = Get-StandardTestPaths
    $mockDataRoot = $testPaths.TestMockData

    return Join-Path $mockDataRoot $DataType
}

function Test-MockDataExist {
    <#
    .SYNOPSIS
        Legacy compatibility wrapper for mock data existence checks.
    #>
    param(
        [string]$DataType,
        [string]$Path
    )

    $mockPath = Get-MockDataPath -DataType $DataType
    $fullPath = Join-Path $mockPath $Path

    return Test-Path $fullPath
}

# Enhanced test integration functions
function Initialize-MockForTestType {
    <#
    .SYNOPSIS
        Initializes appropriate mock data based on test type and context.

    .PARAMETER TestType
        Type of test requiring mock data.

    .PARAMETER TestContext
        Specific test context or component being tested.

    .PARAMETER Scope
        Scope of mock data required.

    .EXAMPLE
        Initialize-MockForTestType -TestType "Integration" -TestContext "ApplicationBackup"
        Initialize-MockForTestType -TestType "EndToEnd" -TestContext "CompleteWorkflow" -Scope "Comprehensive"
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Unit', 'Integration', 'FileOperations', 'EndToEnd')]
        [string]$TestType,

        [string]$TestContext,

        [ValidateSet('Minimal', 'Standard', 'Comprehensive', 'Enterprise')]
        [string]$Scope = 'Standard'
    )

    Write-Information -MessageData "🎯 Initializing mock data for $TestType tests" -InformationAction Continue
    if ($TestContext) {
        Write-Verbose -Message "   Context: $TestContext"
    }

    # Initialize base enhanced infrastructure
    Initialize-EnhancedMockInfrastructure -TestType $TestType -Scope $Scope

    # Apply context-specific customizations
    if ($TestContext) {
        switch ($TestContext) {
            'ApplicationBackup' {
                Update-ApplicationMockData -Scope $Scope
            }
            'GamingIntegration' {
                Update-GamingMockData -Scope $Scope
            }
            'CloudSync' {
                Update-CloudMockData -Scope $Scope
            }
            'WSLManagement' {
                Update-WSLMockData -Scope $Scope
            }
            'SystemSettings' {
                Update-SystemSettingsMockData -Scope $Scope
            }
            'CompleteWorkflow' {
                # Enhance all components for end-to-end testing
                Update-ApplicationMockData -Scope $Scope
                Update-GamingMockData -Scope $Scope
                Update-CloudMockData -Scope $Scope
                Update-WSLMockData -Scope $Scope
                Update-SystemSettingsMockData -Scope $Scope
            }
        }
    }

    Write-Information -MessageData "✓ Mock data initialized for $TestType/$TestContext" -InformationAction Continue
}

function Update-ApplicationMockData {
    <#
    .SYNOPSIS
        Enhances application mock data with additional realistic details.
    #>
    param([string]$Scope)

    $testPaths = Get-StandardTestPaths
    $appDataPath = Join-Path $testPaths.TestMockData "applications"

    # Add realistic configuration files for applications
    $configEnhancements = @{
        'VSCode' = @{
            'settings.json' = @{
                'editor.fontSize' = 14
                'editor.theme' = 'Dark+ (default dark)'
                'extensions.autoUpdate' = $true
                'files.autoSave' = 'onFocusChange'
            }
            'keybindings.json' = @(
                @{ 'key' = 'ctrl+shift+p'; 'command' = 'workbench.action.showCommands' }
            )
        }
        'Chrome' = @{
            'Preferences' = @{
                'profile' = @{
                    'default_content_settings' = @{
                        'popups' = 1
                    }
                }
                'bookmark_bar' = @{
                    'show_on_all_tabs' = $true
                }
            }
        }
        'Firefox' = @{
            'prefs.js' = @(
                'user_pref("browser.startup.homepage", "about:home");'
                'user_pref("browser.newtabpage.enabled", true);'
                'user_pref("privacy.trackingprotection.enabled", true);'
            )
        }
    }

    foreach ($app in $configEnhancements.Keys) {
        $appPath = Join-Path $appDataPath $app
        New-Item -Path $appPath -ItemType Directory -Force | Out-Null

        foreach ($configFile in $configEnhancements[$app].Keys) {
            $configPath = Join-Path $appPath $configFile
            $configContent = $configEnhancements[$app][$configFile]

            if ($configFile.EndsWith('.json')) {
                $configContent | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
            }
 else {
                $configContent -join "`n" | Set-Content -Path $configPath -Encoding UTF8
            }
        }
    }

    Write-Verbose -Message "    ✓ Enhanced application configurations"
}

function Update-GamingMockData {
    <#
    .SYNOPSIS
        Enhances gaming mock data with detailed game libraries and settings.
    #>
    param([string]$Scope)

    $testPaths = Get-StandardTestPaths
    $gamingPath = Join-Path $testPaths.TestMockData "gaming"

    # Steam library folders
    $steamPath = Join-Path $gamingPath "steam"
    New-Item -Path $steamPath -ItemType Directory -Force | Out-Null

    $libraryFolders = @"
"libraryfolders"
{
    "0"
    {
        "path"        "C:\\Program Files (x86)\\Steam"
        "label"       ""
        "mounted"     "1"
        "contentid"   "123456789"
    }
    "1"
    {
        "path"        "D:\\SteamLibrary"
        "label"       "Games"
        "mounted"     "1"
        "contentid"   "987654321"
    }
}
"@

    $libraryFolders | Set-Content -Path (Join-Path $steamPath "libraryfolders.vdf") -Encoding UTF8

    # Steam user data
    $userDataPath = Join-Path $steamPath "userdata\123456789\config"
    New-Item -Path $userDataPath -ItemType Directory -Force | Out-Null

    $localConfig = @"
"UserLocalConfigStore"
{
    "friends"
    {
        "VoiceReceiveVolume"    "0.5"
        "VoiceMicrophoneVolume" "1.0"
        "VoiceQuality"          "1"
    }
    "streaming_v2"
    {
        "EnableStreaming"       "1"
        "QualityFast"          "1"
        "QualityBalanced"      "2"
        "QualityBeautiful"     "3"
    }
}
"@

    $localConfig | Set-Content -Path (Join-Path $userDataPath "localconfig.vdf") -Encoding UTF8

    Write-Verbose -Message "    ✓ Enhanced gaming configurations and libraries"
}

function Update-CloudMockData {
    <#
    .SYNOPSIS
        Enhances cloud mock data with sync status and provider-specific features.
    #>
    param([string]$Scope)

    $testPaths = Get-StandardTestPaths
    $cloudPath = Join-Path $testPaths.TestMockData "cloud"

    # Add detailed sync logs and status files
    foreach ($provider in @('OneDrive', 'GoogleDrive', 'Dropbox', 'Box')) {
        $providerPath = Join-Path $cloudPath $provider

        # Sync log
        $syncLog = @(
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Sync started"
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Uploading WindowsMelodyRecovery\backup-manifest.json"
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Upload completed successfully"
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Sync completed"
        )

        $syncLog | Set-Content -Path (Join-Path $providerPath "sync.log") -Encoding UTF8

        # Provider-specific settings
        $providerSettings = switch ($provider) {
            'OneDrive' {
                @{
                    'PersonalVault' = @{
                        'Enabled' = $true
                        'Locked' = $false
                    }
                    'FilesOnDemand' = $true
                    'BackupSettings' = @{
                        'DesktopBackup' = $false
                        'DocumentsBackup' = $true
                        'PicturesBackup' = $true
                    }
                }
            }
            'GoogleDrive' {
                @{
                    'StreamFiles' = $true
                    'PhotosBackup' = $false
                    'SyncMyDrive' = $true
                    'BandwidthSettings' = @{
                        'DownloadRate' = 'Don''t limit'
                        'UploadRate' = 'Limit to 1024 KB/s'
                    }
                }
            }
            'Dropbox' {
                @{
                    'SmartSync' = $true
                    'CameraUpload' = $false
                    'LanSync' = $true
                    'SelectiveSync' = @(
                        'Documents'
                        'Projects'
                    )
                }
            }
            'Box' {
                @{
                    'BoxSync' = $true
                    'BoxDrive' = $false
                    'OfflineFiles' = @('Important Documents')
                    'AdminSettings' = @{
                        'AllowSync' = $true
                        'AllowBoxEdit' = $true
                    }
                }
            }
        }

        $providerSettings | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $providerPath "settings.json") -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ Enhanced cloud provider settings and sync logs"
}

function Update-WSLMockData {
    <#
    .SYNOPSIS
        Enhances WSL mock data with detailed distribution configurations and package lists.
    #>
    param([string]$Scope)

    $testPaths = Get-StandardTestPaths
    $wslPath = Join-Path $testPaths.TestMockData "wsl"

    # Enhanced package data with more realistic package lists
    $enhancedPackages = @{
        'Ubuntu' = @{
            'development' = @(
                'build-essential (12.9ubuntu3) - Informational list of build-essential packages'
                'cmake (3.22.1-1ubuntu1.22.04.1) - cross-platform, open-source make system'
                'ninja-build (1.10.1-1) - small build system with a focus on speed'
                'pkg-config (0.29.2-1ubuntu3) - manage compile and link flags for libraries'
            )
            'networking' = @(
                'curl (7.81.0-1ubuntu1.15) - command line tool for transferring data with URL syntax'
                'wget (1.21.2-2ubuntu1) - retrieves files from the web'
                'net-tools (1.60+git20181103.0eebece-1ubuntu5) - NET-3 networking toolkit'
                'nmap (7.91+dfsg1+really7.80-2ubuntu0.1) - The Network Mapper'
            )
            'utilities' = @(
                'htop (3.0.5-7build2) - interactive processes viewer'
                'tree (1.8.0-1ubuntu1) - displays an indented directory tree, in color'
                'tmux (3.2a-4ubuntu0.2) - terminal multiplexer'
                'vim (2:8.2.3458-2ubuntu2.2) - Vi IMproved - enhanced vi editor'
            )
        }
        'Debian' = @{
            'core' = @(
                'apt (2.6.1) - commandline package manager'
                'dpkg (1.21.22) - Debian package management system'
                'systemd (252.17-1~deb12u1) - system and service manager'
            )
            'development' = @(
                'gcc (4:12.2.0-3) - GNU C compiler'
                'make (4.3-4.1) - utility for directing compilation'
                'git (1:2.39.2-1.1) - fast, scalable, distributed revision control system'
            )
        }
    }

    foreach ($distro in $enhancedPackages.Keys) {
        $distroPath = Join-Path $wslPath $distro

        foreach ($category in $enhancedPackages[$distro].Keys) {
            $categoryFile = Join-Path $distroPath "$category-packages.txt"
            $enhancedPackages[$distro][$category] | Set-Content -Path $categoryFile -Encoding UTF8
        }
    }

    # Add dotfiles and configuration examples
    foreach ($distro in @('Ubuntu', 'Debian')) {
        $distroPath = Join-Path $wslPath $distro
        $dotfilesPath = Join-Path $distroPath "dotfiles"
        New-Item -Path $dotfilesPath -ItemType Directory -Force | Out-Null

        # Sample .bashrc
        $bashrc = @'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Prompt
PS1='\u@\h:\w\$ '

# Enable color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
fi
'@

        $bashrc | Set-Content -Path (Join-Path $dotfilesPath ".bashrc") -Encoding UTF8

        # Sample .vimrc
        $vimrc = @'
" Basic vim configuration
set number
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set hlsearch
set incsearch
syntax on
'@

        $vimrc | Set-Content -Path (Join-Path $dotfilesPath ".vimrc") -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ Enhanced WSL packages, dotfiles, and configurations"
}

function Update-SystemSettingsMockData {
    <#
    .SYNOPSIS
        Enhances system settings mock data with comprehensive Windows configurations.
    #>
    param([string]$Scope)

    $testPaths = Get-StandardTestPaths
    $systemPath = Join-Path $testPaths.TestMockData "system-settings"

    # Windows Features
    $windowsFeatures = @{
        'Enabled' = @(
            'Microsoft-Windows-Subsystem-Linux'
            'VirtualMachinePlatform'
            'Microsoft-Hyper-V-All'
            'IIS-WebServerRole'
            'IIS-WebServer'
            'IIS-HttpCompressionDynamic'
        )
        'Disabled' = @(
            'Internet-Explorer-Optional-amd64'
            'MediaPlayback'
            'WindowsMediaPlayer'
            'WorkFolders-Client'
        )
        'Available' = @(
            'Microsoft-Windows-PowerShell-ISE'
            'TelnetClient'
            'TFTP'
            'SimpleTCP'
        )
    }

    $windowsFeatures | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $systemPath "windows-features.json") -Encoding UTF8

    # Windows Capabilities
    $windowsCapabilities = @{
        'Installed' = @(
            'Language.Basic~~~en-US~0.0.1.0'
            'Language.Handwriting~~~en-US~0.0.1.0'
            'Language.OCR~~~en-US~0.0.1.0'
            'Language.Speech~~~en-US~0.0.1.0'
        )
        'NotPresent' = @(
            'XPS.Viewer~~~~0.0.1.0'
            'Print.Fax.Scan~~~~0.0.1.0'
            'Print.Management.Console~~~~0.0.1.0'
        )
    }

    $windowsCapabilities | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $systemPath "windows-capabilities.json") -Encoding UTF8

    # Startup programs
    $startupPrograms = @(
        @{
            'Name' = 'Steam'
            'Publisher' = 'Valve Corporation'
            'Command' = '"C:\Program Files (x86)\Steam\steam.exe" -silent'
            'Status' = 'Enabled'
            'Impact' = 'High'
        }
        @{
            'Name' = 'Discord'
            'Publisher' = 'Discord Inc.'
            'Command' = '%LOCALAPPDATA%\Discord\Update.exe --processStart Discord.exe'
            'Status' = 'Enabled'
            'Impact' = 'Medium'
        }
        @{
            'Name' = 'Spotify'
            'Publisher' = 'Spotify AB'
            'Command' = '%APPDATA%\Spotify\Spotify.exe /uri spotify:autostart'
            'Status' = 'Disabled'
            'Impact' = 'Medium'
        }
    )

    $startupPrograms | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $systemPath "startup-programs.json") -Encoding UTF8

    # Environment variables
    $environmentVariables = @{
        'System' = @{
            'PATH' = 'C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Program Files\Git\cmd;C:\Program Files\Docker\Docker\resources\bin'
            'JAVA_HOME' = 'C:\Program Files\Java\jdk-17.0.2'
            'PYTHON_HOME' = 'C:\Users\TestUser\AppData\Local\Programs\Python\Python312'
        }
        'User' = @{
            'OneDrive' = 'C:\Users\TestUser\OneDrive'
            'USERPROFILE' = 'C:\Users\TestUser'
            'TEMP' = 'C:\Users\TestUser\AppData\Local\Temp'
        }
    }

    $environmentVariables | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $systemPath "environment-variables.json") -Encoding UTF8

    Write-Verbose -Message "    ✓ Enhanced system settings: features, capabilities, startup, environment"
}

function Get-MockDataForTest {
    <#
    .SYNOPSIS
        Retrieves appropriate mock data for specific test scenarios.

    .PARAMETER TestName
        Name of the test requiring mock data.

    .PARAMETER Component
        Component being tested.

    .PARAMETER DataFormat
        Required format for the mock data.

    .EXAMPLE
        Get-MockDataForTest -TestName "ApplicationBackup" -Component "winget" -DataFormat "json"
        Get-MockDataForTest -TestName "WSLPackageDiscovery" -Component "Ubuntu" -DataFormat "packagelist"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestName,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [ValidateSet('json', 'xml', 'yaml', 'txt', 'packagelist', 'registry', 'config')]
        [string]$DataFormat = 'json'
    )

    $testPaths = Get-StandardTestPaths
    $mockDataRoot = $testPaths.TestMockData

    # Map test names to component paths
    $componentMap = @{
        'ApplicationBackup' = 'applications'
        'GamingIntegration' = 'gaming'
        'CloudSync' = 'cloud'
        'WSLPackageDiscovery' = 'wsl'
        'SystemSettingsBackup' = 'system-settings'
        'RegistryBackup' = 'registry'
    }

    $componentPath = Join-Path $mockDataRoot $componentMap[$TestName]

    switch ($DataFormat) {
        'json' {
            $dataFile = Join-Path $componentPath "$Component.json"
            if (Test-Path $dataFile) {
                return Get-Content $dataFile | ConvertFrom-Json
            }
        }
        'packagelist' {
            $dataFile = Join-Path $componentPath "$Component\apt-packages.txt"
            if (Test-Path $dataFile) {
                return Get-Content $dataFile
            }
        }
        'config' {
            $dataFile = Join-Path $componentPath "$Component\config.*"
            $configFiles = Get-ChildItem -Path (Split-Path $dataFile -Parent) -Filter (Split-Path $dataFile -Leaf)
            if ($configFiles) {
                return Get-Content $configFiles[0].FullName -Raw
            }
        }
    }

    return $null
}

function Test-MockDataIntegrity {
    <#
    .SYNOPSIS
        Validates the integrity and completeness of mock data.

    .PARAMETER TestType
        Type of test to validate mock data for.

    .RETURNS
        PSObject with validation results.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Unit', 'Integration', 'FileOperations', 'EndToEnd', 'All')]
        [string]$TestType = 'All'
    )

    Write-Information -MessageData "🔍 Validating mock data integrity for $TestType tests..." -InformationAction Continue

    $testPaths = Get-StandardTestPaths
    $mockDataRoot = $testPaths.TestMockData

    $validation = @{
        TestType = $TestType
        Valid = $true
        Issues = @()
        ComponentStatus = @{}
        Summary = @{
            TotalComponents = 0
            ValidComponents = 0
            IssuesFound = 0
        }
    }

    # Define required components for each test type
    $requiredComponents = @{
        'Unit' = @('unit')
        'Integration' = @('applications', 'gaming', 'cloud', 'wsl', 'system-settings', 'registry')
        'FileOperations' = @('file-operations')
        'EndToEnd' = @('end-to-end', 'applications', 'gaming', 'cloud', 'wsl', 'system-settings')
        'All' = @('unit', 'applications', 'gaming', 'cloud', 'wsl', 'system-settings', 'registry', 'file-operations', 'end-to-end')
    }

    $componentsToCheck = $requiredComponents[$TestType]
    $validation.Summary.TotalComponents = $componentsToCheck.Count

    foreach ($component in $componentsToCheck) {
        $componentPath = Join-Path $mockDataRoot $component
        $componentValid = $true
        $componentIssues = @()

        if (-not (Test-Path $componentPath)) {
            $componentValid = $false
            $componentIssues += "Component directory missing: $component"
            $validation.Issues += "Missing component: $component"
        }
 else {
            # Check for required files based on component type
            $requiredFiles = switch ($component) {
                'applications' { @('winget', 'chocolatey', 'scoop') }
                'gaming' { @('steam', 'epic') }
                'cloud' { @('OneDrive', 'GoogleDrive', 'Dropbox') }
                'wsl' { @('distributions.json') }
                'system-settings' { @('display.json', 'power.json', 'network.json') }
                'registry' { @() } # Registry files are dynamic
                default { @() }
            }

            foreach ($requiredFile in $requiredFiles) {
                $filePath = if ($requiredFile.EndsWith('.json')) {
                    Join-Path $componentPath $requiredFile
                }
 else {
                    Join-Path $componentPath "$requiredFile.json"
                }

                if (-not (Test-Path $filePath)) {
                    $componentValid = $false
                    $componentIssues += "Missing required file: $requiredFile"
                    $validation.Issues += "Missing file in $component : $requiredFile"
                }
            }
        }

        $validation.ComponentStatus[$component] = @{
            Valid = $componentValid
            Issues = $componentIssues
        }

        if ($componentValid) {
            $validation.Summary.ValidComponents++
        }
 else {
            $validation.Summary.IssuesFound += $componentIssues.Count
        }
    }

    $validation.Valid = ($validation.Summary.IssuesFound -eq 0)

    # Report results
    if ($validation.Valid) {
        Write-Information -MessageData "✅ Mock data validation passed" -InformationAction Continue
        Write-Verbose -Message "   Components: $($validation.Summary.ValidComponents)/$($validation.Summary.TotalComponents)"
    }
 else {
        Write-Error -Message "❌ Mock data validation failed"
        Write-Verbose -Message "   Components: $($validation.Summary.ValidComponents)/$($validation.Summary.TotalComponents)"
        Write-Error -Message "   Issues: $($validation.Summary.IssuesFound)"

        foreach ($issue in $validation.Issues) {
            Write-Error -Message "     • $issue"
        }
    }

    return $validation
}

# Functions are available when dot-sourced







