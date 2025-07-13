# Initialize-WindowsMelodyRecovery.ps1
# This script ONLY handles configuration - nothing else

function Initialize-WindowsMelodyRecovery {
    [OutputType([bool], [System.Collections.Hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstallPath,

        [Parameter(Mandatory = $false)]
        [switch]$NoPrompt,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # Note: This function only handles configuration and does not require admin privileges

    # Auto-detect module path if not provided
    if (-not $InstallPath -or [string]::IsNullOrWhiteSpace($InstallPath)) {
        $moduleInfo = Get-Module WindowsMelodyRecovery
        if ($moduleInfo) {
            $InstallPath = Split-Path $moduleInfo.Path -Parent
        }
        else {
            # Fallback to default location
            $InstallPath = "$env:USERPROFILE\Scripts\WindowsMelodyRecovery"
            Write-Warning "Could not detect module path. Using default: $InstallPath"
        }
    }

    # Validate InstallPath immediately after it's set
    try {
        # Check if the parent directory exists and is accessible, create if needed
        $parentPath = Split-Path $InstallPath -Parent
        if ($parentPath -and -not [string]::IsNullOrWhiteSpace($parentPath) -and $parentPath -ne $InstallPath) {
            if (-not (Test-Path $parentPath)) {
                # Try to create the parent directory structure (needed for Docker/test environments)
                try {
                    New-Item -Path $parentPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Write-Verbose "Created parent directory: $parentPath"
                }
                catch {
                    throw "The parent directory '$parentPath' does not exist and cannot be created: $($_.Exception.Message)"
                }
            }
        }

        # Check if we can access the installation path (either it exists or we can create it)
        if (Test-Path $InstallPath) {
            # Path exists, check if we can write to it
            try {
                $testFile = Join-Path $InstallPath "test-write-access.tmp"
                New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop | Out-Null
                Remove-Item -Path $testFile -Force -ErrorAction Stop
            }
            catch {
                throw "The installation path '$InstallPath' exists but is not writable: $($_.Exception.Message)"
            }
        }
        else {
            # Path doesn't exist, check if we can create it
            try {
                New-Item -Path $InstallPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Remove-Item -Path $InstallPath -Force -ErrorAction Stop
            }
            catch {
                throw "Cannot create the installation path '$InstallPath': $($_.Exception.Message)"
            }
        }
    }
    catch {
        throw "Invalid installation path '$InstallPath': $($_.Exception.Message)"
    }

    # Configuration should always be in the module's Config directory
    $configFile = Join-Path $InstallPath "Config\windows.env"
    $configExists = Test-Path $configFile

    # Check for legacy configuration and migrate if needed
    $legacyConfigFile = "$env:USERPROFILE\Scripts\WindowsMelodyRecovery\Config\windows.env"
    if (-not $configExists -and (Test-Path $legacyConfigFile)) {
        Write-Warning -Message "Found legacy configuration. Migrating to module directory..."
        $configDir = Join-Path $InstallPath "Config"
        if (!(Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        Copy-Item -Path $legacyConfigFile -Destination $configFile -Force
        $configExists = $true
        Write-Information -MessageData "Configuration migrated successfully." -InformationAction Continue
    }

    # If using existing configuration, validate the path is still accessible
    if ($configExists -and -not $Force) {
        # Validate that the installation path is accessible for existing configs
        if (-not (Test-Path $InstallPath)) {
            throw "The installation path '$InstallPath' is no longer accessible for existing configuration."
        }

        Write-Warning -Message "WindowsMelodyRecovery is already initialized with the following configuration:"
        Get-Content $configFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2]
                Write-Verbose -Message "$key = $value"
            }
        }

        if (-not $NoPrompt) {
            $response = Read-Host "Do you want to replace the existing configuration? (y/N)"
            if ($response -ne 'y') {
                return $true
            }
        }
        else {
            # When -NoPrompt is used and config exists, just return the existing config
            Write-Information -MessageData "Using existing configuration (NoPrompt mode)" -InformationAction Continue
            return $true
        }
    }

    # Get machine name
    if (-not $NoPrompt) {
        Write-Information -MessageData "`nEnter machine name:" -InformationAction Continue
        $userInput = Read-Host "Machine name [default: $env:COMPUTERNAME]"
        $machineName = if ([string]::IsNullOrWhiteSpace($userInput)) {
            $env:COMPUTERNAME
        }
        else {
            $userInput
        }
    }
    else {
        $machineName = $env:COMPUTERNAME
    }

    # Get cloud provider
    if (-not $NoPrompt) {
        Write-Information -MessageData "`nSelect cloud storage provider:" -InformationAction Continue
        Write-Information -MessageData "[O] OneDrive" -InformationAction Continue
        Write-Information -MessageData "[G] Google Drive" -InformationAction Continue
        Write-Information -MessageData "[D] Dropbox" -InformationAction Continue
        Write-Information -MessageData "[B] Box" -InformationAction Continue
        Write-Information -MessageData "[C] Custom location" -InformationAction Continue
    }

    $selectedProvider = if ($NoPrompt) { "OneDrive" } else {
        do {
            $choice = Read-Host "Select provider (O/G/D/B/C)"
            switch ($choice.ToUpper()) {
                'O' { $selectedProvider = 'OneDrive'; break }
                'G' { $selectedProvider = 'GoogleDrive'; break }
                'D' { $selectedProvider = 'Dropbox'; break }
                'B' { $selectedProvider = 'Box'; break }
                'C' { $selectedProvider = 'Custom'; break }
                default {
                    Write-Error -Message "Invalid selection. Please choose O, G, D, B, or C."
                    $selectedProvider = $null
                }
            }
        } while (-not $selectedProvider)
        $selectedProvider
    }

    # Get backup location
    $backupRoot = $null

    if ($selectedProvider -eq 'Custom') {
        if ($NoPrompt) {
            $backupRoot = Join-Path $env:USERPROFILE "Backups\WindowsMelodyRecovery"
        }
        else {
            do {
                $userInput = Read-Host "Enter custom backup location (default: $env:USERPROFILE\Backups\WindowsMelodyRecovery)"
                $path = if ([string]::IsNullOrWhiteSpace($userInput)) {
                    Join-Path $env:USERPROFILE "Backups\WindowsMelodyRecovery"
                }
                else {
                    $userInput
                }
                $valid = Test-Path (Split-Path $path -Parent)
                if (-not $valid) {
                    Write-Error -Message "Parent directory does not exist. Please enter a valid path."
                }
            } while (-not $valid)
            $backupRoot = $path
        }
    }
    elseif ($selectedProvider -eq 'OneDrive') {
        # Find OneDrive paths (including mock paths for testing)
        $onedrivePaths = @(
            "$env:USERPROFILE\OneDrive",
            "$env:USERPROFILE\OneDrive - *",
            "$env:USERPROFILE\OneDriveCommercial",
            "$env:USERPROFILE\OneDrive - Enterprise",
            "/mock-cloud/OneDrive",  # Mock cloud storage for testing
            "/tmp/mock-cloud/OneDrive"  # Alternative mock path
        )

        $possiblePaths = @()
        foreach ($path in $onedrivePaths) {
            Write-Verbose -Message "Checking OneDrive path: $path"
            $item = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($item) {
                Write-Information -MessageData "  Found: $($item.FullName)" -InformationAction Continue
                $possiblePaths += $item
            }
            else {
                Write-Error -Message "  Not found: $path"
            }
        }

        $pathCount = $possiblePaths.Count
        $pathList = $possiblePaths.FullName -join ', '
        Write-Information -MessageData "Found $pathCount OneDrive paths: $pathList" -InformationAction Continue

        if ($possiblePaths.Count -gt 0) {
            if (-not $NoPrompt) {
                Write-Information -MessageData "`nDetected OneDrive locations:" -InformationAction Continue
                for ($i = 0; $i -lt $possiblePaths.Count; $i++) {
                    Write-Information -MessageData "[$i] $($possiblePaths[$i].FullName)" -InformationAction Continue
                }
                Write-Information -MessageData "`[C`] Custom location" -InformationAction Continue

                do {
                    $selection = Read-Host "`nSelect OneDrive location [0-$($possiblePaths.Count-1)] or [C]"
                    if ($selection -eq "C") {
                        $backupRoot = Read-Host "Enter custom backup location"
                    }
                    elseif ($selection -match '^\d+$' -and [int]$selection -lt $possiblePaths.Count) {
                        $selectedOneDrive = $possiblePaths[$selection].FullName
                        $backupRoot = Join-Path $selectedOneDrive "WindowsMelodyRecovery"
                    }
                    else {
                        Write-Error -Message "Invalid selection. Please choose a valid number or C."
                    }
                } while (-not $backupRoot)
            }
            else {
                $backupRoot = Join-Path $possiblePaths[0].FullName "WindowsMelodyRecovery"
            }
        }
        else {
            Write-Warning "No OneDrive paths found. Using default backup location."
            # Use a more robust default location that works in test environments
            if ($NoPrompt) {
                # In test environments, use a predictable location
                $backupRoot = if (Test-Path "/tmp") {
                    "/tmp/Backups/WindowsMelodyRecovery"
                }
                else {
                    Join-Path $env:USERPROFILE "Backups\WindowsMelodyRecovery"
                }
            }
            else {
                $backupRoot = Join-Path $env:USERPROFILE "Backups\WindowsMelodyRecovery"
            }
        }
    }
    else {
        # For other cloud providers, use a default location with provider name
        $backupRoot = Join-Path $env:USERPROFILE "Backups\$selectedProvider\WindowsMelodyRecovery"
        Write-Warning -Message "Using default location for $selectedProvider : $backupRoot"
    }

    # Create configuration
    $config = @{
        BACKUP_ROOT = $backupRoot
        CLOUD_PROVIDER = $selectedProvider
        MACHINE_NAME = $machineName
        WINDOWS_MELODY_RECOVERY_PATH = $InstallPath
    }

    # Create config directory if it doesn't exist
    $configDir = Join-Path $InstallPath "Config"
    if (!(Test-Path $configDir)) {
        try {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        catch {
            Write-Warning "Could not create config directory: $_"
        }
    }

    # Create additional required directories
    $requiredDirs = @(
        (Join-Path $InstallPath "backups"),
        (Join-Path $InstallPath "logs"),
        (Join-Path $InstallPath "scripts")
    )

    foreach ($dir in $requiredDirs) {
        if (!(Test-Path $dir)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            catch {
                Write-Warning "Could not create directory $dir : $_"
            }
        }
    }

    # Copy template files if they exist
    $templateDir = Join-Path $InstallPath "Templates"
    if (Test-Path $templateDir) {
        $templateFiles = @(
            @{ Source = "scripts-config.json"; Dest = "Config\scripts-config.json" }
        )

        foreach ($file in $templateFiles) {
            $sourcePath = Join-Path $templateDir $file.Source
            $destPath = Join-Path $InstallPath $file.Dest

            if (Test-Path $sourcePath) {
                $destDir = Split-Path $destPath -Parent
                if (!(Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Save configuration
    $configContent = $config.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    Set-Content -Path $configFile -Value $configContent -Force

    # Update module configuration state
    Set-WindowsMelodyRecovery -BackupRoot $backupRoot -MachineName $machineName -CloudProvider $selectedProvider -WindowsMelodyRecoveryPath $InstallPath

    # Mark module as initialized
    $script:Config.IsInitialized = $true

    Write-Information -MessageData "" -InformationAction Continue
    Write-Information -MessageData "Configuration saved to: $configFile" -InformationAction Continue
    Write-Information -MessageData "Module configuration updated in memory" -InformationAction Continue

    return $config
}








