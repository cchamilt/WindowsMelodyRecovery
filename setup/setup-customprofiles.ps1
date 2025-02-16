[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$UseExamples,
    [Parameter(Mandatory=$false)]
    [switch]$UseAI
)

# Load environment
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path $scriptPath -Parent) "scripts\load-environment.ps1")

if (!(Load-Environment)) {
    Write-Host "Failed to load environment configuration" -ForegroundColor Red
    exit 1
}

# If neither flag is specified, ask the user
if (!$UseExamples -and !$UseAI) {
    Write-Host "`nHow would you like to generate your shell profiles?" -ForegroundColor Blue
    Write-Host "1. Use example profiles" -ForegroundColor Yellow
    Write-Host "2. Use AI assistance" -ForegroundColor Yellow
    Write-Host "3. Create manually" -ForegroundColor Yellow
    
    do {
        $choice = Read-Host "`nEnter your choice (1-3)"
        switch ($choice) {
            "1" { $UseExamples = $true }
            "2" { $UseAI = $true }
            "3" { 
                Write-Host "Please create your profiles manually at:" -ForegroundColor Yellow
                Write-Host "PowerShell: $PROFILE" -ForegroundColor Cyan
                Write-Host "Bash: ~/.bashrc (in WSL)" -ForegroundColor Cyan
                exit 0
            }
            default { 
                Write-Host "Invalid choice. Please enter 1, 2, or 3." -ForegroundColor Red
                $choice = $null
            }
        }
    } while ($null -eq $choice)
}

function Get-InstalledPackages {
    $packages = @{
        Windows = @()
        Linux = @()
    }

    # Get Windows packages
    Write-Host "Scanning Windows packages..." -ForegroundColor Blue
    
    # Chocolatey packages
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $chocoPackages = choco list --local-only --limit-output | ForEach-Object { ($_ -split '\|')[0] }
        $packages.Windows += $chocoPackages
    }

    # Scoop packages
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        $scoopPackages = scoop list | Select-Object -Skip 1 | ForEach-Object { ($_ -split ' ')[0] }
        $packages.Windows += $scoopPackages
    }

    # Winget packages
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetPackages = winget list | Select-Object -Skip 3 | ForEach-Object {
            if ($_ -match '^(.+?)\s{2,}') {
                $matches[1].Trim()
            }
        }
        $packages.Windows += $wingetPackages
    }

    # Get Linux packages if WSL is available
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        Write-Host "`nScanning Linux packages..." -ForegroundColor Blue
        
        # Get installed packages from common package managers
        try {
            # apt (Debian/Ubuntu)
            $aptPackages = wsl dpkg-query -f '${Package}\n' -W 2>$null
            if ($LASTEXITCODE -eq 0) {
                $packages.Linux += $aptPackages
            }

            # pacman (Arch)
            $pacmanPackages = wsl pacman -Q --quiet 2>$null
            if ($LASTEXITCODE -eq 0) {
                $packages.Linux += $pacmanPackages
            }

            # dnf (Fedora/RHEL)
            $dnfPackages = wsl dnf list installed --quiet 2>$null | ForEach-Object { ($_ -split ' ')[0] }
            if ($LASTEXITCODE -eq 0) {
                $packages.Linux += $dnfPackages
            }
        }
        catch {
            Write-Host "Warning: Error getting Linux packages - $_" -ForegroundColor Yellow
        }
    }

    return $packages
}

function Install-GithubCopilotCli {
    if (!(Get-Command github-copilot-cli -ErrorAction SilentlyContinue)) {
        Write-Host "GitHub Copilot CLI not found. Would you like to install it? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -eq 'Y') {
            try {
                # Install via npm
                if (Get-Command npm -ErrorAction SilentlyContinue) {
                    npm install -g @githubnext/github-copilot-cli
                    Write-Host "GitHub Copilot CLI installed. Please run 'github-copilot-cli auth' to authenticate." -ForegroundColor Green
                    Start-Process "github-copilot-cli" -ArgumentList "auth" -Wait
                    return $true
                } else {
                    Write-Host "npm not found. Please install Node.js first." -ForegroundColor Red
                }
            } catch {
                Write-Host "Failed to install GitHub Copilot CLI: $_" -ForegroundColor Red
            }
        }
    }
    return $false
}

function Get-AvailableAIAssistants {
    $assistants = @()
    
    # Try to install and setup GitHub Copilot CLI
    if (Install-GithubCopilotCli) {
        $assistants += "GitHub Copilot CLI"
    }

    # Check for VS Code with Copilot
    $vscodePath = "$env:APPDATA\Code\User\settings.json"
    if (Test-Path $vscodePath) {
        $settings = Get-Content $vscodePath | ConvertFrom-Json
        if ($settings.PSObject.Properties['github.copilot.enable'] -and $settings.'github.copilot.enable') {
            $assistants += "VS Code Copilot"
        } else {
            Write-Host "VS Code found but Copilot not enabled. Would you like to open VS Code to set it up? (Y/N)" -ForegroundColor Yellow
            $response = Read-Host
            if ($response -eq 'Y') {
                Start-Process "code" -ArgumentList "--install-extension GitHub.copilot" -Wait
                $assistants += "VS Code Copilot"
            }
        }
    }

    # Check for Cursor
    $cursorPath = "$env:LOCALAPPDATA\Programs\Cursor\Cursor.exe"
    if (Test-Path $cursorPath) {
        Write-Host "Cursor found. Would you like to use it for profile generation? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -eq 'Y') {
            $assistants += "Cursor"
        }
    }

    # Check for Claude API access
    if ($env:ANTHROPIC_API_KEY) {
        $assistants += "Claude"
    } else {
        Write-Host "Would you like to set up Claude API access? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -eq 'Y') {
            $apiKey = Read-Host "Enter your Anthropic API key"
            [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $apiKey, "User")
            $env:ANTHROPIC_API_KEY = $apiKey
            $assistants += "Claude"
        }
    }

    return $assistants
}

