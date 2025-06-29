#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simulates the WindowsMelodyRecovery module installation in Docker test environment

.DESCRIPTION
    This script simulates the actual installation process that users would experience
    in production, making the Docker test environment more realistic.
#>

param(
    [switch]$Force,
    [switch]$CleanInstall,
    [switch]$Verbose
)

Write-Host "🔧 Simulating WindowsMelodyRecovery module installation..." -ForegroundColor Cyan

# Define module name
$moduleName = "WindowsMelodyRecovery"

# Use the correct PowerShell 7+ user module path on Linux
$userModulePath = "/root/.local/share/powershell/Modules/$moduleName"
$modulesRoot = "/root/.local/share/powershell/Modules"

# Create the directory structure
$requiredDirs = @(
    $userModulePath,
    (Join-Path $userModulePath "Public"),
    (Join-Path $userModulePath "Private"),
    (Join-Path $userModulePath "Config"),
    (Join-Path $userModulePath "Templates"),
    (Join-Path $userModulePath "docs")
)

foreach ($dir in $requiredDirs) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ($Verbose) {
            Write-Host "Created directory: $dir" -ForegroundColor Green
        }
    }
}

# Handle clean install option
if ($CleanInstall -and (Test-Path $userModulePath)) {
    Write-Host "Clean install requested. Removing existing module..." -ForegroundColor Yellow
    try {
        # Try to remove the module from memory first
        if (Get-Module $moduleName -ErrorAction SilentlyContinue) {
            Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $userModulePath -Recurse -Force
        Write-Host "Existing module removed successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to completely remove existing module: $_"
        if (-not $Force) {
            Write-Host "Use -Force to continue anyway." -ForegroundColor Yellow
            return
        }
    }
}

# Copy module files from workspace to the simulated installation location
Write-Host "Copying module files to simulated installation location..." -ForegroundColor Cyan

# Copy main module files
if (Test-Path "/workspace/$moduleName.psd1") {
    Copy-Item -Path "/workspace/$moduleName.psd1" -Destination $userModulePath -Force
    if ($Verbose) { Write-Host "  Copied $moduleName.psd1" -ForegroundColor Gray }
}

if (Test-Path "/workspace/$moduleName.psm1") {
    Copy-Item -Path "/workspace/$moduleName.psm1" -Destination $userModulePath -Force
    if ($Verbose) { Write-Host "  Copied $moduleName.psm1" -ForegroundColor Gray }
}

# Copy Public directory
if (Test-Path "/workspace/Public") {
    $targetPublic = Join-Path $userModulePath "Public"
    Get-ChildItem -Path "/workspace/Public" -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $targetPublic -Force
        if ($Verbose) { Write-Host "  Copied Public/$($_.Name)" -ForegroundColor Gray }
    }
}

# Copy Private directory
if (Test-Path "/workspace/Private") {
    $targetPrivate = Join-Path $userModulePath "Private"
    Get-ChildItem -Path "/workspace/Private" -Recurse | ForEach-Object {
        if ($_.PSIsContainer) {
            $targetDir = Join-Path $targetPrivate $_.FullName.Replace("/workspace/Private", "")
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
        } else {
            $relativePath = $_.FullName.Replace("/workspace/Private", "")
            $targetFile = Join-Path $targetPrivate $relativePath
            $targetDir = Split-Path $targetFile -Parent
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $targetFile -Force
            if ($Verbose) { Write-Host "  Copied Private/$relativePath" -ForegroundColor Gray }
        }
    }
}

# Copy Templates directory
if (Test-Path "/workspace/Templates") {
    $targetTemplates = Join-Path $userModulePath "Templates"
    Get-ChildItem -Path "/workspace/Templates" -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $targetTemplates -Force
        if ($Verbose) { Write-Host "  Copied Templates/$($_.Name)" -ForegroundColor Gray }
    }
}

# Copy docs directory
if (Test-Path "/workspace/docs") {
    $targetDocs = Join-Path $userModulePath "docs"
    Get-ChildItem -Path "/workspace/docs" -Recurse | ForEach-Object {
        if ($_.PSIsContainer) {
            $targetDir = Join-Path $targetDocs $_.FullName.Replace("/workspace/docs", "")
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
        } else {
            $relativePath = $_.FullName.Replace("/workspace/docs", "")
            $targetFile = Join-Path $targetDocs $relativePath
            $targetDir = Split-Path $targetFile -Parent
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $targetFile -Force
            if ($Verbose) { Write-Host "  Copied docs/$relativePath" -ForegroundColor Gray }
        }
    }
}

# Add the module path to PSModulePath if not already present
if (!($Env:PSModulePath -split ":" -contains $modulesRoot)) {
    $Env:PSModulePath = "$modulesRoot" + ":" + "$Env:PSModulePath"
    if ($Verbose) { Write-Host "Added $modulesRoot to PSModulePath" -ForegroundColor Gray }
}

# Verify the module manifest is valid
try {
    $testResult = Test-ModuleManifest -Path (Join-Path $userModulePath "$moduleName.psd1") -ErrorAction Stop
    Write-Host "✓ Module manifest is valid" -ForegroundColor Green
} catch {
    Write-Host "✗ Error validating module manifest: $_" -ForegroundColor Red
    return
}

# Test module import
try {
    Import-Module $moduleName -Force -ErrorAction Stop
    Write-Host "✓ Module imported successfully" -ForegroundColor Green
    
    # List exported functions
    $exportedFunctions = Get-Command -Module $moduleName -ErrorAction SilentlyContinue
    Write-Host "✓ Exported $($exportedFunctions.Count) functions" -ForegroundColor Green
    
    if ($Verbose) {
        Write-Host "Exported functions:" -ForegroundColor Gray
        $exportedFunctions | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    }
    
} catch {
    Write-Host "✗ Error importing module: $_" -ForegroundColor Red
    return
}

Write-Host "✅ Module installation simulation completed successfully!" -ForegroundColor Green
Write-Host "Module installed to: $userModulePath" -ForegroundColor Cyan
Write-Host "PSModulePath updated to include: $modulesRoot" -ForegroundColor Cyan

return @{
    Success = $true
    ModulePath = $userModulePath
    ExportedFunctions = $exportedFunctions.Count
}
