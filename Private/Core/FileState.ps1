# Private/Core/FileState.ps1

# Requires Convert-WmrPath from PathUtilities.ps1
# Requires EncryptionUtilities.ps1 for encryption/decryption

function Test-WmrFileConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$FileConfig
    )

    # Required properties
    $requiredProps = @('name', 'path', 'type', 'dynamic_state_path')
    foreach ($prop in $requiredProps) {
        # Handle both PSObject and YAML parser object structures
        $propValue = $null
        try {
            $propValue = $FileConfig.$prop
        }
        catch {
            # Property doesn't exist
        }

        if ([string]::IsNullOrWhiteSpace($propValue)) {
            Write-Warning "FileConfig is missing required property: $prop"
            return $false
        }
    }

    # Validate type
    if ($FileConfig.type -notin @('file', 'directory')) {
        Write-Warning "FileConfig type must be 'file' or 'directory', got: $($FileConfig.type)"
        return $false
    }

    return $true
}

function Get-WmrFileState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$FileConfig,

        [Parameter(Mandatory = $true)]
        [string]$StateFilesDirectory,

        [Parameter(Mandatory = $false)]
        [System.Security.SecureString]$Passphrase
    )

    # Validate FileConfig
    if (-not (Test-WmrFileConfig -FileConfig $FileConfig)) {
        Write-Warning "Invalid FileConfig object provided"
        return $null
    }

    # Validate StateFilesDirectory
    if ([string]::IsNullOrWhiteSpace($StateFilesDirectory)) {
        Write-Warning "StateFilesDirectory cannot be null or empty"
        return $null
    }

    Write-Verbose "Getting file state for: $($FileConfig.name)"

    $resolvedPath = $FileConfig.path
    if (-not $resolvedPath.StartsWith("TestDrive:")) {
        $resolvedPath = (Convert-WmrPath -Path $FileConfig.path).Path
    }
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        Write-Warning "Could not resolve path: $($FileConfig.path)"
        return $null
    }

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $FileConfig.dynamic_state_path
    $stateFileDirectory = Split-Path -Path $stateFilePath -Parent

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would backup file state from $resolvedPath to $stateFilePath"
        if (-not (Test-Path $resolvedPath)) {
            Write-Warning "WhatIf: Source path not found: $resolvedPath. Would skip backup for this item."
        }
        else {
            Write-Warning -Message "WhatIf: Would create state file directory: $stateFileDirectory"
            Write-Warning -Message "WhatIf: Would backup $($FileConfig.type) content"
        }
        return $null
    }

    # Ensure the target directory for state file exists
    if (-not (Test-Path $stateFileDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateFileDirectory -Force | Out-Null
    }

    if (-not (Test-Path $resolvedPath)) {
        Write-Warning "Source path not found: $resolvedPath. Skipping backup for this item."
        return $null
    }

    $fileState = @{
        Name = $FileConfig.name
        Path = $resolvedPath
        Type = $FileConfig.type
    }

    if ($FileConfig.type -eq "file") {
        $content = Get-Content -Path $resolvedPath -Raw -Encoding UTF8
        $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($content)

        if ($FileConfig.encrypt) {
            Write-Verbose "Encrypting file content with AES-256"
            if (-not $Passphrase) {
                Write-Warning "Encryption requested but no passphrase provided"
                return $null
            }
            $encryptedContent = Protect-WmrData -Data $contentBytes -Passphrase $Passphrase
            $fileState.Content = $encryptedContent
            $fileState.Encrypted = $true

            # Save encrypted content
            Set-Content -Path $stateFilePath -Value $encryptedContent -Encoding UTF8 -NoNewline
        }
        else {
            $fileState.Content = [System.Convert]::ToBase64String($contentBytes)
            $fileState.Encrypted = $false

            # Save original content
            Set-Content -Path $stateFilePath -Value $content -Encoding UTF8 -NoNewline
        }

        if ($FileConfig.checksum_type) {
            $fileState.Checksum = (Get-FileHash -Path $resolvedPath -Algorithm $FileConfig.checksum_type).Hash
            $fileState.ChecksumType = $FileConfig.checksum_type
        }

        # Save metadata
        $metadata = @{
            Encrypted = $fileState.Encrypted
            OriginalSize = $contentBytes.Length
            Encoding = "UTF8"
        }
        $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
        $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8 -NoNewline

    }
    elseif ($FileConfig.type -eq "directory") {
        # For directories, capture a list of files and their hashes/metadata INCLUDING file contents
        $dirContent = Get-ChildItem -Path $resolvedPath -Recurse | ForEach-Object {
            Write-Debug "Processing item: $($_.FullName)"
            Write-Debug "Base path: $resolvedPath"

            # Handle TestDrive paths specially
            if ($resolvedPath.StartsWith("TestDrive:")) {
                $basePath = $resolvedPath
                $relativePath = $_.FullName.Substring($basePath.Length).TrimStart('\')
                # Remove the brittle regex replacement - use simple path calculation instead
                Write-Debug "TestDrive original relative path: $relativePath"
            }
            else {
                # For regular paths, ensure consistent path separators and trim trailing separator
                $fullPath = $_.FullName.Replace('/', '\').TrimEnd('\')
                $basePath = $resolvedPath.Replace('/', '\').TrimEnd('\')

                # Improved relative path calculation with better error handling
                if ($fullPath.StartsWith($basePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relativePath = $fullPath.Substring($basePath.Length).TrimStart('\')
                } else {
                    # Fallback: use just the filename if path calculation fails
                    $relativePath = $_.Name
                    Write-Warning "Path calculation failed for $($_.FullName), using filename: $relativePath"
                }
            }

            Write-Debug "Full path: $($_.FullName)"
            Write-Debug "Base path: $basePath"
            Write-Debug "Relative path: $relativePath"

            $item = @{
                FullName = $_.FullName
                Length = $_.Length
                LastWriteTimeUtc = $_.LastWriteTimeUtc
                PSIsContainer = $_.PSIsContainer
                RelativePath = $relativePath
            }

            # For files, also capture their content
            if (-not $_.PSIsContainer) {
                try {
                    $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                    $item.Content = $content
                    Write-Debug "Captured content for file: $($_.FullName)"
                }
                catch {
                    Write-Warning "Could not read content for file $($_.FullName): $($_.Exception.Message)"
                    $item.Content = $null
                }
            }

            $item
        }
        $fileState.Contents = $dirContent | ConvertTo-Json -Compress

        # Save directory content metadata to dynamic_state_path
        Write-Debug "Saving directory content to $stateFilePath"
        Write-Debug "Content: $($dirContent | ConvertTo-Json -Compress)"
        $dirContent | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -Encoding UTF8 -NoNewline
    }

    Write-Verbose "File state for $($FileConfig.name) captured and saved to $stateFilePath"
    return $fileState
}

function Set-WmrFileState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$FileConfig,

        [Parameter(Mandatory = $true)]
        [string]$StateFilesDirectory,

        [Parameter(Mandatory = $false)]
        [System.Security.SecureString]$Passphrase
    )

    # Validate FileConfig
    if (-not (Test-WmrFileConfig -FileConfig $FileConfig)) {
        Write-Warning "Invalid FileConfig object provided"
        return
    }

    # Validate StateFilesDirectory
    if ([string]::IsNullOrWhiteSpace($StateFilesDirectory)) {
        Write-Warning "StateFilesDirectory cannot be null or empty"
        return
    }

    Write-Verbose "Setting file state for: $($FileConfig.name)"

    $pathToUse = if ($FileConfig.destination) { $FileConfig.destination } else { $FileConfig.path }
    if ([string]::IsNullOrWhiteSpace($pathToUse)) {
        Write-Warning "No valid path found for $($FileConfig.name). Skipping restore for this item."
        return
    }

    $destinationPath = $pathToUse
    if (-not $destinationPath.StartsWith("TestDrive:")) {
        $destinationPath = (Convert-WmrPath -Path $pathToUse).Path
    }
    if ([string]::IsNullOrWhiteSpace($destinationPath)) {
        Write-Warning "Could not resolve destination path for $($FileConfig.name). Original path: $pathToUse. Skipping restore for this item."
        return
    }

    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $FileConfig.dynamic_state_path

    if (-not (Test-Path $stateFilePath)) {
        Write-Warning "State file not found for $($FileConfig.name) at $stateFilePath. Skipping restore for this item."
        return
    }

    if ($WhatIfPreference) {
        Write-Warning -Message "WhatIf: Would restore file state from $stateFilePath to $destinationPath"
        Write-Warning -Message "WhatIf: Would create target directory if needed"
        return
    }

    # Create target directory if it doesn't exist
    $targetDir = Split-Path -Path $destinationPath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if ($FileConfig.type -eq "file") {
        $content = Get-Content -Path $stateFilePath -Raw -Encoding UTF8

        if ($FileConfig.encrypt) {
            Write-Verbose "Decrypting file content"
            if (-not $Passphrase) {
                Write-Warning "Decryption requested but no passphrase provided"
                return
            }
            $decryptedBytes = Unprotect-WmrData -EncodedData $content -Passphrase $Passphrase
            Set-Content -Path $destinationPath -Value ([System.Text.Encoding]::UTF8.GetString($decryptedBytes)) -Encoding UTF8 -NoNewline
        }
        else {
            Set-Content -Path $destinationPath -Value $content -Encoding UTF8 -NoNewline
        }
    }
    elseif ($FileConfig.type -eq "directory") {
        $dirContent = Get-Content -Path $stateFilePath -Raw -Encoding UTF8 | ConvertFrom-Json

        # Create the target directory if it doesn't exist
        if (-not (Test-Path $destinationPath)) {
            New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
        }

        Write-Debug "Processing directory content for $($FileConfig.name)"
        Write-Debug "Destination path: $destinationPath"
        Write-Debug "State file content: $($dirContent | ConvertTo-Json -Compress)"

        # Process each item in the directory content
        foreach ($item in $dirContent) {
            if (-not $item.RelativePath) {
                Write-Warning "Item $($item.FullName) has no relative path information. Skipping."
                continue
            }

            # Sanitize the relative path to prevent path traversal attacks
            $sanitizedRelativePath = $item.RelativePath.Replace('..', '').Replace(':', '').TrimStart('\', '/')
            if ([string]::IsNullOrWhiteSpace($sanitizedRelativePath)) {
                Write-Warning "Invalid relative path for item $($item.FullName). Skipping."
                continue
            }

            # Construct the new path using the sanitized relative path
            $targetPath = Join-Path -Path $destinationPath -ChildPath $sanitizedRelativePath
            Write-Debug "Target path: $targetPath"

            # Additional safety check: ensure target path is within destination directory
            $resolvedTargetPath = [System.IO.Path]::GetFullPath($targetPath)
            $resolvedDestinationPath = [System.IO.Path]::GetFullPath($destinationPath)
            if (-not $resolvedTargetPath.StartsWith($resolvedDestinationPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Warning "Target path $targetPath is outside destination directory $destinationPath. Skipping for security."
                continue
            }

            # Create directory or file based on PSIsContainer
            if ($item.PSIsContainer) {
                if (-not (Test-Path $targetPath)) {
                    Write-Debug "Creating directory: $targetPath"
                    try {
                        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                    }
                    catch {
                        Write-Warning "Failed to create directory $targetPath : $($_.Exception.Message)"
                        continue
                    }
                }
            }
            else {
                # Ensure parent directory exists
                $parentDir = Split-Path -Path $targetPath -Parent
                if (-not (Test-Path $parentDir)) {
                    Write-Debug "Creating parent directory: $parentDir"
                    try {
                        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                    }
                    catch {
                        Write-Warning "Failed to create parent directory $parentDir : $($_.Exception.Message)"
                        continue
                    }
                }

                # Create file with original content if available
                if ($null -ne $item.Content) {
                    Write-Debug "Creating file with content: $targetPath"
                    try {
                        Set-Content -Path $targetPath -Value $item.Content -Encoding UTF8 -NoNewline
                    }
                    catch {
                        Write-Warning "Failed to create file $targetPath : $($_.Exception.Message)"
                        continue
                    }
                }
                else {
                    # Create empty file to maintain structure
                    if (-not (Test-Path $targetPath)) {
                        Write-Debug "Creating empty file: $targetPath"
                        try {
                            New-Item -ItemType File -Path $targetPath -Force | Out-Null
                        }
                        catch {
                            Write-Warning "Failed to create empty file $targetPath : $($_.Exception.Message)"
                            continue
                        }
                    }
                }
            }
        }
    }

    Write-Verbose "File state restored for $($FileConfig.name) to $destinationPath"
}







