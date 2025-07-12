#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Enhanced Mock Infrastructure for Windows Melody Recovery Testing

.DESCRIPTION
    Comprehensive mock data generation and management system providing realistic
    Windows environment simulation for all test categories:

    - System settings and configurations
    - Application data and installations
    - Gaming platforms and libraries
    - Cloud storage providers and sync
    - WSL distributions and packages
    - Registry keys and values
    - File system structures
    - Network and hardware configurations

.NOTES
    This enhanced infrastructure replaces basic mock utilities with comprehensive,
    realistic data generation that scales across unit, integration, and end-to-end tests.

    In Docker environments, dynamic mock data is generated in Docker volumes to avoid
    polluting the source tree, while static mock data remains in source control.
#>

# Enhanced mock infrastructure configuration
$script:EnhancedMockConfig = @{
    # Docker environment detection and paths
    DockerEnvironment = @{
        IsDockerEnvironment = $false
        DynamicMockRoot = $null
        DynamicPaths = @{}
        DockerIndicators = @()
    }

    DataSources = @{
        # Real-world application data for realistic testing
        WingetApps = @(
            @{ Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code"; Version = "1.88.1"; Source = "winget" }
            @{ Id = "Google.Chrome"; Name = "Google Chrome"; Version = "124.0.6367.208"; Source = "winget" }
            @{ Id = "Mozilla.Firefox"; Name = "Mozilla Firefox"; Version = "125.0.3"; Source = "winget" }
            @{ Id = "VideoLAN.VLC"; Name = "VLC Media Player"; Version = "3.0.20"; Source = "winget" }
            @{ Id = "7zip.7zip"; Name = "7-Zip"; Version = "24.01"; Source = "winget" }
            @{ Id = "Git.Git"; Name = "Git"; Version = "2.45.0"; Source = "winget" }
            @{ Id = "Microsoft.PowerShell"; Name = "PowerShell"; Version = "7.4.1"; Source = "winget" }
            @{ Id = "Docker.DockerDesktop"; Name = "Docker Desktop"; Version = "4.28.0"; Source = "winget" }
            @{ Id = "Microsoft.Teams"; Name = "Microsoft Teams"; Version = "24109.415.2669.7070"; Source = "winget" }
            @{ Id = "Slack.Slack"; Name = "Slack"; Version = "4.38.125"; Source = "winget" }
        )

        ChocolateyApps = @(
            @{ Id = "notepadplusplus"; Name = "Notepad++"; Version = "8.6.4"; Source = "chocolatey" }
            @{ Id = "wireshark"; Name = "Wireshark"; Version = "4.2.4"; Source = "chocolatey" }
            @{ Id = "putty"; Name = "PuTTY"; Version = "0.80"; Source = "chocolatey" }
            @{ Id = "filezilla"; Name = "FileZilla"; Version = "3.66.5"; Source = "chocolatey" }
            @{ Id = "keepass"; Name = "KeePass"; Version = "2.56"; Source = "chocolatey" }
        )

        ScoopApps = @(
            @{ Id = "nodejs"; Name = "Node.js"; Version = "20.12.2"; Source = "scoop"; Bucket = "main" }
            @{ Id = "python"; Name = "Python"; Version = "3.12.3"; Source = "scoop"; Bucket = "main" }
            @{ Id = "go"; Name = "Go"; Version = "1.22.2"; Source = "scoop"; Bucket = "main" }
            @{ Id = "rust"; Name = "Rust"; Version = "1.77.2"; Source = "scoop"; Bucket = "main" }
            @{ Id = "ripgrep"; Name = "ripgrep"; Version = "14.1.0"; Source = "scoop"; Bucket = "main" }
        )

        SteamGames = @(
            @{ AppId = "730"; Name = "Counter-Strike 2"; InstallDir = "Counter-Strike Global Offensive"; SizeOnDisk = "27834567890" }
            @{ AppId = "570"; Name = "Dota 2"; InstallDir = "dota 2 beta"; SizeOnDisk = "26843545600" }
            @{ AppId = "440"; Name = "Team Fortress 2"; InstallDir = "Team Fortress 2"; SizeOnDisk = "15367890123" }
            @{ AppId = "271590"; Name = "Grand Theft Auto V"; InstallDir = "Grand Theft Auto V"; SizeOnDisk = "94567890123" }
            @{ AppId = "292030"; Name = "The Witcher 3: Wild Hunt"; InstallDir = "The Witcher 3"; SizeOnDisk = "65432109876" }
        )

        EpicGames = @(
            @{ DisplayName = "Fortnite"; AppName = "Fortnite"; InstallLocation = "C:\Program Files\Epic Games\Fortnite"; InstallSize = "87654321098" }
            @{ DisplayName = "Rocket League"; AppName = "Sugar"; InstallLocation = "C:\Program Files\Epic Games\rocketleague"; InstallSize = "23456789012" }
            @{ DisplayName = "Fall Guys"; AppName = "0a2d9f6403244d12969e11da6713137b"; InstallLocation = "C:\Program Files\Epic Games\FallGuys"; InstallSize = "45678901234" }
        )

        WSLDistributions = @(
            @{ Name = "Ubuntu"; Version = "22.04.3"; DefaultUser = "testuser"; State = "Running" }
            @{ Name = "Debian"; Version = "12.5"; DefaultUser = "testuser"; State = "Stopped" }
            @{ Name = "Ubuntu-20.04"; Version = "20.04.6"; DefaultUser = "devuser"; State = "Stopped" }
        )

        CloudProviders = @(
            @{ Name = "OneDrive"; Path = "$env:USERPROFILE\OneDrive"; SyncStatus = "UpToDate"; Account = "user@example.com" }
            @{ Name = "GoogleDrive"; Path = "$env:USERPROFILE\Google Drive"; SyncStatus = "Syncing"; Account = "user@gmail.com" }
            @{ Name = "Dropbox"; Path = "$env:USERPROFILE\Dropbox"; SyncStatus = "UpToDate"; Account = "user@dropbox.com" }
            @{ Name = "Box"; Path = "$env:USERPROFILE\Box"; SyncStatus = "Error"; Account = "user@company.com" }
        )
    }

    Templates = @{
        # Realistic system configuration templates
        DisplaySettings = @{
            PrimaryDisplay = @{
                Width = 1920; Height = 1080; RefreshRate = 60
                ColorDepth = 32; Orientation = 0; ScaleFactor = 100
            }
            SecondaryDisplay = @{
                Width = 1366; Height = 768; RefreshRate = 60
                ColorDepth = 32; Orientation = 0; ScaleFactor = 100
            }
        }

        PowerSettings = @{
            ActiveScheme = "High performance"
            ScreenTimeout = 15; SleepTimeout = 30; HibernateTimeout = 60
            USBSelectiveSuspend = $false; HybridSleep = $true
        }

        NetworkSettings = @{
            Adapters = @(
                @{ Name = "Ethernet"; Type = "Wired"; Status = "Connected"; IP = "192.168.1.100" }
                @{ Name = "Wi-Fi"; Type = "Wireless"; Status = "Connected"; IP = "192.168.1.101" }
            )
            DNS = @("8.8.8.8", "8.8.4.4")
            Gateway = "192.168.1.1"
        }
    }

    FileSystemStructure = @{
        # Common Windows application data paths
        AppDataPaths = @(
            "AppData\Local\Microsoft\Edge\User Data\Default\Preferences"
            "AppData\Local\Google\Chrome\User Data\Default\Preferences"
            "AppData\Local\Mozilla\Firefox\Profiles\default\prefs.js"
            "AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
            "AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState"
            "AppData\Roaming\7-Zip\7zFM.ini"
            "AppData\Local\Steam\config\config.vdf"
            "AppData\Roaming\Git\config"
        )

        ProgramFilesPaths = @(
            "Microsoft\Edge\Application\msedge.exe"
            "Google\Chrome\Application\chrome.exe"
            "Mozilla Firefox\firefox.exe"
            "7-Zip\7z.exe"
            "Git\bin\git.exe"
            "Steam\steam.exe"
            "Microsoft\Teams\current\Teams.exe"
        )

        SystemPaths = @(
            "Windows\System32\drivers\etc\hosts"
            "Windows\System32\WindowsPowerShell\v1.0\profile.ps1"
            "ProgramData\Microsoft\Windows\Start Menu\Programs"
            "Users\Public\Desktop"
        )
    }
}

function Initialize-DockerEnvironment {
    <#
    .SYNOPSIS
        Detects Docker environment and initializes dynamic mock data paths.

    .DESCRIPTION
        Checks for Docker environment variables and sets up appropriate paths
        for dynamic mock data generation in Docker volumes.

        SAFETY: Enhanced mock infrastructure can only run in Docker environments
        to prevent source tree pollution.
    #>

    # Check for Docker environment indicators
    $isDocker = $false
    $dynamicPaths = @{}
    $dockerIndicators = @()

    # Primary check: Docker environment variables
    $dockerEnvVars = @(
        'DYNAMIC_MOCK_ROOT',
        'DYNAMIC_APPLICATIONS',
        'DYNAMIC_GAMING',
        'DYNAMIC_SYSTEM_SETTINGS',
        'DYNAMIC_WSL_ROOT',
        'DYNAMIC_WSL_PACKAGES',
        'DYNAMIC_CLOUD_ROOT'
    )

    foreach ($envVar in $dockerEnvVars) {
        $value = [Environment]::GetEnvironmentVariable($envVar)
        if ($value) {
            $isDocker = $true
            $dynamicPaths[$envVar] = $value
            $dockerIndicators += "Environment variable: $envVar"
        }
    }

    # Secondary checks: Container indicators
    $containerChecks = @(
        @{ Test = { Test-Path "/.dockerenv" }; Name = "Docker environment file (/.dockerenv)" },
        @{ Test = { $env:HOSTNAME -and $env:HOSTNAME.StartsWith("wmr-") }; Name = "WMR container hostname" },
        @{ Test = { $env:CONTAINER_NAME -and $env:CONTAINER_NAME.StartsWith("wmr-") }; Name = "WMR container name" },
        @{ Test = { $env:DOCKER_CONTAINER -eq "true" }; Name = "Docker container flag" },
        @{ Test = { Test-Path "/proc/1/cgroup" -and (Get-Content "/proc/1/cgroup" -ErrorAction SilentlyContinue | Select-String "docker") }; Name = "Docker cgroup detection" }
    )

    foreach ($check in $containerChecks) {
        try {
            if (& $check.Test) {
                $isDocker = $true
                $dockerIndicators += $check.Name
            }
        } catch {
            # Ignore errors in detection
        }
    }

    # Tertiary check: Docker volume mounts
    if (-not $isDocker) {
        $dockerVolumePaths = @(
            "/dynamic-mock-data",
            "/dynamic-applications",
            "/dynamic-gaming",
            "/mock-registry",
            "/mock-appdata"
        )

        foreach ($volumePath in $dockerVolumePaths) {
            # Only test Unix-style paths if we're actually on Unix or in Docker
            if (($IsLinux -or $IsMacOS) -and (Test-Path $volumePath)) {
                $isDocker = $true
                $dockerIndicators += "Docker volume mount: $volumePath"
                break
            }
        }
    }

    # Update configuration
    $script:EnhancedMockConfig.DockerEnvironment.IsDockerEnvironment = $isDocker
    $script:EnhancedMockConfig.DockerEnvironment.DynamicPaths = $dynamicPaths
    $script:EnhancedMockConfig.DockerEnvironment.DockerIndicators = $dockerIndicators

    if ($isDocker) {
        # Set default dynamic root if not specified - only for actual Docker environments
        if (-not $dynamicPaths['DYNAMIC_MOCK_ROOT']) {
            $dynamicPaths['DYNAMIC_MOCK_ROOT'] = '/dynamic-mock-data'
        }
        $script:EnhancedMockConfig.DockerEnvironment.DynamicMockRoot = $dynamicPaths['DYNAMIC_MOCK_ROOT']

        Write-Information -MessageData "🐳 Docker environment detected" -InformationAction Continue
        Write-Verbose -Message "   Dynamic mock root: $($dynamicPaths['DYNAMIC_MOCK_ROOT'])"
        Write-Verbose -Message "   Indicators: $($dockerIndicators.Count)"

        # Create Docker environment lock file
        Set-DockerEnvironmentLock
    } else {
        Write-Information -MessageData "🖥️  Local environment detected" -InformationAction Continue
        Write-Warning -Message "   Enhanced mocks DISABLED for safety"
        # Clear any Unix-style paths that might cause Windows pollution
        $dynamicPaths.Clear()
    }
}

function Set-DockerEnvironmentLock {
    <#
    .SYNOPSIS
        Creates a Docker environment lock file to validate container execution.

    .DESCRIPTION
        Creates a lock file with Docker environment metadata that can be used
        to validate that enhanced mock operations are running in Docker.
    #>

    try {
        $lockData = @{
            IsDockerEnvironment = $true
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
            ProcessId = $PID
            Hostname = $env:HOSTNAME
            ContainerName = $env:CONTAINER_NAME
            DynamicPaths = $script:EnhancedMockConfig.DockerEnvironment.DynamicPaths
            DockerIndicators = $script:EnhancedMockConfig.DockerEnvironment.DockerIndicators
        }

        # Cross-platform lock path
        if ($IsLinux -or $IsMacOS) {
            $lockPath = "/tmp/wmr-docker-env.lock"
        } else {
            # Windows - use temp directory
            $tempDir = $env:TEMP ?? $env:TMP ?? "$env:USERPROFILE\AppData\Local\Temp"
            $lockPath = Join-Path $tempDir "wmr-docker-env.lock"
        }

        # Ensure directory exists
        $lockDir = Split-Path $lockPath -Parent
        if (-not (Test-Path $lockDir)) {
            New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
        }

        $lockData | ConvertTo-Json -Depth 10 | Set-Content -Path $lockPath -Encoding UTF8

        # Also set in environment for quick access
        $env:WMR_DOCKER_LOCK = $lockPath

        Write-Verbose -Message "   🔒 Docker environment lock created: $lockPath"

    } catch {
        Write-Warning "⚠️  Could not create Docker environment lock: $_"
    }
}

function Test-DockerEnvironmentLock {
    <#
    .SYNOPSIS
        Validates that we're running in a Docker environment using lock file.

    .DESCRIPTION
        Checks for Docker environment lock file and validates its contents
        to ensure enhanced mock operations are only running in Docker.

    .PARAMETER ThrowOnFailure
        If true, throws an exception when not in Docker environment.
        If false, returns boolean result.
    #>
    param(
        [switch]$ThrowOnFailure
    )

    $isValid = $false
    $reason = "Unknown"

    try {
        # Check for lock file
        $lockPath = $env:WMR_DOCKER_LOCK
        if (-not $lockPath) {
            # Cross-platform default lock path
            if ($IsLinux -or $IsMacOS) {
                $lockPath = "/tmp/wmr-docker-env.lock"
            } else {
                $tempDir = $env:TEMP ?? $env:TMP ?? "$env:USERPROFILE\AppData\Local\Temp"
                $lockPath = Join-Path $tempDir "wmr-docker-env.lock"
            }
        }

        if (Test-Path $lockPath) {
            $lockData = Get-Content $lockPath | ConvertFrom-Json

            # Validate lock data
            if ($lockData.IsDockerEnvironment -and
                $lockData.ProcessId -eq $PID -and
                $lockData.DynamicPaths -and
                $lockData.DockerIndicators) {
                $isValid = $true
                $reason = "Valid Docker environment lock"
            } else {
                $reason = "Invalid lock data"
            }
        } else {
            $reason = "No Docker environment lock file found"
        }

        # Additional runtime validation
        if ($isValid) {
            $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment
            if (-not $dockerConfig.IsDockerEnvironment) {
                $isValid = $false
                $reason = "Docker environment not detected at runtime"
            }
        }

    } catch {
        $isValid = $false
        $reason = "Lock validation error: $_"
    }

    if ($ThrowOnFailure -and -not $isValid) {
        throw "🚫 SAFETY VIOLATION: Enhanced mock infrastructure can only run in Docker environments. Reason: $reason"
    }

    return $isValid
}

function Assert-DockerEnvironment {
    <#
    .SYNOPSIS
        Asserts that we're running in a Docker environment or throws an exception.

    .DESCRIPTION
        Safety check that must be called before any enhanced mock operations.
        Throws an exception if not running in Docker environment.
    #>

    Write-Warning -Message "🔒 Validating Docker environment..."

    # Re-initialize Docker environment to ensure fresh detection
    Initialize-DockerEnvironment

    # Validate using lock file
    $isValid = Test-DockerEnvironmentLock -ThrowOnFailure:$false

    if (-not $isValid) {
        Write-Error -Message "❌ SAFETY CHECK FAILED"
        Write-Error -Message "   Enhanced mock infrastructure requires Docker environment"
        Write-Error -Message "   This prevents source tree pollution and ensures proper isolation"
        Write-Information -MessageData ""  -InformationAction Continue-ForegroundColor Red
        Write-Warning -Message "   To run enhanced mocks:"
        Write-Warning -Message "   1. Use: docker-compose -f docker-compose.test.yml up test-runner"
        Write-Warning -Message "   2. Or run tests inside Docker containers"
        Write-Information -MessageData ""  -InformationAction Continue-ForegroundColor Red

        throw "🚫 SAFETY VIOLATION: Enhanced mock infrastructure can only run in Docker environments"
    }

    Write-Information -MessageData "✅ Docker environment validated" -InformationAction Continue
    Write-Information -MessageData "   Safe to proceed with enhanced mock operations" -InformationAction Continue
}

function Get-DynamicMockPath {
    <#
    .SYNOPSIS
        Gets the appropriate path for dynamic mock data based on environment.

    .PARAMETER Component
        Component type (applications, gaming, system-settings, wsl, cloud).

    .PARAMETER SubPath
        Optional sub-path within the component.

    .EXAMPLE
        Get-DynamicMockPath -Component "applications"
        Get-DynamicMockPath -Component "gaming" -SubPath "steam"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('applications', 'gaming', 'system-settings', 'wsl', 'cloud', 'registry')]
        [string]$Component,

        [string]$SubPath
    )

    $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment

    if ($dockerConfig.IsDockerEnvironment) {
        # Use Docker volume paths
        $basePath = switch ($Component) {
            'applications' { $dockerConfig.DynamicPaths['DYNAMIC_APPLICATIONS'] ?? '/dynamic-applications' }
            'gaming' { $dockerConfig.DynamicPaths['DYNAMIC_GAMING'] ?? '/dynamic-gaming' }
            'system-settings' { $dockerConfig.DynamicPaths['DYNAMIC_SYSTEM_SETTINGS'] ?? '/dynamic-system-settings' }
            'wsl' { $dockerConfig.DynamicPaths['DYNAMIC_WSL_ROOT'] ?? '/dynamic-wsl' }
            'cloud' { $dockerConfig.DynamicPaths['DYNAMIC_CLOUD_ROOT'] ?? '/dynamic-cloud' }
            'registry' { Join-Path ($dockerConfig.DynamicPaths['DYNAMIC_MOCK_ROOT'] ?? '/dynamic-mock-data') 'registry' }
            default { Join-Path ($dockerConfig.DynamicPaths['DYNAMIC_MOCK_ROOT'] ?? '/dynamic-mock-data') $Component }
        }
    } else {
        # Use local standardized test paths with dynamic subdirectory
        $testPaths = Get-StandardTestPaths
        $basePath = Join-Path $testPaths.TestMockData $Component "generated"
    }

    if ($SubPath) {
        return Join-Path $basePath $SubPath
    } else {
        return $basePath
    }
}