function New-CustomProfile {
    param(
        [string]$ProfileType,
        [array]$Packages,
        [array]$AIAssistants
    )

    $profileContent = ""
    
    if ($UseExamples) {
        # Load example profile based on ProfileType
        $examplePath = Join-Path $scriptPath "example-profiles\$ProfileType.example"
        if (Test-Path $examplePath) {
            $profileContent = Get-Content $examplePath -Raw
        }
    }
    elseif ($UseAI) {
        $prompt = @"
Create a $ProfileType shell profile with these requirements:
1. Support for installed packages: $($Packages -join ', ')
2. Include useful aliases and functions for development
3. Add environment setup for development tools
4. Include shell customization (prompt, colors, etc.)
5. Add helpful utility functions
6. Ensure good performance (lazy loading where appropriate)
7. Include error handling
8. Add comments explaining complex parts
"@

        # Try AI assistants in order of preference
        foreach ($assistant in $AIAssistants) {
            try {
                switch ($assistant) {
                    "GitHub Copilot CLI" {
                        $profileContent = github-copilot-cli --shell $prompt
                        break
                    }
                    "VS Code Copilot" {
                        $tempFile = Join-Path $env:TEMP "temp_profile.$ProfileType"
                        Set-Content -Path $tempFile -Value "# $prompt"
                        Start-Process "code" -ArgumentList $tempFile -Wait
                        $profileContent = Get-Content $tempFile -Raw
                        Remove-Item $tempFile
                        break
                    }
                    "Cursor" {
                        $tempFile = Join-Path $env:TEMP "temp_profile.$ProfileType"
                        Set-Content -Path $tempFile -Value "# $prompt"
                        Start-Process $cursorPath -ArgumentList $tempFile -Wait
                        $profileContent = Get-Content $tempFile -Raw
                        Remove-Item $tempFile
                        break
                    }
                    "Claude" {
                        # You'll need to implement the Claude API call here
                        $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers @{
                            "x-api-key" = $env:ANTHROPIC_API_KEY
                            "anthropic-version" = "2023-06-01"
                        } -ContentType "application/json" -Body (@{
                            "model" = "claude-3-sonnet-20240229"
                            "max_tokens" = 4096
                            "messages" = @(@{
                                "role" = "user"
                                "content" = $prompt
                            })
                        } | ConvertTo-Json)
                        $profileContent = $response.content
                        break
                    }
                }
                
                if ($profileContent) { break }
            }
            catch {
                Write-Host "Failed to generate profile using $assistant: $_" -ForegroundColor Red
                continue
            }
        }
    }
    
    if (!$profileContent) {
        Write-Host "No profile content generated. Please create profile manually." -ForegroundColor Yellow
        return $null
    }
    
    return $profileContent
}

function Setup-CustomProfiles {
    $packages = Get-InstalledPackages
    $aiAssistants = Get-AvailableAIAssistants

    Write-Host "`nAvailable AI Assistants:" -ForegroundColor Blue
    $aiAssistants | ForEach-Object { Write-Host "- $_" -ForegroundColor Green }

    # Setup PowerShell profile
    Write-Host "`nSetting up PowerShell profile..." -ForegroundColor Blue
    $psProfilePath = $PROFILE
    $psProfileContent = New-CustomProfile -ProfileType "powershell" -Packages $packages.Windows -AIAssistants $aiAssistants

    if ($psProfileContent) {
        try {
            $psProfileDir = Split-Path $PROFILE -Parent
            if (!(Test-Path $psProfileDir)) {
                New-Item -Path $psProfileDir -ItemType Directory -Force | Out-Null
            }
            Set-Content -Path $PROFILE -Value $psProfileContent
            Write-Host "PowerShell profile created successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create PowerShell profile: $_" -ForegroundColor Red
        }
    }

    # Setup Bash profile if WSL is available
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        Write-Host "`nSetting up Bash profile..." -ForegroundColor Blue
        $bashProfileContent = New-CustomProfile -ProfileType "bash" -Packages $packages.Linux -AIAssistants $aiAssistants

        if ($bashProfileContent) {
            try {
                $bashProfile = wsl echo '~/.bashrc'
                wsl echo $bashProfileContent > $bashProfile
                Write-Host "Bash profile created successfully" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to create Bash profile: $_" -ForegroundColor Red
            }
        }
    }
}

# Run the setup
Setup-CustomProfiles
