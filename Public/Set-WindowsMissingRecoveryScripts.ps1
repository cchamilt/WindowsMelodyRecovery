function Set-WindowsMissingRecoveryScripts {
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
            Write-Host "No scripts configuration found." -ForegroundColor Yellow
            return
        }
        
        Write-Host "`nWindows Missing Recovery Scripts Configuration:" -ForegroundColor Green
        Write-Host "=" * 60 -ForegroundColor Green
        
        foreach ($cat in @('backup', 'restore', 'setup')) {
            if ($config.$cat -and $config.$cat.enabled) {
                Write-Host "`n$($cat.ToUpper()) Scripts:" -ForegroundColor Cyan
                Write-Host ("-" * 40) -ForegroundColor Cyan
                
                foreach ($script in $config.$cat.enabled) {
                    $status = if ($script.enabled) { "✅ ENABLED" } else { "❌ DISABLED" }
                    $required = if ($script.required) { " (REQUIRED)" } else { "" }
                    Write-Host "  $($script.name)$required" -ForegroundColor White
                    Write-Host "    Status: $status" -ForegroundColor $(if ($script.enabled) { 'Green' } else { 'Red' })
                    Write-Host "    Function: $($script.function)" -ForegroundColor Gray
                    Write-Host "    Category: $($script.category)" -ForegroundColor Gray
                    if ($script.description) {
                        Write-Host "    Description: $($script.description)" -ForegroundColor Gray
                    }
                    Write-Host ""
                }
            }
        }
        return
    }
    
    # Interactive configuration
    if ($Interactive) {
        Write-Host "Interactive Script Configuration" -ForegroundColor Green
        Write-Host "================================" -ForegroundColor Green
        
        $config = Get-ScriptsConfig
        if (-not $config) {
            Write-Host "No scripts configuration found." -ForegroundColor Yellow
            return
        }
        
        foreach ($cat in @('backup', 'restore', 'setup')) {
            if ($config.$cat -and $config.$cat.enabled) {
                Write-Host "`nConfiguring $($cat.ToUpper()) Scripts:" -ForegroundColor Cyan
                
                foreach ($script in $config.$cat.enabled) {
                    if ($script.required) {
                        Write-Host "  $($script.name) - REQUIRED (cannot be disabled)" -ForegroundColor Yellow
                        continue
                    }
                    
                    $currentStatus = if ($script.enabled) { "enabled" } else { "disabled" }
                    $response = Read-Host "  $($script.name) is currently $currentStatus. Enable? (Y/N/Skip)"
                    
                    switch ($response.ToUpper()) {
                        'Y' { 
                            if (-not $script.enabled) {
                                Set-ScriptsConfig -Category $cat -ScriptName $script.name -Enabled $true
                                Write-Host "    ✅ Enabled $($script.name)" -ForegroundColor Green
                            }
                        }
                        'N' { 
                            if ($script.enabled) {
                                Set-ScriptsConfig -Category $cat -ScriptName $script.name -Enabled $false
                                Write-Host "    ❌ Disabled $($script.name)" -ForegroundColor Red
                            }
                        }
                        'SKIP' { 
                            Write-Host "    ⏭️ Skipped $($script.name)" -ForegroundColor Gray
                        }
                        default {
                            Write-Host "    ⏭️ Invalid response, skipping $($script.name)" -ForegroundColor Gray
                        }
                    }
                }
            }
        }
        
        Write-Host "`nScript configuration updated!" -ForegroundColor Green
        return
    }
    
    # Direct configuration
    if ($Category -and $ScriptName -and ($null -ne $Enabled)) {
        $result = Set-ScriptsConfig -Category $Category -ScriptName $ScriptName -Enabled $Enabled
        if ($result) {
            $status = if ($Enabled) { "enabled" } else { "disabled" }
            Write-Host "Successfully $status $ScriptName in $Category scripts." -ForegroundColor Green
        } else {
            Write-Host "Failed to update script configuration." -ForegroundColor Red
        }
        return
    }
    
    # Show usage if no valid parameters provided
    Write-Host "Usage Examples:" -ForegroundColor Yellow
    Write-Host "  Set-WindowsMissingRecoveryScripts -ListAll" -ForegroundColor Cyan
    Write-Host "  Set-WindowsMissingRecoveryScripts -Interactive" -ForegroundColor Cyan
    Write-Host "  Set-WindowsMissingRecoveryScripts -Category backup -ScriptName 'Terminal Settings' -Enabled `$true" -ForegroundColor Cyan
    Write-Host "  Set-WindowsMissingRecoveryScripts -Category restore -ScriptName 'Applications' -Enabled `$false" -ForegroundColor Cyan
} 