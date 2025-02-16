# Load all function definitions
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)

# Module configuration path
$script:ConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'WindowsConfig'
$script:ConfigFile = Join-Path $script:ConfigPath 'config.json'

# Initialize module configuration
function Initialize-ModuleConfig {
    if (!(Test-Path $script:ConfigPath)) {
        New-Item -ItemType Directory -Path $script:ConfigPath -Force | Out-Null
    }

    if (Test-Path $script:ConfigFile) {
        $script:Config = Get-Content $script:ConfigFile | ConvertFrom-Json
    } else {
        $script:Config = @{
            BackupRoot = $null
            MachineName = $env:COMPUTERNAME
            BackupSubDir = $null
            LastBackup = $null
            EmailSettings = @{
                FromAddress = $null
                ToAddress = $null
                Password = $null
                SMTPServer = $null
                SMTPPort = $null
                SMTPUser = $null
                SMTPSSL = $null
            }
            GitSettings = @{
                UserName = $null
                UserEmail = $null
                DefaultBranch = $null
                GitPath = $null
            }
            SSHEncryptionPassword = $null
        }
    }
}

# Save module configuration
function Save-ModuleConfig {
    $script:Config | ConvertTo-Json | Set-Content $script:ConfigFile
}

# Export configuration functions
function Get-WindowsConfig {
    return $script:Config
}

function Set-WindowsConfig {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupRoot,
        [string]$FromAddress,
        [string]$ToAddress,
        [SecureString]$EmailPassword
    )
    
    $script:Config.BackupRoot = $BackupRoot
    if ($FromAddress) { $script:Config.EmailSettings.FromAddress = $FromAddress }
    if ($ToAddress) { $script:Config.EmailSettings.ToAddress = $ToAddress }
    if ($EmailPassword) {
        $script:Config.EmailSettings.Password = ConvertFrom-SecureString $EmailPassword
    }
    
    Save-ModuleConfig
}

# Dot source the files
foreach ($import in @($Public + $Private)) {
    try {
        . $import.FullName
    } catch {
        Write-Error "Failed to import function $($import.FullName): $_"
    }
}

# Initialize module configuration
Initialize-ModuleConfig

# Export public functions
Export-ModuleMember -Function ($Public.BaseName + @('Get-WindowsConfig','Set-WindowsConfig')) 