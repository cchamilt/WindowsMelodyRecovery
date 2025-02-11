# Update Installed Apps/Tools/etc.

# Collect any errors during update
$updateErrors = @()

# Create a temporary file for capturing console output
$tempLogFile = [System.IO.Path]::GetTempFileName()

try {
    # Start transcript to capture all console output
    Start-Transcript -Path $tempLogFile -Append

    Write-Host "Starting system updates..." -ForegroundColor Blue

    # Update Windows Store apps
    Write-Host "`nChecking for Windows Store app updates..." -ForegroundColor Yellow
    try {
        Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | 
            Invoke-CimMethod -MethodName UpdateScanMethod
        Write-Host "Windows Store apps check completed" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to check Windows Store apps: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update Winget packages
    Write-Host "`nUpdating Winget packages..." -ForegroundColor Yellow
    try {
        winget upgrade --all --accept-source-agreements --accept-package-agreements --include-unknown
        Write-Host "Winget packages updated successfully" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update Winget packages: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update Chocolatey packages if installed
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "`nUpdating Chocolatey packages..." -ForegroundColor Yellow
        try {
            choco upgrade all -y
            Write-Host "Chocolatey packages updated successfully" -ForegroundColor Green
        } catch {
            $errorMessage = "Failed to update Chocolatey packages: $_"
            Write-Host $errorMessage -ForegroundColor Red
            $updateErrors += $errorMessage
        }
    }

    # Update PowerShell modules
    Write-Host "`nUpdating PowerShell modules..." -ForegroundColor Yellow
    try {
        # Update PowerShellGet itself first if needed
        $psgModule = Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        $psgLatest = Find-Module PowerShellGet
        if ($psgModule.Version -lt $psgLatest.Version) {
            Write-Host "Updating PowerShellGet..." -ForegroundColor Yellow
            Install-Module PowerShellGet -Force -AllowClobber
            Write-Host "PowerShellGet updated. Please restart PowerShell to use the new version." -ForegroundColor Green
        }

        # Update all installed modules
        $modules = Get-InstalledModule
        foreach ($module in $modules) {
            try {
                $latest = Find-Module -Name $module.Name
                if ($latest.Version -gt $module.Version) {
                    Write-Host "Updating $($module.Name) from $($module.Version) to $($latest.Version)..." -ForegroundColor Yellow
                    Update-Module -Name $module.Name -Force
                    # Clean up older versions
                    Get-InstalledModule -Name $module.Name -AllVersions | 
                        Where-Object Version -lt $latest.Version | 
                        Uninstall-Module -Force
                }
            } catch {
                $errorMessage = "Failed to update module $($module.Name): $_"
                Write-Host $errorMessage -ForegroundColor Red
                $updateErrors += $errorMessage
            }
        }
        Write-Host "PowerShell modules updated successfully" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update PowerShell modules: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    # Update NuGet packages
    Write-Host "`nUpdating NuGet packages..." -ForegroundColor Yellow
    try {
        # Update NuGet provider if needed
        $nugetProvider = Get-PackageProvider -Name NuGet
        $nugetLatest = Find-PackageProvider -Name NuGet
        if ($nugetProvider.Version -lt $nugetLatest.Version) {
            Write-Host "Updating NuGet provider..." -ForegroundColor Yellow
            Install-PackageProvider -Name NuGet -Force
        }

        # Update all installed NuGet packages
        $packages = Get-Package -ProviderName NuGet
        foreach ($package in $packages) {
            try {
                $latest = Find-Package -Name $package.Name -ProviderName NuGet
                if ($latest.Version -gt $package.Version) {
                    Write-Host "Updating $($package.Name) from $($package.Version) to $($latest.Version)..." -ForegroundColor Yellow
                    Install-Package -Name $package.Name -ProviderName NuGet -Force
                }
            } catch {
                $errorMessage = "Failed to update package $($package.Name): $_"
                Write-Host $errorMessage -ForegroundColor Red
                $updateErrors += $errorMessage
            }
        }
        Write-Host "NuGet packages updated successfully" -ForegroundColor Green
    } catch {
        $errorMessage = "Failed to update NuGet packages: $_"
        Write-Host $errorMessage -ForegroundColor Red
        $updateErrors += $errorMessage
    }

    Write-Host "`nSystem update completed!" -ForegroundColor Green
    Write-Host "Note: Some updates may require a system restart to take effect" -ForegroundColor Yellow

} finally {
    # Stop transcript
    Stop-Transcript

    # Read the console output and look for error patterns
    $consoleOutput = Get-Content -Path $tempLogFile -Raw
    $errorPatterns = @(
        'error',
        'exception',
        'failed',
        'failure',
        'unable to'
    )

    foreach ($pattern in $errorPatterns) {
        if ($consoleOutput -match "(?im)$pattern") {
            $matches = [regex]::Matches($consoleOutput, "(?im).*$pattern.*")
            foreach ($match in $matches) {
                $errorMessage = "Console output error: $($match.Value.Trim())"
                if ($updateErrors -notcontains $errorMessage) {
                    $updateErrors += $errorMessage
                }
            }
        }
    }

    # Clean up temporary file
    Remove-Item -Path $tempLogFile -Force
}

# Email notification function
function Send-UpdateNotification {
    param (
        [string[]]$Errors,
        [string]$Subject,
        [string]$SmtpServer = "smtp.office365.com",
        [int]$Port = 587
    )
    
    # Email configuration - load from environment variables for security
    $fromAddress = $env:BACKUP_EMAIL_FROM
    $toAddress = $env:BACKUP_EMAIL_TO
    $emailPassword = $env:BACKUP_EMAIL_PASSWORD
    
    # Check if email configuration exists
    if (!$fromAddress -or !$toAddress -or !$emailPassword) {
        Write-Host "Email notification skipped - environment variables not configured" -ForegroundColor Yellow
        return
    }
    
    try {
        # Create email body with more detailed information
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $body = @"
System Update Status Report from $env:COMPUTERNAME
Timestamp: $timestamp

Summary:
- Total Errors: $($Errors.Count)

Errors encountered during update:
$($Errors | ForEach-Object { "- $_`n" })

This is an automated message.
"@
        
        # Create credential object
        $securePassword = ConvertTo-SecureString $emailPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($fromAddress, $securePassword)
        
        # Send email
        Send-MailMessage `
            -From $fromAddress `
            -To $toAddress `
            -Subject $Subject `
            -Body $body `
            -SmtpServer $SmtpServer `
            -Port $Port `
            -UseSsl `
            -Credential $credential
            
        Write-Host "Update notification email sent successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to send email notification: $_" -ForegroundColor Red
    }
}

# Send email notification if there were any errors
if ($updateErrors.Count -gt 0) {
    $subject = "⚠️ System Update Failed on $env:COMPUTERNAME ($($updateErrors.Count) errors)"
    Send-UpdateNotification -Errors $updateErrors -Subject $subject
}

