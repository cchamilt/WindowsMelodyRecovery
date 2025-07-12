# Install-Module.ps1 - Install the WindowsMelodyRecovery module
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$CleanInstall
)

# Define module name
$moduleName = "WindowsMelodyRecovery"

# First, let's check if the module manifest has a valid GUID
$manifestPath = Join-Path (Get-Location) "$moduleName.psd1"
$manifestContent = Get-Content -Path $manifestPath -Raw -ErrorAction SilentlyContinue

if ($manifestContent -match "GUID\s*=\s*['`"]new-guid['`"]") {
    Write-Warning -Message "Fixing GUID in module manifest..."
    $newGuid = [System.Guid]::NewGuid().ToString()
    $manifestContent = $manifestContent -replace "GUID\s*=\s*['`"]new-guid['`"]", "GUID = '$newGuid'"
    Set-Content -Path $manifestPath -Value $manifestContent
    Write-Information -MessageData "Module GUID updated to $newGuid" -InformationAction Continue
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
        Write-Warning -Message "Detected non-Windows environment, using standard PowerShell module path..."
        $standardModulePath = if ($psVersion -ge 7) {
            "/usr/local/share/powershell/Modules"
        }
 else {
            "$HOME/.local/share/powershell/Modules"
        }
        $modulesPath = Join-Path $standardModulePath $moduleName
    }
 else {
        # Fallback for Windows when Documents path is not detected
        $documentsPath = Join-Path $userProfile "Documents"
        $modulesPath = Join-Path $documentsPath "$moduleRoot\Modules\$moduleName"
    }
}
 else {
    # Normal Windows path logic
    if ($documentsPath -notmatch "OneDrive" -and $userProfile -match "OneDrive") {
        # OneDrive is in use but not properly detected
        $documentsPath = Join-Path $userProfile "Documents"
    }
    $modulesPath = Join-Path $documentsPath "$moduleRoot\Modules\$moduleName"
}

# Handle clean install option
if ($CleanInstall -and (Test-Path $modulesPath)) {
    Write-Warning -Message "Clean install requested. Removing existing module..."
    try {
        # Try to remove the module from memory first
        if (Get-Module $moduleName -ErrorAction SilentlyContinue) {
            Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $modulesPath -Recurse -Force
        Write-Information -MessageData "Existing module removed successfully." -InformationAction Continue
    }
    catch {
        Write-Warning "Failed to completely remove existing module: $_"
        if (-not $Force) {
            Write-Warning -Message "Use -Force to continue anyway, or close all PowerShell sessions using the module."
            return
        }
    }
}

# Create module directory
if (!(Test-Path $modulesPath)) {
    New-Item -ItemType Directory -Path $modulesPath -Force | Out-Null
    Write-Information -MessageData "Created module directory: $modulesPath" -InformationAction Continue
}
 elseif ($Force -or $CleanInstall) {
    Write-Warning -Message "Module directory exists. Updating files..."
}
 else {
    Write-Warning -Message "Module directory exists: $modulesPath"
    Write-Information -MessageData "Use -Force to overwrite existing files or -CleanInstall for a fresh installation." -InformationAction Continue
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
        Write-Information -MessageData "Created directory: $targetDir" -InformationAction Continue
    }
}

# Copy module files
if ($Force -or $CleanInstall -or !(Test-Path $modulesPath)) {
    Write-Information -MessageData "Copying module manifest and main module file..." -InformationAction Continue
    Copy-Item -Path "$moduleName.psd1" -Destination $modulesPath -Force
    Copy-Item -Path "$moduleName.psm1" -Destination $modulesPath -Force
}
 else {
    Write-Warning -Message "Skipping module files (use -Force to overwrite)"
}

# Copy Public and Private directories
foreach ($dir in @("Public", "Private", "Templates", "docs")) {
    if (Test-Path ".\$dir") {
        if ($Force -or $CleanInstall -or !(Test-Path (Join-Path $modulesPath $dir))) {
            Write-Information -MessageData "Copying $dir directory..." -InformationAction Continue
            $sourceDir = Join-Path (Get-Location) $dir
            $targetDir = Join-Path $modulesPath $dir

            # Copy all files in the directory
            Get-ChildItem -Path $sourceDir -File | ForEach-Object {
                Write-Verbose -Message "  Copying $($_.Name)..."
                Copy-Item -Path $_.FullName -Destination $targetDir -Force
            }
        }
 else {
            Write-Warning -Message "Skipping $dir directory (use -Force to overwrite)"
            continue
        }

        # Copy subdirectories recursively
        Get-ChildItem -Path $sourceDir -Directory | ForEach-Object {
            $subDirName = $_.Name
            $targetSubDir = Join-Path $targetDir $subDirName

            Write-Verbose -Message "  Copying subdirectory $subDirName..."
            if (!(Test-Path $targetSubDir)) {
                New-Item -ItemType Directory -Path $targetSubDir -Force | Out-Null
            }

            # Use robocopy for better file overwriting
            if (Get-Command robocopy -ErrorAction SilentlyContinue) {
                & robocopy "$($_.FullName)" "$targetSubDir" /E /IS /IT /IM > $null
            }
 else {
                Copy-Item -Path "$($_.FullName)\*" -Destination $targetSubDir -Recurse -Force
            }
        }
    }
}

Write-Information -MessageData "$moduleName files copied to $modulesPath" -InformationAction Continue

# Verify the module manifest is valid
try {
    $testResult = Test-ModuleManifest -Path (Join-Path $modulesPath "$moduleName.psd1") -ErrorAction Stop
    Write-Information -MessageData "Module manifest is valid." -InformationAction Continue

    # Add the module path to PSModulePath if needed
    $modulesRoot = Split-Path $modulesPath
    $pathSeparator = if ($IsWindows) { ";" } else { ":" }
    if (!($Env:PSModulePath -split $pathSeparator -contains $modulesRoot)) {
        $Env:PSModulePath = "$modulesRoot$pathSeparator$Env:PSModulePath"
    }

    Write-Information -MessageData "$moduleName module installed successfully!" -InformationAction Continue
    Write-Warning -Message "`nNext steps:"
    Write-Information -MessageData "1. Run Initialize-WindowsMelodyRecovery to configure the module" -InformationAction Continue
    Write-Information -MessageData "2. Run Setup-WindowsMelodyRecovery to set up optional components" -InformationAction Continue
    Write-Information -MessageData "3. Use Backup-WindowsMelodyRecovery to create your first backup" -InformationAction Continue
    Write-Information -MessageData "`nInstall options for updates:" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue- Use '.\Install-Module.ps1 -Force' to overwrite existing files" -ForegroundColor White
    Write-Information -MessageData " -InformationAction Continue- Use '.\Install-Module.ps1 -CleanInstall' for a fresh installation" -ForegroundColor White
    Write-Information -MessageData "`nClean separation achieved:" -InformationAction Continue
    Write-Information -MessageData " -InformationAction Continue- Install: Only installs the module files" -ForegroundColor White
    Write-Information -MessageData " -InformationAction Continue- Initialize: Only handles configuration" -ForegroundColor White
    Write-Information -MessageData " -InformationAction Continue- Setup: Only handles optional component setup" -ForegroundColor White
    Write-Information -MessageData " -InformationAction Continue- Private scripts are loaded on-demand only when needed" -ForegroundColor White
}
catch {
    Write-Error -Message "Error: $_"
    Write-Warning -Message "Please check the module manifest for errors."
}







