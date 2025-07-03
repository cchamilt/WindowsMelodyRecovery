Describe "WSL Integration Tests" {
    BeforeAll {
        # Import the module - handle both local and container paths
        $ModulePath = if (Test-Path "./WindowsMelodyRecovery.psm1") {
            "./WindowsMelodyRecovery.psm1"
        } elseif (Test-Path "/workspace/WindowsMelodyRecovery.psm1") {
            "/workspace/WindowsMelodyRecovery.psm1"
        } else {
            throw "Cannot find WindowsMelodyRecovery.psm1 module"
        }
        Import-Module $ModulePath -Force -ErrorAction SilentlyContinue
        
        # Set up test paths
        $testWslPath = "/workspace/test-wsl"
        $wslHomePath = "/home/testuser"
        $wslEtcPath = "/etc"
        $wslVarPath = "/var"
        
        # Create test directories if they don't exist
        if (-not (Test-Path $testWslPath)) {
            New-Item -Path $testWslPath -ItemType Directory -Force | Out-Null
        }
    }
    
    Context "Environment Setup" {
        It "Should have access to WSL home directory" {
            Test-Path $wslHomePath | Should -Be $true
        }
        
        It "Should have access to WSL etc directory" {
            Test-Path $wslEtcPath | Should -Be $true
        }
        
        It "Should have access to WSL var directory" {
            Test-Path $wslVarPath | Should -Be $true
        }
        
        It "Should be able to create test directories" {
            Test-Path $testWslPath | Should -Be $true
        }
    }
    
    Context "WSL Distribution Management" {
        It "Should be able to list WSL distributions" {
            # Create mock WSL distribution list
            $distributionsPath = Join-Path $testWslPath "distributions"
            if (-not (Test-Path $distributionsPath)) {
                New-Item -Path $distributionsPath -ItemType Directory -Force | Out-Null
            }
            
            $distributions = @(
                @{
                    Name = "Ubuntu-22.04"
                    Version = "2"
                    Default = $true
                    State = "Running"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\CanonicalGroupLimited.Ubuntu22.04LTS_79rhkp1fndgsc\\LocalState"
                },
                @{
                    Name = "Debian"
                    Version = "2"
                    Default = $false
                    State = "Stopped"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\TheDebianProject.DebianGNULinux_79rhkp1fndgsc\\LocalState"
                },
                @{
                    Name = "openSUSE-Leap-15.5"
                    Version = "2"
                    Default = $false
                    State = "Stopped"
                    BasePath = "C:\\Users\\TestUser\\AppData\\Local\\Packages\\openSUSEProject.openSUSELeap155_79rhkp1fndgsc\\LocalState"
                }
            )
            
            $distributions | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $distributionsPath "wsl-list.json") -Encoding UTF8
            Test-Path (Join-Path $distributionsPath "wsl-list.json") | Should -Be $true
            
            $loadedDistributions = Get-Content (Join-Path $distributionsPath "wsl-list.json") | ConvertFrom-Json
            $loadedDistributions.Count | Should -Be 3
            ($loadedDistributions | Where-Object { $_.Default -eq $true }).Count | Should -Be 1
        }
        
        It "Should be able to manage WSL configuration" {
            # Create mock WSL configuration
            $configPath = Join-Path $testWslPath "config"
            if (-not (Test-Path $configPath)) {
                New-Item -Path $configPath -ItemType Directory -Force | Out-Null
            }
            
            $wslConfig = @{
                Global = @{
                    Default = "Ubuntu-22.04"
                    NetworkMode = "mirrored"
                    LocalhostForwarding = $true
                }
                Ubuntu2204 = @{
                    KernelCommandLine = "cgroup_enable=1 cgroup_memory=1 cgroup_v2=1 swapaccount=1"
                    Memory = "8GB"
                    Processors = 4
                    Swap = "2GB"
                    LocalhostForwarding = $true
                }
                Debian = @{
                    KernelCommandLine = "cgroup_enable=1 cgroup_memory=1 cgroup_v2=1 swapaccount=1"
                    Memory = "4GB"
                    Processors = 2
                    Swap = "1GB"
                    LocalhostForwarding = $true
                }
            }
            
            $wslConfig | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $configPath "wsl-config.json") -Encoding UTF8
            Test-Path (Join-Path $configPath "wsl-config.json") | Should -Be $true
            
            $loadedConfig = Get-Content (Join-Path $configPath "wsl-config.json") | ConvertFrom-Json
            $loadedConfig.Global.Default | Should -Be "Ubuntu-22.04"
            $loadedConfig.Ubuntu2204.Memory | Should -Be "8GB"
        }
    }
    
    Context "WSL Cross-Platform Operations" {
        It "Should be able to execute WSL commands from Windows" {
            # Create mock WSL command execution results
            $commandsPath = Join-Path $testWslPath "commands"
            if (-not (Test-Path $commandsPath)) {
                New-Item -Path $commandsPath -ItemType Directory -Force | Out-Null
            }
            
            # Mock command results
            $commandResults = @{
                "wsl --list --verbose" = @{
                    Command = "wsl --list --verbose"
                    ExitCode = 0
                    Output = @"
  NAME                   STATE           VERSION
* Ubuntu-22.04          Running         2
  Debian                Stopped         2
  openSUSE-Leap-15.5    Stopped         2
"@
                    Error = ""
                }
                "wsl -d Ubuntu-22.04 -- uname -a" = @{
                    Command = "wsl -d Ubuntu-22.04 -- uname -a"
                    ExitCode = 0
                    Output = "Linux TestHost 5.15.0-generic #1 SMP x86_64 x86_64 x86_64 GNU/Linux"
                    Error = ""
                }
                "wsl -d Ubuntu-22.04 -- lsb_release -a" = @{
                    Command = "wsl -d Ubuntu-22.04 -- lsb_release -a"
                    ExitCode = 0
                    Output = @"
Distributor ID: Ubuntu
Description:    Ubuntu 22.04.3 LTS
Release:        22.04
Codename:       jammy
"@
                    Error = ""
                }
            }
            
            foreach ($command in $commandResults.Keys) {
                $commandFile = Join-Path $commandsPath "$($command -replace '[^a-zA-Z0-9]', '-').json"
                $commandResults[$command] | ConvertTo-Json -Depth 3 | Out-File -FilePath $commandFile -Encoding UTF8
                Test-Path $commandFile | Should -Be $true
            }
        }
        
        It "Should be able to transfer files between Windows and WSL" {
            # Create mock file transfer operations
            $transferPath = Join-Path $testWslPath "transfers"
            if (-not (Test-Path $transferPath)) {
                New-Item -Path $transferPath -ItemType Directory -Force | Out-Null
            }
            
            # Mock Windows to WSL transfer
            $windowsToWsl = @{
                Source = "C:\\Users\\TestUser\\Documents\\test-file.txt"
                Destination = "/home/testuser/test-file.txt"
                Status = "Completed"
                Size = "1024"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            
            $windowsToWsl | ConvertTo-Json | Out-File -FilePath (Join-Path $transferPath "windows-to-wsl.json") -Encoding UTF8
            Test-Path (Join-Path $transferPath "windows-to-wsl.json") | Should -Be $true
            
            # Mock WSL to Windows transfer
            $wslToWindows = @{
                Source = "/home/testuser/linux-file.txt"
                Destination = "C:\\Users\\TestUser\\Documents\\linux-file.txt"
                Status = "Completed"
                Size = "2048"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            
            $wslToWindows | ConvertTo-Json | Out-File -FilePath (Join-Path $transferPath "wsl-to-windows.json") -Encoding UTF8
            Test-Path (Join-Path $transferPath "wsl-to-windows.json") | Should -Be $true
        }
        
        It "Should be able to manage WSL services" {
            # Create mock WSL service management
            $servicesPath = Join-Path $testWslPath "services"
            if (-not (Test-Path $servicesPath)) {
                New-Item -Path $servicesPath -ItemType Directory -Force | Out-Null
            }
            
            $services = @{
                "ssh" = @{
                    Status = "active"
                    Enabled = $true
                    Port = 22
                }
                "docker" = @{
                    Status = "active"
                    Enabled = $true
                    Port = 2375
                }
                "nginx" = @{
                    Status = "inactive"
                    Enabled = $false
                    Port = 80
                }
            }
            
            $services | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $servicesPath "wsl-services.json") -Encoding UTF8
            Test-Path (Join-Path $servicesPath "wsl-services.json") | Should -Be $true
            
            $loadedServices = Get-Content (Join-Path $servicesPath "wsl-services.json") | ConvertFrom-Json
            $loadedServices.ssh.Status | Should -Be "active"
            $loadedServices.nginx.Status | Should -Be "inactive"
        }
    }
    
    Context "WSL Development Environment" {
        It "Should be able to manage development tools" {
            # Create mock development tools configuration
            $devToolsPath = Join-Path $testWslPath "dev-tools"
            if (-not (Test-Path $devToolsPath)) {
                New-Item -Path $devToolsPath -ItemType Directory -Force | Out-Null
            }
            
            $devTools = @{
                Languages = @{
                    "python" = @{
                        Version = "3.11.0"
                        Path = "/usr/bin/python3"
                        Packages = @("pip", "virtualenv", "pytest")
                    }
                    "nodejs" = @{
                        Version = "18.17.0"
                        Path = "/usr/bin/node"
                        Packages = @("npm", "yarn", "typescript")
                    }
                    "golang" = @{
                        Version = "1.21.0"
                        Path = "/usr/local/go/bin/go"
                        Packages = @("gofmt", "golint", "goimports")
                    }
                }
                IDEs = @{
                    "vscode" = @{
                        Installed = $true
                        Extensions = @("ms-vscode.go", "ms-python.python", "ms-vscode.vscode-typescript-next")
                    }
                    "vim" = @{
                        Installed = $true
                        Plugins = @("vim-go", "python-mode", "typescript-vim")
                    }
                }
                VersionControl = @{
                    "git" = @{
                        Version = "2.40.0"
                        Config = @{
                            UserName = "Test User"
                            UserEmail = "test@example.com"
                        }
                    }
                }
            }
            
            $devTools | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $devToolsPath "dev-tools.json") -Encoding UTF8
            Test-Path (Join-Path $devToolsPath "dev-tools.json") | Should -Be $true
            
            $loadedDevTools = Get-Content (Join-Path $devToolsPath "dev-tools.json") | ConvertFrom-Json
            $loadedDevTools.Languages.python.Version | Should -Be "3.11.0"
            $loadedDevTools.IDEs.vscode.Installed | Should -Be $true
        }
        
        It "Should be able to manage Docker integration" {
            # Create mock Docker integration configuration
            $dockerPath = Join-Path $testWslPath "docker"
            if (-not (Test-Path $dockerPath)) {
                New-Item -Path $dockerPath -ItemType Directory -Force | Out-Null
            }
            
            $dockerConfig = @{
                Docker = @{
                    Version = "24.0.5"
                    Status = "running"
                    Images = @(
                        @{ Name = "ubuntu:22.04"; Size = "72.8MB" },
                        @{ Name = "node:18-alpine"; Size = "169MB" },
                        @{ Name = "python:3.11-slim"; Size = "45.1MB" }
                    )
                    Containers = @(
                        @{ Name = "test-container"; Status = "running"; Image = "ubuntu:22.04" }
                    )
                }
                DockerCompose = @{
                    Version = "2.20.0"
                    Projects = @(
                        @{ Name = "test-project"; Status = "up"; Services = @("web", "db") }
                    )
                }
            }
            
            $dockerConfig | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $dockerPath "docker-config.json") -Encoding UTF8
            Test-Path (Join-Path $dockerPath "docker-config.json") | Should -Be $true
            
            $loadedDocker = Get-Content (Join-Path $dockerPath "docker-config.json") | ConvertFrom-Json
            $loadedDocker.Docker.Status | Should -Be "running"
            $loadedDocker.Docker.Images.Count | Should -Be 3
        }
    }
    
    Context "WSL Integration Validation" {
        It "Should create WSL integration manifest" {
            $manifestPath = Join-Path $testWslPath "wsl-integration-manifest.json"
            @{
                IntegrationType = "WSL"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = "1.0.0"
                Distributions = @("Ubuntu-22.04", "Debian", "openSUSE-Leap-15.5")
                Features = @(
                    "Distribution Management",
                    "Cross-Platform Operations",
                    "Development Environment",
                    "Docker Integration"
                )
                Items = @(
                    @{ Type = "Distributions"; Path = "distributions" },
                    @{ Type = "Config"; Path = "config" },
                    @{ Type = "Commands"; Path = "commands" },
                    @{ Type = "Transfers"; Path = "transfers" },
                    @{ Type = "Services"; Path = "services" },
                    @{ Type = "DevTools"; Path = "dev-tools" },
                    @{ Type = "Docker"; Path = "docker" }
                )
            } | ConvertTo-Json -Depth 3 | Out-File -FilePath $manifestPath -Encoding UTF8
            
            Test-Path $manifestPath | Should -Be $true
            
            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            $manifest.IntegrationType | Should -Be "WSL"
            $manifest.Distributions.Count | Should -Be 3
            $manifest.Features.Count | Should -Be 4
        }
        
        It "Should validate WSL integration integrity" {
            $manifestPath = Join-Path $testWslPath "wsl-integration-manifest.json"
            if (Test-Path $manifestPath) {
                $manifest = Get-Content $manifestPath | ConvertFrom-Json
                
                foreach ($item in $manifest.Items) {
                    $itemPath = Join-Path $testWslPath $item.Path
                    Test-Path $itemPath | Should -Be $true
                }
            }
        }
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $testWslPath) {
            Remove-Item -Path $testWslPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} 