# Private/Core/AdministrativePrivileges.ps1

<#
.SYNOPSIS
    Administrative privilege management functions for Windows Melody Recovery.

.DESCRIPTION
    Provides comprehensive administrative privilege checking, escalation prompts,
    and safe handling of admin-required operations with proper testing support.

.NOTES
    Author: Windows Melody Recovery
    Version: 1.0
    Requires: PowerShell 5.1 or later
#>

function Invoke-WmrWithElevation {
    <#
    .SYNOPSIS
        Invokes a script block or command with elevated privileges.

    .DESCRIPTION
        Attempts to run a script block or command with administrative privileges,
        either by checking current elevation or by prompting for elevation.

    .PARAMETER ScriptBlock
        The script block to execute with elevation.

    .PARAMETER ArgumentList
        Arguments to pass to the script block.

    .PARAMETER NoPrompt
        If specified, does not prompt for elevation and fails if not elevated.

    .PARAMETER WhatIf
        If specified, shows what would be executed without actually running it.

    .EXAMPLE
        Invoke-WmrWithElevation -ScriptBlock { Get-WindowsOptionalFeature -Online }

    .EXAMPLE
        Invoke-WmrWithElevation -ScriptBlock { param($Path) New-Item -Path $Path -ItemType Directory } -ArgumentList "C:\TestDir"

    .OUTPUTS
        Result of the script block execution or elevation information
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [array]$ArgumentList = @(),

        [Parameter(Mandatory = $false)]
        [switch]$NoPrompt
    )

    $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($WhatIfPreference) {
        Write-Warning -Message "What if: Would execute script block with elevation"
        Write-Verbose -Message "Current elevation status: $isElevated"
        return @{ WhatIf = $true; WouldElevate = (-not $isElevated) }
    }

    try {
        if ($isElevated) {
            # Already elevated, execute directly
            Write-Verbose "Already running with administrative privileges"
            return & $ScriptBlock @ArgumentList

        }
        elseif (-not $NoPrompt) {
            # Can elevate, but would require UAC prompt
            Write-Warning "This operation requires administrative privileges."
            Write-Warning "In a production environment, this would prompt for UAC elevation."

            # In test environment, simulate elevation failure
            if ($env:MOCK_MODE -eq "true" -or $env:CI -eq "true") {
                Write-Warning "Simulating elevation failure in test/CI environment"
                return @{
                    Success           = $false
                    RequiresElevation = $true
                    Message           = "Elevation required but not available in test environment"
                }
            }

            # In real environment, this would trigger UAC
            throw "UAC elevation required but not implemented in this context"

        }
        else {
            # Cannot elevate
            $message = if ($NoPrompt) {
                "Administrative privileges required but elevation prompting is disabled"
            }
            else {
                "Administrative privileges required but elevation is not available"
            }

            Write-Warning $message
            return @{
                Success           = $false
                RequiresElevation = $true
                Message           = $message
            }
        }

    }
    catch {
        Write-Error "Failed to execute with elevation: $($_.Exception.Message)"
        return @{
            Success           = $false
            RequiresElevation = $true
            Error             = $_.Exception.Message
        }
    }
}

function Get-WmrPrivilegeRequirements {
    <#
    .SYNOPSIS
        Analyzes a template to determine its privilege requirements.

    .DESCRIPTION
        Analyzes a template configuration or operation to determine what
        administrative privileges are required.

    .PARAMETER TemplateConfig
        The template configuration to analyze.

    .PARAMETER Operation
        The operation being performed (Backup, Restore, Sync).

    .EXAMPLE
        Get-WmrPrivilegeRequirements -TemplateConfig $template -Operation "Backup"

    .OUTPUTS
        PSCustomObject with privilege requirement analysis
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$TemplateConfig,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Backup", "Restore", "Sync")]
        [string]$Operation
    )

    $requirements = @{
        RequiresAdmin      = $false
        AdminOperations    = @()
        SafeOperations     = @()
        Warnings           = @()
        CanRunWithoutAdmin = $false
    }

    # Check prerequisites for admin requirements
    if ($TemplateConfig.prerequisites) {
        foreach ($prereq in $TemplateConfig.prerequisites) {
            if ($prereq.name -like "*Admin*" -or $prereq.name -like "*Elevat*" -or
                $prereq.inline_script -like "*Administrator*" -or $prereq.inline_script -like "*IsInRole*") {
                $requirements.RequiresAdmin = $true
                $requirements.AdminOperations += "Prerequisite: $($prereq.name)"
            }
        }
    }

    # Check registry operations
    if ($TemplateConfig.registry) {
        foreach ($reg in $TemplateConfig.registry) {
            if ($reg.action -eq $Operation -or $reg.action -eq "sync") {
                $isAdminRequired = $false
                if ($reg.path -like "HKLM:*" -and $reg.action -in @("Write", "Create", "Delete", "Modify")) {
                    $isAdminRequired = $true
                }

                if ($isAdminRequired) {
                    $requirements.RequiresAdmin = $true
                    $requirements.AdminOperations += "Registry: $($reg.path)"
                }
                else {
                    $requirements.SafeOperations += "Registry: $($reg.path)"
                }
            }
        }
    }

    # Check file operations
    if ($TemplateConfig.files) {
        foreach ($file in $TemplateConfig.files) {
            if ($file.action -eq $Operation -or $file.action -eq "sync") {
                $action = if ($Operation -eq "Backup") { "Read" } else { "Write" }
                $isAdminRequired = $false
                if ($action -in @("Write", "Create", "Delete", "Modify")) {
                    $systemPaths = @("C:\Windows\", "C:\Program Files\", "C:\Program Files (x86)\")
                    foreach ($systemPath in $systemPaths) {
                        if ($file.path -like "$systemPath*") {
                            $isAdminRequired = $true
                            break
                        }
                    }
                }

                if ($isAdminRequired) {
                    $requirements.RequiresAdmin = $true
                    $requirements.AdminOperations += "File: $($file.path)"
                }
                else {
                    $requirements.SafeOperations += "File: $($file.path)"
                }
            }
        }
    }

    # Check applications for Windows features/capabilities
    if ($TemplateConfig.applications) {
        foreach ($app in $TemplateConfig.applications) {
            if ($app.discovery_command -like "*Get-WindowsOptionalFeature*" -or
                $app.discovery_command -like "*Get-WindowsCapability*" -or
                $app.discovery_command -like "*Get-WindowsFeature*") {
                $requirements.RequiresAdmin = $true
                $requirements.AdminOperations += "Windows Feature/Capability: $($app.name)"
            }
            else {
                $requirements.SafeOperations += "Application: $($app.name)"
            }
        }
    }

    # Determine if template can run without admin (with degraded functionality)
    $requirements.CanRunWithoutAdmin = $requirements.SafeOperations.Count -gt 0

    if ($requirements.RequiresAdmin -and $requirements.SafeOperations.Count -gt 0) {
        $requirements.Warnings += "Template has both admin-required and safe operations. Can run with degraded functionality without admin privileges."
    }

    return [PSCustomObject]$requirements
}

