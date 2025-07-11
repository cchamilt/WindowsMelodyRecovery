#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Registry Mock Utilities for Linux Container Testing

.DESCRIPTION
    Provides mock registry operations for testing Windows registry functionality
    in Linux container environments where Windows registry is not available.
#>

# Global mock registry storage
$script:MockRegistry = @{}

function Initialize-MockRegistry {
    <#
    .SYNOPSIS
    Initializes the mock registry with default test data
    #>

    $script:MockRegistry = @{
        'HKCU:\SOFTWARE\WmrRegTest' = @{
            'TestValue' = 'OriginalData'
            'NumericValue' = 12345
            'EncryptedValue' = 'SecretData'
        }
        'HKCU:\SOFTWARE\WmrRegTestDest' = @{}
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion' = @{
            'ProgramFilesDir' = 'C:\Program Files'
            'CommonFilesDir' = 'C:\Program Files\Common Files'
        }
        'HKCU:\Control Panel\Desktop' = @{
            'DisplayOrientation' = '1'
            'ResolutionHeight' = '1024'
            'ResolutionWidth' = '768'
        }
    }

    Write-Verbose "Mock registry initialized with test data"
}

function Get-MockItemProperty {
    <#
    .SYNOPSIS
    Mock implementation of Get-ItemProperty for registry testing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Name
    )

    # Initialize mock registry if not already done
    if (-not $script:MockRegistry) {
        Initialize-MockRegistry
    }

    # Normalize the path
    $normalizedPath = $Path -replace '/', '\'

    # Check if the registry key exists
    if (-not $script:MockRegistry.ContainsKey($normalizedPath)) {
        $errorMessage = "Registry key not found: $Path"
        if ($ErrorActionPreference -eq "Stop") {
            throw $errorMessage
        } else {
            Write-Warning $errorMessage
            return $null
        }
    }

    $keyData = $script:MockRegistry[$normalizedPath]

    if ($Name) {
        # Return specific value
        if ($keyData.ContainsKey($Name)) {
            return @{ $Name = $keyData[$Name] }
        } else {
            $errorMessage = "Registry value not found: $Path\$Name"
            if ($ErrorActionPreference -eq "Stop") {
                throw $errorMessage
            } else {
                Write-Warning $errorMessage
                return $null
            }
        }
    } else {
        # Return all values as PSObject
        $result = New-Object PSObject
        foreach ($key in $keyData.Keys) {
            $result | Add-Member -MemberType NoteProperty -Name $key -Value $keyData[$key]
        }
        return $result
    }
}

function Set-MockItemProperty {
    <#
    .SYNOPSIS
    Mock implementation of Set-ItemProperty for registry testing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # Initialize mock registry if not already done
    if (-not $script:MockRegistry) {
        Initialize-MockRegistry
    }

    # Normalize the path
    $normalizedPath = $Path -replace '/', '\'

    # Create the key if it doesn't exist
    if (-not $script:MockRegistry.ContainsKey($normalizedPath)) {
        $script:MockRegistry[$normalizedPath] = @{}
    }

    # Set the value
    $script:MockRegistry[$normalizedPath][$Name] = $Value

    Write-Verbose "Mock registry: Set $normalizedPath\$Name = $Value"
    return $true
}

function Test-MockPath {
    <#
    .SYNOPSIS
    Mock implementation of Test-Path for registry testing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$PathType
    )

    # For registry paths, check mock registry
    if ($Path -match '^HK(CU|LM|CR|U|CC):') {
        if (-not $script:MockRegistry) {
            Initialize-MockRegistry
        }

        $normalizedPath = $Path -replace '/', '\'
        return $script:MockRegistry.ContainsKey($normalizedPath)
    }

    # For file system paths, use actual Test-Path
    return (& (Get-Command Test-Path -CommandType Cmdlet) @PSBoundParameters)
}

function New-MockItem {
    <#
    .SYNOPSIS
    Mock implementation of New-Item for registry testing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$ItemType,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # For registry paths, add to mock registry
    if ($Path -match '^HK(CU|LM|CR|U|CC):') {
        if (-not $script:MockRegistry) {
            Initialize-MockRegistry
        }

        $normalizedPath = $Path -replace '/', '\'
        if (-not $script:MockRegistry.ContainsKey($normalizedPath)) {
            $script:MockRegistry[$normalizedPath] = @{}
        }

        Write-Verbose "Mock registry: Created key $normalizedPath"
        return @{ FullName = $normalizedPath }
    }

    # For file system paths, use actual New-Item
    return (& (Get-Command New-Item -CommandType Cmdlet) @PSBoundParameters)
}

function Remove-MockItem {
    <#
    .SYNOPSIS
    Mock implementation of Remove-Item for registry testing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # For registry paths, remove from mock registry
    if ($Path -match '^HK(CU|LM|CR|U|CC):') {
        if (-not $script:MockRegistry) {
            Initialize-MockRegistry
        }

        $normalizedPath = $Path -replace '/', '\'
        if ($script:MockRegistry.ContainsKey($normalizedPath)) {
            $script:MockRegistry.Remove($normalizedPath)
            Write-Verbose "Mock registry: Removed key $normalizedPath"
        }
        return $true
    }

    # For file system paths, use actual Remove-Item
    return (& (Get-Command Remove-Item -CommandType Cmdlet) @PSBoundParameters)
}

function Enable-RegistryMocking {
    <#
    .SYNOPSIS
    Enables registry mocking by creating aliases for registry cmdlets
    #>

    # Create aliases for registry operations
    Set-Alias -Name "Get-ItemProperty" -Value "Get-MockItemProperty" -Scope Global -Force
    Set-Alias -Name "Set-ItemProperty" -Value "Set-MockItemProperty" -Scope Global -Force
    Set-Alias -Name "Test-Path" -Value "Test-MockPath" -Scope Global -Force
    Set-Alias -Name "New-Item" -Value "New-MockItem" -Scope Global -Force
    Set-Alias -Name "Remove-Item" -Value "Remove-MockItem" -Scope Global -Force

    Initialize-MockRegistry

    Write-Information -MessageData "✓ Registry mocking enabled for testing" -InformationAction Continue
}

function Disable-RegistryMocking {
    <#
    .SYNOPSIS
    Disables registry mocking by removing aliases
    #>

    # Remove aliases to restore original cmdlets
    Remove-Alias -Name "Get-ItemProperty" -Scope Global -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name "Set-ItemProperty" -Scope Global -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name "Test-Path" -Scope Global -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name "New-Item" -Scope Global -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name "Remove-Item" -Scope Global -Force -ErrorAction SilentlyContinue

    Write-Warning -Message "✓ Registry mocking disabled"
}

function Get-MockRegistryState {
    <#
    .SYNOPSIS
    Returns the current state of the mock registry for debugging
    #>

    if (-not $script:MockRegistry) {
        return @{}
    }

    return $script:MockRegistry
}

# Export functions for use in tests (only when called as a module)
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    # When dot-sourced, functions are automatically available in the calling scope
    Write-Verbose "Registry mock functions loaded via dot-sourcing"
} else {
    # When imported as a module, export functions
    Export-ModuleMember -Function @(
        'Initialize-MockRegistry',
        'Get-MockItemProperty',
        'Set-MockItemProperty',
        'Test-MockPath',
        'New-MockItem',
        'Remove-MockItem',
        'Enable-RegistryMocking',
        'Disable-RegistryMocking',
        'Get-MockRegistryState'
    )
}







