function Set-WindowsMelodyRecoveryScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('backup', 'restore', 'setup')]
        [string]$Category,

        [Parameter(Mandatory=$false)]
        [string]$ScriptName,

        [Parameter(Mandatory=$false)]
        [bool]$Enabled,

        [Parameter(Mandatory=$false)]
        [switch]$ListAll,

        [Parameter(Mandatory=$false)]
        [switch]$Interactive
    )

    # List all available scripts if requested
    if ($ListAll) {
        $config = Get-ScriptsConfig
        if (-not $config) {
            Write-Warning -Message "No scripts configuration found."
            return
        }

        Write-Information -MessageData "`nWindows Melody Recovery Scripts Configuration:" -InformationAction Continue
        Write-Information -MessageData "=" -InformationAction Continue * 60 -ForegroundColor Green

        foreach ($cat in @('backup', 'restore', 'setup')) {
            if ($config.$cat -and $config.$cat.enabled) {
                Write-Information -MessageData "`n$($cat.ToUpper()) Scripts:" -InformationAction Continue
                Write-Information -MessageData (" -InformationAction Continue-" * 40) -ForegroundColor Cyan

                foreach ($script in $config.$cat.enabled) {
                    $status = if ($script.enabled) { "✅ ENABLED" } else { "❌ DISABLED" }
                    $required = if ($script.required) { " (REQUIRED)" } else { "" }
                    Write-Information -MessageData "  $($script.name)$required"  -InformationAction Continue-ForegroundColor White
                    Write-Information -MessageData "    Status: $status"  -InformationAction Continue-ForegroundColor $(if ($script.enabled) { 'Green' } else { 'Red' })
                    Write-Verbose -Message "    Function: $($script.function)"
                    Write-Verbose -Message "    Category: $($script.category)"
                    if ($script.description) {
                        Write-Verbose -Message "    Description: $($script.description)"
                    }
                    Write-Information -MessageData "" -InformationAction Continue
                }
            }
        }
        return
    }

    # Interactive configuration
    if ($Interactive) {
        Write-Information -MessageData "Interactive Script Configuration" -InformationAction Continue
        Write-Information -MessageData "================================" -InformationAction Continue

        $config = Get-ScriptsConfig
        if (-not $config) {
            Write-Warning -Message "No scripts configuration found."
            return
        }

        foreach ($cat in @('backup', 'restore', 'setup')) {
            if ($config.$cat -and $config.$cat.enabled) {
                Write-Information -MessageData "`nConfiguring $($cat.ToUpper()) Scripts:" -InformationAction Continue

                foreach ($script in $config.$cat.enabled) {
                    if ($script.required) {
                        Write-Warning -Message "  $($script.name) - REQUIRED (cannot be disabled)"
                        continue
                    }

                    $currentStatus = if ($script.enabled) { "enabled" } else { "disabled" }
                    $response = Read-Host "  $($script.name) is currently $currentStatus. Enable? (Y/N/Skip)"

                    switch ($response.ToUpper()) {
                        'Y' {
                            if (-not $script.enabled) {
                                Set-ScriptsConfig -Category $cat -ScriptName $script.name -Enabled $true
                                Write-Information -MessageData "    ✅ Enabled $($script.name)" -InformationAction Continue
                            }
                        }
                        'N' {
                            if ($script.enabled) {
                                Set-ScriptsConfig -Category $cat -ScriptName $script.name -Enabled $false
                                Write-Error -Message "    ❌ Disabled $($script.name)"
                            }
                        }
                        'SKIP' {
                            Write-Verbose -Message "    ⏭️ Skipped $($script.name)"
                        }
                        default {
                            Write-Verbose -Message "    ⏭️ Invalid response, skipping $($script.name)"
                        }
                    }
                }
            }
        }

        Write-Information -MessageData "`nScript configuration updated!" -InformationAction Continue
        return
    }

    # Direct configuration
    if ($Category -and $ScriptName -and ($null -ne $Enabled)) {
        $result = Set-ScriptsConfig -Category $Category -ScriptName $ScriptName -Enabled $Enabled
        if ($result) {
            $status = if ($Enabled) { "enabled" } else { "disabled" }
            Write-Information -MessageData "Successfully $status $ScriptName in $Category scripts." -InformationAction Continue
        } else {
            Write-Error -Message "Failed to update script configuration."
        }
        return
    }

    # Show usage if no valid parameters provided
    Write-Warning -Message "Usage Examples:"
    Write-Information -MessageData "  Set-WindowsMelodyRecoveryScripts -ListAll" -InformationAction Continue
    Write-Information -MessageData "  Set-WindowsMelodyRecoveryScripts -Interactive" -InformationAction Continue
    Write-Information -MessageData "  Set-WindowsMelodyRecoveryScripts -Category backup -ScriptName 'Terminal Settings' -Enabled `$true" -InformationAction Continue
    Write-Information -MessageData "  Set-WindowsMelodyRecoveryScripts -Category restore -ScriptName 'Applications' -Enabled `$false" -InformationAction Continue
}







