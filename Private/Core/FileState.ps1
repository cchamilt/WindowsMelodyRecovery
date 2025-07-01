# Private/Core/FileState.ps1

# Requires Convert-WmrPath from PathUtilities.ps1
# Requires EncryptionUtilities.ps1 for encryption/decryption (will be created in Task 2.5)

function Get-WmrFileState {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$FileConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Getting file state for: $($FileConfig.name)"

    $resolvedPath = (Convert-WmrPath -Path $FileConfig.path).Path
    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $FileConfig.dynamic_state_path
    $stateFileDirectory = Split-Path -Path $stateFilePath

    # Ensure the target directory for state file exists
    if (-not (Test-Path $stateFileDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateFileDirectory -Force | Out-Null
    }

    if (-not (Test-Path $resolvedPath)) {
        Write-Warning "    Source path not found: $resolvedPath. Skipping backup for this item."
        return $null
    }

    $fileState = @{
        Name = $FileConfig.name
        Path = $resolvedPath
        Type = $FileConfig.type
    }

    if ($FileConfig.type -eq "file") {
        $content = Get-Content -Path $resolvedPath -Encoding Byte -Raw
        if ($FileConfig.encrypt) {
            Write-Host "    Encrypting file content with AES-256"
            $encryptedContent = Protect-WmrData -DataBytes $content
            $fileState.Content = $encryptedContent
            $fileState.Encrypted = $true
        } else {
            $fileState.Content = [System.Convert]::ToBase64String($content)
            $fileState.Encrypted = $false
        }

        if ($FileConfig.checksum_type) {
            # Placeholder for checksum calculation
            $fileState.Checksum = (Get-FileHash -Path $resolvedPath -Algorithm $FileConfig.checksum_type).Hash
            $fileState.ChecksumType = $FileConfig.checksum_type
        }

        # Save file content to dynamic_state_path
        if ($FileConfig.encrypt) {
            # Save encrypted content as text (Base64 encoded within the encryption)
            Set-Content -Path $stateFilePath -Value $fileState.Content -Encoding UTF8
            # Save metadata about encryption
            $metadata = @{ Encrypted = $true; OriginalSize = $content.Length }
            $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8
        } else {
            # Save raw bytes for non-encrypted content
            [System.IO.File]::WriteAllBytes($stateFilePath, $content)
            # Save metadata about non-encryption
            $metadata = @{ Encrypted = $false; OriginalSize = $content.Length }
            $metadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8
        }

    } elseif ($FileConfig.type -eq "directory") {
        # For directories, capture a list of files and their hashes/metadata
        $dirContent = Get-ChildItem -Path $resolvedPath -Recurse | Select-Object FullName, Length, LastWriteTimeUtc
        $fileState.Contents = $dirContent | ConvertTo-Json -Compress

        # Save directory content metadata to dynamic_state_path
        $dirContent | ConvertTo-Json -Compress | Set-Content -Path $stateFilePath -Encoding Utf8

        # TODO: Implement optional actual file content backup for directories if desired
    }

    Write-Host "  File state for $($FileConfig.name) captured and saved to $stateFilePath."
    return $fileState
}

function Set-WmrFileState {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$FileConfig,

        [Parameter(Mandatory=$true)]
        [string]$StateFilesDirectory # Base directory where dynamic state files are stored
    )

    Write-Host "  Setting file state for: $($FileConfig.name)"

    $destinationPath = (Convert-WmrPath -Path ($FileConfig.destination -or $FileConfig.path)).Path
    $stateFilePath = Join-Path -Path $StateFilesDirectory -ChildPath $FileConfig.dynamic_state_path

    if (-not (Test-Path $stateFilePath)) {
        Write-Warning "    State file not found for $($FileConfig.name) at $stateFilePath. Skipping restore for this item."
        return
    }

    $targetDirectory = Split-Path -Path $destinationPath
    if (-not (Test-Path $targetDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    if ($FileConfig.type -eq "file") {
        $contentBytes = [System.IO.File]::ReadAllBytes($stateFilePath)

        # Check if the content was encrypted during backup
        $wasEncrypted = $false
        try {
            # Try to read state metadata to check if content was encrypted
            $stateMetadataPath = $stateFilePath -replace '\.[^.]+$', '.metadata.json'
            if (Test-Path $stateMetadataPath) {
                $metadata = Get-Content -Path $stateMetadataPath -Raw | ConvertFrom-Json
                $wasEncrypted = $metadata.Encrypted -eq $true
            }
        } catch {
            # Fallback: assume encryption based on file config
            $wasEncrypted = $FileConfig.encrypt -eq $true
        }

        if ($wasEncrypted) {
            Write-Host "    Decrypting file content with AES-256"
            # Content is encrypted string, not raw bytes
            $encryptedContent = Get-Content -Path $stateFilePath -Raw -Encoding UTF8
            $decryptedBytes = Unprotect-WmrData -EncodedData $encryptedContent
            [System.IO.File]::WriteAllBytes($destinationPath, $decryptedBytes)
        } else {
            # Content is Base64 encoded bytes
            [System.IO.File]::WriteAllBytes($destinationPath, $contentBytes)
        }

        Write-Host "  File $($FileConfig.name) restored to $destinationPath."

    } elseif ($FileConfig.type -eq "directory") {
        # For directories, read the metadata and recreate structure/copy files
        $dirContentJson = Get-Content -Path $stateFilePath -Raw -Encoding Utf8 | ConvertFrom-Json

        # TODO: This is a simplified recreation. A robust solution would compare hashes/timestamps
        # and selectively copy. For now, we assume we're recreating the directory structure
        # and potentially copying actual files if they were also backed up. 
        # The current Get-WmrFileState for directory only captures metadata, not actual file content.

        foreach ($item in $dirContentJson) {
            $targetItemPath = Join-Path -Path $destinationPath -ChildPath (Split-Path -Path $item.FullName -NoParent)
            if ($item.PSIsContainer) { # If it was a directory
                if (-not (Test-Path $targetItemPath -PathType Container)) {
                    New-Item -ItemType Directory -Path $targetItemPath -Force | Out-Null
                }
            } else { # If it was a file
                # This part would need to read the actual file content from a separate state file
                # if we decide to backup individual files within a directory.
                Write-Host "    Simulating restoration of file: $($item.FullName) to $($targetItemPath) (Content not restored in this basic example)"
            }
        }
        Write-Host "  Directory structure for $($FileConfig.name) recreated at $destinationPath (file contents may be missing)."
    }
}

# Functions are available via dot-sourcing - no Export-ModuleMember needed
# Available functions: Get-WmrFileState, Set-WmrFileState 