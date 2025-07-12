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
        # Set basic environment variables for the command
        $envCommand = "export HOME=/home/$User USER=$User SHELL=/bin/bash PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; $Command"

        # Build the docker exec command with basic bash shell
        $dockerArgs = @(
            "exec"
            "-i"
            "--user", $User
            "--workdir", $WorkingDirectory
            $ContainerName
            "bash", "-c", $envCommand
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
            return @{
                Success = $true
                Error = $null
                Output = $result.Output
                Method = "Docker"
            }
        }
        else {
            Write-Warning "WSL Docker connectivity test failed: $($result.Output)"
            return @{
                Success = $false
                Error = "Connectivity test failed: $($result.Output)"
                Output = $result.Output
                Method = "Docker"
            }
        }
    }
    catch {
        Write-Warning "WSL Docker connectivity test error: $($_.Exception.Message)"
        return @{
            Success = $false
            Error = $_.Exception.Message
            Output = ""
            Method = "Docker"
        }
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
function Get-WSLDockerDistribution {
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
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,

        [Parameter(Mandatory = $false)]
        [string]$ContainerName = "wmr-wsl-mock",

        [Parameter(Mandatory = $false)]
        [string]$ScriptType = "bash"
    )

    try {
        # Create a temporary script file in the container
        $scriptFile = "/tmp/script-$(Get-Random).sh"

        # Clean up the script content - remove Windows line endings and fix paths
        $cleanContent = $ScriptContent -replace "`r`n", "`n" -replace "`r", "`n"

        # Write the script content to the container using printf to handle line endings properly
        $lines = $cleanContent -split "`n"
        $createCommands = @()

        # Clear the file first
        $createCommands += "printf '' > $scriptFile"

        # Add each line with proper line ending
        foreach ($line in $lines) {
            if ($line.Trim() -ne "") {
                $escapedLine = $line -replace '"', '\"' -replace '`', '\`' -replace '\$', '\\$'
                $createCommands += "printf '%s\n' `"$escapedLine`" >> $scriptFile"
            } else {
                $createCommands += "printf '\n' >> $scriptFile"
            }
        }

        # Execute all create commands
        $createScript = $createCommands -join " && "
        $createResult = docker exec $ContainerName bash -c $createScript
        if ($LASTEXITCODE -ne 0) {
            return @{
                Success = $false
                Output = "Failed to create script file: $createResult"
                Error = "Script creation failed"
                Method = "Docker"
            }
        }

        # Make the script executable
        $chmodResult = docker exec $ContainerName chmod +x $scriptFile
        if ($LASTEXITCODE -ne 0) {
            return @{
                Success = $false
                Output = "Failed to make script executable: $chmodResult"
                Error = "Chmod failed"
                Method = "Docker"
            }
        }

        # Execute the script with proper environment
        $executeCommand = "cd /home/testuser && export HOME=/home/testuser && export USER=testuser && export SHELL=/bin/bash && bash $scriptFile"
        $result = docker exec $ContainerName bash -c $executeCommand
        $exitCode = $LASTEXITCODE

        # Clean up the script file
        docker exec $ContainerName rm -f $scriptFile | Out-Null

        return @{
            Success = ($exitCode -eq 0)
            Output = if ($result) { $result -join "`n" } else { "" }
            Error = if ($exitCode -ne 0) { "Script execution failed with exit code $exitCode" } else { $null }
            Method = "Docker"
            ExitCode = $exitCode
        }
    }
    catch {
        return @{
            Success = $false
            Output = ""
            Error = $_.Exception.Message
            Method = "Docker"
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
function Get-WSLDockerPackage {
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