function Get-StaticMockPath {
    <#
    .SYNOPSIS
        Gets the path for static mock data (always in source control).

    .PARAMETER Component
        Component type (applications, gaming, system-settings, wsl, cloud).

    .PARAMETER SubPath
        Optional sub-path within the component.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component,

        [string]$SubPath
    )

    $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment

    if ($dockerConfig.IsDockerEnvironment) {
        # In Docker, static mock data is mounted read-only
        $basePath = switch ($Component) {
            'registry' { '/mock-registry' }
            'appdata' { '/mock-appdata' }
            'programfiles' { '/mock-programfiles' }
            'steam' { '/mock-steam' }
            'epic' { '/mock-epic' }
            'gog' { '/mock-gog' }
            'ea' { '/mock-ea' }
            'wsl' { '/mnt/test-data' }
            'cloud' { '/mock-data/cloud' }
            default { "/mock-data/$Component" }
        }
    } else {
        # Local environment uses source tree paths
        $testPaths = Get-StandardTestPaths
        $basePath = Join-Path $testPaths.TestMockData $Component
    }

    if ($SubPath) {
        return Join-Path $basePath $SubPath
    } else {
        return $basePath
    }
}

function Initialize-EnhancedMockInfrastructure {
    <#
    .SYNOPSIS
        Initializes the enhanced mock infrastructure with comprehensive data generation.

    .PARAMETER TestType
        Type of testing requiring mock data (Unit, Integration, FileOperations, EndToEnd, All).

    .PARAMETER Scope
        Scope of mock data to generate (Minimal, Standard, Comprehensive, Enterprise).

    .PARAMETER Force
        Force regeneration of existing mock data.

    .PARAMETER SkipSafetyCheck
        Skip Docker environment safety check (for testing only).

    .EXAMPLE
        Initialize-EnhancedMockInfrastructure -TestType "Integration" -Scope "Standard"
        Initialize-EnhancedMockInfrastructure -TestType "EndToEnd" -Scope "Comprehensive" -Force
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Unit', 'Integration', 'FileOperations', 'EndToEnd', 'All')]
        [string]$TestType = 'All',

        [ValidateSet('Minimal', 'Standard', 'Comprehensive', 'Enterprise')]
        [string]$Scope = 'Standard',

        [switch]$Force,

        [switch]$SkipSafetyCheck
    )

    Write-Information -MessageData "🚀 Initializing Enhanced Mock Infrastructure" -InformationAction Continue
    Write-Verbose -Message "   Test Type: $TestType | Scope: $Scope | Force: $Force"
    Write-Information -MessageData "" -InformationAction Continue

    # SAFETY CHECK: Ensure we're running in Docker environment
    if (-not $SkipSafetyCheck) {
        try {
            Assert-DockerEnvironment
        } catch {
            Write-Error -Message "🚫 Enhanced mock infrastructure initialization BLOCKED"
            Write-Error -Message "   Reason: $_"
            return $null
        }
    }

    # Get appropriate mock data root based on environment
    $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment
    if ($dockerConfig.IsDockerEnvironment) {
        $mockDataRoot = $dockerConfig.DynamicMockRoot
        Write-Information -MessageData "   Environment: Docker (dynamic data in volumes)" -InformationAction Continue
    } else {
        $testPaths = Get-StandardTestPaths
        $mockDataRoot = $testPaths.TestMockData
        Write-Information -MessageData "   Environment: Local (dynamic data in generated subdirectories)" -InformationAction Continue
    }

    # Initialize mock data generators based on test type
    switch ($TestType) {
        'Unit' {
            Initialize-UnitMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
        }
        'Integration' {
            Initialize-IntegrationMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
        }
        'FileOperations' {
            Initialize-FileOperationsMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
        }
        'EndToEnd' {
            Initialize-EndToEndMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
        }
        'All' {
            Initialize-UnitMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
            Initialize-IntegrationMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
            Initialize-FileOperationsMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
            Initialize-EndToEndMockData -MockRoot $mockDataRoot -Scope $Scope -Force:$Force
        }
    }

    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "🎉 Enhanced mock infrastructure initialized successfully!" -InformationAction Continue
    Write-Verbose -Message "   Root: $mockDataRoot"
    Write-Verbose -Message "   Type: $TestType | Scope: $Scope"
    Write-Information -MessageData "" -InformationAction Continue
}

