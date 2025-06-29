# Private/Core/PathUtilities.ps1

function Convert-WmrPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Handle environment variables like $env:VAR, $HOME
    $ExpandedPath = [System.Environment]::ExpandEnvironmentVariables($Path)

    # Handle WSL paths (wsl:///home/$user/...) and winreg (winreg://HKLM/...)
    if ($ExpandedPath.StartsWith("wsl://")) {
        # For WSL paths, we need to extract the distribution and the path within WSL
        # Example: wsl://WSLVM/home/$user/.bashrc or wsl:///home/$user/.bashrc
        $wslPath = $ExpandedPath.Substring("wsl://".Length)
        if ($wslPath.StartsWith("/")) {
            # Default WSL distribution
            $distribution = ""
            $internalPath = $wslPath
        } else {
            # Specific WSL distribution
            $parts = $wslPath.Split('/', 2)
            $distribution = $parts[0]
            $internalPath = "/" + $parts[1]
        }

        # Resolve $user in WSL context if applicable (this would require querying WSL for current user)
        # For now, we'll leave it as is or assume it's already expanded by ExpandEnvironmentVariables if $user is a Windows env var
        # More robust implementation would involve calling `wsl -d $distribution bash -c 'echo $USER'`
        $ResolvedInternalPath = $internalPath -replace '$user', $env:USERNAME # Placeholder: assuming $user maps to Windows username for now

        # Return a custom object or formatted string indicating WSL path
        [PSCustomObject]@{ 
            PathType = "WSL"; 
            Distribution = $distribution; 
            Path = $ResolvedInternalPath; 
            Original = $Path 
        }
    }
    elseif ($ExpandedPath.StartsWith("winreg://")) {
        # Convert winreg://HKLM/Software/... to HKLM:\Software\...
        $regPath = $ExpandedPath.Substring("winreg://".Length)
        $regPath = $regPath -replace '/', '\\'
        $regPath = $regPath -replace '^HKLM\\', 'HKLM:'
        $regPath = $regPath -replace '^HKCU\\', 'HKCU:'
        $regPath = $regPath -replace '^HKCR\\', 'HKCR:'
        $regPath = $regPath -replace '^HKU\\', 'HKU:'
        $regPath = $regPath -replace '^HKCC\\', 'HKCC:'

        [PSCustomObject]@{ 
            PathType = "Registry"; 
            Path = $regPath; 
            Original = $Path 
        }
    }
    elseif ($ExpandedPath.StartsWith("file://")) {
        # Remove "file://" prefix and normalize slashes
        $filePath = $ExpandedPath.Substring("file://".Length)
        $normalizedPath = $filePath -replace '/', '\\'

        [PSCustomObject]@{ 
            PathType = "File"; 
            Path = $normalizedPath; 
            Original = $Path 
        }
    }
    else {
        # Assume it's a regular Windows path
        [PSCustomObject]@{ 
            PathType = "File"; 
            Path = $ExpandedPath; 
            Original = $Path 
        }
    }
} 