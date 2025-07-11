# Setup-WSLFonts.ps1 - Install development fonts for WSL

function Setup-WSLFonts {
    [CmdletBinding()]
    param()

    # Check for admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This function requires administrator privileges. Please run PowerShell as Administrator."
        return $false
    }

    # Load environment configuration (optional - module will use fallback configuration)
    try {
        Load-Environment | Out-Null
    } catch {
        Write-Verbose "Using module configuration fallback"
    }

    try {
        Write-Host "Configuring WSL fonts..." -ForegroundColor Blue

        # Define the fonts directory
        $fontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
        $systemFontsDir = "$env:SystemRoot\Fonts"
        $wslFontsDir = "/usr/share/fonts/truetype/custom"

        # Create fonts directory if it doesn't exist
        if (!(Test-Path $fontsDir)) {
            New-Item -ItemType Directory -Path $fontsDir -Force | Out-Null
        }

        # Download and install Nerd Fonts
        $nerdFonts = @(
            "CascadiaCode",
            "FiraCode",
            "JetBrainsMono",
            "Meslo",
            "Hack",
            "SourceCodePro",
            "UbuntuMono",
            "DejaVuSansMono",
            "DroidSansMono",
            "Inconsolata",
            "RobotoMono",
            "Terminus",
            "IBMPlexMono"
        )

        foreach ($font in $nerdFonts) {
            Write-Host "Installing $font Nerd Font..." -ForegroundColor Yellow
            try {
                # Download font from GitHub
                $releaseUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.zip"
                $zipPath = Join-Path $env:TEMP "$font.zip"
                $extractPath = Join-Path $env:TEMP $font

                # Download and extract
                Invoke-WebRequest -Uri $releaseUrl -OutFile $zipPath -TimeoutSec 60
                Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

                # Install fonts
                Get-ChildItem -Path $extractPath -Filter "*.ttf" -Recurse | ForEach-Object {
                    $fontName = $_.Name
                    $fontPath = Join-Path $fontsDir $fontName

                    # Copy to user fonts directory
                    Copy-Item $_.FullName -Destination $fontPath -Force

                    # Copy to system fonts directory
                    Copy-Item $_.FullName -Destination $systemFontsDir -Force

                    # Register font
                    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                    Set-ItemProperty -Path $regPath -Name "$fontName (TrueType)" -Value $fontName -Type String
                }

                Write-Host "Successfully installed $font" -ForegroundColor Green

                # Cleanup
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

            } catch {
                Write-Host "Failed to install $font : $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }

        # Install Ubuntu fonts
        Write-Host "`nInstalling Ubuntu fonts..." -ForegroundColor Blue
        try {
            # Download Ubuntu fonts
            $fontUrl = "https://assets.ubuntu.com/v1/fad7939b-ubuntu-font-family-0.83.zip"
            $fontZip = "$env:TEMP\ubuntu-fonts.zip"
            $fontExtract = "$env:TEMP\ubuntu-fonts"

            # Download and extract
            Invoke-WebRequest -Uri $fontUrl -OutFile $fontZip -TimeoutSec 60
            Expand-Archive -Path $fontZip -DestinationPath $fontExtract -Force

            # Install fonts
            Get-ChildItem -Path $fontExtract -Filter "*.ttf" -Recurse | ForEach-Object {
                $fontName = $_.Name
                $fontPath = Join-Path $fontsDir $fontName

                # Copy to user fonts directory
                Copy-Item $_.FullName -Destination $fontPath -Force

                # Copy to system fonts directory
                Copy-Item $_.FullName -Destination $systemFontsDir -Force

                # Register font
                $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                Set-ItemProperty -Path $regPath -Name "$fontName (TrueType)" -Value $fontName -Type String
            }

            Write-Host "Successfully installed Ubuntu fonts" -ForegroundColor Green

            # Cleanup
            Remove-Item $fontZip -Force -ErrorAction SilentlyContinue
            Remove-Item $fontExtract -Recurse -Force -ErrorAction SilentlyContinue

        } catch {
            Write-Host "Failed to install Ubuntu fonts: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Configure WSL to use the fonts
        if (Get-Command wsl -ErrorAction SilentlyContinue) {
            Write-Host "`nConfiguring WSL to use the fonts..." -ForegroundColor Yellow

            # Create a temporary script to handle font copying in WSL
            $tempScript = Join-Path $env:TEMP "copy-fonts.sh"
            $windowsFontsDir = "/mnt/" + (($fontsDir -replace '\\', '/') -replace ':', '').ToLower()
            $wslTempScript = "/mnt/" + (($tempScript -replace '\\', '/') -replace ':', '').ToLower()

            $scriptContent = @(
                "#!/bin/bash",
                "set -e",
                "",
                "# Create fonts directory",
                "mkdir -p $wslFontsDir",
                "",
                "# Copy all TTF fonts",
                "find `"$windowsFontsDir`" -name `"*.ttf`" -type f -exec cp {} $wslFontsDir/ \;",
                "",
                "# Set permissions",
                "chmod 644 $wslFontsDir/*.ttf",
                "",
                "# Update font cache",
                "fc-cache -f -v"
            ) -join "`n"

            # Create UTF8 encoding without BOM
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($tempScript, $scriptContent, $utf8NoBom)

            try {
                # Make script executable and run it with sudo
                wsl --exec bash -c "chmod +x '$wslTempScript' && sudo '$wslTempScript'"
                Write-Host "Successfully configured WSL fonts" -ForegroundColor Green
            } catch {
                Write-Host "Failed to configure WSL fonts: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "You may need to manually copy fonts to WSL" -ForegroundColor Yellow
            }

            # Cleanup temporary script
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "WSL not found. Fonts installed for Windows only." -ForegroundColor Yellow
        }

        Write-Host "`nWSL fonts configuration completed!" -ForegroundColor Green
        Write-Host "Note: You may need to restart your WSL terminal to see the changes" -ForegroundColor Yellow
        return $true

    } catch {
        Write-Host "Failed to configure WSL fonts: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

