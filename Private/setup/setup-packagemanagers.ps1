function Setup-PackageManagers {
    [CmdletBinding()]
    param()

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Setting up package managers..." -ForegroundColor Blue

        # Check for admin rights
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (!$isAdmin) {
            Write-Warning "This script requires administrator privileges to install package managers."
            return $false
        }

        # Check/Install Chocolatey
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                
                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                
                Write-Host "Chocolatey installed successfully" -ForegroundColor Green
            } catch {
                Write-Host "Failed to install Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "✓ Chocolatey is already installed" -ForegroundColor Green
        }

        # Check/Install Scoop
        if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Host "Installing Scoop..." -ForegroundColor Yellow
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
                    Write-Host "Scoop installed successfully" -ForegroundColor Green
                } else {
                    Write-Host "Scoop installation may have failed. Please check manually." -ForegroundColor Yellow
                }

                # Refresh environment variables
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } catch {
                Write-Host "Failed to install Scoop: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "✓ Scoop is already installed" -ForegroundColor Green
        }

        # Verify winget is available
        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host "Winget not found. Please ensure you have App Installer installed from the Microsoft Store" -ForegroundColor Yellow
            Write-Host "You can install it from: https://www.microsoft.com/store/productId/9NBLGGH4NNS1" -ForegroundColor Yellow
        } else {
            Write-Host "✓ Winget is already installed" -ForegroundColor Green
        }

        Write-Host "Package manager setup complete!" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "Failed to setup package managers: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

