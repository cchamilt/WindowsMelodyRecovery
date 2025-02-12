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
                # Network adapters and configuration
                "HKLM\SYSTEM\CurrentControlSet\Control\Network",
                "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip",
                "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6",
                "HKLM\SYSTEM\CurrentControlSet\Services\NetBT",
                
                # Network profiles
                "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList",
                "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                
                # Firewall settings
                "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess",
                "HKLM\SYSTEM\CurrentControlSet\Services\mpssvc",
                
                # Network sharing
                "HKLM\SYSTEM\CurrentControlSet\Control\LanmanServer",
                "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer",
                "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation",
                
                # DNS and DHCP settings
                "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache",
                "HKLM\SYSTEM\CurrentControlSet\Services\Dhcp"
            )

            foreach ($regPath in $regPaths) {
                $regFile = "$backupPath\$($regPath.Split('\')[-1]).reg"
                reg export $regPath $regFile /y 2>$null
            }

            # Export network adapters configuration
            $networkAdapters = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter } | Select-Object -Property *
            $networkAdapters | ConvertTo-Json -Depth 10 | Out-File "$backupPath\network_adapters.json" -Force

            # Export adapter configurations
            $adapterConfigs = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled } | Select-Object -Property *
            $adapterConfigs | ConvertTo-Json -Depth 10 | Out-File "$backupPath\adapter_configs.json" -Force

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
            "Failed to backup [Feature]"
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