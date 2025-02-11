

# Install Ubuntu fonts
try {
    Write-Host "Installing Ubuntu fonts..." -ForegroundColor Blue
    
    # Download Ubuntu fonts
    $fontUrl = "https://assets.ubuntu.com/v1/fad7939b-ubuntu-font-family-0.83.zip"
    $fontZip = "$env:TEMP\ubuntu-fonts.zip"
    $fontExtract = "$env:TEMP\ubuntu-fonts"
    
    # Create extraction directory if it doesn't exist
    if (!(Test-Path $fontExtract)) {
        New-Item -ItemType Directory -Path $fontExtract -Force | Out-Null
    }
    
    # Download and extract
    Invoke-WebRequest -Uri $fontUrl -OutFile $fontZip
    Expand-Archive -Path $fontZip -DestinationPath $fontExtract -Force
    
    # Install all Ubuntu fonts for all users
    $fontFiles = Get-ChildItem -Path "$fontExtract\ubuntu-font-family-0.83" -Filter "*.ttf"
    foreach ($font in $fontFiles) {
        $fontDestination = "C:\Windows\Fonts\$($font.Name)"
        Copy-Item -Path $font.FullName -Destination $fontDestination -Force
        
        # Add font to registry
        $regValue = @{
            'Name' = $font.BaseName
            'Type' = "REG_SZ"
            'Value' = $font.Name
            'Path' = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        }
        Set-ItemProperty @regValue
    }
    
    # Also install Nerd Font version of Ubuntu Mono for dev icons
    $nerdFontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/UbuntuMono.zip"
    $nerdFontZip = "$env:TEMP\ubuntu-nerd-fonts.zip"
    
    Invoke-WebRequest -Uri $nerdFontUrl -OutFile $nerdFontZip
    Expand-Archive -Path $nerdFontZip -DestinationPath "$fontExtract\nerd-fonts" -Force
    
    $nerdFontFiles = Get-ChildItem -Path "$fontExtract\nerd-fonts" -Filter "*.ttf"
    foreach ($font in $nerdFontFiles) {
        $fontDestination = "C:\Windows\Fonts\$($font.Name)"
        Copy-Item -Path $font.FullName -Destination $fontDestination -Force
        
        # Add font to registry
        $regValue = @{
            'Name' = $font.BaseName
            'Type' = "REG_SZ"
            'Value' = $font.Name
            'Path' = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        }
        Set-ItemProperty @regValue
    }
    
    # Cleanup
    Remove-Item $fontZip -Force
    Remove-Item $nerdFontZip -Force
    Remove-Item $fontExtract -Recurse -Force
    
    Write-Host "Ubuntu fonts installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to install Ubuntu fonts: $_" -ForegroundColor Red
}
