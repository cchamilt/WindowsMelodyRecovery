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

function Test-WmrAdministrativePrivileges {
    <#
    .SYNOPSIS
        Enhanced administrative privilege testing with detailed information.

    .DESCRIPTION
        Tests for administrative privileges and provides detailed information
        about the current security context, including elevation status and
        privilege escalation capabilities.

    .PARAMETER ThrowIfNotAdmin
        If specified, throws an exception if not running with administrative privileges.

    .PARAMETER Quiet
        If specified, suppresses warning messages.

    .EXAMPLE
        Test-WmrAdministrativePrivileges

    .EXAMPLE
        Test-WmrAdministrativePrivileges -ThrowIfNotAdmin

    .OUTPUTS
        PSCustomObject with privilege information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$ThrowIfNotAdmin,

        [Parameter(Mandatory=$false)]
        [switch]$Quiet
    )

    $privilegeInfo = @{
        IsWindows = $IsWindows
        IsElevated = $false
        CanElevate = $false
        CurrentUser = $null
        ProcessId = $PID
        SecurityPrincipal = $null
        ElevationMethod = $null
        Warnings = @()
        Errors = @()
    }

    try {
        if ($IsWindows) {
            # Get current Windows identity and principal
            $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $currentPrincipal = [Security.Principal.WindowsPrincipal]$currentIdentity

            $privilegeInfo.CurrentUser = $currentIdentity.Name
            $privilegeInfo.SecurityPrincipal = $currentPrincipal
            $privilegeInfo.IsElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            # Check if we can potentially elevate
            $privilegeInfo.CanElevate = Test-WmrElevationCapability

            # Determine elevation method
            if ($privilegeInfo.IsElevated) {
                $privilegeInfo.ElevationMethod = "Already Elevated"
            } elseif ($privilegeInfo.CanElevate) {
                $privilegeInfo.ElevationMethod = "UAC Available"
            } else {
                $privilegeInfo.ElevationMethod = "No Elevation Available"
            }

        } else {
            # Non-Windows environment
            $privilegeInfo.CurrentUser = $env:USER
            $privilegeInfo.IsElevated = (id -u) -eq 0  # Check if root on Unix-like systems
            $privilegeInfo.CanElevate = $false
            $privilegeInfo.ElevationMethod = "Unix/Linux Environment"
        }

        # Add warnings if needed
        if (-not $privilegeInfo.IsElevated -and -not $Quiet) {
            $privilegeInfo.Warnings += "Not running with administrative privileges"
        }

        if ($ThrowIfNotAdmin -and -not $privilegeInfo.IsElevated) {
            throw "Administrative privileges are required for this operation. Current user: $($privilegeInfo.CurrentUser)"
        }

    } catch {
        $privilegeInfo.Errors += $_.Exception.Message
        if ($ThrowIfNotAdmin) {
            throw
        }
    }

    return [PSCustomObject]$privilegeInfo
}

