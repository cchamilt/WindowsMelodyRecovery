# Install module to user's modules directory
$modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\WindowsRecovery"
if (!(Test-Path $modulePath)) {
    New-Item -ItemType Directory -Path $modulePath -Force
}

# Copy module files
Copy-Item -Path ".\*" -Destination $modulePath -Recurse -Force

# Import module
Import-Module WindowsRecovery -Force

Write-Host "WindowsRecovery module installed successfully!" -ForegroundColor Green
Write-Host "You can now use Install-WindowsRecovery to set up your Windows recovery." 