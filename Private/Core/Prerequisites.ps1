# Private/Core/Prerequisites.ps1

# Requires Convert-WmrPath from PathUtilities.ps1
# Requires WindowsMelodyRecovery.Template.psm1 for template schema, although not directly called here.

function Test-WmrPrerequisite {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$TemplateConfig,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Backup", "Restore")]
        [string]$Operation
    )

    Write-Information -MessageData "Checking prerequisites for $($TemplateConfig.metadata.name) ($Operation operation)..." -InformationAction Continue

    $allPrerequisitesMet = $true

    if ($TemplateConfig.prerequisites) {
        foreach ($prereq in $TemplateConfig.prerequisites) {
            $prereqMet = $false
            $checkResult = ""

            Write-Host "  Checking prerequisite: $($prereq.name) (Type: $($prereq.type))..." -NoNewline

            switch ($prereq.type) {
                "application" {
                    try {
                        # Execute the check_command safely using script block
                        $scriptBlock = [scriptblock]::Create($prereq.check_command)
                        $commandOutput = & $scriptBlock | Out-String
                        $checkResult = "Output: `n$commandOutput`n"
                        if ($commandOutput -match $prereq.expected_output) {
                            $prereqMet = $true
                        }
                    }
                    catch {
                        $checkResult = "Error: $($_.Exception.Message)`n"
                    }
                }
                "registry" {
                    try {
                        $regPath = (Convert-WmrPath -Path $prereq.path).Path # Convert winreg URI to PowerShell path
                        if ($prereq.key_name) {
                            # Check a specific registry value
                            $regValue = (Get-ItemProperty -Path $regPath -Name $prereq.key_name -ErrorAction Stop).($prereq.key_name)
                            $checkResult = "Current Value: $regValue`n"
                            if ($regValue -eq $prereq.expected_value) {
                                $prereqMet = $true
                            }
                        }
                        else {
                            # Check if the registry key exists
                            if (Test-Path $regPath -ErrorAction Stop) {
                                $checkResult = "Key exists.`n"
                                $prereqMet = $true
                            }
                        }
                    }
                    catch {
                        $checkResult = "Error: $($_.Exception.Message)`n"
                    }
                }
                "script" {
                    try {
                        if ($prereq.path) {
                            # Execute script from path using call operator
                            $scriptOutput = & $prereq.path | Out-String
                        }
                        elseif ($prereq.inline_script) {
                            # Execute inline script using script block
                            $scriptBlock = [scriptblock]::Create($prereq.inline_script)
                            $scriptOutput = & $scriptBlock | Out-String
                        }
                        $checkResult = "Output: `n$scriptOutput`n"
                        if ($scriptOutput -match $prereq.expected_output) {
                            $prereqMet = $true
                        }
                    }
                    catch {
                        $checkResult = "Error: $($_.Exception.Message)`n"
                    }
                }
                default {
                    Write-Warning "  Unknown prerequisite type: $($prereq.type)"
                    $checkResult = "Unknown type.`n"
                }
            }

            if (-not $prereqMet) {
                Write-Host " FAILED." -ForegroundColor Red
                Write-Warning "    Prerequisite `'$($prereq.name)`' is missing or failed: $($prereq.check_command) $($prereq.path) $checkResult"

                switch ($prereq.on_missing) {
                    "warn" {
                        Write-Warning "    Warning: This prerequisite is set to `'$($prereq.on_missing)`' and will not stop the operation."
                        # Don't set allPrerequisitesMet to false for warnings
                    }
                    "fail_backup" {
                        if ($Operation -eq "Backup") {
                            $allPrerequisitesMet = $false
                            throw "    Error: Prerequisite `'$($prereq.name)`' failed. Cannot proceed with Backup operation as `'$($prereq.on_missing)`' is set."
                        }
                    }
                    "fail_restore" {
                        if ($Operation -eq "Restore") {
                            $allPrerequisitesMet = $false
                            throw "    Error: Prerequisite `'$($prereq.name)`' failed. Cannot proceed with Restore operation as `'$($prereq.on_missing)`' is set."
                        }
                    }
                    default {
                        # For any other on_missing value or if not specified, fail the prerequisites
                        $allPrerequisitesMet = $false
                    }
                }
            }
            else {
                Write-Host " PASSED." -ForegroundColor Green
            }
        }
    }

    if ($allPrerequisitesMet) {
        Write-Information -MessageData "All specified prerequisites passed for $($TemplateConfig.metadata.name) ($Operation operation)." -InformationAction Continue
    }
    else {
        Write-Information -MessageData "Some prerequisites failed for $($TemplateConfig.metadata.name) ($Operation operation). Check warnings/errors above." -InformationAction Continue
    }

    return $allPrerequisitesMet
}

# Function is available via dot-sourcing - no # Functions are available when dot-sourced
# Available function: Test-WmrPrerequisites








