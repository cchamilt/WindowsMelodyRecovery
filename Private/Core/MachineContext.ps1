# Private/Core/MachineContext.ps1

<#
.SYNOPSIS
    Machine context and selection functionality for Windows Melody Recovery template inheritance.

.DESCRIPTION
    Provides functions to collect machine context information, test machine selectors,
    and determine which machine-specific configurations apply to the current machine.

.NOTES
    Author: Windows Melody Recovery
    Version: 2.0
    Requires: PowerShell 5.1 or later
#>

function Get-WmrMachineContext {
    <#
    .SYNOPSIS
        Gets machine context information for inheritance resolution.

    .DESCRIPTION
        Collects information about the current machine that can be used
        for inheritance resolution, including machine name, environment
        variables, hardware information, and software checks.

    .EXAMPLE
        $context = Get-WmrMachineContext
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param()

    Write-Verbose "Collecting machine context information"

    try {
        $context = @{
            MachineName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            UserProfile = $env:USERPROFILE
            OSVersion = [System.Environment]::OSVersion.Version.ToString()
            Architecture = $env:PROCESSOR_ARCHITECTURE
            Domain = $env:USERDOMAIN
            EnvironmentVariables = @{}
            HardwareInfo = @{}
            SoftwareInfo = @{}
            Timestamp = Get-Date
        }

        # Collect relevant environment variables
        $relevantEnvVars = @("COMPUTERNAME", "USERNAME", "USERPROFILE", "PROCESSOR_ARCHITECTURE", "USERDOMAIN", "PROCESSOR_IDENTIFIER")
        foreach ($envVar in $relevantEnvVars) {
            $envValue = [System.Environment]::GetEnvironmentVariable($envVar)
            if ($envValue) {
                $context.EnvironmentVariables[$envVar] = $envValue
            }
        }

        # Collect basic hardware information
        try {
            $context.HardwareInfo.Processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
            $context.HardwareInfo.Memory = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum | Select-Object -ExpandProperty Sum
            $context.HardwareInfo.VideoControllers = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name, AdapterRAM
        } catch {
            Write-Warning "Failed to collect hardware information: $($_.Exception.Message)"
        }

        # Collect basic software information
        try {
            $context.SoftwareInfo.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            $context.SoftwareInfo.DotNetVersion = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        } catch {
            Write-Warning "Failed to collect software information: $($_.Exception.Message)"
        }

        Write-Verbose "Machine context collection completed"
        return $context

    } catch {
        Write-Error "Failed to collect machine context: $($_.Exception.Message)"
        throw
    }
}

function Get-WmrApplicableMachineConfigurations {
    <#
    .SYNOPSIS
        Gets machine-specific configurations that apply to the current machine.
    #>
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory=$true)]
        [array]$MachineSpecificConfigs,

        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )

    $applicableConfigs = @()

    foreach ($config in $MachineSpecificConfigs) {
        if (Test-WmrMachineSelector -MachineSelectors $config.machine_selectors -MachineContext $MachineContext) {
            Write-Verbose "Machine-specific configuration '$($config.name)' applies to this machine"
            $applicableConfigs += $config
        }
    }

    # Sort by priority (higher priority first)
    $applicableConfigs = $applicableConfigs | Sort-Object { if ($_.priority) { $_.priority } else { 80 } } -Descending

    return $applicableConfigs
}

function Test-WmrMachineSelector {
    <#
    .SYNOPSIS
        Tests if machine selectors match the current machine.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [array]$MachineSelectors,

        [Parameter(Mandatory=$true)]
        [PSObject]$MachineContext
    )

    foreach ($selector in $MachineSelectors) {
        $result = $false

        switch ($selector.type) {
            "machine_name" {
                $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                $result = Test-WmrStringComparison -Value $MachineContext.MachineName -Expected $selector.value -Operator $selector.operator -CaseSensitive $caseSensitive
            }
            "hostname_pattern" {
                $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                $result = Test-WmrStringComparison -Value $MachineContext.MachineName -Expected $selector.value -Operator "matches" -CaseSensitive $caseSensitive
            }
            "environment_variable" {
                $envValue = $MachineContext.EnvironmentVariables[$selector.value]
                if ($envValue) {
                    $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                    $result = Test-WmrStringComparison -Value $envValue -Expected $selector.expected_value -Operator $selector.operator -CaseSensitive $caseSensitive
                }
            }
            "registry_value" {
                try {
                    $regValue = Get-ItemProperty -Path $selector.path -Name $selector.key_name -ErrorAction SilentlyContinue
                    if ($regValue) {
                        $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                        $result = Test-WmrStringComparison -Value $regValue.$($selector.key_name) -Expected $selector.expected_value -Operator $selector.operator -CaseSensitive $caseSensitive
                    }
                } catch {
                    Write-Verbose "Failed to read registry value for selector: $($_.Exception.Message)"
                }
            }
            "script" {
                try {
                    $scriptBlock = [ScriptBlock]::Create($selector.script)
                    $scriptResult = & $scriptBlock $MachineContext
                    $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                    $result = Test-WmrStringComparison -Value $scriptResult -Expected $selector.expected_result -Operator $selector.operator -CaseSensitive $caseSensitive
                } catch {
                    Write-Verbose "Failed to execute selector script: $($_.Exception.Message)"
                }
            }
        }

        if ($result) {
            return $true  # At least one selector matches
        }
    }

    return $false  # No selectors matched
}

function Test-WmrStringComparison {
    <#
    .SYNOPSIS
        Tests string comparison with various operators.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Value,

        [Parameter(Mandatory=$true)]
        [string]$Expected,

        [Parameter(Mandatory=$false)]
        [string]$Operator = "equals",

        [Parameter(Mandatory=$false)]
        [bool]$CaseSensitive = $false
    )

    switch ($Operator) {
        "equals" {
            if ($CaseSensitive) {
                return $Value -ceq $Expected
            } else {
                return $Value -eq $Expected
            }
        }
        "not_equals" {
            if ($CaseSensitive) {
                return $Value -cne $Expected
            } else {
                return $Value -ne $Expected
            }
        }
        "contains" {
            if ($CaseSensitive) {
                return $Value -clike "*$Expected*"
            } else {
                return $Value -like "*$Expected*"
            }
        }
        "matches" {
            if ($CaseSensitive) {
                return $Value -cmatch $Expected
            } else {
                return $Value -match $Expected
            }
        }
        "greater_than" {
            if ($CaseSensitive) {
                return $Value -cgt $Expected
            } else {
                return $Value -gt $Expected
            }
        }
        "less_than" {
            if ($CaseSensitive) {
                return $Value -clt $Expected
            } else {
                return $Value -lt $Expected
            }
        }
        default {
            Write-Warning "Unknown comparison operator: $Operator"
            return $false
        }
    }
}

# Functions are available when dot-sourced, no need to export when not in module context