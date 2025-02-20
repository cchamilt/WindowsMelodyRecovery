#Validates the recovery setup and backup integrity
#Also runs the private functions from the module individually

# Initialize the module
Initialize-WindowsRecovery

# Get the current configuration
Get-WindowsRecovery
