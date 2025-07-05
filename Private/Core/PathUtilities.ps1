# Private/Core/PathUtilities.ps1

function Convert-WmrPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Determine path type based on prefix
    $pathType = "Unknown"
    $normalizedPath = $Path.Replace('/', '\').TrimEnd('\')
    
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
        $pathType = "FileSystem"
    }
    elseif ($normalizedPath -match '^\\\\') {
        $pathType = "NetworkPath"
    }
    elseif ($normalizedPath -match '^~') {
        $pathType = "UserHome"
        # Convert ~ to user home directory
        $normalizedPath = $normalizedPath -replace '^~', $env:USERPROFILE
    }
    else {
        $pathType = "RelativePath"
    }

    return @{
        Path = $normalizedPath
        Original = $Path
        PathType = $pathType
        IsResolved = $true
    }
} 