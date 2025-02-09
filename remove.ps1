# Confidence: Low - This script is not fully tested and may remove important Lenovo/ASUS applications.


#Remove: Lenovo*, new outlook, etc.
Write-Host "Removing Lenovo bloatware..." -ForegroundColor Blue

try {
    # $excludeApps = @(
    #     "LenovoVantage",  # Example of an app you might want to keep
    #     "LenovoUtility"
    # )

    $lenovoApps = Get-AppxPackage -AllUsers | Where-Object { 
        $_.Name -like "*Lenovo*" -and $_.Name -notin $excludeApps 
    }
    
    # Remove each Lenovo app
    foreach ($app in $lenovoApps) {
        Write-Host "Removing $($app.Name)..." -ForegroundColor Yellow
        Remove-AppxPackage -Package $app.PackageFullName
        Remove-AppxProvisionedPackage -Online -PackageName $app.Name
    }

    # Remove Lenovo programs using WMI
    Get-WmiObject -Class Win32_Product | Where-Object { 
        $_.Name -like "*Lenovo*" 
    } | ForEach-Object {
        Write-Host "Removing $($_.Name)..." -ForegroundColor Yellow
        $_.Uninstall()
    }
    
    Write-Host "Lenovo bloatware removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove some Lenovo applications: $_" -ForegroundColor Red
}

# Remove new outlook
Write-Host "Removing new outlook..." -ForegroundColor Blue

try {
    # Remove Outlook from the registry
    Write-Host "Removing Outlook from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft.Office.16.0.Outlook" -Recurse -Force

    # Remove Outlook from the registry
    Write-Host "Removing Outlook from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft.Office.16.0.Outlook" -Recurse -Force 

    Write-Host "Outlook removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove Outlook: $_" -ForegroundColor Red
}

# Remove McAfee AV
Write-Host "Removing McAfee AV..." -ForegroundColor Blue

try {
    # Remove McAfee from the registry
    Write-Host "Removing McAfee from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKLM:\SOFTWARE\McAfee" -Recurse -Force

    # Remove McAfee from the registry
    Write-Host "Removing McAfee from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKLM:\SOFTWARE\McAfee" -Recurse -Force   

    Write-Host "McAfee removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove McAfee: $_" -ForegroundColor Red
}

# Remove ASUS bloatware
Write-Host "Removing ASUS bloatware..." -ForegroundColor Blue

try {
    # Remove ASUS from the registry
    Write-Host "Removing ASUS from registry..." -ForegroundColor Yellow 
    Remove-Item -Path "HKLM:\SOFTWARE\ASUS" -Recurse -Force

    # Remove ASUS from the registry
    Write-Host "Removing ASUS from registry..." -ForegroundColor Yellow
    Remove-Item -Path "HKLM:\SOFTWARE\ASUS" -Recurse -Force

    Write-Host "ASUS removal completed" -ForegroundColor Green
} catch {
    Write-Host "Failed to remove ASUS: $_" -ForegroundColor Red
}










