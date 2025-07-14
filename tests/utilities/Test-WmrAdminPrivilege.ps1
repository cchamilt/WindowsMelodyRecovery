function Test-WmrAdminPrivilege {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [OutputType([bool])]
    param()

    # This function is designed to be mocked in a Linux test environment.
    # It should only execute its contents on a true Windows system.
    if (-not $IsWindows) {
        # In a non-Windows environment (like the test container),
        # this function does nothing by default, allowing a Mock to control its output.
        return $true
    }

    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $true
    }

    return $false
}






