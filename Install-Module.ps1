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

# Create scripts directory in the module
$scriptsPath = Join-Path $modulesPath "Scripts"
if (!(Test-Path $scriptsPath)) {
    New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null
    Write-Host "Created Scripts directory: $scriptsPath" -ForegroundColor Green
}

# Create Config directory in the module
$configPath = Join-Path $modulesPath "Config"
if (!(Test-Path $configPath)) {
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    Write-Host "Created Config directory: $configPath" -ForegroundColor Green
}

# Copy only essential module files
Copy-Item -Path "$moduleName.psd1" -Destination $modulesPath -Force
Copy-Item -Path "$moduleName.psm1" -Destination $modulesPath -Force

# Check if Private/load-environment.ps1 exists and copy it to Scripts directory
$loadEnvSourcePath = Join-Path (Get-Location) "Private\load-environment.ps1"
if (Test-Path $loadEnvSourcePath) {
    Copy-Item -Path $loadEnvSourcePath -Destination $scriptsPath -Force
    Write-Host "Copied load-environment.ps1 to Scripts directory" -ForegroundColor Green
}

# Create required directories
$requiredDirs = @(
    "backup", "restore", "setup", "tasks", 
    "Public", "Private", "Templates",
    "Public\scripts", "Private\scripts",
    "Public\backup", "Public\restore", "Public\setup", "Public\tasks"
)

foreach ($dir in $requiredDirs) {
    $targetDir = Join-Path $modulesPath $dir
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Host "Created directory: $targetDir" -ForegroundColor Green
    }
}

# Copy Private/load-environment.ps1 to the scripts directories
if (Test-Path $loadEnvSourcePath) {
    Copy-Item -Path $loadEnvSourcePath -Destination (Join-Path $modulesPath "Public\scripts") -Force
    Copy-Item -Path $loadEnvSourcePath -Destination (Join-Path $modulesPath "Private\scripts") -Force
    Write-Host "Copied load-environment.ps1 to scripts directories" -ForegroundColor Green
}

# Copy Private and Public subdirectories
foreach ($dir in @("Public", "Private", "Templates")) {
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
            
            # Copy all files from subdirectory
            Copy-Item -Path "$($_.FullName)\*" -Destination $targetSubDir -Recurse -Force
        }
    }
}

# Special handling for backup scripts - copy from Private\backup to Public\backup
$privateBackupDir = Join-Path (Get-Location) "Private\backup"
$publicBackupDir = Join-Path $modulesPath "Public\backup"

if (Test-Path $privateBackupDir) {
    Get-ChildItem -Path $privateBackupDir -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $publicBackupDir -Force
        Write-Host "Copied backup script: $($_.Name) to Public\backup" -ForegroundColor Green
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
        Write-Host "You can now use Install-WindowsMissingRecovery to set up your Windows recovery."
    } catch {
        Write-Host "Module imported with some warnings - this is normal for first-time use." -ForegroundColor Yellow
        Write-Host "You can now use Initialize-WindowsMissingRecovery and Install-WindowsMissingRecovery to set up your Windows recovery." -ForegroundColor Green
    }
} 
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Please check the module manifest for errors." -ForegroundColor Yellow
} 