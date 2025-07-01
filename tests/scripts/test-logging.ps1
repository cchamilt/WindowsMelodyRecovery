# Test Logging Module for Windows Melody Recovery
# Provides centralized logging functionality for test scripts

# Global logging configuration
$Global:LogConfig = @{
    LogLevel = "INFO"
    LogPath = "/test-results/logs"
    ConsoleOutput = $true
}

function Initialize-TestLogging {
    param(
        [string]$LogPath = "/test-results/logs",
        [string]$LogLevel = "INFO"
    )
    
    $Global:LogConfig.LogPath = $LogPath
    $Global:LogConfig.LogLevel = $LogLevel
    
    # Create log directory
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Initialize main log file
    $mainLogFile = Join-Path $LogPath "test-execution.log"
    "Test Execution Log - Started at $(Get-Date)" | Out-File -FilePath $mainLogFile -Encoding UTF8
    
    return $mainLogFile
}

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [string]$Component = "TEST",
        [string]$LogFile = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    # Write to console with appropriate color
    if ($Global:LogConfig.ConsoleOutput) {
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "SUCCESS" { "Green" }
            "INFO" { "White" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        Write-Host $logEntry -ForegroundColor $color
    }
    
    # Write to log file
    $targetLogFile = if ($LogFile) { $LogFile } else { Join-Path $Global:LogConfig.LogPath "test-execution.log" }
    try {
        $logEntry | Out-File -FilePath $targetLogFile -Append -Encoding UTF8
    } catch {
        Write-Warning "Failed to write to log file: $targetLogFile"
    }
}

function Write-TestHeader {
    param(
        [string]$Title,
        [string]$LogFile = $null
    )
    
    $border = "=" * 80
    Write-TestLog $border "INFO" "HEADER" $LogFile
    Write-TestLog "  $Title" "INFO" "HEADER" $LogFile
    Write-TestLog $border "INFO" "HEADER" $LogFile
}

function Write-TestSection {
    param(
        [string]$Section,
        [string]$LogFile = $null
    )
    
    $border = "-" * 60
    Write-TestLog $border "INFO" "SECTION" $LogFile
    Write-TestLog "  $Section" "INFO" "SECTION" $LogFile
    Write-TestLog $border "INFO" "SECTION" $LogFile
}

function Start-TestLog {
    param(
        [string]$TestName,
        [string]$LogPath = $null
    )
    
    $effectiveLogPath = if ($LogPath) { $LogPath } else { $Global:LogConfig.LogPath }
    $testLogFile = Join-Path $effectiveLogPath "$TestName.log"
    
    "Test Log for $TestName - Started at $(Get-Date)" | Out-File -FilePath $testLogFile -Encoding UTF8
    Write-TestLog "Started test log for $TestName" "INFO" "LOGGING"
    
    return $testLogFile
}

function Stop-TestLog {
    param(
        [string]$TestName,
        [string]$LogFile,
        [string]$Result = "Unknown"
    )
    
    "Test $TestName completed with result: $Result - Ended at $(Get-Date)" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-TestLog "Stopped test log for $TestName (Result: $Result)" "INFO" "LOGGING"
}

# Export functions for module usage
Export-ModuleMember -Function Initialize-TestLogging, Write-TestLog, Write-TestHeader, Write-TestSection, Start-TestLog, Stop-TestLog 