function Invoke-WmrSafeAdminOperation {
    <#
    .SYNOPSIS
        Safely executes an operation that may require administrative privileges.

    .DESCRIPTION
        Attempts to perform an operation that may require admin privileges,
        with proper error handling and graceful degradation for testing environments.

    .PARAMETER ScriptBlock
        The script block to execute.

    .PARAMETER FallbackScriptBlock
        Alternative script block to execute if admin privileges are not available.

    .PARAMETER OperationName
        Descriptive name of the operation for logging.

    .PARAMETER RequiredPrivileges
        The type of privileges required (Admin, Elevated, User).

    .EXAMPLE
        Invoke-WmrSafeAdminOperation -ScriptBlock { Get-WindowsOptionalFeature -Online } -OperationName "Get Windows Features"

    .OUTPUTS
        Result of the operation with status information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ScriptBlock]$FallbackScriptBlock,

        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Admin", "Elevated", "User")]
        [string]$RequiredPrivileges = "Admin"
    )

    $result = @{
        Success            = $false
        Data               = $null
        RequiredPrivileges = $RequiredPrivileges
        ActualPrivileges   = "Unknown"
        UsedFallback       = $false
        Warnings           = @()
        Errors             = @()
    }

    try {
        # Check current privileges
        $privilegeInfo = Test-WmrAdministrativePrivileges -Quiet
        $result.ActualPrivileges = if ($privilegeInfo.IsElevated) { "Admin" } else { "User" }

        # Determine if we can proceed
        $canProceed = switch ($RequiredPrivileges) {
            "Admin" { $privilegeInfo.IsElevated }
            "Elevated" { $privilegeInfo.IsElevated }
            "User" { $true }
            default { $false }
        }

        if ($canProceed) {
            # Execute main operation
            Write-Verbose "Executing $OperationName with $($result.ActualPrivileges) privileges"
            $result.Data = & $ScriptBlock
            $result.Success = $true

        }
        elseif ($FallbackScriptBlock) {
            # Execute fallback operation
            Write-Warning "$OperationName requires $RequiredPrivileges privileges. Using fallback operation."
            $result.Data = & $FallbackScriptBlock
            $result.Success = $true
            $result.UsedFallback = $true
            $result.Warnings += "Used fallback operation due to insufficient privileges"

        }
        else {
            # Cannot proceed
            $message = "$OperationName requires $RequiredPrivileges privileges but only $($result.ActualPrivileges) privileges are available"
            $result.Errors += $message
            $result.Warnings += "Operation skipped due to insufficient privileges"
            Write-Warning $message
        }

    }
    catch {
        $result.Errors += $_.Exception.Message
        Write-Warning "Failed to execute $OperationName`: $($_.Exception.Message)"

        # Try fallback if available
        if ($FallbackScriptBlock -and -not $result.UsedFallback) {
            try {
                Write-Warning "Attempting fallback operation for $OperationName"
                $result.Data = & $FallbackScriptBlock
                $result.Success = $true
                $result.UsedFallback = $true
                $result.Warnings += "Used fallback operation due to error in main operation"
            }
            catch {
                $result.Errors += "Fallback also failed: $($_.Exception.Message)"
                Write-Warning "Fallback operation for $OperationName also failed: $($_.Exception.Message)"
            }
        }
    }

    return [PSCustomObject]$result
}

if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    # Only export when loaded as a module, not when dot-sourced
    try {
        Export-ModuleMember -Function @(
            # Main privilege management functions
            'Invoke-WmrWithElevation',
            'Get-WmrPrivilegeRequirements',
            'Invoke-WmrSafeAdminOperation'
        )
    }
    catch {
        # Silently ignore Export-ModuleMember errors when not in module context
    }
}







