# Module metadata
$ModuleName = "WindowsMissingRecovery"
$ModuleVersion = "1.0.0"

# Module configuration (in-memory state)
$script:Config = @{
    BackupRoot = $null
    MachineName = $env:COMPUTERNAME
    WindowsMissingRecoveryPath = Join-Path $PSScriptRoot "Config"
    CloudProvider = $null
    ModuleVersion = $ModuleVersion
    LastConfigured = $null
    IsInitialized = $false
    EmailSettings = @{
        FromAddress = $null
        ToAddress = $null
        Password = $null
        SmtpServer = $null
        SmtpPort = 587
        EnableSsl = $true
    }
    BackupSettings = @{
        RetentionDays = 30
        ExcludePaths = @()
        IncludePaths = @()
    }
    ScheduleSettings = @{
        BackupSchedule = $null
        UpdateSchedule = $null
    }
    NotificationSettings = @{
        EnableEmail = $false
        NotifyOnSuccess = $false
        NotifyOnFailure = $true
    }
    RecoverySettings = @{
        Mode = "Selective"
        ForceOverwrite = $false
    }
    LoggingSettings = @{
        Path = $null
        Level = "Information"
    }
    UpdateSettings = @{
        AutoUpdate = $true
        ExcludePackages = @()
    }
}

# Define core functions first
function Get-WindowsMissingRecovery {
    return $script:Config
}

function Set-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Config,
        
        [Parameter(Mandatory=$false)]
        [string]$BackupRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$MachineName,
        
        [Parameter(Mandatory=$false)]
        [string]$WindowsMissingRecoveryPath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('OneDrive', 'GoogleDrive', 'Dropbox', 'Box', 'Custom')]
        [string]$CloudProvider
    )
    
    if ($Config) {
        $script:Config = $Config
    } else {
        if ($BackupRoot) { $script:Config.BackupRoot = $BackupRoot }
        if ($MachineName) { $script:Config.MachineName = $MachineName }
        if ($WindowsMissingRecoveryPath) { $script:Config.WindowsMissingRecoveryPath = $WindowsMissingRecoveryPath }
        if ($CloudProvider) { $script:Config.CloudProvider = $CloudProvider }
    }
    
    $script:Config.LastConfigured = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Load core utilities first
$CorePath = Join-Path $PSScriptRoot "Private\Core\WindowsMissingRecovery.Core.ps1"
if (Test-Path $CorePath) {
    try {
        . $CorePath
        Write-Verbose "Successfully loaded core utilities from: $CorePath"
    } catch {
        Write-Warning "Failed to load core utilities from: $CorePath"
        Write-Warning $_.Exception.Message
    }
} else {
    Write-Warning "Core utilities not found at: $CorePath"
}

# Define public and private functions
$PublicPath = Join-Path $PSScriptRoot "Public"
$PrivatePath = Join-Path $PSScriptRoot "Private"

if (-not (Test-Path $PublicPath)) {
    Write-Warning "Public functions directory not found at: $PublicPath"
    $Public = @()
} else {
    $Public = @(Get-ChildItem -Path "$PublicPath\*.ps1" -ErrorAction SilentlyContinue)
}

if (-not (Test-Path $PrivatePath)) {
    Write-Warning "Private functions directory not found at: $PrivatePath"
    $Private = @()
} else {
    $Private = @(Get-ChildItem -Path "$PrivatePath\*.ps1" -ErrorAction SilentlyContinue -Recurse) | 
        Where-Object { $_.FullName -ne $CorePath }
}

# Load private functions first
foreach ($import in $Private) {
    try {
        . $import.FullName
        Write-Verbose "Successfully loaded private function: $($import.FullName)"
    } catch {
        Write-Warning "Failed to import private function $($import.FullName): $_"
    }
}

# Load public functions
foreach ($import in $Public) {
    try {
        . $import.FullName
        Write-Verbose "Successfully loaded public function: $($import.FullName)"
    } catch {
        Write-Warning "Failed to import public function $($import.FullName): $_"
    }
}

# Export public functions
if ($Public.Count -gt 0) {
    Export-ModuleMember -Function $Public.BaseName
} else {
    Write-Warning "No public functions found to export"
} 