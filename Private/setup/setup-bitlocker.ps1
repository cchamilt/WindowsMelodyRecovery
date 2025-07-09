# Setup-BitLocker.ps1 - Configure BitLocker drive encryption settings

function Setup-BitLocker {
    [CmdletBinding()]
    param(
        [string]$Drive = $env:SystemDrive,
        [switch]$EnableAutoUnlock,
        [switch]$SkipHardwareTest,
        [ValidateSet('TPM', 'Password', 'RecoveryKey', 'StartupKey')]
        [string[]]$ProtectorTypes = @('TPM', 'RecoveryKey')
    )

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Configuring BitLocker Drive Encryption..." -ForegroundColor Blue

        # Check if BitLocker is available
        Write-Host "Checking BitLocker availability..." -ForegroundColor Yellow
        $bitlockerFeature = Get-WindowsOptionalFeature -Online -FeatureName "BitLocker" -ErrorAction SilentlyContinue
        if (-not $bitlockerFeature -or $bitlockerFeature.State -ne "Enabled") {
            Write-Warning "BitLocker feature is not enabled. Attempting to enable..."
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName "BitLocker" -All -NoRestart
                Write-Host "BitLocker feature enabled. A restart may be required." -ForegroundColor Yellow
            } catch {
                Write-Error "Failed to enable BitLocker feature: $($_.Exception.Message)"
                return $false
            }
        }

        # Check TPM status
        Write-Host "Checking TPM (Trusted Platform Module) status..." -ForegroundColor Yellow
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            if ($tpm.TpmPresent) {
                Write-Host "  TPM is present and ready: $($tpm.TpmReady)" -ForegroundColor Green
                if (-not $tpm.TpmReady) {
                    Write-Warning "  TPM is present but not ready. BitLocker may require additional configuration."
                }
                if (-not $tpm.TpmEnabled) {
                    Write-Warning "  TPM is present but not enabled. Please enable TPM in BIOS/UEFI settings."
                }
            } else {
                Write-Warning "  TPM is not present. BitLocker will require alternative authentication methods."
            }
        } catch {
            Write-Warning "Unable to check TPM status: $($_.Exception.Message)"
        }

        # Check current BitLocker status
        Write-Host "Checking current BitLocker status for drive $Drive..." -ForegroundColor Yellow
        $bitlockerStatus = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
        
        if ($bitlockerStatus) {
            Write-Host "  Current protection status: $($bitlockerStatus.ProtectionStatus)" -ForegroundColor Cyan
            Write-Host "  Current encryption percentage: $($bitlockerStatus.EncryptionPercentage)%" -ForegroundColor Cyan
            Write-Host "  Current volume status: $($bitlockerStatus.VolumeStatus)" -ForegroundColor Cyan
            
            if ($bitlockerStatus.KeyProtector) {
                Write-Host "  Current key protectors:" -ForegroundColor Cyan
                foreach ($protector in $bitlockerStatus.KeyProtector) {
                    Write-Host "    - $($protector.KeyProtectorType): $($protector.KeyProtectorId)" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "  BitLocker is not currently configured for drive $Drive" -ForegroundColor Yellow
        }

        # Configure BitLocker based on current status
        if (-not $bitlockerStatus -or $bitlockerStatus.ProtectionStatus -eq "Off") {
            Write-Host "Configuring BitLocker for drive $Drive..." -ForegroundColor Yellow
            
            # Prepare protector configuration
            $protectorParams = @{
                MountPoint = $Drive
            }
            
            # Add TPM protector if available and requested
            if ($ProtectorTypes -contains 'TPM') {
                try {
                    $tpm = Get-Tpm -ErrorAction Stop
                    if ($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled) {
                        Write-Host "  Adding TPM key protector..." -ForegroundColor Yellow
                        Add-BitLockerKeyProtector -MountPoint $Drive -TpmProtector | Out-Null
                        Write-Host "  TPM key protector added successfully" -ForegroundColor Green
                    } else {
                        Write-Warning "  TPM is not ready. Skipping TPM protector."
                    }
                } catch {
                    Write-Warning "  Failed to add TPM protector: $($_.Exception.Message)"
                }
            }
            
            # Add recovery key protector if requested
            if ($ProtectorTypes -contains 'RecoveryKey') {
                Write-Host "  Adding recovery key protector..." -ForegroundColor Yellow
                try {
                    $recoveryKey = Add-BitLockerKeyProtector -MountPoint $Drive -RecoveryKeyProtector
                    Write-Host "  Recovery key protector added successfully" -ForegroundColor Green
                    Write-Host "  Recovery Key ID: $($recoveryKey.KeyProtectorId)" -ForegroundColor Cyan
                    
                    # Save recovery key to a secure location
                    $recoveryKeyPath = Join-Path $env:USERPROFILE "Documents\BitLocker_Recovery_Key_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                    try {
                        $recoveryKeyInfo = Get-BitLockerVolume -MountPoint $Drive | Select-Object -ExpandProperty KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryKey' }
                        if ($recoveryKeyInfo) {
                            "BitLocker Recovery Key for $env:COMPUTERNAME - Drive $Drive" | Out-File -FilePath $recoveryKeyPath -Encoding UTF8
                            "Generated: $(Get-Date)" | Out-File -FilePath $recoveryKeyPath -Append -Encoding UTF8
                            "Key ID: $($recoveryKeyInfo.KeyProtectorId)" | Out-File -FilePath $recoveryKeyPath -Append -Encoding UTF8
                            "" | Out-File -FilePath $recoveryKeyPath -Append -Encoding UTF8
                            "Recovery Key:" | Out-File -FilePath $recoveryKeyPath -Append -Encoding UTF8
                            (Get-BitLockerVolume -MountPoint $Drive).KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryKey' } | ForEach-Object { $_.RecoveryKey } | Out-File -FilePath $recoveryKeyPath -Append -Encoding UTF8
                            
                            Write-Host "  Recovery key saved to: $recoveryKeyPath" -ForegroundColor Green
                            Write-Warning "  IMPORTANT: Store this recovery key in a secure location!"
                        }
                    } catch {
                        Write-Warning "  Failed to save recovery key to file: $($_.Exception.Message)"
                    }
                } catch {
                    Write-Warning "  Failed to add recovery key protector: $($_.Exception.Message)"
                }
            }
            
            # Add password protector if requested
            if ($ProtectorTypes -contains 'Password') {
                Write-Host "  Password protector requested but not implemented in this version" -ForegroundColor Yellow
                Write-Host "  Use: Add-BitLockerKeyProtector -MountPoint $Drive -PasswordProtector" -ForegroundColor Cyan
            }
            
            # Enable BitLocker encryption
            Write-Host "  Starting BitLocker encryption..." -ForegroundColor Yellow
            try {
                $encryptionParams = @{
                    MountPoint = $Drive
                    EncryptionMethod = 'XtsAes256'
                    UsedSpaceOnly = $true
                }
                
                if ($SkipHardwareTest) {
                    $encryptionParams.SkipHardwareTest = $true
                }
                
                Enable-BitLocker @encryptionParams
                Write-Host "  BitLocker encryption started successfully" -ForegroundColor Green
                Write-Host "  Encryption will continue in the background" -ForegroundColor Yellow
            } catch {
                Write-Error "  Failed to start BitLocker encryption: $($_.Exception.Message)"
                return $false
            }
            
        } elseif ($bitlockerStatus.ProtectionStatus -eq "On") {
            Write-Host "BitLocker is already enabled and protecting drive $Drive" -ForegroundColor Green
            
            # Configure auto-unlock for additional drives if requested
            if ($EnableAutoUnlock -and $Drive -ne $env:SystemDrive) {
                Write-Host "  Configuring auto-unlock for drive $Drive..." -ForegroundColor Yellow
                try {
                    Enable-BitLockerAutoUnlock -MountPoint $Drive
                    Write-Host "  Auto-unlock enabled for drive $Drive" -ForegroundColor Green
                } catch {
                    Write-Warning "  Failed to enable auto-unlock: $($_.Exception.Message)"
                }
            }
        }

        # Configure BitLocker policies through registry
        Write-Host "Configuring BitLocker policies..." -ForegroundColor Yellow
        try {
            $bitlockerPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
            if (-not (Test-Path $bitlockerPolicyPath)) {
                New-Item -Path $bitlockerPolicyPath -Force | Out-Null
            }
            
            # Configure recovery options
            Set-ItemProperty -Path $bitlockerPolicyPath -Name "OSRecovery" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $bitlockerPolicyPath -Name "OSManageDRA" -Value 1 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $bitlockerPolicyPath -Name "OSRecoveryPassword" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $bitlockerPolicyPath -Name "OSRecoveryKey" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            
            Write-Host "  BitLocker policies configured" -ForegroundColor Green
        } catch {
            Write-Warning "  Failed to configure BitLocker policies: $($_.Exception.Message)"
        }

        # Final status check
        Write-Host "Verifying BitLocker configuration..." -ForegroundColor Yellow
        $finalStatus = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
        if ($finalStatus) {
            Write-Host "  Protection Status: $($finalStatus.ProtectionStatus)" -ForegroundColor Green
            Write-Host "  Encryption Percentage: $($finalStatus.EncryptionPercentage)%" -ForegroundColor Green
            Write-Host "  Volume Status: $($finalStatus.VolumeStatus)" -ForegroundColor Green
            
            if ($finalStatus.ProtectionStatus -eq "On") {
                Write-Host "BitLocker configuration completed successfully!" -ForegroundColor Green
                return $true
            } else {
                Write-Warning "BitLocker configuration may not be complete. Check the status manually."
                return $false
            }
        } else {
            Write-Warning "Unable to verify BitLocker status after configuration."
            return $false
        }

    } catch {
        Write-Host "Failed to configure BitLocker: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $false
    }
}

# Function to check BitLocker status without making changes
function Test-BitLockerStatus {
    [CmdletBinding()]
    param(
        [string]$Drive = $env:SystemDrive
    )
    
    try {
        $status = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
        if ($status) {
            return @{
                IsEnabled = $status.ProtectionStatus -eq "On"
                EncryptionPercentage = $status.EncryptionPercentage
                VolumeStatus = $status.VolumeStatus
                KeyProtectors = $status.KeyProtector
            }
        } else {
            return @{
                IsEnabled = $false
                EncryptionPercentage = 0
                VolumeStatus = "Not Configured"
                KeyProtectors = @()
            }
        }
    } catch {
        Write-Warning "Failed to check BitLocker status: $($_.Exception.Message)"
        return $null
    }
} 