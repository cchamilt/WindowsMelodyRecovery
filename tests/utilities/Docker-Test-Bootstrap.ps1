# Docker Test Bootstrap for Windows Melody Recovery
# This script sets up the test environment for Docker-based testing

# Detect if running in Docker environment
$script:IsDockerEnvironment = ($env:DOCKER_TEST -eq 'true') -or ($env:CONTAINER -eq 'true') -or (Test-Path '/.dockerenv')

if ($script:IsDockerEnvironment) {
    Write-Verbose "Docker environment detected, loading mocks and path utilities"
    
    # Load Docker-specific mocks
    $mockPath = Join-Path $PSScriptRoot "Docker-Path-Mocks.ps1"
    if (Test-Path $mockPath) {
        . $mockPath
        Write-Verbose "Loaded Docker path mocks from: $mockPath"
    } else {
        Write-Warning "Docker path mocks not found at: $mockPath"
    }
    
    # Set up Docker-specific environment variables
    $env:WMR_DOCKER_TEST = 'true'
    $env:WMR_BACKUP_PATH = $env:WMR_BACKUP_PATH ?? '/tmp/wmr-test-backup'
    $env:WMR_LOG_PATH = $env:WMR_LOG_PATH ?? '/tmp/wmr-test-logs'
    $env:WMR_STATE_PATH = $env:WMR_STATE_PATH ?? '/tmp/wmr-test-state'
    
    # Create test directories
    @($env:WMR_BACKUP_PATH, $env:WMR_LOG_PATH, $env:WMR_STATE_PATH) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Write-Verbose "Created test directory: $_"
        }
    }
    
    # Mock Windows-specific environment variables
    $env:USERPROFILE = $env:USERPROFILE ?? '/mock-c/Users/TestUser'
    $env:PROGRAMFILES = $env:PROGRAMFILES ?? '/mock-c/Program Files'
    $env:PROGRAMDATA = $env:PROGRAMDATA ?? '/mock-c/ProgramData'
    $env:COMPUTERNAME = $env:COMPUTERNAME ?? 'TEST-MACHINE'
    $env:HOSTNAME = $env:HOSTNAME ?? 'TEST-MACHINE'
    $env:USERNAME = $env:USERNAME ?? 'TestUser'
    $env:PROCESSOR_ARCHITECTURE = $env:PROCESSOR_ARCHITECTURE ?? 'AMD64'
    $env:USERDOMAIN = $env:USERDOMAIN ?? 'WORKGROUP'
    $env:PROCESSOR_IDENTIFIER = $env:PROCESSOR_IDENTIFIER ?? 'Intel64 Family 6 Model 158 Stepping 10, GenuineIntel'
    
    # Mock Get-CimInstance for hardware information
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance {
            [CmdletBinding()]
            param(
                [string]$ClassName,
                [string]$ErrorAction = 'Continue'
            )
            
            switch ($ClassName) {
                'Win32_Processor' {
                    return @(
                        [PSCustomObject]@{
                            Name = 'Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz'
                            NumberOfCores = 6
                            NumberOfLogicalProcessors = 12
                        }
                    )
                }
                'Win32_PhysicalMemory' {
                    return @(
                        [PSCustomObject]@{
                            Capacity = 17179869184  # 16GB
                        }
                    )
                }
                'Win32_VideoController' {
                    return @(
                        [PSCustomObject]@{
                            Name = 'NVIDIA GeForce GTX 1080'
                            AdapterRAM = 8589934592  # 8GB
                        }
                    )
                }
                default {
                    return @()
                }
            }
        }
    }
    
    # Set up mock Windows drives
    if (-not (Test-Path '/mock-c')) {
        New-Item -Path '/mock-c' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Users' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Users/TestUser' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Program Files' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/ProgramData' -ItemType Directory -Force | Out-Null
        New-Item -Path '/mock-c/Windows' -ItemType Directory -Force | Out-Null
        Write-Verbose "Created mock Windows directory structure"
    }
    
    Write-Host "🐳 Docker test environment initialized" -ForegroundColor Cyan
} else {
    Write-Verbose "Native Windows environment detected, using standard functionality"
}

# Helper function to check if running in Docker
function Test-DockerEnvironment {
    return $script:IsDockerEnvironment
}

# Helper function to get appropriate path for current environment
function Get-WmrTestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath
    )
    
    if ($script:IsDockerEnvironment) {
        return Convert-WmrPathForDocker -Path $WindowsPath
    } else {
        return $WindowsPath
    }
}

# Helper function to normalize line endings for cross-platform tests
function ConvertTo-UnixLineEndings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Text
    )
    
    process {
        return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    }
}

# Helper function to create test directories safely
function New-WmrTestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $testPath = Get-WmrTestPath -WindowsPath $Path
    if (-not (Test-Path $testPath)) {
        New-Item -Path $testPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created test directory: $testPath"
    }
    return $testPath
}

# Helper function to clean up test directories
function Remove-WmrTestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $testPath = Get-WmrTestPath -WindowsPath $Path
    if (Test-Path $testPath) {
        Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Verbose "Cleaned up test directory: $testPath"
    }
}

# Functions are available when dot-sourced, no need to export when not in module context 