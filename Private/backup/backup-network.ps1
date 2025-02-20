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

function Backup-NetworkSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up Network Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "Network" -BackupType "Network Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Export network registry settings
            $regPaths = @(
                # Network adapter settings
                "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}",
                "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters",
                
                # Network profiles
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList",
                
                # Network sharing settings
                "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\HomeGroup",
                
                # VPN settings
                "HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters",
                "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections"
            )

            foreach ($regPath in $regPaths) {
                # Check if registry key exists before trying to export
                $keyExists = $false
                if ($regPath -match '^HKCU\\') {
                    $keyExists = Test-Path "Registry::HKEY_CURRENT_USER\$($regPath.Substring(5))"
                } elseif ($regPath -match '^HKLM\\') {
                    $keyExists = Test-Path "Registry::HKEY_LOCAL_MACHINE\$($regPath.Substring(5))"
                }
                
                if ($keyExists) {
                    try {
                        $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                        $result = reg export $regPath $regFile /y 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "Warning: Could not export registry key: $regPath" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Warning: Failed to export registry key: $regPath" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
                }
            }

            # Export network adapters configuration
            try {
                $networkAdapters = Get-NetAdapter | Select-Object -Property *
                $networkAdapters | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_adapters.json" -Force
            } catch {
                Write-Host "Warning: Could not retrieve network adapter information" -ForegroundColor Yellow
            }

            # Export IP configuration
            try {
                $ipConfig = @{
                    IPAddresses = Get-NetIPAddress | Select-Object -Property *
                    Routes = Get-NetRoute | Select-Object -Property *
                    DNSSettings = Get-DnsClientServerAddress | Select-Object -Property *
                }
                $ipConfig | ConvertTo-Json -Depth 10 | Out-File "$backupPath\ip_config.json" -Force
            } catch {
                Write-Host "Warning: Could not retrieve IP configuration" -ForegroundColor Yellow
            }

            # Export network profiles
            $profiles = @{
                NetConnectionProfiles = Get-NetConnectionProfile
                FirewallProfiles = Get-NetFirewallProfile
            }
            $profiles | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_profiles.json" -Force

            # Export firewall rules
            $firewallRules = Get-NetFirewallRule | Select-Object -Property *
            $firewallRules | ConvertTo-Json -Depth 10 | Out-File "$backupPath\firewall_rules.json" -Force

            # Export network shares
            $shares = Get-WmiObject Win32_Share | Select-Object -Property *
            $shares | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_shares.json" -Force

            # Export proxy settings
            $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
            $proxySettings | ConvertTo-Json | Out-File "$backupPath\proxy_settings.json" -Force

            # Export hosts file
            Copy-Item -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Destination "$backupPath\hosts" -Force
            
            Write-Host "Network Settings backed up successfully to: $backupPath" -ForegroundColor Green
            return $true
        }
        return $false
    } catch {
        $errorRecord = $_
        $errorMessage = @(
            "Failed to backup Network Settings"
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
    Backup-NetworkSettings -BackupRootPath $BackupRootPath
} 