function Initialize-UnitMockData {
    <#
    .SYNOPSIS
        Initializes minimal mock data for unit tests (logic-only testing).
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)

    Write-Warning -Message "📦 Generating unit test mock data..."

    # Unit tests need minimal mock data - mostly configuration objects
    $unitMockPath = Join-Path $MockRoot "unit"
    New-Item -Path $unitMockPath -ItemType Directory -Force | Out-Null

    # Generate mock configuration objects
    New-MockConfiguration -OutputPath (Join-Path $unitMockPath "configurations") -Scope $Scope

    # Generate sample template data
    New-MockTemplateData -OutputPath (Join-Path $unitMockPath "templates") -Scope $Scope

    Write-Information -MessageData "  ✓ Unit mock data generated" -InformationAction Continue
}

function Initialize-IntegrationMockData {
    <#
    .SYNOPSIS
        Initializes comprehensive mock data for integration tests.
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)

    Write-Warning -Message "🔧 Generating integration test mock data..."

    # Integration tests need realistic system data
    $components = @('applications', 'system-settings', 'gaming', 'cloud', 'wsl', 'registry')

    foreach ($component in $components) {
        # Use dynamic mock path for each component
        $componentPath = Get-DynamicMockPath -Component $component

        switch ($component) {
            'applications' {
                New-ApplicationMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'system-settings' {
                New-SystemSettingsMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'gaming' {
                New-GamingMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'cloud' {
                New-CloudMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'wsl' {
                New-WSLMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'registry' {
                New-RegistryMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
        }

        Write-Information -MessageData "  ✓ $component mock data generated" -InformationAction Continue
    }
}

function Initialize-FileOperationsMockData {
    <#
    .SYNOPSIS
        Initializes safe mock data for file operations testing.
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)

    Write-Warning -Message "📁 Generating file operations mock data..."

    # File operations need realistic file structures
    $fileOpsMockPath = Join-Path $MockRoot "file-operations"

    # Generate realistic AppData structure
    New-AppDataStructure -OutputPath (Join-Path $fileOpsMockPath "appdata") -Scope $Scope

    # Generate Program Files structure
    New-ProgramFilesStructure -OutputPath (Join-Path $fileOpsMockPath "programfiles") -Scope $Scope

    # Generate test configuration files
    New-ConfigurationFiles -OutputPath (Join-Path $fileOpsMockPath "configs") -Scope $Scope

    Write-Information -MessageData "  ✓ File operations mock data generated" -InformationAction Continue
}

function Initialize-EndToEndMockData {
    <#
    .SYNOPSIS
        Initializes comprehensive mock data for end-to-end testing.
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)

    Write-Warning -Message "🌐 Generating end-to-end mock data..."

    # End-to-end tests need complete environment simulation
    $e2eMockPath = Join-Path $MockRoot "end-to-end"

    # Generate multiple user profiles
    New-UserProfileMockData -OutputPath (Join-Path $e2eMockPath "users") -Scope $Scope

    # Generate system state data
    New-SystemStateMockData -OutputPath (Join-Path $e2eMockPath "system") -Scope $Scope

    # Generate network and hardware configurations
    New-HardwareMockData -OutputPath (Join-Path $e2eMockPath "hardware") -Scope $Scope

    Write-Information -MessageData "  ✓ End-to-end mock data generated" -InformationAction Continue
}

function New-ApplicationMockData {
    <#
    .SYNOPSIS
        Generates realistic application installation and configuration data.
    #>
    param([string]$OutputPath, [string]$Scope, [bool]$Force)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # Generate winget package data
    $wingetPath = Join-Path $OutputPath "winget"
    New-Item -Path $wingetPath -ItemType Directory -Force | Out-Null

    $wingetData = @{
        Sources = @(
            @{ Name = "winget"; Argument = "https://cdn.winget.microsoft.com/cache" }
        )
        Packages = $script:EnhancedMockConfig.DataSources.WingetApps
    }

    $wingetData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $wingetPath "installed_packages.json") -Encoding UTF8

    # Generate chocolatey package data
    $chocoPath = Join-Path $OutputPath "chocolatey"
    New-Item -Path $chocoPath -ItemType Directory -Force | Out-Null

    $chocoData = @{
        Packages = $script:EnhancedMockConfig.DataSources.ChocolateyApps
    }

    $chocoData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $chocoPath "installed_packages.json") -Encoding UTF8

    # Generate scoop package data
    $scoopPath = Join-Path $OutputPath "scoop"
    New-Item -Path $scoopPath -ItemType Directory -Force | Out-Null

    $scoopData = @{
        Apps = $script:EnhancedMockConfig.DataSources.ScoopApps
        Buckets = @(
            @{ Name = "main"; Source = "https://github.com/ScoopInstaller/Main" }
            @{ Name = "extras"; Source = "https://github.com/ScoopInstaller/Extras" }
        )
    }

    $scoopData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $scoopPath "installed_packages.json") -Encoding UTF8

    Write-Verbose -Message "    ✓ Application mock data: winget, chocolatey, scoop"
}

