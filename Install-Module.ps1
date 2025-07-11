# Install-Module.ps1 - Install the WindowsMelodyRecovery module
param(
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$CleanInstall
)

# Define module name
$moduleName = "WindowsMelodyRecovery"

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

# Handle Linux/container environments where GetFolderPath might not work
if ([string]::IsNullOrEmpty($documentsPath)) {
    if ($IsLinux -or $IsMacOS -or [string]::IsNullOrEmpty([Environment]::GetFolderPath("MyDocuments"))) {
        # In Linux/container environments, use PowerShell's standard module path
        Write-Host "Detected non-Windows environment, using standard PowerShell module path..." -ForegroundColor Yellow
        $standardModulePath = if ($psVersion -ge 7) {
            "/usr/local/share/powershell/Modules"
        } else {
            "$HOME/.local/share/powershell/Modules"
        }
        $modulesPath = Join-Path $standardModulePath $moduleName
    } else {
        # Fallback for Windows when Documents path is not detected
        $documentsPath = Join-Path $userProfile "Documents"
        $modulesPath = Join-Path $documentsPath "$moduleRoot\Modules\$moduleName"
    }
} else {
    # Normal Windows path logic
    if ($documentsPath -notmatch "OneDrive" -and $userProfile -match "OneDrive") {
        # OneDrive is in use but not properly detected
        $documentsPath = Join-Path $userProfile "Documents"
    }
    $modulesPath = Join-Path $documentsPath "$moduleRoot\Modules\$moduleName"
}

# Handle clean install option
if ($CleanInstall -and (Test-Path $modulesPath)) {
    Write-Host "Clean install requested. Removing existing module..." -ForegroundColor Yellow
    try {
        # Try to remove the module from memory first
        if (Get-Module $moduleName -ErrorAction SilentlyContinue) {
            Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $modulesPath -Recurse -Force
        Write-Host "Existing module removed successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to completely remove existing module: $_"
        if (-not $Force) {
            Write-Host "Use -Force to continue anyway, or close all PowerShell sessions using the module." -ForegroundColor Yellow
            return
        }
    }
}

# Create module directory
if (!(Test-Path $modulesPath)) {
    New-Item -ItemType Directory -Path $modulesPath -Force | Out-Null
    Write-Host "Created module directory: $modulesPath" -ForegroundColor Green
} elseif ($Force -or $CleanInstall) {
    Write-Host "Module directory exists. Updating files..." -ForegroundColor Yellow
} else {
    Write-Host "Module directory exists: $modulesPath" -ForegroundColor Yellow
    Write-Host "Use -Force to overwrite existing files or -CleanInstall for a fresh installation." -ForegroundColor Cyan
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
if ($Force -or $CleanInstall -or !(Test-Path $modulesPath)) {
    Write-Host "Copying module manifest and main module file..." -ForegroundColor Cyan
    Copy-Item -Path "$moduleName.psd1" -Destination $modulesPath -Force
    Copy-Item -Path "$moduleName.psm1" -Destination $modulesPath -Force
} else {
    Write-Host "Skipping module files (use -Force to overwrite)" -ForegroundColor Yellow
}

# Copy Public and Private directories
foreach ($dir in @("Public", "Private", "Templates", "docs")) {
    if (Test-Path ".\$dir") {
        if ($Force -or $CleanInstall -or !(Test-Path (Join-Path $modulesPath $dir))) {
            Write-Host "Copying $dir directory..." -ForegroundColor Cyan
            $sourceDir = Join-Path (Get-Location) $dir
            $targetDir = Join-Path $modulesPath $dir

            # Copy all files in the directory
            Get-ChildItem -Path $sourceDir -File | ForEach-Object {
                Write-Host "  Copying $($_.Name)..." -ForegroundColor Gray
                Copy-Item -Path $_.FullName -Destination $targetDir -Force
            }
        } else {
            Write-Host "Skipping $dir directory (use -Force to overwrite)" -ForegroundColor Yellow
            continue
        }

        # Copy subdirectories recursively
        Get-ChildItem -Path $sourceDir -Directory | ForEach-Object {
            $subDirName = $_.Name
            $targetSubDir = Join-Path $targetDir $subDirName

            Write-Host "  Copying subdirectory $subDirName..." -ForegroundColor Gray
            if (!(Test-Path $targetSubDir)) {
                New-Item -ItemType Directory -Path $targetSubDir -Force | Out-Null
            }

            # Use robocopy for better file overwriting
            if (Get-Command robocopy -ErrorAction SilentlyContinue) {
                & robocopy "$($_.FullName)" "$targetSubDir" /E /IS /IT /IM > $null
            } else {
                Copy-Item -Path "$($_.FullName)\*" -Destination $targetSubDir -Recurse -Force
            }
        }
    }
}

Write-Host "$moduleName files copied to $modulesPath" -ForegroundColor Green

# Verify the module manifest is valid
try {
    $testResult = Test-ModuleManifest -Path (Join-Path $modulesPath "$moduleName.psd1") -ErrorAction Stop
    Write-Host "Module manifest is valid." -ForegroundColor Green

    # Add the module path to PSModulePath if needed
    $modulesRoot = Split-Path $modulesPath
    $pathSeparator = if ($IsWindows) { ";" } else { ":" }
    if (!($Env:PSModulePath -split $pathSeparator -contains $modulesRoot)) {
        $Env:PSModulePath = "$modulesRoot$pathSeparator$Env:PSModulePath"
    }

    Write-Host "$moduleName module installed successfully!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Run Initialize-WindowsMelodyRecovery to configure the module" -ForegroundColor Cyan
    Write-Host "2. Run Setup-WindowsMelodyRecovery to set up optional components" -ForegroundColor Cyan
    Write-Host "3. Use Backup-WindowsMelodyRecovery to create your first backup" -ForegroundColor Cyan
    Write-Host "`nInstall options for updates:" -ForegroundColor Green
    Write-Host "- Use '.\Install-Module.ps1 -Force' to overwrite existing files" -ForegroundColor White
    Write-Host "- Use '.\Install-Module.ps1 -CleanInstall' for a fresh installation" -ForegroundColor White
    Write-Host "`nClean separation achieved:" -ForegroundColor Green
    Write-Host "- Install: Only installs the module files" -ForegroundColor White
    Write-Host "- Initialize: Only handles configuration" -ForegroundColor White
    Write-Host "- Setup: Only handles optional component setup" -ForegroundColor White
    Write-Host "- Private scripts are loaded on-demand only when needed" -ForegroundColor White
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Please check the module manifest for errors." -ForegroundColor Yellow
}