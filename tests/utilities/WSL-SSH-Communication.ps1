# tests/utilities/WSL-SSH-Communication.ps1
# WSL SSH Communication Utilities
# Provides SSH-based communication functions for WSL container testing

<#
.SYNOPSIS
Executes commands in the WSL container using SSH

.DESCRIPTION
This function provides SSH-based communication with the WSL mock container as an alternative to Docker exec.

.PARAMETER Command
The command to execute in the WSL container

.PARAMETER User
The user to execute the command as (default: testuser)

.PARAMETER ContainerHost
The hostname or IP of the WSL container (default: wmr-wsl-mock)

.PARAMETER Port
The SSH port to connect to (default: 2222)

.EXAMPLE
Invoke-WSLSSHCommand -Command "whoami"
Invoke-WSLSSHCommand -Command "ls -la" -User "testuser"
#>
function Invoke-WSLSSHCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [Parameter(Mandatory = $false)]
        [string]$HostName = "wmr-wsl-mock",
        
        [Parameter(Mandatory = $false)]
        [string]$UserName = "testuser",
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 22
    )
    
    try {
        # Execute command via SSH with proper key authentication
        $sshCommand = "docker exec wmr-test-runner ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i /workspace/tests/mock-data/ssh/id_rsa $UserName@$HostName '$Command'"
        
        $result = Invoke-Expression $sshCommand
        $exitCode = $LASTEXITCODE
        
        return @{
            Success = ($exitCode -eq 0)
            Output = if ($result) { $result -join "`n" } else { "" }
            Error = if ($exitCode -ne 0) { "SSH command failed with exit code $exitCode" } else { $null }
            Method = "SSH"
            ExitCode = $exitCode
        }
    }
    catch {
        return @{
            Success = $false
            Output = ""
            Error = $_.Exception.Message
            Method = "SSH"
        }
    }
}

<#
.SYNOPSIS
Tests SSH connectivity to the WSL container

.DESCRIPTION
Verifies that the WSL container is accessible via SSH

.PARAMETER ContainerHost
The hostname or IP of the WSL container

.PARAMETER Port
The SSH port to connect to

.EXAMPLE
Test-WSLSSHConnectivity
#>
function Test-WSLSSHConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$HostName = "wmr-wsl-mock",
        
        [Parameter(Mandatory = $false)]
        [string]$UserName = "testuser",
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 22
    )
    
    try {
        # Test SSH connectivity using the container's SSH key
        $sshCommand = "docker exec wmr-test-runner ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i /workspace/tests/mock-data/ssh/id_rsa $UserName@$HostName 'echo connection-test'"
        
        $result = Invoke-Expression $sshCommand
        $success = ($LASTEXITCODE -eq 0) -and ($result -eq "connection-test")
        
        if ($success) {
            Write-Verbose "SSH connectivity test passed"
        } else {
            Write-Warning "SSH connectivity test failed. Exit code: $LASTEXITCODE, Output: $result"
        }
        
        return $success
    }
    catch {
        Write-Warning "SSH connectivity test error: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
Copies files to/from WSL container using SCP

.DESCRIPTION
Uses SCP to transfer files between the host and WSL container

.PARAMETER SourcePath
The source file or directory path

.PARAMETER DestinationPath
The destination file or directory path

.PARAMETER ToContainer
Switch to indicate copying to container (default is from container)

.PARAMETER ContainerHost
The hostname or IP of the WSL container

.PARAMETER Port
The SSH port to connect to

.EXAMPLE
Copy-WSLSSHFile -SourcePath "/local/file.txt" -DestinationPath "/home/testuser/file.txt" -ToContainer
Copy-WSLSSHFile -SourcePath "/home/testuser/file.txt" -DestinationPath "/local/file.txt"
#>
function Copy-WSLSSHFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$ToContainer,
        
        [Parameter(Mandatory = $false)]
        [string]$User = "testuser",
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerHost = "wmr-wsl-mock",
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 2222
    )
    
    try {
        if ($ToContainer) {
            # Copy from host to container
            $destination = "$User@${ContainerHost}:$DestinationPath"
            $source = $SourcePath
        }
        else {
            # Copy from container to host
            $source = "$User@${ContainerHost}:$SourcePath"
            $destination = $DestinationPath
        }
        
        $scpArgs = @(
            "-o", "StrictHostKeyChecking=no"
            "-o", "UserKnownHostsFile=/dev/null"
            "-o", "LogLevel=ERROR"
            "-P", $Port
            "-r"
            $source
            $destination
        )
        
        Write-Verbose "Executing: scp $($scpArgs -join ' ')"
        
        # Execute the SCP command
        $result = & scp @scpArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        return @{
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output = $result
            SourcePath = $SourcePath
            DestinationPath = $DestinationPath
            Method = "SCP"
        }
    }
    catch {
        return @{
            Success = $false
            ExitCode = -1
            Output = $_.Exception.Message
            SourcePath = $SourcePath
            DestinationPath = $DestinationPath
            Method = "SCP"
            Error = $_.Exception
        }
    }
}

