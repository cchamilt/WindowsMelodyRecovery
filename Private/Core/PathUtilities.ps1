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