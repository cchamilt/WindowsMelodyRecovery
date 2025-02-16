[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BackupRootPath = $null
)

# Load environment if not provided
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!$BackupRootPath) {
    if (!(Load-Environment)) {
        Write-Host "Failed to load environment configuration" -ForegroundColor Red
        exit 1
    }
    $BackupRootPath = "$env:BACKUP_ROOT\$env:MACHINE_NAME"
}

function Backup-SystemSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up System Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "SystemSettings" -BackupType "System Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Create registry backup directory
            $registryPath = Join-Path $backupPath "Registry"
            New-Item -ItemType Directory -Force -Path $registryPath | Out-Null

            # System-wide registry settings to backup
            $regPaths = @(
                # System settings
                "HKLM\SYSTEM\CurrentControlSet\Control",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup",
                
                # Performance and memory
                "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
                
                # System environment
                "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
                
                # Power settings
                "HKLM\SYSTEM\CurrentControlSet\Control\Power",
                
                # Time and region
                "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation",
                "HKCU\Control Panel\International",
                
                # System restore
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore",
                
                # Remote settings
                "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance",
                "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server",
                
                # Security settings
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
                "HKLM\SYSTEM\CurrentControlSet\Control\Lsa"
            )

            foreach ($regPath in $regPaths) {
                $regFile = Join-Path $registryPath "$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export additional system configurations
            $systemConfigPath = Join-Path $backupPath "SystemConfig"
            New-Item -ItemType Directory -Force -Path $systemConfigPath | Out-Null

            # Export power schemes
            powercfg /list | Out-File (Join-Path $systemConfigPath "power_schemes.txt") -Force
            powercfg /query | Out-File (Join-Path $systemConfigPath "power_settings.txt") -Force

            # Export system performance settings
            Get-CimInstance Win32_OperatingSystem | 
                Select-Object FreePhysicalMemory, TotalVisibleMemorySize, SizeStoredInPagingFiles |
                ConvertTo-Json | Out-File (Join-Path $systemConfigPath "performance_settings.json") -Force

            # Export system restore points
            Get-ComputerRestorePoint | 
                Select-Object Description, CreationTime, RestorePointType, SequenceNumber |
                ConvertTo-Json | Out-File (Join-Path $systemConfigPath "restore_points.json") -Force

            # Export page file settings
            Get-CimInstance Win32_PageFileSetting | 
                Select-Object Name, InitialSize, MaximumSize |
                ConvertTo-Json | Out-File (Join-Path $systemConfigPath "pagefile_settings.json") -Force

            # Export time and region settings
            $timeSettings = @{
                TimeZone = (Get-TimeZone).Id
                Region = (Get-WinHomeLocation).GeoId
                SystemLocale = (Get-WinSystemLocale).Name
                UserLocale = (Get-WinUserLanguageList)[0].LanguageTag
            }
            $timeSettings | ConvertTo-Json | Out-File (Join-Path $systemConfigPath "time_settings.json") -Force

            # Export printer settings
            try {
                $printerPath = Join-Path $backupPath "Printers"
                New-Item -ItemType Directory -Path $printerPath -Force | Out-Null

                # Export printer list and settings
                $printers = Get-Printer
                $printers | Export-Clixml "$printerPath\printers.xml"

                # Export printer configurations for each printer
                $printerConfigs = @{}
                foreach ($printer in $printers) {
                    try {
                        $config = Get-PrintConfiguration -PrinterName $printer.Name -ErrorAction SilentlyContinue
                        if ($config) {
                            $printerConfigs[$printer.Name] = $config
                        }
                    } catch {
                        Write-Host "Warning: Could not get configuration for printer: $($printer.Name)" -ForegroundColor Yellow
                    }
                }
                $printerConfigs | Export-Clixml "$printerPath\printer-configs.xml"

                # Export printer ports
                Get-PrinterPort | Export-Clixml "$printerPath\printer-ports.xml"

                # Export printer drivers
                Get-PrinterDriver | Export-Clixml "$printerPath\printer-drivers.xml"
                
                Write-Host "Printer settings backed up successfully" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Could not backup printer settings - $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # Backup network profiles
            $networkPath = Join-Path $backupPath "Network"
            New-Item -ItemType Directory -Force -Path $networkPath | Out-Null
            Get-NetAdapter | Export-Clixml "$networkPath\adapters.xml"
            Get-NetIPAddress | Export-Clixml "$networkPath\ip-addresses.xml"
            netsh wlan export profile folder="$networkPath" key=clear

            # Backup scheduled tasks (custom only)
            $tasksPath = Join-Path $backupPath "ScheduledTasks"
            New-Item -ItemType Directory -Force -Path $tasksPath | Out-Null
            Get-ScheduledTask | Where-Object { $_.TaskPath -like "\Custom Tasks\*" } | 
                ForEach-Object {
                    Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | 
                    Out-File "$tasksPath\$($_.TaskName).xml"
                }

            # Backup environment variables (user only)
            [Environment]::GetEnvironmentVariables('User') | 
                ConvertTo-Json | 
                Out-File (Join-Path $backupPath "user-environment-variables.json")

            # Backup mapped drives
            Get-PSDrive -PSProvider FileSystem | 
                Where-Object { $_.DisplayRoot } | 
                Export-Clixml (Join-Path $backupPath "mapped-drives.xml")

            Write-Host "System Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup System Settings"
            "Error Message: $($errorRecord.Exception.Message)"
            "Error Type: $($errorRecord.Exception.GetType().FullName)"
            "Script Line Number: $($errorRecord.InvocationInfo.ScriptLineNumber)"
            "Script Name: $($errorRecord.InvocationInfo.ScriptName)"
            "Statement: $($errorRecord.InvocationInfo.Line.Trim())"
            if ($errorRecord.Exception.StackTrace) { "Stack Trace: $($errorRecord.Exception.StackTrace)" }
            if ($errorRecord.Exception.InnerException) { "Inner Exception: $($errorRecord.Exception.InnerException.Message)" }
        ) -join "`n"
        
        Write-Host $errorMessage -ForegroundColor Red
        return $false
    }
}

# Allow script to be run directly or sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Script was run directly
    Backup-SystemSettings -BackupRootPath $BackupRootPath
} 