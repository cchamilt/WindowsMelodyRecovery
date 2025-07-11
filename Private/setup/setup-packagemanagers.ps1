function Initialize-PackageManagers {
    [CmdletBinding()]
    param()

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Import-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Information -MessageData "Setting up package managers..." -InformationAction Continue

        # Check for admin rights
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (!$isAdmin) {
            Write-Warning "This script requires administrator privileges to install package managers."
            return $false
        }

        # Check/Install Chocolatey
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Warning -Message "Installing Chocolatey..."
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

                Write-Information -MessageData "Chocolatey installed successfully" -InformationAction Continue
            } catch {
                Write-Error -Message "Failed to install Chocolatey: $($_.Exception.Message)"
            }
        } else {
            Write-Information -MessageData "✓ Chocolatey is already installed" -InformationAction Continue
        }

        # Check/Install Scoop
        if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Warning -Message "Installing Scoop..."
            try {
                # Create a temporary script to install Scoop
                $tempScript = @'
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
'@
                $tempScriptPath = Join-Path $env:TEMP "InstallScoop.ps1"
                $tempScript | Out-File -FilePath $tempScriptPath -Force

                # Run the script as the current user
                $process = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`"" -LoadUserProfile -Wait -PassThru
                Remove-Item $tempScriptPath -Force

                if ($process.ExitCode -eq 0) {
                    Write-Information -MessageData "Scoop installed successfully" -InformationAction Continue
                } else {
                    Write-Warning -Message "Scoop installation may have failed. Please check manually."
                }

                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } catch {
                Write-Error -Message "Failed to install Scoop: $($_.Exception.Message)"
            }
        } else {
            Write-Information -MessageData "✓ Scoop is already installed" -InformationAction Continue
        }

        # Verify winget is available
        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Warning -Message "Winget not found. Please ensure you have App Installer installed from the Microsoft Store"
            Write-Warning -Message "You can install it from: https://www.microsoft.com/store/productId/9NBLGGH4NNS1"
        } else {
            Write-Information -MessageData "✓ Winget is already installed" -InformationAction Continue
        }

        Write-Information -MessageData "Package manager setup complete!" -InformationAction Continue
        return $true

    } catch {
        Write-Error -Message "Failed to setup package managers: $($_.Exception.Message)"
        return $false
    }
}













