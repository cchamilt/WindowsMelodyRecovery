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

function Backup-WSLSSHSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRootPath
    )
    
    try {
        Write-Host "Backing up WSL SSH Settings..." -ForegroundColor Blue
        $backupPath = Initialize-BackupDirectory -Path "WSLSSH" -BackupType "WSL SSH Settings" -BackupRootPath $BackupRootPath
        
        if ($backupPath) {
            # Create SSH backup directory
            New-Item -ItemType Directory -Path "$backupPath\ssh" -Force | Out-Null

            # Export SSH configuration from WSL
            try {
                # Create directories for different SSH components
                $sshConfigPath = Join-Path $backupPath "Config"
                $sshKeysPath = Join-Path $backupPath "Keys"
                $sshKnownHostsPath = Join-Path $backupPath "KnownHosts"
                
                New-Item -ItemType Directory -Force -Path $sshConfigPath | Out-Null
                New-Item -ItemType Directory -Force -Path $sshKeysPath | Out-Null
                New-Item -ItemType Directory -Force -Path $sshKnownHostsPath | Out-Null

                # Export SSH config with proper error handling
                $sshConfig = wsl bash -c 'if [ -f ~/.ssh/config ]; then cat ~/.ssh/config; fi' 2>$null
                if ($sshConfig) {
                    $sshConfig | Out-File "$sshConfigPath\config" -Encoding utf8
                    Write-Host "SSH config exported successfully" -ForegroundColor Green
                }

                # Export public keys with proper error handling
                $pubKeys = wsl bash -c 'for key in ~/.ssh/*.pub; do if [ -f "$key" ]; then cat "$key"; echo ""; fi; done' 2>$null
                if ($pubKeys) {
                    $pubKeys | Out-File "$sshKeysPath\public_keys.txt" -Encoding utf8
                    Write-Host "Public keys exported successfully" -ForegroundColor Green
                }

                # Export known_hosts with proper error handling
                $knownHosts = wsl bash -c 'if [ -f ~/.ssh/known_hosts ]; then cat ~/.ssh/known_hosts; fi' 2>$null
                if ($knownHosts) {
                    $knownHosts | Out-File "$sshKnownHostsPath\known_hosts" -Encoding utf8
                    Write-Host "Known hosts exported successfully" -ForegroundColor Green
                }

                # Export system-wide SSH config with proper error handling
                $systemConfig = wsl bash -c 'if [ -f /etc/ssh/ssh_config ]; then sudo cat /etc/ssh/ssh_config; fi' 2>$null
                if ($systemConfig) {
                    $systemConfig | Out-File "$sshConfigPath\system_config" -Encoding utf8
                    Write-Host "System SSH config exported successfully" -ForegroundColor Green
                }

                # Export private keys (safely)
                $privateKeys = @()
                $privateKeysList = wsl bash -c 'for key in ~/.ssh/id_*; do if [ -f "$key" ] && [[ ! "$key" =~ \.pub$ ]]; then echo "$key"; fi; done' 2>$null
                if ($privateKeysList) {
                    $privateKeysList -split "`n" | ForEach-Object {
                        $keyPath = $_.Trim()
                        if (![string]::IsNullOrEmpty($keyPath)) {
                            $keyName = Split-Path $keyPath -Leaf
                            try {
                                # Create a temporary copy with safe permissions
                                wsl bash -c "cp '$keyPath' '/tmp/$keyName' && chmod 644 '/tmp/$keyName' && cat '/tmp/$keyName' && rm '/tmp/$keyName'" > "$sshKeysPath\$keyName" 2>$null
                                $privateKeys += $keyName
                                Write-Host "Private key $keyName exported successfully" -ForegroundColor Green
                            } catch {
                                Write-Host "Warning: Could not export private key $keyName" -ForegroundColor Yellow
                            }
                        }
                    }
                }

                # Write backup summary
                Write-Host "`nWSL SSH Backup Summary:" -ForegroundColor Green
                Write-Host "SSH Config: $(Test-Path "$sshConfigPath\config")" -ForegroundColor Yellow
                Write-Host "Public Keys: $(Test-Path "$sshKeysPath\public_keys.txt")" -ForegroundColor Yellow
                Write-Host "Known Hosts: $(Test-Path "$sshKnownHostsPath\known_hosts")" -ForegroundColor Yellow
                Write-Host "System Config: $(Test-Path "$sshConfigPath\system_config")" -ForegroundColor Yellow
                Write-Host "Private Keys: $($privateKeys.Count) found" -ForegroundColor Yellow

            } catch {
                Write-Host "Warning: Could not export WSL SSH settings - $($_.Exception.Message)" -ForegroundColor Yellow
            }

            # Output summary
            Write-Host "`nWSL SSH Backup Summary:" -ForegroundColor Green
            Write-Host "SSH Config: $(Test-Path "$backupPath\ssh\config.tar.gz")" -ForegroundColor Yellow
            Write-Host "Public Keys: $(Test-Path "$backupPath\ssh\public_keys.tar.gz")" -ForegroundColor Yellow
            Write-Host "Known Hosts: $(Test-Path "$backupPath\ssh\known_hosts")" -ForegroundColor Yellow
            Write-Host "System Config: $(Test-Path "$backupPath\ssh\system_config.tar.gz")" -ForegroundColor Yellow
            Write-Host "Private Keys: $((Get-ChildItem "$backupPath\ssh\id_*.enc").Count) found" -ForegroundColor Yellow
            
            Write-Host "WSL SSH Settings backed up successfully to: $backupPath" -ForegroundColor Green
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
    Backup-WSLSSHSettings -BackupRootPath $BackupRootPath
} 