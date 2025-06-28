# Mock Microsoft.PowerShell_profile.ps1 for integration testing
Write-Host "[MOCK PROFILE] Microsoft.PowerShell_profile.ps1 loaded." -ForegroundColor Cyan

# Set a custom prompt
default
function prompt {
    "[MOCK-PS] PS $($executionContext.SessionState.Path.CurrentLocation)> "
} 