<#
.SYNOPSIS
Executes a script file in the WSL container via SSH

.DESCRIPTION
Transfers a script file to the WSL container and executes it via SSH

.PARAMETER ScriptContent
The script content to execute

.PARAMETER ScriptType
The type of script (bash, python, etc.)

.PARAMETER ContainerHost
The hostname or IP of the WSL container

.PARAMETER Port
The SSH port to connect to

.EXAMPLE
$script = @"
#!/bin/bash
echo "Hello from WSL via SSH"
whoami
pwd
"@
Invoke-WSLSSHScript -ScriptContent $script -ScriptType "bash"
#>
function Invoke-WSLSSHScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,
        
        [Parameter(Mandatory = $false)]
        [string]$ScriptType = "bash",
        
        [Parameter(Mandatory = $false)]
        [string]$HostName = "wmr-wsl-mock",
        
        [Parameter(Mandatory = $false)]
        [string]$UserName = "testuser",
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 22
    )
    
    try {
        # Create a temporary script file and execute it
        $scriptFile = "/tmp/ssh-script-$(Get-Random).sh"
        
        # First, create the script file via SSH
        $createCommand = "cat > $scriptFile << 'EOF'`n$ScriptContent`nEOF && chmod +x $scriptFile"
        $createResult = Invoke-WSLSSHCommand -Command $createCommand -HostName $HostName -UserName $UserName -Port $Port
        
        if (-not $createResult.Success) {
            return @{
                Success = $false
                Output = "Failed to create script file: $($createResult.Output)"
                Error = "Script creation failed"
                Method = "SSH"
            }
        }
        
        # Execute the script with proper environment
        $executeCommand = "cd /home/$UserName && export HOME=/home/$UserName && export USER=$UserName && export SHELL=/bin/bash && $scriptFile"
        $result = Invoke-WSLSSHCommand -Command $executeCommand -HostName $HostName -UserName $UserName -Port $Port
        
        # Clean up the script file
        Invoke-WSLSSHCommand -Command "rm -f $scriptFile" -HostName $HostName -UserName $UserName -Port $Port | Out-Null
        
        return @{
            Success = $result.Success
            Output = $result.Output
            Error = $result.Error
            Method = "SSH"
            ExitCode = $result.ExitCode
        }
    }
    catch {
        return @{
            Success = $false
            Output = ""
            Error = $_.Exception.Message
            Method = "SSH"
        }
    }
}

<#
.SYNOPSIS
Creates an SSH tunnel to the WSL container

.DESCRIPTION
Establishes an SSH tunnel for persistent communication with the WSL container

.PARAMETER LocalPort
The local port to bind the tunnel to

.PARAMETER RemotePort
The remote port to tunnel to

.PARAMETER ContainerHost
The hostname or IP of the WSL container

.PARAMETER Port
The SSH port to connect to

.EXAMPLE
New-WSLSSHTunnel -LocalPort 8080 -RemotePort 80
#>
function New-WSLSSHTunnel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$LocalPort,
        
        [Parameter(Mandatory = $true)]
        [int]$RemotePort,
        
        [Parameter(Mandatory = $false)]
        [string]$User = "testuser",
        
        [Parameter(Mandatory = $false)]
        [string]$ContainerHost = "wmr-wsl-mock",
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 2222
    )
    
    try {
        $sshArgs = @(
            "-o", "StrictHostKeyChecking=no"
            "-o", "UserKnownHostsFile=/dev/null"
            "-o", "LogLevel=ERROR"
            "-L", "${LocalPort}:localhost:${RemotePort}"
            "-N"
            "-f"
            "-p", $Port
            "$User@$ContainerHost"
        )
        
        Write-Verbose "Creating SSH tunnel: ssh $($sshArgs -join ' ')"
        
        # Create the tunnel
        $result = & ssh @sshArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Verbose "SSH tunnel created successfully: localhost:$LocalPort -> ${ContainerHost}:$RemotePort"
        }
        
        return @{
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output = $result
            LocalPort = $LocalPort
            RemotePort = $RemotePort
            Method = "SSH Tunnel"
        }
    }
    catch {
        return @{
            Success = $false
            ExitCode = -1
            Output = $_.Exception.Message
            LocalPort = $LocalPort
            RemotePort = $RemotePort
            Method = "SSH Tunnel"
            Error = $_.Exception
        }
    }
}

# Functions are available for dot-sourcing in tests
# Note: Export-ModuleMember cannot be used in dot-sourced scripts 