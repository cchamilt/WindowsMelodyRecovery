# tests/utilities/WSL-Docker-Communication.ps1
# WSL Docker Container Communication Utilities
# Provides functions to communicate with WSL containers in Docker environment

<#
.SYNOPSIS
Executes commands in the WSL Docker container using docker exec

.DESCRIPTION
This function replaces the native `wsl` command when running in Docker test environment.
It uses docker exec to communicate with the WSL mock container.

.PARAMETER Command
The command to execute in the WSL container

.PARAMETER User
The user to execute the command as (default: testuser)

.PARAMETER WorkingDirectory
The working directory to execute the command in (default: /home/testuser)

.PARAMETER ContainerName
The name of the WSL container (default: wmr-wsl-mock)

.EXAMPLE
Invoke-WSLDockerCommand -Command "whoami"
Invoke-WSLDockerCommand -Command "ls -la" -WorkingDirectory "/tmp"
#>
function Invoke-WSLDockerCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [Parameter(Mandatory = $false)]
        [string]$User = "testuser",
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = "/home/testuser",
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock"
    )
    
    try {
        # Build the docker exec command
        $dockerArgs = @(
            "exec"
            "-i"
            "--user", $User
            "--workdir", $WorkingDirectory
            $ContainerName
            "bash", "-c", $Command
        )
        
        Write-Verbose "Executing: docker $($dockerArgs -join ' ')"
        
        # Execute the command
        $result = & docker @dockerArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        return @{
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output = $result
            Command = $Command
        }
    }
    catch {
        return @{
            Success = $false
            ExitCode = -1
            Output = $_.Exception.Message
            Command = $Command
            Error = $_.Exception
        }
    }
}

<#
.SYNOPSIS
Tests connectivity to the WSL Docker container

.DESCRIPTION
Verifies that the WSL container is running and accessible via docker exec

.PARAMETER ContainerName
The name of the WSL container to test

.EXAMPLE
Test-WSLDockerConnectivity
#>
function Test-WSLDockerConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock"
    )
    
    try {
        # Test basic connectivity
        $result = Invoke-WSLDockerCommand -Command "echo 'CONNECTIVITY_TEST_PASSED'" -ContainerName $ContainerName
        
        if ($result.Success -and $result.Output -match "CONNECTIVITY_TEST_PASSED") {
            Write-Verbose "WSL Docker connectivity test passed"
            return $true
        }
        else {
            Write-Warning "WSL Docker connectivity test failed: $($result.Output)"
            return $false
        }
    }
    catch {
        Write-Warning "WSL Docker connectivity test error: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
Lists WSL distributions in the Docker environment

.DESCRIPTION
Simulates the `wsl --list` command for Docker environment by checking container status

.PARAMETER ContainerName
The name of the WSL container

.EXAMPLE
Get-WSLDockerDistributions
#>
function Get-WSLDockerDistributions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock"
    )
    
    try {
        # Check if container is running
        $containerStatus = & docker ps --filter "name=$ContainerName" --format "{{.Status}}" 2>$null
        
        if ($containerStatus -match "Up") {
            # Get distribution info from container
            $distroInfo = Invoke-WSLDockerCommand -Command "cat /etc/os-release | grep -E '^(NAME|VERSION)='" -ContainerName $ContainerName
            
            if ($distroInfo.Success) {
                $distroName = "Ubuntu-22.04"  # Default for our mock
                $status = "Running"
                
                return @{
                    Name = $distroName
                    Status = $status
                    Version = "2"
                    Default = $true
                }
            }
        }
        
        return $null
    }
    catch {
        Write-Warning "Failed to get WSL distributions: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
Executes a script in the WSL Docker container

.DESCRIPTION
Executes a bash script in the WSL container and returns the results

.PARAMETER ScriptContent
The bash script content to execute

.PARAMETER User
The user to execute the script as

.PARAMETER ContainerName
The name of the WSL container

.EXAMPLE
$script = @"
#!/bin/bash
echo "Hello from WSL"
whoami
pwd
"@
Invoke-WSLDockerScript -ScriptContent $script
#>
function Invoke-WSLDockerScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,
        
        [Parameter(Mandatory = $false)]
        [string]$User = "testuser",
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock"
    )
    
    try {
        # Create a temporary script file in the container
        $scriptFileName = "temp_script_$(Get-Random).sh"
        $scriptPath = "/tmp/$scriptFileName"
        
        # Normalize line endings for Unix (LF only)
        $normalizedScript = $ScriptContent -replace "`r`n", "`n" -replace "`r", "`n"
        
        # Split script into lines and write each line separately to avoid quoting issues
        $scriptLines = $normalizedScript -split "`n"
        
        # Create empty file first
        $createResult = Invoke-WSLDockerCommand -Command "touch $scriptPath" -User $User -ContainerName $ContainerName
        if (-not $createResult.Success) {
            throw "Failed to create script file: $($createResult.Output)"
        }
        
        # Write each line to the file
        foreach ($line in $scriptLines) {
            if ($line.Trim() -ne "") {
                # Escape single quotes in the line
                $escapedLine = $line -replace "'", "'\'''"
                $writeResult = Invoke-WSLDockerCommand -Command "echo '$escapedLine' >> $scriptPath" -User $User -ContainerName $ContainerName
                if (-not $writeResult.Success) {
                    throw "Failed to write line to script: $($writeResult.Output)"
                }
            } else {
                # Write empty line
                $writeResult = Invoke-WSLDockerCommand -Command "echo '' >> $scriptPath" -User $User -ContainerName $ContainerName
                if (-not $writeResult.Success) {
                    throw "Failed to write empty line to script: $($writeResult.Output)"
                }
            }
        }
        
        # Make script executable
        $chmodResult = Invoke-WSLDockerCommand -Command "chmod +x $scriptPath" -User $User -ContainerName $ContainerName
        
        if (-not $chmodResult.Success) {
            throw "Failed to make script executable: $($chmodResult.Output)"
        }
        
        # Execute the script
        $executeResult = Invoke-WSLDockerCommand -Command "bash $scriptPath" -User $User -ContainerName $ContainerName
        
        # Clean up the temporary script
        Invoke-WSLDockerCommand -Command "rm -f $scriptPath" -User $User -ContainerName $ContainerName | Out-Null
        
        return $executeResult
    }
    catch {
        return @{
            Success = $false
            ExitCode = -1
            Output = $_.Exception.Message
            Error = $_.Exception
        }
    }
}

