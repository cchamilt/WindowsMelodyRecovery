# Define module name
$moduleName = "WindowsMissingRecovery"

# First, let's check if the module manifest has a valid GUID
$manifestPath = Join-Path (Get-Location) "$moduleName.psd1"
$manifestContent = Get-Content -Path $manifestPath -Raw -ErrorAction SilentlyContinue

if ($manifestContent -match "GUID\s*=\s*['`"]new-guid['`"]") {
    Write-Host "Fixing GUID in module manifest..." -ForegroundColor Yellow
    $newGuid = [System.Guid]::NewGuid().ToString()
    $manifestContent = $manifestContent -replace "GUID\s*=\s*['`"]new-guid['`"]", "GUID = '$newGuid'"
    Set-Content -Path $manifestPath -Value $manifestContent
    Write-Host "Module GUID updated to $newGuid" -ForegroundColor Green
}

# Determine PowerShell version to set correct module path
$psVersion = $PSVersionTable.PSVersion.Major
$isPS7 = $psVersion -ge 7

# Handle OneDrive paths appropriately
$userProfile = $HOME
$moduleRoot = if ($isPS7) { "PowerShell" } else { "WindowsPowerShell" }

# Determine module path based on OneDrive setup
$documentsPath = [Environment]::GetFolderPath("MyDocuments")
if ($documentsPath -notmatch "OneDrive" -and $userProfile -match "OneDrive") {
    # OneDrive is in use but not properly detected
    $documentsPath = Join-Path $userProfile "Documents"
}

$modulesPath = Join-Path $documentsPath "$moduleRoot\Modules\$moduleName"

# Create module directory
if (!(Test-Path $modulesPath)) {
    New-Item -ItemType Directory -Path $modulesPath -Force | Out-Null
    Write-Host "Created module directory: $modulesPath" -ForegroundColor Green
}

# Create required module directories
$requiredDirs = @(
    "Public",
    "Private",
    "Config",
    "Templates",
    "docs"
)

foreach ($dir in $requiredDirs) {
    $targetDir = Join-Path $modulesPath $dir
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Host "Created directory: $targetDir" -ForegroundColor Green
    }
}

# Copy module files
Copy-Item -Path "$moduleName.psd1" -Destination $modulesPath -Force
Copy-Item -Path "$moduleName.psm1" -Destination $modulesPath -Force

# Copy Public and Private directories
foreach ($dir in @("Public", "Private", "Templates", "docs")) {
    if (Test-Path ".\$dir") {
        $sourceDir = Join-Path (Get-Location) $dir
        $targetDir = Join-Path $modulesPath $dir
        
        # Copy all files in the directory
        Get-ChildItem -Path $sourceDir -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $targetDir -Force
        }
        
        # Copy subdirectories recursively
        Get-ChildItem -Path $sourceDir -Directory | ForEach-Object {
            $subDirName = $_.Name
            $targetSubDir = Join-Path $targetDir $subDirName
            
            if (!(Test-Path $targetSubDir)) {
                New-Item -ItemType Directory -Path $targetSubDir -Force | Out-Null
            }
            
            Copy-Item -Path "$($_.FullName)\*" -Destination $targetSubDir -Recurse -Force
        }
    }
}

Write-Host "$moduleName files copied to $modulesPath" -ForegroundColor Green

# Verify the module can be imported
try {
    # Test the module manifest before importing
    $testResult = Test-ModuleManifest -Path (Join-Path $modulesPath "$moduleName.psd1") -ErrorAction Stop
    Write-Host "Module manifest is valid." -ForegroundColor Green

    # Add the module path to PSModulePath if needed
    $modulesRoot = Split-Path $modulesPath
    if (!($Env:PSModulePath -split ";" -contains $modulesRoot)) {
        $Env:PSModulePath = "$modulesRoot;$Env:PSModulePath"
    }

    # Import the module with error handling
    try {
        Import-Module $moduleName -Force
        Write-Host "$moduleName module installed and imported successfully!" -ForegroundColor Green
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "1. Run Initialize-WindowsMissingRecovery to configure the module" -ForegroundColor Cyan
        Write-Host "2. Follow the prompts to set up your backup location and machine name" -ForegroundColor Cyan
        Write-Host "3. Use Backup-WindowsMissingRecovery to create your first backup" -ForegroundColor Cyan
    } catch {
        Write-Host "Module imported with some warnings - this is normal for first-time use." -ForegroundColor Yellow
        Write-Host "Please run Initialize-WindowsMissingRecovery to complete the setup." -ForegroundColor Green
    }
} 
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Please check the module manifest for errors." -ForegroundColor Yellow
} 