function New-GamingMockData {
    <#
    .SYNOPSIS
        Generates realistic gaming platform data (Steam, Epic, GOG, EA).
    #>
    param([string]$OutputPath, [string]$Scope, [bool]$Force)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # Steam data
    $steamPath = Join-Path $OutputPath "steam"
    New-Item -Path $steamPath -ItemType Directory -Force | Out-Null

    $steamConfig = @"
"InstallConfigStore"
{
    "Software"
    {
        "Valve"
        {
            "Steam"
            {
                "SourceModInstallPath"  "C:\Program Files (x86)\Steam\steamapps\sourcemods"
                "BaseInstallFolder_1"   "C:\Program Files (x86)\Steam"
                "BaseInstallFolder_2"   "D:\SteamLibrary"
            }
        }
    }
}
"@

    $steamConfig | Set-Content -Path (Join-Path $steamPath "config.vdf") -Encoding UTF8

    $steamApps = @{
        Apps = $script:EnhancedMockConfig.DataSources.SteamGames
    }

    $steamApps | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $steamPath "installed_games.json") -Encoding UTF8

    # Epic Games data
    $epicPath = Join-Path $OutputPath "epic"
    New-Item -Path $epicPath -ItemType Directory -Force | Out-Null

    $epicData = @{
        InstallationList = $script:EnhancedMockConfig.DataSources.EpicGames
    }

    $epicData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $epicPath "installed_games.json") -Encoding UTF8

    # GOG data
    $gogPath = Join-Path $OutputPath "gog"
    New-Item -Path $gogPath -ItemType Directory -Force | Out-Null

    $gogConfig = @"