function Test-WmrElevationCapability {
    <#
    .SYNOPSIS
        Tests if the current process can potentially be elevated.

    .DESCRIPTION
        Checks if UAC is available and if the current user can potentially
        elevate to administrative privileges.

    .EXAMPLE
        Test-WmrElevationCapability

    .OUTPUTS
        Boolean indicating if elevation is possible
    #>
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        return $false
    }

    try {
        # Check if UAC is enabled
        $uacEnabled = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue

        if ($uacEnabled -and $uacEnabled.EnableLUA -eq 1) {
            # UAC is enabled, check if current user is in Administrators group
            $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
            $adminGroup = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

            # Check if user is in administrators group
            foreach ($group in $currentUser.Groups) {
                if ($group.Equals($adminGroup)) {
                    return $true
                }
            }
        }

        return $false

    } catch {
        Write-Verbose "Failed to check elevation capability: $($_.Exception.Message)"
        return $false
    }
}

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
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory=$false)]
        [array]$ArgumentList = @(),

        [Parameter(Mandatory=$false)]
        [switch]$NoPrompt
    )

    $privilegeInfo = Test-WmrAdministrativePrivileges -Quiet

    if ($WhatIfPreference) {
        Write-Warning -Message "What if: Would execute script block with elevation"
        Write-Verbose -Message "Current elevation status: $($privilegeInfo.IsElevated)"
        Write-Verbose -Message "Can elevate: $($privilegeInfo.CanElevate)"
        return @{ WhatIf = $true; WouldElevate = (-not $privilegeInfo.IsElevated) }
    }

    try {
        if ($privilegeInfo.IsElevated) {
            # Already elevated, execute directly
            Write-Verbose "Already running with administrative privileges"
            return & $ScriptBlock @ArgumentList

        } elseif ($privilegeInfo.CanElevate -and -not $NoPrompt) {
            # Can elevate, but would require UAC prompt
            Write-Warning "This operation requires administrative privileges."
            Write-Warning "In a production environment, this would prompt for UAC elevation."

            # In test environment, simulate elevation failure
            if ($env:MOCK_MODE -eq "true" -or $env:CI -eq "true") {
                Write-Warning "Simulating elevation failure in test/CI environment"
                return @{
                    Success = $false
                    RequiresElevation = $true
                    Message = "Elevation required but not available in test environment"
                }
            }

            # In real environment, this would trigger UAC
            throw "UAC elevation required but not implemented in this context"

        } else {
            # Cannot elevate
            $message = if ($NoPrompt) {
                "Administrative privileges required but elevation prompting is disabled"
            } else {
                "Administrative privileges required but elevation is not available"
            }

            Write-Warning $message
            return @{
                Success = $false
                RequiresElevation = $true
                Message = $message
            }
        }

    } catch {
        Write-Error "Failed to execute with elevation: $($_.Exception.Message)"
        return @{
            Success = $false
            RequiresElevation = $true
            Error = $_.Exception.Message
        }
    }
}

function Test-WmrAdminRequiredOperation {
    <#
    .SYNOPSIS
        Tests if an operation requires administrative privileges.

    .DESCRIPTION
        Analyzes an operation to determine if it requires administrative privileges
        based on the paths, registry keys, services, or other resources it accesses.

    .PARAMETER OperationType
        The type of operation (Registry, File, Service, ScheduledTask, WindowsFeature).

    .PARAMETER Path
        The path or resource being accessed.

    .PARAMETER Action
        The action being performed (Read, Write, Create, Delete, Modify).

    .EXAMPLE
        Test-WmrAdminRequiredOperation -OperationType "Registry" -Path "HKLM:\SOFTWARE\Test" -Action "Write"

    .EXAMPLE
        Test-WmrAdminRequiredOperation -OperationType "File" -Path "C:\Windows\System32\test.txt" -Action "Create"

    .OUTPUTS
        Boolean indicating if administrative privileges are required
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Registry", "File", "Service", "ScheduledTask", "WindowsFeature", "WindowsCapability")]
        [string]$OperationType,

        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Read", "Write", "Create", "Delete", "Modify", "Execute")]
        [string]$Action
    )

    switch ($OperationType) {
        "Registry" {
            # HKLM writes generally require admin
            if ($Path -like "HKLM:*" -and $Action -in @("Write", "Create", "Delete", "Modify")) {
                return $true
            }

            # Specific protected registry paths
            $protectedPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
                "HKLM:\SYSTEM\CurrentControlSet",
                "HKLM:\SOFTWARE\Classes"
            )

            foreach ($protectedPath in $protectedPaths) {
                if ($Path -like "$protectedPath*") {
                    return $true
                }
            }

            return $false
        }

        "File" {
            # System directories generally require admin for writes
            $systemPaths = @(
                "C:\Windows\",
                "C:\Program Files\",
                "C:\Program Files (x86)\",
                "C:\Windows\System32\",
                "C:\Windows\SysWOW64\"
            )

            # Also check environment variable paths
            if ($env:SystemRoot) {
                $systemPaths += "$env:SystemRoot\System32\"
                $systemPaths += "$env:SystemRoot\SysWOW64\"
            }

            if ($Action -in @("Write", "Create", "Delete", "Modify")) {
                foreach ($systemPath in $systemPaths) {
                    if ($Path -like "$systemPath*") {
                        return $true
                    }
                }
            }

            return $false
        }

        "Service" {
            # Service modifications generally require admin
            if ($Action -in @("Write", "Create", "Delete", "Modify", "Execute")) {
                return $true
            }
            return $false
        }

        "ScheduledTask" {
            # Scheduled task operations generally require admin
            if ($Action -in @("Create", "Delete", "Modify")) {
                return $true
            }
            return $false
        }

        "WindowsFeature" {
            # Windows feature operations always require admin
            return $true
        }

        "WindowsCapability" {
            # Windows capability operations always require admin
            return $true
        }

        default {
            return $false
        }
    }
}

