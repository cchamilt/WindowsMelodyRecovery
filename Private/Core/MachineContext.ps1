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
            MachineName          = $env:COMPUTERNAME
            UserName             = $env:USERNAME
            UserProfile          = $env:USERPROFILE
            OSVersion            = [System.Environment]::OSVersion.Version.ToString()
            Architecture         = $env:PROCESSOR_ARCHITECTURE
            Domain               = $env:USERDOMAIN
            EnvironmentVariables = @{}
            HardwareInfo         = @{}
            SoftwareInfo         = @{}
            Timestamp            = Get-Date
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
        }
        catch {
            Write-Warning "Failed to collect hardware information: $($_.Exception.Message)"
        }

        # Collect basic software information
        try {
            $context.SoftwareInfo.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            $context.SoftwareInfo.DotNetVersion = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        }
        catch {
            Write-Warning "Failed to collect software information: $($_.Exception.Message)"
        }

        Write-Verbose "Machine context collection completed"
        return $context

    }
    catch {
        Write-Error "Failed to collect machine context: $($_.Exception.Message)"
        throw
    }
}

function Get-WmrApplicableMachineConfiguration {
    <#
    .SYNOPSIS
        Gets machine-specific configurations that apply to the current machine.
    #>
    [CmdletBinding()]
    [OutputType([System.Array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$MachineSpecificConfigs,

        [Parameter(Mandatory = $true)]
        [PSObject]$MachineContext
    )

    $applicableConfigs = @()

    foreach ($config in $MachineSpecificConfigs) {
        $configApplicable = $false
        foreach ($selector in $config.machine_selectors) {
            $result = $false
            switch ($selector.type) {
                "machine_name" {
                    $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                    if ($caseSensitive) {
                        $result = $MachineContext.MachineName -ceq $selector.value
                    }
                    else {
                        $result = $MachineContext.MachineName -eq $selector.value
                    }
                }
                "hostname_pattern" {
                    $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                    if ($caseSensitive) {
                        $result = $MachineContext.MachineName -cmatch $selector.value
                    }
                    else {
                        $result = $MachineContext.MachineName -match $selector.value
                    }
                }
                "environment_variable" {
                    $envValue = $MachineContext.EnvironmentVariables[$selector.value]
                    if ($envValue) {
                        $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                        if ($caseSensitive) {
                            $result = $envValue -ceq $selector.expected_value
                        }
                        else {
                            $result = $envValue -eq $selector.expected_value
                        }
                    }
                }
                "registry_value" {
                    try {
                        $regValue = Get-ItemProperty -Path $selector.path -Name $selector.key_name -ErrorAction SilentlyContinue
                        if ($regValue) {
                            $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                            if ($caseSensitive) {
                                $result = $regValue.$($selector.key_name) -ceq $selector.expected_value
                            }
                            else {
                                $result = $regValue.$($selector.key_name) -eq $selector.expected_value
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Failed to read registry value for selector: $($_.Exception.Message)"
                    }
                }
                "script" {
                    try {
                        $scriptBlock = [ScriptBlock]::Create($selector.script)
                        $scriptResult = & $scriptBlock $MachineContext
                        $caseSensitive = if ($null -ne $selector.case_sensitive -and $selector.case_sensitive -ne "") { [bool]$selector.case_sensitive } else { $false }
                        if ($caseSensitive) {
                            $result = $scriptResult -ceq $selector.expected_result
                        }
                        else {
                            $result = $scriptResult -eq $selector.expected_result
                        }
                    }
                    catch {
                        Write-Verbose "Failed to execute selector script: $($_.Exception.Message)"
                    }
                }
            }
            if ($result) {
                $configApplicable = $true
                break
            }
        }
        if ($configApplicable) {
            Write-Verbose "Machine-specific configuration '$($config.name)' applies to this machine"
            $applicableConfigs += $config
        }
    }

    # Sort by priority (higher priority first)
    $applicableConfigs = $applicableConfigs | Sort-Object { if ($_.priority) { $_.priority } else { 80 } } -Descending

    return $applicableConfigs
}

# Functions are available when dot-sourced, no need to export when not in module context






