# Mock Microsoft.PowerShell_profile.ps1 for integration testing
Write-Information -MessageData "[MOCK PROFILE] Microsoft.PowerShell_profile.ps1 loaded." -InformationAction Continue

# Set a custom prompt
function prompt {
    "[MOCK-PS] PS $($executionContext.SessionState.Path.CurrentLocation)> "
}
