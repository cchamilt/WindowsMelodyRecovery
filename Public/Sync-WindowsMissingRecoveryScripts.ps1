function Sync-WindowsMissingRecoveryScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [switch]$NoPrompt
    )

    Write-Host "Syncing Scripts Configuration with Available Scripts..." -ForegroundColor Green
    
    # Get current module root - handle cases where PSScriptRoot might be empty
    $moduleRoot = $null
    
    # First, try to get the module path directly
    $moduleInfo = Get-Module WindowsMissingRecovery -ErrorAction SilentlyContinue
    if ($moduleInfo) {
        $moduleRoot = Split-Path $moduleInfo.Path -Parent
    } elseif ($PSScriptRoot) {
        $moduleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    } else {
        # Last resort: use current directory or workspace
        $moduleRoot = if (Test-Path "/workspace") { "/workspace" } else { Get-Location }
    }
    
    # Additional fallback for test environments
    if (-not $moduleRoot -or -not (Test-Path $moduleRoot)) {
        # Try to find the module by looking for the .psm1 file
        $possiblePaths = @(
            "/workspace",
            (Get-Location),
            (Split-Path (Get-Command WindowsMissingRecovery -ErrorAction SilentlyContinue).Source -Parent -ErrorAction SilentlyContinue),
            (Split-Path $PSCommandPath -Parent -ErrorAction SilentlyContinue),
            "/root/.local/share/powershell/Modules/WindowsMissingRecovery"
        )
        
        foreach ($path in $possiblePaths) {
            if ($path -and (Test-Path (Join-Path $path "WindowsMissingRecovery.psm1"))) {
                $moduleRoot = $path
                break
            }
        }
    }
    
    # Validate module root
    if (-not $moduleRoot -or -not (Test-Path $moduleRoot)) {
        Write-Error "Could not determine module root path. Tried: $moduleRoot"
        return
    }
    
    $configPath = Join-Path $moduleRoot "Config\scripts-config.json"
    $templatePath = Join-Path $moduleRoot "Templates\scripts-config.json"
    
    # Load current configuration or template
    $currentConfig = $null
    if (Test-Path $configPath) {
        $currentConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        Write-Host "Found existing user configuration" -ForegroundColor Green
    } elseif (Test-Path $templatePath) {
        $currentConfig = Get-Content $templatePath -Raw | ConvertFrom-Json
        Write-Host "Using template configuration as base" -ForegroundColor Yellow
    } else {
        Write-Error "No configuration template found"
        return
    }
    
    # Scan for actual script files
    $categories = @('backup', 'restore', 'setup')
    $discoveredScripts = @{}
    
    foreach ($category in $categories) {
        $categoryPath = Join-Path $moduleRoot "Private\$category"
        $discoveredScripts[$category] = @()
        
        if (Test-Path $categoryPath) {
            $scripts = Get-ChildItem -Path $categoryPath -Filter "*.ps1" | Where-Object { $_.Name -ne 'template.ps1' }
            
            foreach ($script in $scripts) {
                # Try to extract function name from script content
                $content = Get-Content $script.FullName -Raw
                $functionMatch = [regex]::Match($content, 'function\s+([A-Za-z-]+)\s*{')
                
                if ($functionMatch.Success) {
                    $functionName = $functionMatch.Groups[1].Value
                    $scriptName = $functionName -replace "^(Backup|Restore|Setup)-", "" -replace "Settings$", " Settings"
                    
                    # Try to find existing configuration for this script
                    $existingScript = $currentConfig.$category.enabled | Where-Object { 
                        $_.function -eq $functionName -or $_.script -eq $script.Name 
                    }
                    
                    $discoveredScript = @{
                        name = if ($existingScript) { $existingScript.name } else { $scriptName }
                        function = $functionName
                        script = $script.Name
                        category = if ($existingScript) { $existingScript.category } else { "System" }
                        description = if ($existingScript) { $existingScript.description } else { "Auto-discovered script" }
                        enabled = if ($existingScript) { $existingScript.enabled } else { $true }
                        required = if ($existingScript) { $existingScript.required } else { $false }
                    }
                    
                    $discoveredScripts[$category] += $discoveredScript
                    
                    if ($WhatIf) {
                        $status = if ($existingScript) { "EXISTS" } else { "NEW" }
                        Write-Host "  [$status] $category`: $($discoveredScript.name) -> $functionName" -ForegroundColor $(if ($existingScript) { 'Green' } else { 'Cyan' })
                    }
                } else {
                    Write-Warning "Could not determine function name for script: $($script.Name)"
                }
            }
        }
    }
    
    if ($WhatIf) {
        Write-Host "`nSummary:" -ForegroundColor Yellow
        foreach ($category in $categories) {
            $existing = @($currentConfig.$category.enabled).Count
            $discovered = @($discoveredScripts[$category]).Count
            Write-Host "  $category`: $existing existing, $discovered discovered" -ForegroundColor Gray
        }
        Write-Host "`nUse -Force to apply changes" -ForegroundColor Cyan
        return
    }
    
    if (-not $Force -and -not $NoPrompt) {
        Write-Host "`nChanges to be made:" -ForegroundColor Yellow
        foreach ($category in $categories) {
            $existing = @($currentConfig.$category.enabled).Count
            $discovered = @($discoveredScripts[$category]).Count
            Write-Host "  $category`: $existing -> $discovered scripts" -ForegroundColor Gray
        }
        
        $response = Read-Host "Apply these changes? (Y/N)"
        if ($response -ne 'Y') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    # Update the configuration with discovered scripts
    foreach ($category in $categories) {
        $currentConfig.$category.enabled = $discoveredScripts[$category]
    }
    
    # Save the updated configuration
    $configDir = Split-Path $configPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force
    
    Write-Host "`nScripts configuration successfully synced!" -ForegroundColor Green
    Write-Host "Configuration saved to: $configPath" -ForegroundColor Cyan
    
    # Show summary
    foreach ($category in $categories) {
        $count = @($discoveredScripts[$category]).Count
        Write-Host "  $category`: $count scripts configured" -ForegroundColor Gray
    }
} 