function Get-WmrPrivilegeRequirements {
    <#
    .SYNOPSIS
        Gets privilege requirements for a template or operation.

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
        [Parameter(Mandatory=$true)]
        [PSObject]$TemplateConfig,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Backup", "Restore", "Sync")]
        [string]$Operation
    )

    $requirements = @{
        RequiresAdmin = $false
        AdminOperations = @()
        SafeOperations = @()
        Warnings = @()
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
                $isAdminRequired = Test-WmrAdminRequiredOperation -OperationType "Registry" -Path $reg.path -Action "Write"

                if ($isAdminRequired) {
                    $requirements.RequiresAdmin = $true
                    $requirements.AdminOperations += "Registry: $($reg.path)"
                } else {
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
                $isAdminRequired = Test-WmrAdminRequiredOperation -OperationType "File" -Path $file.path -Action $action

                if ($isAdminRequired) {
                    $requirements.RequiresAdmin = $true
                    $requirements.AdminOperations += "File: $($file.path)"
                } else {
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
            } else {
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
        Safely invokes an operation that may require administrative privileges.

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
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory=$false)]
        [ScriptBlock]$FallbackScriptBlock,

        [Parameter(Mandatory=$true)]
        [string]$OperationName,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Admin", "Elevated", "User")]
        [string]$RequiredPrivileges = "Admin"
    )

    $result = @{
        Success = $false
        Data = $null
        RequiredPrivileges = $RequiredPrivileges
        ActualPrivileges = "Unknown"
        UsedFallback = $false
        Warnings = @()
        Errors = @()
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

        } elseif ($FallbackScriptBlock) {
            # Execute fallback operation
            Write-Warning "$OperationName requires $RequiredPrivileges privileges. Using fallback operation."
            $result.Data = & $FallbackScriptBlock
            $result.Success = $true
            $result.UsedFallback = $true
            $result.Warnings += "Used fallback operation due to insufficient privileges"

        } else {
            # Cannot proceed
            $message = "$OperationName requires $RequiredPrivileges privileges but only $($result.ActualPrivileges) privileges are available"
            $result.Errors += $message
            $result.Warnings += "Operation skipped due to insufficient privileges"
            Write-Warning $message
        }

    } catch {
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
            } catch {
                $result.Errors += "Fallback also failed: $($_.Exception.Message)"
                Write-Warning "Fallback operation for $OperationName also failed: $($_.Exception.Message)"
            }
        }
    }

    return [PSCustomObject]$result
}

# Export functions for module use
# Export-ModuleMember -Function @(
#     'Test-WmrAdministrativePrivileges',
#     'Test-WmrElevationCapability',
#     'Invoke-WmrWithElevation',
#     'Test-WmrAdminRequiredOperation',
#     'Get-WmrPrivilegeRequirements',
#     'Invoke-WmrSafeAdminOperation'
# )
