# Setup-BitLocker.ps1 - Configure BitLocker drive encryption settings

function Enable-BitLocker {
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

    # Import required modules
    Import-Module WindowsMelodyRecovery -ErrorAction Stop

    try {
        Write-Information -MessageData "Configuring BitLocker Drive Encryption..." -InformationAction Continue

        # Check if BitLocker is available
        Write-Warning -Message "Checking BitLocker availability..."
        $bitlockerFeature = Get-WindowsOptionalFeature -Online -FeatureName "BitLocker" -ErrorAction SilentlyContinue
        if (-not $bitlockerFeature -or $bitlockerFeature.State -ne "Enabled") {
            Write-Warning "BitLocker feature is not enabled. Attempting to enable..."
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName "BitLocker" -All -NoRestart
                Write-Warning -Message "BitLocker feature enabled. A restart may be required."
            }
            catch {
                Write-Error "Failed to enable BitLocker feature: $($_.Exception.Message)"
                return $false
            }
        }

        # Check TPM status
        Write-Warning -Message "Checking TPM (Trusted Platform Module) status..."
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            if ($tpm.TpmPresent) {
                Write-Information -MessageData "  TPM is present and ready: $($tpm.TpmReady)" -InformationAction Continue
                if (-not $tpm.TpmReady) {
                    Write-Warning "  TPM is present but not ready. BitLocker may require additional configuration."
                }
                if (-not $tpm.TpmEnabled) {
                    Write-Warning "  TPM is present but not enabled. Please enable TPM in BIOS/UEFI settings."
                }
            }
            else {
                Write-Warning "  TPM is not present. BitLocker will require alternative authentication methods."
            }
        }
        catch {
            Write-Warning "Unable to check TPM status: $($_.Exception.Message)"
        }

        # Check current BitLocker status
        Write-Warning -Message "Checking current BitLocker status for drive $Drive..."
        $bitlockerStatus = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue

        if ($bitlockerStatus) {
            Write-Information -MessageData "  Current protection status: $($bitlockerStatus.ProtectionStatus)" -InformationAction Continue
            Write-Information -MessageData "  Current encryption percentage: $($bitlockerStatus.EncryptionPercentage)%" -InformationAction Continue
            Write-Information -MessageData "  Current volume status: $($bitlockerStatus.VolumeStatus)" -InformationAction Continue

            if ($bitlockerStatus.KeyProtector) {
                Write-Information -MessageData "  Current key protectors:" -InformationAction Continue
                foreach ($protector in $bitlockerStatus.KeyProtector) {
                    Write-Verbose -Message "    - $($protector.KeyProtectorType): $($protector.KeyProtectorId)"
                }
            }
        }
        else {
            Write-Warning -Message "  BitLocker is not currently configured for drive $Drive"
        }

        # Configure BitLocker based on current status
        if (-not $bitlockerStatus -or $bitlockerStatus.ProtectionStatus -eq "Off") {
            Write-Warning -Message "Configuring BitLocker for drive $Drive..."

            # Prepare protector configuration
            $protectorParams = @{
                MountPoint = $Drive
            }

            # Add TPM protector if available and requested
            if ($ProtectorTypes -contains 'TPM') {
                try {
                    $tpm = Get-Tpm -ErrorAction Stop
                    if ($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled) {
                        Write-Warning -Message "  Adding TPM key protector..."
                        Add-BitLockerKeyProtector -MountPoint $Drive -TpmProtector | Out-Null
                        Write-Information -MessageData "  TPM key protector added successfully" -InformationAction Continue
                    }
                    else {
                        Write-Warning "  TPM is not ready. Skipping TPM protector."
                    }
                }
                catch {
                    Write-Warning "  Failed to add TPM protector: $($_.Exception.Message)"
                }
            }

            # Add recovery key protector if requested
            if ($ProtectorTypes -contains 'RecoveryKey') {
                Write-Warning -Message "  Adding recovery key protector..."
                try {
                    $recoveryKey = Add-BitLockerKeyProtector -MountPoint $Drive -RecoveryKeyProtector
                    Write-Information -MessageData "  Recovery key protector added successfully" -InformationAction Continue
                    Write-Information -MessageData "  Recovery Key ID: $($recoveryKey.KeyProtectorId)" -InformationAction Continue

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

                            Write-Information -MessageData "  Recovery key saved to: $recoveryKeyPath" -InformationAction Continue
                            Write-Warning "  IMPORTANT: Store this recovery key in a secure location!"
                        }
                    }
                    catch {
                        Write-Warning "  Failed to save recovery key to file: $($_.Exception.Message)"
                    }
                }
                catch {
                    Write-Warning "  Failed to add recovery key protector: $($_.Exception.Message)"
                }
            }

            # Add password protector if requested
            if ($ProtectorTypes -contains 'Password') {
                Write-Warning -Message "  Password protector requested but not implemented in this version"
                Write-Information -MessageData "  Use: Add-BitLockerKeyProtector -MountPoint $Drive -PasswordProtector" -InformationAction Continue
            }

            # Enable BitLocker encryption
            Write-Warning -Message "  Starting BitLocker encryption..."
            try {
                $encryptionParams = @{
                    MountPoint       = $Drive
                    EncryptionMethod = 'XtsAes256'
                    UsedSpaceOnly    = $true
                }

                if ($SkipHardwareTest) {
                    $encryptionParams.SkipHardwareTest = $true
                }

                Enable-BitLocker @encryptionParams
                Write-Information -MessageData "  BitLocker encryption started successfully" -InformationAction Continue
                Write-Warning -Message "  Encryption will continue in the background"
            }
            catch {
                Write-Error "  Failed to start BitLocker encryption: $($_.Exception.Message)"
                return $false
            }

        }
        elseif ($bitlockerStatus.ProtectionStatus -eq "On") {
            Write-Information -MessageData "BitLocker is already enabled and protecting drive $Drive" -InformationAction Continue

            # Configure auto-unlock for additional drives if requested
            if ($EnableAutoUnlock -and $Drive -ne $env:SystemDrive) {
                Write-Warning -Message "  Configuring auto-unlock for drive $Drive..."
                try {
                    Enable-BitLockerAutoUnlock -MountPoint $Drive
                    Write-Information -MessageData "  Auto-unlock enabled for drive $Drive" -InformationAction Continue
                }
                catch {
                    Write-Warning "  Failed to enable auto-unlock: $($_.Exception.Message)"
                }
            }
        }

        # Configure BitLocker policies through registry
        Write-Warning -Message "Configuring BitLocker policies..."
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

            Write-Information -MessageData "  BitLocker policies configured" -InformationAction Continue
        }
        catch {
            Write-Warning "  Failed to configure BitLocker policies: $($_.Exception.Message)"
        }

        # Final status check
        Write-Warning -Message "Verifying BitLocker configuration..."
        $finalStatus = Get-BitLockerVolume -MountPoint $Drive -ErrorAction SilentlyContinue
        if ($finalStatus) {
            Write-Information -MessageData "  Protection Status: $($finalStatus.ProtectionStatus)" -InformationAction Continue
            Write-Information -MessageData "  Encryption Percentage: $($finalStatus.EncryptionPercentage)%" -InformationAction Continue
            Write-Information -MessageData "  Volume Status: $($finalStatus.VolumeStatus)" -InformationAction Continue

            if ($finalStatus.ProtectionStatus -eq "On") {
                Write-Information -MessageData "BitLocker configuration completed successfully!" -InformationAction Continue
                return $true
            }
            else {
                Write-Warning "BitLocker configuration may not be complete. Check the status manually."
                return $false
            }
        }
        else {
            Write-Warning "Unable to verify BitLocker status after configuration."
            return $false
        }

    }
    catch {
        Write-Error -Message "Failed to configure BitLocker: $($_.Exception.Message)"
        Write-Error -Message "Stack Trace: $($_.ScriptStackTrace)"
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
                IsEnabled            = $status.ProtectionStatus -eq "On"
                EncryptionPercentage = $status.EncryptionPercentage
                VolumeStatus         = $status.VolumeStatus
                KeyProtectors        = $status.KeyProtector
            }
        }
        else {
            return @{
                IsEnabled            = $false
                EncryptionPercentage = 0
                VolumeStatus         = "Not Configured"
                KeyProtectors        = @()
            }
        }
    }
    catch {
        Write-Warning "Failed to check BitLocker status: $($_.Exception.Message)"
        return $null
    }
}











