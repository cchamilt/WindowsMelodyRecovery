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
#>

# Enhanced mock infrastructure configuration
$script:EnhancedMockConfig = @{
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
        
        [switch]$Force
    )
    
    Write-Host "🚀 Initializing Enhanced Mock Infrastructure" -ForegroundColor Cyan
    Write-Host "   Test Type: $TestType | Scope: $Scope | Force: $Force" -ForegroundColor Gray
    Write-Host ""
    
    # Get standardized test paths
    $testPaths = Get-StandardTestPaths
    $mockDataRoot = $testPaths.TestMockData
    
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
    
    Write-Host ""
    Write-Host "🎉 Enhanced mock infrastructure initialized successfully!" -ForegroundColor Green
    Write-Host "   Root: $mockDataRoot" -ForegroundColor Gray
    Write-Host "   Type: $TestType | Scope: $Scope" -ForegroundColor Gray
    Write-Host ""
}

function Initialize-UnitMockData {
    <#
    .SYNOPSIS
        Initializes minimal mock data for unit tests (logic-only testing).
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)
    
    Write-Host "📦 Generating unit test mock data..." -ForegroundColor Yellow
    
    # Unit tests need minimal mock data - mostly configuration objects
    $unitMockPath = Join-Path $MockRoot "unit"
    New-Item -Path $unitMockPath -ItemType Directory -Force | Out-Null
    
    # Generate mock configuration objects
    Generate-MockConfiguration -OutputPath (Join-Path $unitMockPath "configurations") -Scope $Scope
    
    # Generate sample template data
    Generate-MockTemplateData -OutputPath (Join-Path $unitMockPath "templates") -Scope $Scope
    
    Write-Host "  ✓ Unit mock data generated" -ForegroundColor Green
}

function Initialize-IntegrationMockData {
    <#
    .SYNOPSIS
        Initializes comprehensive mock data for integration tests.
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)
    
    Write-Host "🔧 Generating integration test mock data..." -ForegroundColor Yellow
    
    # Integration tests need realistic system data
    $components = @('applications', 'system-settings', 'gaming', 'cloud', 'wsl', 'registry')
    
    foreach ($component in $components) {
        $componentPath = Join-Path $MockRoot $component
        
        switch ($component) {
            'applications' { 
                Generate-ApplicationMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'system-settings' { 
                Generate-SystemSettingsMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'gaming' { 
                Generate-GamingMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'cloud' { 
                Generate-CloudMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'wsl' { 
                Generate-WSLMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
            'registry' { 
                Generate-RegistryMockData -OutputPath $componentPath -Scope $Scope -Force:$Force
            }
        }
        
        Write-Host "  ✓ $component mock data generated" -ForegroundColor Green
    }
}

function Initialize-FileOperationsMockData {
    <#
    .SYNOPSIS
        Initializes safe mock data for file operations testing.
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)
    
    Write-Host "📁 Generating file operations mock data..." -ForegroundColor Yellow
    
    # File operations need realistic file structures
    $fileOpsMockPath = Join-Path $MockRoot "file-operations"
    
    # Generate realistic AppData structure
    Generate-AppDataStructure -OutputPath (Join-Path $fileOpsMockPath "appdata") -Scope $Scope
    
    # Generate Program Files structure
    Generate-ProgramFilesStructure -OutputPath (Join-Path $fileOpsMockPath "programfiles") -Scope $Scope
    
    # Generate test configuration files
    Generate-ConfigurationFiles -OutputPath (Join-Path $fileOpsMockPath "configs") -Scope $Scope
    
    Write-Host "  ✓ File operations mock data generated" -ForegroundColor Green
}

function Initialize-EndToEndMockData {
    <#
    .SYNOPSIS
        Initializes comprehensive mock data for end-to-end testing.
    #>
    param([string]$MockRoot, [string]$Scope, [bool]$Force)
    
    Write-Host "🌐 Generating end-to-end mock data..." -ForegroundColor Yellow
    
    # End-to-end tests need complete environment simulation
    $e2eMockPath = Join-Path $MockRoot "end-to-end"
    
    # Generate multiple user profiles
    Generate-UserProfileMockData -OutputPath (Join-Path $e2eMockPath "users") -Scope $Scope
    
    # Generate system state data
    Generate-SystemStateMockData -OutputPath (Join-Path $e2eMockPath "system") -Scope $Scope
    
    # Generate network and hardware configurations
    Generate-HardwareMockData -OutputPath (Join-Path $e2eMockPath "hardware") -Scope $Scope
    
    Write-Host "  ✓ End-to-end mock data generated" -ForegroundColor Green
}

function Generate-ApplicationMockData {
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
    
    Write-Host "    ✓ Application mock data: winget, chocolatey, scoop" -ForegroundColor Gray
}

function Generate-GamingMockData {
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
    
    Write-Host "    ✓ Gaming mock data: Steam, Epic, GOG, EA" -ForegroundColor Gray
}

function Generate-SystemSettingsMockData {
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
    
    Write-Host "    ✓ System settings mock data: display, power, network, sound, input" -ForegroundColor Gray
}

function Generate-CloudMockData {
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
    
    Write-Host "    ✓ Cloud provider mock data: OneDrive, GoogleDrive, Dropbox, Box" -ForegroundColor Gray
}

function Generate-WSLMockData {
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
    
    Write-Host "    ✓ WSL mock data: Ubuntu, Debian, packages, configurations" -ForegroundColor Gray
}

function Generate-RegistryMockData {
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
    
    Write-Host "    ✓ Registry mock data: Explorer, Desktop, Themes, System" -ForegroundColor Gray
}

function Generate-AppDataStructure {
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
    
    Write-Host "    ✓ AppData structure: browser configs, app settings, user data" -ForegroundColor Gray
}

function Generate-ProgramFilesStructure {
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
    
    Write-Host "    ✓ Program Files structure: applications, executables, metadata" -ForegroundColor Gray
}

function Generate-MockConfiguration {
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

function Generate-MockTemplateData {
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
    #>
    [CmdletBinding()]
    param(
        [string]$Component,
        
        [ValidateSet('Minimal', 'Standard', 'Comprehensive', 'Enterprise')]
        [string]$Scope = 'Standard'
    )
    
    Write-Host "🔄 Resetting enhanced mock data..." -ForegroundColor Yellow
    
    $testPaths = Get-StandardTestPaths
    $mockDataRoot = $testPaths.TestMockData
    
    if ($Component) {
        $componentPath = Join-Path $mockDataRoot $Component
        if (Test-Path $componentPath) {
            Remove-Item -Path $componentPath -Recurse -Force
            Write-Host "  ✓ Removed $Component mock data" -ForegroundColor Green
        }
        
        # Regenerate specific component
        switch ($Component) {
            'applications' { Generate-ApplicationMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'gaming' { Generate-GamingMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'cloud' { Generate-CloudMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'wsl' { Generate-WSLMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'system-settings' { Generate-SystemSettingsMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
            'registry' { Generate-RegistryMockData -OutputPath $componentPath -Scope $Scope -Force:$true }
        }
        
        Write-Host "  ✓ Regenerated $Component mock data" -ForegroundColor Green
    } else {
        # Reset all mock data
        if (Test-Path $mockDataRoot) {
            Remove-Item -Path $mockDataRoot -Recurse -Force
        }
        
        Initialize-EnhancedMockInfrastructure -TestType "All" -Scope $Scope -Force
    }
    
    Write-Host "🎉 Mock data reset completed!" -ForegroundColor Green
}

# Functions are available when dot-sourced 