[Galaxy]
clientExecutable=C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe
libraryPath=C:\Program Files (x86)\GOG Galaxy\Games
"@

    $gogConfig | Set-Content -Path (Join-Path $gogPath "config.cfg") -Encoding UTF8

    # EA Desktop data
    $eaPath = Join-Path $OutputPath "ea"
    New-Item -Path $eaPath -ItemType Directory -Force | Out-Null

    $eaConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <appSettings>
        <add key="InstallPath" value="C:\Program Files\EA Games" />
        <add key="LibraryPath" value="C:\Users\Public\Documents\EA Games" />
    </appSettings>
</configuration>
"@

    $eaConfig | Set-Content -Path (Join-Path $eaPath "config.xml") -Encoding UTF8

    Write-Verbose -Message "    ✓ Gaming mock data: Steam, Epic, GOG, EA"
}

function New-SystemSettingsMockData {
    <#
    .SYNOPSIS
        Generates realistic Windows system settings data.
    #>
    param([string]$OutputPath, [string]$Scope, [bool]$Force)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # Display settings
    $displayData = $script:EnhancedMockConfig.Templates.DisplaySettings
    $displayData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "display.json") -Encoding UTF8

    # Power settings
    $powerData = $script:EnhancedMockConfig.Templates.PowerSettings
    $powerData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "power.json") -Encoding UTF8

    # Network settings
    $networkData = $script:EnhancedMockConfig.Templates.NetworkSettings
    $networkData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "network.json") -Encoding UTF8

    # Sound settings
    $soundData = @{
        DefaultPlaybackDevice = "Speakers (Realtek High Definition Audio)"
        DefaultRecordingDevice = "Microphone (Realtek High Definition Audio)"
        Volume = 75
        Muted = $false
    }
    $soundData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "sound.json") -Encoding UTF8

    # Mouse and keyboard settings
    $inputData = @{
        Mouse = @{
            PointerSpeed = 6
            DoubleClickSpeed = 500
            SwapButtons = $false
            WheelScrollLines = 3
        }
        Keyboard = @{
            RepeatDelay = 250
            RepeatRate = 31
            CursorBlinkRate = 530
        }
    }
    $inputData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "input.json") -Encoding UTF8

    Write-Verbose -Message "    ✓ System settings mock data: display, power, network, sound, input"
}

