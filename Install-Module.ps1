# Install module to user's modules directory
$modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\WindowsConfig"
if (!(Test-Path $modulePath)) {
    New-Item -ItemType Directory -Path $modulePath -Force
}

# Copy module files
Copy-Item -Path ".\*" -Destination $modulePath -Recurse -Force

# Import module
Import-Module WindowsConfig -Force

Write-Host "WindowsConfig module installed successfully!" -ForegroundColor Green
Write-Host "You can now use Install-WindowsConfig to set up your Windows configuration." 