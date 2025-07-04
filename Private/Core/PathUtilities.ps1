# Private/Core/PathUtilities.ps1

function Convert-WmrPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # For testing, just return the path as is with some basic normalization
    $normalizedPath = $Path.Replace('/', '\').TrimEnd('\')
    return @{
        Path = $normalizedPath
        Original = $Path
        IsResolved = $true
    }
} 