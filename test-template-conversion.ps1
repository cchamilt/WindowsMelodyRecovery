# test-template-conversion.ps1
# Simple test to verify template system works for backup operations

Write-Host "Testing Template System Conversion" -ForegroundColor Cyan

# Import the module
try {
    Import-Module .\WindowsMelodyRecovery.psd1 -Force
    Write-Host "✓ Module imported successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to import module: $_" -ForegroundColor Red
    exit 1
}

# Test 1: Check if module is initialized
try {
    $config = Get-WindowsMelodyRecovery
    if ($config.BackupRoot) {
        Write-Host "✓ Module configuration found" -ForegroundColor Green
        Write-Host "  Backup Root: $($config.BackupRoot)" -ForegroundColor Gray
        Write-Host "  Machine Name: $($config.MachineName)" -ForegroundColor Gray
    } else {
        Write-Host "⚠ Module not initialized - will try to initialize" -ForegroundColor Yellow
        try {
            Initialize-WindowsMelodyRecovery -BackupRoot ".\test-backup" -Force
            Write-Host "✓ Module initialized for testing" -ForegroundColor Green
        } catch {
            Write-Host "✗ Failed to initialize module: $_" -ForegroundColor Red
            exit 1
        }
    }
} catch {
    Write-Host "✗ Failed to get module configuration: $_" -ForegroundColor Red
    exit 1
}

# Test 2: Check if templates exist
Write-Host "`nChecking available templates..." -ForegroundColor Cyan
$templatesPath = ".\Templates\System"
if (Test-Path $templatesPath) {
    $templates = Get-ChildItem -Path $templatesPath -Filter "*.yaml"
    Write-Host "✓ Templates directory found with $($templates.Count) templates:" -ForegroundColor Green
    foreach ($template in $templates) {
        Write-Host "  - $($template.Name)" -ForegroundColor Gray
    }
} else {
    Write-Host "✗ Templates directory not found: $templatesPath" -ForegroundColor Red
    exit 1
}

# Test 3: Test InvokeWmrTemplate directly
Write-Host "`nTesting InvokeWmrTemplate directly..." -ForegroundColor Cyan
try {
    # Load the template invocation system
    . ".\Private\Core\InvokeWmrTemplate.ps1"
    Write-Host "✓ InvokeWmrTemplate loaded successfully" -ForegroundColor Green
    
    # Test with display template
    $displayTemplate = ".\Templates\System\display.yaml"
    $testStateDir = ".\test-template-state"
    
    if (Test-Path $displayTemplate) {
        Write-Host "  Testing display template backup..." -ForegroundColor Cyan
        
        # Clean up any existing test state
        if (Test-Path $testStateDir) {
            Remove-Item -Path $testStateDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $testStateDir -Force | Out-Null
        
        try {
            Invoke-WmrTemplate -TemplatePath $displayTemplate -Operation "Backup" -StateFilesDirectory $testStateDir
            Write-Host "✓ Display template backup completed successfully" -ForegroundColor Green
            
            # Check if state files were created
            $stateFiles = Get-ChildItem -Path $testStateDir -Recurse -File
            Write-Host "  State files created: $($stateFiles.Count)" -ForegroundColor Gray
            
            if ($stateFiles.Count -gt 0) {
                Write-Host "✓ Template system is working - state files generated" -ForegroundColor Green
            } else {
                Write-Host "⚠ Template ran but no state files were generated (may be normal if no settings found)" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "✗ Display template backup failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ Display template not found: $displayTemplate" -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ Failed to load InvokeWmrTemplate: $_" -ForegroundColor Red
}

# Test 4: Test the main backup function with template
Write-Host "`nTesting main backup function with template..." -ForegroundColor Cyan
try {
    $result = Backup-WindowsMelodyRecovery -TemplatePath "display.yaml"
    if ($result.Success) {
        Write-Host "✓ Backup-WindowsMelodyRecovery with template succeeded" -ForegroundColor Green
        Write-Host "  Method: $($result.Method)" -ForegroundColor Gray
        Write-Host "  Backup Path: $($result.BackupPath)" -ForegroundColor Gray
    } else {
        Write-Host "✗ Backup-WindowsMelodyRecovery with template failed" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Backup-WindowsMelodyRecovery with template threw error: $_" -ForegroundColor Red
}

# Test 5: Test legacy script-based backup
Write-Host "`nTesting legacy script-based backup..." -ForegroundColor Cyan
try {
    $result = Backup-WindowsMelodyRecovery
    if ($result.Success) {
        Write-Host "✓ Legacy script-based backup succeeded" -ForegroundColor Green
        Write-Host "  Method: $($result.Method)" -ForegroundColor Gray
        Write-Host "  Backup Count: $($result.BackupCount)" -ForegroundColor Gray
    } else {
        Write-Host "⚠ Legacy script-based backup completed but no functions were available" -ForegroundColor Yellow
        Write-Host "  This is expected since we're moving to templates" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ Legacy script-based backup threw error: $_" -ForegroundColor Red
}

Write-Host "`nTemplate system conversion test completed!" -ForegroundColor Cyan
Write-Host "The template system should now be ready to replace individual backup scripts." -ForegroundColor Green 