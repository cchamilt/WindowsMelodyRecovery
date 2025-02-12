# Get all backup scripts
$backupScripts = Get-ChildItem -Path "backup" -Filter "backup-*.ps1"

foreach ($script in $backupScripts) {
    $content = Get-Content $script.FullName -Raw
    
    # Extract the feature name from the filename
    $feature = $script.BaseName -replace '^backup-',''
    
    # Extract the backup logic (everything between the try block markers)
    if ($content -match '(?s)# Backup logic here\s*(.*?)\s*Write-Host.*backed up successfully') {
        $backupLogic = $matches[1].Trim()
        
        # Read the template
        $template = Get-Content "backup/template.ps1" -Raw
        
        # Replace [Feature] with actual feature name (properly cased)
        $featurePascalCase = (Get-Culture).TextInfo.ToTitleCase($feature) -replace '-'
        $newContent = $template -replace '\[Feature\]', $featurePascalCase
        
        # Insert the existing backup logic
        $newContent = $newContent -replace '# Backup logic here', "# Backup logic here`n            $backupLogic"
        
        # Save the updated script
        $newContent | Set-Content $script.FullName -NoNewline
    }
}