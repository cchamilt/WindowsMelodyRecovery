function Find-ModulePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ModuleName = "WindowsMissingRecovery",
        
        [Parameter(Mandatory=$false)]
        [string]$CallerPath = $null
    )
    
    # If we have a caller path, try to find the module relative to that
    if ($CallerPath) {
        $scriptPath = Split-Path -Parent $CallerPath
        $modulePath = Split-Path -Parent $scriptPath
        
        # Check if this path looks like a valid module path
        if (Test-Path (Join-Path $modulePath "Private") -or 
            Test-Path (Join-Path $modulePath "Public")) {
            return $modulePath
        }
    }
    
    # Try to find module in both PowerShell and WindowsPowerShell paths
    $psModulePaths = $env:PSModulePath -split ';'
    $windowsPowerShellPath = $psModulePaths | Where-Object { $_ -like "*WindowsPowerShell*" } | Select-Object -First 1
    $powerShellPath = $psModulePaths | Where-Object { $_ -like "*PowerShell*" -and $_ -notlike "*WindowsPowerShell*" } | Select-Object -First 1
    
    $possiblePaths = @()
    if ($windowsPowerShellPath) {
        $possiblePaths += Join-Path $windowsPowerShellPath "Modules\$ModuleName"
    }
    if ($powerShellPath) {
        $possiblePaths += Join-Path $powerShellPath "Modules\$ModuleName"
    }
    
    # Try any custom paths that might be set in the environment
    if ($env:PSModuleCustomPath) {
        $possiblePaths += Join-Path $env:PSModuleCustomPath $ModuleName
    }
    
    # Add the standard program files paths
    $possiblePaths += @(
        "$env:ProgramFiles\WindowsPowerShell\Modules\$ModuleName",
        "${env:ProgramFiles(x86)}\WindowsPowerShell\Modules\$ModuleName",
        "$env:ProgramFiles\PowerShell\Modules\$ModuleName",
        "${env:ProgramFiles(x86)}\PowerShell\Modules\$ModuleName"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Verbose "Found module at: $path"
            return $path
        }
    }
    
    # If we get here, we couldn't find the module
    Write-Warning "Could not find module path for: $ModuleName"
    return $null
}

# Export the function for use in other scripts
Export-ModuleMember -Function Find-ModulePath 