<#
.SYNOPSIS
Gets package information from WSL Docker container

.DESCRIPTION
Retrieves information about installed packages in the WSL container

.PARAMETER PackageManager
The package manager to use (apt, pip3, npm)

.PARAMETER ContainerName
The name of the WSL container

.EXAMPLE
Get-WSLDockerPackages -PackageManager "apt"
Get-WSLDockerPackages -PackageManager "pip3"
#>
function Get-WSLDockerPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("apt", "pip3", "npm")]
        [string]$PackageManager,
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock"
    )
    
    $commands = @{
        "apt" = "dpkg --get-selections | grep -v deinstall"
        "pip3" = "pip3 list --format=freeze"
        "npm" = "npm list -g --depth=0 --json"
    }
    
    $command = $commands[$PackageManager]
    if (-not $command) {
        throw "Unsupported package manager: $PackageManager"
    }
    
    try {
        $result = Invoke-WSLDockerCommand -Command $command -ContainerName $ContainerName
        
        if ($result.Success) {
            return @{
                PackageManager = $PackageManager
                Success = $true
                Packages = $result.Output
                Count = ($result.Output | Measure-Object).Count
            }
        }
        else {
            return @{
                PackageManager = $PackageManager
                Success = $false
                Error = $result.Output
                Count = 0
            }
        }
    }
    catch {
        return @{
            PackageManager = $PackageManager
            Success = $false
            Error = $_.Exception.Message
            Count = 0
        }
    }
}

<#
.SYNOPSIS
Backs up WSL configuration files

.DESCRIPTION
Creates backups of important WSL configuration files

.PARAMETER BackupPath
The path to store backups

.PARAMETER ContainerName
The name of the WSL container

.EXAMPLE
Backup-WSLDockerConfiguration -BackupPath "/workspace/test-backups/wsl"
#>
function Backup-WSLDockerConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock"
    )
    
    $configFiles = @(
        "/etc/wsl.conf",
        "/etc/fstab",
        "/etc/hosts",
        "/home/testuser/.bashrc",
        "/home/testuser/.profile",
        "/home/testuser/.gitconfig",
        "/home/testuser/.config/chezmoi/chezmoi.toml"
    )
    
    $backupResults = @()
    
    foreach ($configFile in $configFiles) {
        try {
            # Check if file exists
            $checkResult = Invoke-WSLDockerCommand -Command "test -f '$configFile' && echo 'exists' || echo 'missing'" -ContainerName $ContainerName
            
            if ($checkResult.Success -and $checkResult.Output -match "exists") {
                # Create backup directory structure
                $relativePath = $configFile.TrimStart('/')
                $backupFilePath = Join-Path $BackupPath $relativePath
                $backupDir = Split-Path $backupFilePath -Parent
                
                if (-not (Test-Path $backupDir)) {
                    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
                }
                
                # Copy file content
                $contentResult = Invoke-WSLDockerCommand -Command "cat '$configFile'" -ContainerName $ContainerName
                
                if ($contentResult.Success) {
                    $contentResult.Output | Out-File -FilePath $backupFilePath -Encoding UTF8
                    
                    # Get file size safely
                    $fileSize = 0
                    try {
                        if (Test-Path $backupFilePath) {
                            $fileSize = (Get-Item $backupFilePath).Length
                        }
                    }
                    catch {
                        # If we can't get file size, just use 0
                        $fileSize = 0
                    }
                    
                    $backupResults += @{
                        File = $configFile
                        BackupPath = $backupFilePath
                        Success = $true
                        Size = $fileSize
                    }
                }
                else {
                    $backupResults += @{
                        File = $configFile
                        Success = $false
                        Error = "Failed to read file content"
                    }
                }
            }
            else {
                $backupResults += @{
                    File = $configFile
                    Success = $false
                    Error = "File does not exist"
                }
            }
        }
        catch {
            $backupResults += @{
                File = $configFile
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    return $backupResults
}

# Functions are available for dot-sourcing in tests
# Note: Export-ModuleMember cannot be used in dot-sourced scripts 