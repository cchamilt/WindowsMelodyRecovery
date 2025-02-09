function Restore-RDPSettings {
    try {
        Write-Host "Restoring Remote Desktop profiles..." -ForegroundColor Blue
        $rdpPath = Test-BackupPath -Path "RDP" -BackupType "Remote Desktop"
        
        if ($rdpPath) {
            # Destination RDP directory
            $rdpDestPath = "$env:USERPROFILE\Documents\Remote Desktop Connection Manager"
            
            # Create the RDP directory if it doesn't exist
            if (!(Test-Path -Path $rdpDestPath)) {
                New-Item -ItemType Directory -Path $rdpDestPath -Force | Out-Null
            }
            
            # Copy RDP files
            Copy-Item -Path "$rdpPath\*.rdp" -Destination $rdpDestPath -Force
            Write-Host "Remote Desktop profiles copied successfully" -ForegroundColor Green
            
            # Import registry settings for saved credentials
            $regFile = "$rdpPath\rdp_credentials.reg"
            if (Test-Path -Path $regFile) {
                reg import $regFile
                Write-Host "Remote Desktop credentials imported" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "Failed to restore Remote Desktop profiles: $_" -ForegroundColor Red
    }
} 