function New-CloudMockData {
    <#
    .SYNOPSIS
        Generates realistic cloud storage provider data.
    #>
    param([string]$OutputPath, [string]$Scope, [bool]$Force)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    foreach ($provider in $script:EnhancedMockConfig.DataSources.CloudProviders) {
        $providerPath = Join-Path $OutputPath $provider.Name
        New-Item -Path $providerPath -ItemType Directory -Force | Out-Null

        # Create WindowsMelodyRecovery directory structure
        $wmrPath = Join-Path $providerPath "WindowsMelodyRecovery"
        New-Item -Path $wmrPath -ItemType Directory -Force | Out-Null

        # Provider info file
        $providerInfo = @{
            Name = $provider.Name
            Path = $provider.Path
            SyncStatus = $provider.SyncStatus
            Account = $provider.Account
            LastSync = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            AvailableSpace = "50GB"
            UsedSpace = "25GB"
        }

        $providerInfo | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $providerPath "cloud-provider-info.json") -Encoding UTF8

        # Sample backup manifest
        $backupManifest = @{
            Version = "1.0"
            CreatedDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            MachineName = "TEST-MACHINE"
            Components = @("applications", "system-settings", "gaming", "wsl")
        }

        $backupManifest | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $wmrPath "backup-manifest.json") -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ Cloud provider mock data: OneDrive, GoogleDrive, Dropbox, Box"
}

