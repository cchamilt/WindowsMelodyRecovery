# Private/Core/PathUtilities.ps1

function Convert-WmrPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Handle URI schemes first
    if ($Path.StartsWith('file://')) {
        $normalizedPath = $Path.Substring(7).Replace('/', '\')
        # Expand environment variables in the path
        $normalizedPath = [System.Environment]::ExpandEnvironmentVariables($normalizedPath)

        # Apply test environment redirection AFTER normalization
        $normalizedPath = ConvertTo-TestEnvironmentPath -Path $normalizedPath

        return @{
            PathType = "File"
            Type = "File"  # For backwards compatibility
            Path = $normalizedPath
            Original = $Path
            IsResolved = $true
        }
    }
    elseif ($Path.StartsWith('winreg://')) {
        $registryPath = $Path.Replace('winreg://', '')
        # Convert to PowerShell registry format - keep backslashes for registry paths
        $normalizedPath = $registryPath -replace '^HKLM/', 'HKLM:\' -replace '^HKCU/', 'HKCU:\' -replace '^HKCR/', 'HKCR:\' -replace '^HKU/', 'HKU:\' -replace '^HKCC/', 'HKCC:\'
        # Convert remaining forward slashes to backslashes for registry paths
        $normalizedPath = $normalizedPath.Replace('/', '\')
        return @{
            PathType = "Registry"
            Type = "Registry"  # For backwards compatibility
            Path = $normalizedPath
            Original = $Path
            IsResolved = $true
        }
    }
    elseif ($Path.StartsWith('wsl://')) {
        $wslPath = $Path.Replace('wsl://', '')

        # Handle empty path after wsl://
        if ([string]::IsNullOrEmpty($wslPath)) {
            return @{
                PathType = "WSL"
                Type = "WSL"
                Path = "/"
                Distribution = ""
                Original = $Path
                IsResolved = $true
            }
        }

        # Extract distribution name if present
        $distribution = ""
        $linuxPath = ""

        # Handle wsl:/// (triple slash) - default distribution
        if ($wslPath.StartsWith('/')) {
            $distribution = ""
            $linuxPath = $wslPath
        } else {
            # Handle wsl://Ubuntu/path format
            $slashIndex = $wslPath.IndexOf('/')
            if ($slashIndex -gt 0) {
                $distribution = $wslPath.Substring(0, $slashIndex)
                $linuxPath = $wslPath.Substring($slashIndex)
            } else {
                # No slash found, treat as distribution name only
                $distribution = $wslPath
                $linuxPath = "/"
            }
        }

        # Replace $user with Windows username and handle empty user case
        $linuxPath = $linuxPath.Replace('$user', $env:USERNAME)

        # Handle case where $user was expanded to empty string by PowerShell, causing double slashes
        $linuxPath = $linuxPath -replace '//', "/$env:USERNAME/"

        return @{
            PathType = "WSL"
            Type = "WSL"  # For backwards compatibility
            Path = $linuxPath
            Distribution = $distribution
            Original = $Path
            IsResolved = $true
        }
    }

    # Handle regular paths
    $normalizedPath = $Path.Replace('/', '\').TrimEnd('\')

    # Expand environment variables
    $normalizedPath = [System.Environment]::ExpandEnvironmentVariables($normalizedPath)

    # Apply test environment redirection for file paths BEFORE path type determination
    if (-not ($normalizedPath -match '^HK')) {  # Don't redirect registry paths
        $normalizedPath = ConvertTo-TestEnvironmentPath -Path $normalizedPath
    }

    # Determine path type based on prefix
    $pathType = "Unknown"

    if ($normalizedPath -match '^HK(EY_)?(LOCAL_MACHINE|LM)\\') {
        $pathType = "Registry"
        $normalizedPath = $normalizedPath -replace '^HK(EY_)?LOCAL_MACHINE\\', 'HKLM:\'
        $normalizedPath = $normalizedPath -replace '^HKLM\\', 'HKLM:\'
    }
    elseif ($normalizedPath -match '^HK(EY_)?(CURRENT_USER|CU)\\') {
        $pathType = "Registry"
        $normalizedPath = $normalizedPath -replace '^HK(EY_)?CURRENT_USER\\', 'HKCU:\'
        $normalizedPath = $normalizedPath -replace '^HKCU\\', 'HKCU:\'
    }
    elseif ($normalizedPath -match '^HK(EY_)?(CLASSES_ROOT|CR)\\') {
        $pathType = "Registry"
        $normalizedPath = $normalizedPath -replace '^HK(EY_)?CLASSES_ROOT\\', 'HKCR:\'
        $normalizedPath = $normalizedPath -replace '^HKCR\\', 'HKCR:\'
    }
    elseif ($normalizedPath -match '^HK(EY_)?(USERS|U)\\') {
        $pathType = "Registry"
        $normalizedPath = $normalizedPath -replace '^HK(EY_)?USERS\\', 'HKU:\'
        $normalizedPath = $normalizedPath -replace '^HKU\\', 'HKU:\'
    }
    elseif ($normalizedPath -match '^HK(EY_)?(CURRENT_CONFIG|CC)\\') {
        $pathType = "Registry"
        $normalizedPath = $normalizedPath -replace '^HK(EY_)?CURRENT_CONFIG\\', 'HKCC:\'
        $normalizedPath = $normalizedPath -replace '^HKCC\\', 'HKCC:\'
    }
    elseif ($normalizedPath -match '^HK(LM|CU|CR|U|CC):') {
        $pathType = "Registry"
        # Already in PowerShell registry format
    }
    elseif ($normalizedPath -match '^[A-Za-z]:\\') {
        $pathType = "File"
    }
    elseif ($normalizedPath -match '^\\\\') {
        $pathType = "File"  # Network path is still a file path
    }
    elseif ($normalizedPath -match '^~') {
        $pathType = "File"
        # Convert ~ to user home directory
        $normalizedPath = $normalizedPath -replace '^~', $env:USERPROFILE
        # Apply test environment redirection after ~ expansion
        $normalizedPath = ConvertTo-TestEnvironmentPath -Path $normalizedPath
    }
    elseif ($Path.Contains('://')) {
        # For unrecognized URI schemes, return the original path unchanged
        $pathType = "File"
        $normalizedPath = $Path
    }
    else {
        $pathType = "File"  # Default to file for relative paths
    }

    return @{
        PathType = $pathType
        Type = $pathType  # For backwards compatibility
        Path = $normalizedPath
        Original = $Path
        IsResolved = $true
    }
}

function ConvertTo-TestEnvironmentPath {
    <#
    .SYNOPSIS
        Redirects dangerous system paths to safe test directories when in test environments.

    .DESCRIPTION
        This function prevents accidental writes to system directories by redirecting
        paths to appropriate test directories when running in test mode.

        CRITICAL: This function prevents writes to C:\ root directories during testing!

    .PARAMETER Path
        The path to potentially redirect.

    .RETURNS
        Safe test path if in test environment, original path otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Only redirect if we're in a test environment
    if (-not ($env:WMR_TEST_MODE -eq 'true' -or $env:PESTER_OUTPUT_PATH -or $env:WMR_DOCKER_TEST -eq 'true')) {
        return $Path
    }

    # Get test directories from environment if available
    $testRestorePath = $env:WMR_STATE_PATH
    $testBackupPath = $env:WMR_BACKUP_PATH

    # Fallback to safe defaults if environment variables not set
    if (-not $testRestorePath) {
        if ($env:WMR_DOCKER_TEST -eq 'true' -or $env:DOCKER_TEST -eq 'true' -or $env:CONTAINER -eq 'true' -or (Test-Path '/.dockerenv' -ErrorAction SilentlyContinue)) {
            $testRestorePath = "/workspace/Temp/test-restore"
        } else {
            # Use project root Temp directory for local environments
            $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $testRestorePath = Join-Path $moduleRoot "Temp\test-restore"
        }
    }

    Write-Verbose "ConvertTo-TestEnvironmentPath: Processing path '$Path'"

    # Define path mappings for test environment redirection
    $pathMappings = @{
        'C:\Program Files (x86)\Steam' = Join-Path $testRestorePath "TEST-MACHINE\programfiles\steam"
        'C:\Program Files\Steam' = Join-Path $testRestorePath "TEST-MACHINE\programfiles\steam"
        'C:\Program Files (x86)' = Join-Path $testRestorePath "TEST-MACHINE\programfiles"
        'C:\Program Files' = Join-Path $testRestorePath "TEST-MACHINE\programfiles"
        'C:\ProgramData' = Join-Path $testRestorePath "TEST-MACHINE\programdata"
        'C:\Windows' = Join-Path $testRestorePath "TEST-MACHINE\windows"
        'C:\Users' = Join-Path $testRestorePath "TEST-MACHINE\users"
    }

    # Check for matching path mappings (longest first for specificity)
    $sortedMappings = $pathMappings.GetEnumerator() | Sort-Object { $_.Key.Length } -Descending

    foreach ($mapping in $sortedMappings) {
        if ($Path.StartsWith($mapping.Key, [System.StringComparison]::OrdinalIgnoreCase)) {
            $redirectedPath = $Path.Replace($mapping.Key, $mapping.Value)
            Write-Verbose "ConvertTo-TestEnvironmentPath: Redirected '$Path' -> '$redirectedPath'"
            return $redirectedPath
        }
    }

    # If it's any other C:\ path (except if it's already in our project), redirect to mock area
    if ($Path.StartsWith("C:\") -and -not $Path.Contains("WindowsMelodyRecovery")) {
        $relativePath = $Path.Substring(3)  # Remove "C:\"
        $redirectedPath = Join-Path $testRestorePath "TEST-MACHINE\mock-c\$relativePath"
        Write-Verbose "ConvertTo-TestEnvironmentPath: Generic C:\ redirection '$Path' -> '$redirectedPath'"
        return $redirectedPath
    }

    # If it starts with environment variables that resolve to C:\, redirect those too
    if ($Path.StartsWith($env:USERPROFILE) -and $env:USERPROFILE.StartsWith("C:\") -and -not $Path.Contains("WindowsMelodyRecovery")) {
        $relativePath = $Path.Substring($env:USERPROFILE.Length).TrimStart('\')
        $redirectedPath = Join-Path $testRestorePath "TEST-MACHINE\userprofile\$relativePath"
        Write-Verbose "ConvertTo-TestEnvironmentPath: USERPROFILE redirection '$Path' -> '$redirectedPath'"
        return $redirectedPath
    }

    # Return original path if no redirection needed
    Write-Verbose "ConvertTo-TestEnvironmentPath: No redirection needed for '$Path'"
    return $Path
}