function New-WSLMockData {
    <#
    .SYNOPSIS
        Generates realistic WSL distribution and package data.
    #>
    param([string]$OutputPath, [string]$Scope, [bool]$Force)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # WSL distribution list
    $wslData = @{
        Distributions = $script:EnhancedMockConfig.DataSources.WSLDistributions
    }

    $wslData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "distributions.json") -Encoding UTF8

    # Package data for each distribution
    foreach ($distro in $script:EnhancedMockConfig.DataSources.WSLDistributions) {
        $distroPath = Join-Path $OutputPath $distro.Name
        New-Item -Path $distroPath -ItemType Directory -Force | Out-Null

        # APT packages (for Ubuntu/Debian)
        if ($distro.Name -like "*Ubuntu*" -or $distro.Name -eq "Debian") {
            $aptPackages = @(
                "curl/jammy-updates,jammy-security,now 7.81.0-1ubuntu1.15 amd64 [installed]"
                "git/jammy-updates,now 1:2.34.1-1ubuntu1.10 amd64 [installed]"
                "vim/jammy,now 2:8.2.3458-2ubuntu2.2 amd64 [installed]"
                "wget/jammy-updates,jammy-security,now 1.21.2-2ubuntu1 amd64 [installed]"
                "build-essential/jammy,now 12.9ubuntu3 amd64 [installed]"
            )

            $aptPackages -join "`n" | Set-Content -Path (Join-Path $distroPath "apt-packages.txt") -Encoding UTF8
        }

        # PIP packages
        $pipPackages = @(
            "certifi==2024.2.2"
            "charset-normalizer==3.3.2"
            "idna==3.6"
            "pip==24.0"
            "requests==2.31.0"
            "setuptools==69.2.0"
            "urllib3==2.2.1"
        )

        $pipPackages -join "`n" | Set-Content -Path (Join-Path $distroPath "pip-packages.txt") -Encoding UTF8

        # NPM packages (global)
        $npmPackages = @{
            dependencies = @{
                "@angular/cli" = "17.3.4"
                "typescript" = "5.4.5"
                "nodemon" = "3.1.0"
                "eslint" = "8.57.0"
                "prettier" = "3.2.5"
            }
        }

        $npmPackages | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $distroPath "npm-packages.json") -Encoding UTF8

        # WSL configuration
        $wslConfig = @"
[wsl2]
memory=4GB
processors=2
localhostForwarding=true
kernelCommandLine = cgroup_v2=1 swapaccount=1

[user]
default=$($distro.DefaultUser)
"@

        $wslConfig | Set-Content -Path (Join-Path $distroPath "wsl.conf") -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ WSL mock data: Ubuntu, Debian, packages, configurations"
}

function New-RegistryMockData {
    <#
    .SYNOPSIS
        Generates realistic Windows registry data for testing.
    #>
    param([string]$OutputPath, [string]$Scope, [bool]$Force)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # Common registry keys and values
    $registryData = @{
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' = @{
            'ShowHidden' = 1
            'HideFileExt' = 0
            'ShowSuperHidden' = 1
        }
        'HKCU\Control Panel\Desktop' = @{
            'Wallpaper' = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
            'WallpaperStyle' = '10'
            'TileWallpaper' = '0'
        }
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion' = @{
            'ProgramFilesDir' = 'C:\Program Files'
            'ProgramFilesDir (x86)' = 'C:\Program Files (x86)'
            'CommonFilesDir' = 'C:\Program Files\Common Files'
        }
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes' = @{
            'CurrentTheme' = 'C:\WINDOWS\resources\Themes\aero.theme'
            'ThemeChangesMousePointers' = 0
        }
    }

    foreach ($keyPath in $registryData.Keys) {
        $safePath = $keyPath -replace '[\\/:]', '_'
        $keyDataPath = Join-Path $OutputPath "$safePath.json"

        $registryData[$keyPath] | ConvertTo-Json -Depth 10 | Set-Content -Path $keyDataPath -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ Registry mock data: Explorer, Desktop, Themes, System"
}

function New-AppDataStructure {
    <#
    .SYNOPSIS
        Generates realistic AppData directory structure with configuration files.
    #>
    param([string]$OutputPath, [string]$Scope)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    foreach ($appDataPath in $script:EnhancedMockConfig.FileSystemStructure.AppDataPaths) {
        $fullPath = Join-Path $OutputPath $appDataPath
        $directory = Split-Path $fullPath -Parent

        New-Item -Path $directory -ItemType Directory -Force | Out-Null

        # Generate appropriate content based on file type
        $fileName = Split-Path $fullPath -Leaf
        $content = switch -Regex ($fileName) {
            '\.json$' { '{"version": "1.0", "settings": {}, "lastModified": "' + (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") + '"}' }
            '\.js$' { '// Configuration file generated for testing' }
            '\.ini$' { '[Settings]' + "`nVersion=1.0" + "`nLastModified=" + (Get-Date -Format "yyyy-MM-dd") }
            '\.vdf$' { '"AppInfo"' + "`n{" + "`n`t`"version`"`t`"1.0`"" + "`n}" }
            'config$' { '[core]' + "`n`tautocrlf = true" + "`n`tuser = testuser" }
            default { "Test configuration file: $fileName" }
        }

        $content | Set-Content -Path $fullPath -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ AppData structure: browser configs, app settings, user data"
}

function New-ProgramFilesStructure {
    <#
    .SYNOPSIS
        Generates realistic Program Files directory structure.
    #>
    param([string]$OutputPath, [string]$Scope)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    foreach ($programPath in $script:EnhancedMockConfig.FileSystemStructure.ProgramFilesPaths) {
        $fullPath = Join-Path $OutputPath $programPath
        $directory = Split-Path $fullPath -Parent

        New-Item -Path $directory -ItemType Directory -Force | Out-Null

        # Create mock executable info
        $exeInfo = @{
            FileName = Split-Path $fullPath -Leaf
            Version = "1.0.0.0"
            InstallDate = (Get-Date).ToString("yyyy-MM-dd")
            Size = Get-Random -Minimum 1000000 -Maximum 100000000
        }

        $exeInfo | ConvertTo-Json | Set-Content -Path "$fullPath.info" -Encoding UTF8
    }

    Write-Verbose -Message "    ✓ Program Files structure: applications, executables, metadata"
}

function New-MockConfiguration {
    <#
    .SYNOPSIS
        Generates mock configuration objects for unit testing.
    #>
    param([string]$OutputPath, [string]$Scope)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # Sample backup configuration
    $backupConfig = @{
        BackupRoot = "C:\TestBackups"
        CloudProvider = "OneDrive"
        EncryptionEnabled = $true
        Components = @("applications", "system-settings", "gaming")
        Schedule = @{
            Enabled = $true
            Frequency = "Daily"
            Time = "02:00"
        }
    }

    $backupConfig | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "backup-config.json") -Encoding UTF8

    # Sample restoration configuration
    $restoreConfig = @{
        RestoreRoot = "C:\TestRestore"
        Components = @("applications", "system-settings")
        Options = @{
            OverwriteExisting = $false
            CreateBackupBeforeRestore = $true
            VerifyIntegrity = $true
        }
    }

    $restoreConfig | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "restore-config.json") -Encoding UTF8
}

function New-MockTemplateData {
    <#
    .SYNOPSIS
        Generates mock template data for template processing tests.
    #>
    param([string]$OutputPath, [string]$Scope)

    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null

    # Sample template with various data types
    $sampleTemplate = @{
        metadata = @{
            name = "test-template"
            version = "1.0"
            description = "Sample template for testing"
            category = "system-settings"
            requirements = @("Windows 10+", "Administrator")
        }
        backup = @{
            registry = @(
                @{
                    path = "HKCU\Software\TestApp"
                    values = @("Setting1", "Setting2")
                }
            )
            files = @(
                @{
                    source = "%APPDATA%\TestApp\config.json"
                    backup_name = "testapp-config"
                }
            )
        }
        restore = @{
            registry = @(
                @{
                    path = "HKCU\Software\TestApp"
                    create_key = $true
                }
            )
            files = @(
                @{
                    backup_name = "testapp-config"
                    target = "%APPDATA%\TestApp\config.json"
                }
            )
        }
    }

    $sampleTemplate | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath "sample-template.json") -Encoding UTF8
}

function Get-EnhancedMockData {
    <#
    .SYNOPSIS
        Retrieves mock data for specific component and type.

    .PARAMETER Component
        Component type (applications, gaming, cloud, wsl, etc.).

    .PARAMETER DataType
        Specific data type within component.

    .EXAMPLE
        Get-EnhancedMockData -Component "applications" -DataType "winget"
        Get-EnhancedMockData -Component "gaming" -DataType "steam"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $false)]
        [string]$DataType
    )

    $testPaths = Get-StandardTestPaths
    $mockDataRoot = $testPaths.TestMockData

    $componentPath = Join-Path $mockDataRoot $Component

    if ($DataType) {
        $dataFile = Join-Path $componentPath "$DataType.json"
        if (Test-Path $dataFile) {
            return Get-Content $dataFile | ConvertFrom-Json
        }
    } else {
        if (Test-Path $componentPath) {
            $dataFiles = Get-ChildItem -Path $componentPath -Filter "*.json"
            $result = @{}
            foreach ($file in $dataFiles) {
                $key = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $result[$key] = Get-Content $file.FullName | ConvertFrom-Json
            }
            return $result
        }
    }

    return $null
}

function Reset-EnhancedMockData {
    <#
    .SYNOPSIS
        Resets mock data to clean state and regenerates.

    .PARAMETER Component
        Specific component to reset, or all if not specified.

    .PARAMETER Scope
        Scope of data to regenerate.

    .PARAMETER SkipSafetyCheck
        Skip Docker environment safety check (for testing only).
    #>
    [CmdletBinding()]
    param(
        [string]$Component,

        [ValidateSet('Minimal', 'Standard', 'Comprehensive', 'Enterprise')]
        [string]$Scope = 'Standard',

        [switch]$SkipSafetyCheck
    )

    Write-Warning -Message "🔄 Resetting enhanced mock data..."

    # SAFETY CHECK: Ensure we're running in Docker environment
    if (-not $SkipSafetyCheck) {
        try {
            Assert-DockerEnvironment
        } catch {
            Write-Error -Message "🚫 Enhanced mock data reset BLOCKED"
            Write-Error -Message "   Reason: $_"
            return $null
        }
    }

    $dockerConfig = $script:EnhancedMockConfig.DockerEnvironment

    if ($Component) {
        # Reset specific component
        if ($dockerConfig.IsDockerEnvironment) {
            # In Docker, simply regenerate in the volume (will overwrite existing)
            Write-Information -MessageData "  🐳 Docker environment: Regenerating $Component in volume" -InformationAction Continue
            $componentPath = Get-DynamicMockPath -Component $Component
        } else {
            # In local environment, clean only the generated subdirectory
            Write-Information -MessageData "  🖥️  Local environment: Cleaning $Component generated data" -InformationAction Continue
            $componentPath = Get-DynamicMockPath -Component $Component

            if (Test-Path $componentPath) {
                Remove-Item -Path $componentPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Information -MessageData "  ✓ Removed $Component dynamic data" -InformationAction Continue
            } else {
                Write-Information -MessageData "  ✅ No $Component dynamic data to clean" -InformationAction Continue
            }
        }

        # Regenerate specific component
        switch ($Component) {
            'applications' { New-ApplicationMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'gaming' { New-GamingMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'cloud' { New-CloudMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'wsl' { New-WSLMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'system-settings' { New-SystemSettingsMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'registry' { New-RegistryMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
        }

        Write-Information -MessageData "  ✓ Regenerated $Component mock data" -InformationAction Continue
    } else {
        # Reset all components
        if ($dockerConfig.IsDockerEnvironment) {
            Write-Information -MessageData "  🐳 Docker environment: Regenerating all components in volumes" -InformationAction Continue
        } else {
            Write-Information -MessageData "  🖥️  Local environment: Cleaning all generated data" -InformationAction Continue
        }

        $components = @("applications", "gaming", "cloud", "wsl", "system-settings", "registry")
        foreach ($comp in $components) {
            Reset-EnhancedMockData -Component $comp -Scope $Scope -SkipSafetyCheck
        }
    }

    Write-Information -MessageData "🎉 Mock data reset completed safely!" -InformationAction Continue
}

# Functions are available when dot-sourced







