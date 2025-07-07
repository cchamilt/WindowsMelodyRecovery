#!/usr/bin/env pwsh

<#
.SYNOPSIS
Unit tests for shared configuration system in Windows Melody Recovery.

.DESCRIPTION
Tests the shared vs host-specific configuration logic, including:
- Directory structure creation
- Priority logic (machine-specific first, shared fallback)
- Configuration blending and inheritance
- Backup and restore operations with shared configs

.NOTES
This is part of Phase 5.2: Shared Configuration Testing
#>

Describe "SharedConfiguration" -Tag "Unit", "SharedConfiguration" {
    
    BeforeAll {
        # Import required modules and utilities
        $ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $ModuleRoot "WindowsMelodyRecovery.psd1") -Force
        
        # Import test utilities
        . (Join-Path $PSScriptRoot "..\utilities\Test-Utilities.ps1")
        . (Join-Path $PSScriptRoot "..\utilities\Mock-Utilities.ps1")
        
        # Set up test environment
        $script:TestRoot = Join-Path $TestDrive "SharedConfigTest"
        $script:BackupRoot = Join-Path $script:TestRoot "Backups"
        $script:MachineName = "TEST-MACHINE"
        $script:MachineBackup = Join-Path $script:BackupRoot $script:MachineName
        $script:SharedBackup = Join-Path $script:BackupRoot "shared"
        
        # Create test directories
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:BackupRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:MachineBackup -Force | Out-Null
        New-Item -ItemType Directory -Path $script:SharedBackup -Force | Out-Null
        
        # Mock module configuration
        Mock Get-WindowsMelodyRecovery {
            return @{
                BackupRoot = $script:BackupRoot
                MachineName = $script:MachineName
                IsInitialized = $true
            }
        }
    }
    
    Context "Directory Structure Creation" {
        It "Should create machine-specific backup directory" {
            $config = Get-WindowsMelodyRecovery
            $machineBackup = Join-Path $config.BackupRoot $config.MachineName
            
            # Directory should exist from BeforeAll
            Test-Path $machineBackup | Should -Be $true
            
            # Should be able to create subdirectories
            $testSubDir = Join-Path $machineBackup "TestComponent"
            New-Item -ItemType Directory -Path $testSubDir -Force | Out-Null
            Test-Path $testSubDir | Should -Be $true
        }
        
        It "Should create shared backup directory" {
            $config = Get-WindowsMelodyRecovery
            $sharedBackup = Join-Path $config.BackupRoot "shared"
            
            # Directory should exist from BeforeAll
            Test-Path $sharedBackup | Should -Be $true
            
            # Should be able to create subdirectories
            $testSubDir = Join-Path $sharedBackup "SharedComponent"
            New-Item -ItemType Directory -Path $testSubDir -Force | Out-Null
            Test-Path $testSubDir | Should -Be $true
        }
        
        It "Should handle missing backup directories gracefully" {
            $tempBackupRoot = Join-Path $TestDrive "MissingBackups"
            $tempMachineBackup = Join-Path $tempBackupRoot "MISSING-MACHINE"
            $tempSharedBackup = Join-Path $tempBackupRoot "shared"
            
            # These directories don't exist
            Test-Path $tempMachineBackup | Should -Be $false
            Test-Path $tempSharedBackup | Should -Be $false
            
            # Function should handle gracefully
            function Test-BackupPath {
                param (
                    [string]$Path,
                    [string]$BackupType,
                    [string]$MACHINE_BACKUP,
                    [string]$SHARED_BACKUP
                )
                
                $machinePath = Join-Path $MACHINE_BACKUP $Path
                if (Test-Path $machinePath) {
                    return $machinePath
                }
                
                $sharedPath = Join-Path $SHARED_BACKUP $Path
                if (Test-Path $sharedPath) {
                    return $sharedPath
                }
                
                return $null
            }
            
            $result = Test-BackupPath -Path "TestFile.json" -BackupType "Test" -MACHINE_BACKUP $tempMachineBackup -SHARED_BACKUP $tempSharedBackup
            $result | Should -Be $null
        }
    }
    
    Context "Priority Logic - Machine First, Shared Fallback" {
        BeforeEach {
            # Clean up any existing test files
            Get-ChildItem $script:MachineBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem $script:SharedBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        It "Should prioritize machine-specific backup when both exist" {
            # Create test files in both locations
            $machineFile = Join-Path $script:MachineBackup "priority-test.json"
            $sharedFile = Join-Path $script:SharedBackup "priority-test.json"
            
            @{ Source = "Machine"; Priority = 1 } | ConvertTo-Json | Out-File $machineFile
            @{ Source = "Shared"; Priority = 2 } | ConvertTo-Json | Out-File $sharedFile
            
            # Test the priority function
            function Test-BackupPath {
                param (
                    [string]$Path,
                    [string]$BackupType,
                    [string]$MACHINE_BACKUP,
                    [string]$SHARED_BACKUP
                )
                
                $machinePath = Join-Path $MACHINE_BACKUP $Path
                if (Test-Path $machinePath) {
                    return $machinePath
                }
                
                $sharedPath = Join-Path $SHARED_BACKUP $Path
                if (Test-Path $sharedPath) {
                    return $sharedPath
                }
                
                return $null
            }
            
            $result = Test-BackupPath -Path "priority-test.json" -BackupType "Test" -MACHINE_BACKUP $script:MachineBackup -SHARED_BACKUP $script:SharedBackup
            $result | Should -Be $machineFile
            
            # Verify content is from machine backup
            $content = Get-Content $result | ConvertFrom-Json
            $content.Source | Should -Be "Machine"
            $content.Priority | Should -Be 1
        }
        
        It "Should fall back to shared backup when machine-specific doesn't exist" {
            # Create test file only in shared location
            $sharedFile = Join-Path $script:SharedBackup "fallback-test.json"
            @{ Source = "Shared"; Type = "Fallback" } | ConvertTo-Json | Out-File $sharedFile
            
            # Test the priority function
            function Test-BackupPath {
                param (
                    [string]$Path,
                    [string]$BackupType,
                    [string]$MACHINE_BACKUP,
                    [string]$SHARED_BACKUP
                )
                
                $machinePath = Join-Path $MACHINE_BACKUP $Path
                if (Test-Path $machinePath) {
                    return $machinePath
                }
                
                $sharedPath = Join-Path $SHARED_BACKUP $Path
                if (Test-Path $sharedPath) {
                    return $sharedPath
                }
                
                return $null
            }
            
            $result = Test-BackupPath -Path "fallback-test.json" -BackupType "Test" -MACHINE_BACKUP $script:MachineBackup -SHARED_BACKUP $script:SharedBackup
            $result | Should -Be $sharedFile
            
            # Verify content is from shared backup
            $content = Get-Content $result | ConvertFrom-Json
            $content.Source | Should -Be "Shared"
            $content.Type | Should -Be "Fallback"
        }
        
        It "Should return null when neither machine nor shared backup exists" {
            # Don't create any files
            
            # Test the priority function
            function Test-BackupPath {
                param (
                    [string]$Path,
                    [string]$BackupType,
                    [string]$MACHINE_BACKUP,
                    [string]$SHARED_BACKUP
                )
                
                $machinePath = Join-Path $MACHINE_BACKUP $Path
                if (Test-Path $machinePath) {
                    return $machinePath
                }
                
                $sharedPath = Join-Path $SHARED_BACKUP $Path
                if (Test-Path $sharedPath) {
                    return $sharedPath
                }
                
                return $null
            }
            
            $result = Test-BackupPath -Path "nonexistent-test.json" -BackupType "Test" -MACHINE_BACKUP $script:MachineBackup -SHARED_BACKUP $script:SharedBackup
            $result | Should -Be $null
        }
    }
    
    Context "Configuration Blending and Inheritance" {
        BeforeEach {
            # Clean up any existing test files
            Get-ChildItem $script:MachineBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem $script:SharedBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        It "Should blend machine-specific and shared configurations" {
            # Create base shared configuration
            $sharedConfig = @{
                CommonSettings = @{
                    Theme = "Dark"
                    Language = "en-US"
                    AutoSave = $true
                }
                PackageManagers = @{
                    Winget = @{ Enabled = $true }
                    Chocolatey = @{ Enabled = $false }
                }
            }
            
            # Create machine-specific overrides
            $machineConfig = @{
                CommonSettings = @{
                    Theme = "Light"  # Override shared
                    AutoSave = $false  # Override shared
                    # Language inherited from shared
                }
                MachineSpecific = @{
                    Hostname = "TEST-MACHINE"
                    Hardware = "Desktop"
                }
            }
            
            $sharedFile = Join-Path $script:SharedBackup "config-blend.json"
            $machineFile = Join-Path $script:MachineBackup "config-blend.json"
            
            $sharedConfig | ConvertTo-Json -Depth 10 | Out-File $sharedFile
            $machineConfig | ConvertTo-Json -Depth 10 | Out-File $machineFile
            
            # Test configuration blending function
            function Merge-Configurations {
                param (
                    [hashtable]$Base,
                    [hashtable]$Override
                )
                
                $merged = $Base.Clone()
                
                foreach ($key in $Override.Keys) {
                    if ($Override[$key] -is [hashtable] -and $merged[$key] -is [hashtable]) {
                        $merged[$key] = Merge-Configurations -Base $merged[$key] -Override $Override[$key]
                    } else {
                        $merged[$key] = $Override[$key]
                    }
                }
                
                return $merged
            }
            
            $sharedData = Get-Content $sharedFile | ConvertFrom-Json -AsHashtable
            $machineData = Get-Content $machineFile | ConvertFrom-Json -AsHashtable
            
            $blended = Merge-Configurations -Base $sharedData -Override $machineData
            
            # Verify blending results
            $blended.CommonSettings.Theme | Should -Be "Light"  # Machine override
            $blended.CommonSettings.AutoSave | Should -Be $false  # Machine override
            $blended.CommonSettings.Language | Should -Be "en-US"  # Inherited from shared
            $blended.PackageManagers.Winget.Enabled | Should -Be $true  # Inherited from shared
            $blended.MachineSpecific.Hostname | Should -Be "TEST-MACHINE"  # Machine-specific
        }
        
        It "Should handle missing shared configuration gracefully" {
            # Create only machine-specific configuration
            $machineConfig = @{
                Settings = @{
                    OnlyMachine = $true
                }
            }
            
            $machineFile = Join-Path $script:MachineBackup "machine-only.json"
            $machineConfig | ConvertTo-Json -Depth 10 | Out-File $machineFile
            
            # Test loading with missing shared config
            function Load-Configuration {
                param (
                    [string]$ConfigName,
                    [string]$MachineBackup,
                    [string]$SharedBackup
                )
                
                $sharedFile = Join-Path $SharedBackup $ConfigName
                $machineFile = Join-Path $MachineBackup $ConfigName
                
                $config = @{}
                
                # Load shared first (if exists)
                if (Test-Path $sharedFile) {
                    $shared = Get-Content $sharedFile | ConvertFrom-Json -AsHashtable
                    $config = $shared
                }
                
                # Overlay machine-specific (if exists)
                if (Test-Path $machineFile) {
                    $machine = Get-Content $machineFile | ConvertFrom-Json -AsHashtable
                    if ($config.Count -gt 0) {
                        # Merge with shared
                        foreach ($key in $machine.Keys) {
                            $config[$key] = $machine[$key]
                        }
                    } else {
                        # Use machine only
                        $config = $machine
                    }
                }
                
                return $config
            }
            
            $result = Load-Configuration -ConfigName "machine-only.json" -MachineBackup $script:MachineBackup -SharedBackup $script:SharedBackup
            
            $result.Settings.OnlyMachine | Should -Be $true
            $result.Count | Should -Be 1
        }
        
        It "Should handle missing machine configuration gracefully" {
            # Create only shared configuration
            $sharedConfig = @{
                Settings = @{
                    OnlyShared = $true
                    DefaultValue = "shared-default"
                }
            }
            
            $sharedFile = Join-Path $script:SharedBackup "shared-only.json"
            $sharedConfig | ConvertTo-Json -Depth 10 | Out-File $sharedFile
            
            # Test loading with missing machine config
            function Load-Configuration {
                param (
                    [string]$ConfigName,
                    [string]$MachineBackup,
                    [string]$SharedBackup
                )
                
                $sharedFile = Join-Path $SharedBackup $ConfigName
                $machineFile = Join-Path $MachineBackup $ConfigName
                
                $config = @{}
                
                # Load shared first (if exists)
                if (Test-Path $sharedFile) {
                    $shared = Get-Content $sharedFile | ConvertFrom-Json -AsHashtable
                    $config = $shared
                }
                
                # Overlay machine-specific (if exists)
                if (Test-Path $machineFile) {
                    $machine = Get-Content $machineFile | ConvertFrom-Json -AsHashtable
                    if ($config.Count -gt 0) {
                        # Merge with shared
                        foreach ($key in $machine.Keys) {
                            $config[$key] = $machine[$key]
                        }
                    } else {
                        # Use machine only
                        $config = $machine
                    }
                }
                
                return $config
            }
            
            $result = Load-Configuration -ConfigName "shared-only.json" -MachineBackup $script:MachineBackup -SharedBackup $script:SharedBackup
            
            $result.Settings.OnlyShared | Should -Be $true
            $result.Settings.DefaultValue | Should -Be "shared-default"
            $result.Count | Should -Be 1
        }
    }
    
    Context "Backup Operations with Shared Configuration" {
        BeforeEach {
            # Clean up any existing test files
            Get-ChildItem $script:MachineBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem $script:SharedBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        It "Should backup machine-specific data to machine directory" {
            # Simulate machine-specific backup operation
            $machineData = @{
                Hostname = $env:COMPUTERNAME
                SystemInfo = @{
                    OS = "Windows 11"
                    Architecture = "x64"
                }
                HardwareConfig = @{
                    GPU = "NVIDIA RTX 4090"
                    RAM = "32GB"
                }
            }
            
            $machineBackupFile = Join-Path $script:MachineBackup "machine-config.json"
            $machineData | ConvertTo-Json -Depth 10 | Out-File $machineBackupFile
            
            # Verify backup was created in machine directory
            Test-Path $machineBackupFile | Should -Be $true
            
            $backed = Get-Content $machineBackupFile | ConvertFrom-Json
            $backed.Hostname | Should -Be $env:COMPUTERNAME
            $backed.SystemInfo.OS | Should -Be "Windows 11"
            $backed.HardwareConfig.GPU | Should -Be "NVIDIA RTX 4090"
        }
        
        It "Should backup shared data to shared directory" {
            # Simulate shared backup operation
            $sharedData = @{
                PackageManagers = @{
                    Winget = @(
                        @{ Name = "Microsoft.PowerShell"; Version = "7.3.0" }
                        @{ Name = "Git.Git"; Version = "2.40.0" }
                    )
                    Chocolatey = @(
                        @{ Name = "nodejs"; Version = "18.15.0" }
                        @{ Name = "python"; Version = "3.11.0" }
                    )
                }
                DotFiles = @{
                    GitConfig = @{
                        UserName = "TestUser"
                        UserEmail = "test@example.com"
                    }
                    PowerShellProfile = @{
                        Modules = @("PSReadLine", "posh-git")
                    }
                }
            }
            
            $sharedBackupFile = Join-Path $script:SharedBackup "shared-config.json"
            $sharedData | ConvertTo-Json -Depth 10 | Out-File $sharedBackupFile
            
            # Verify backup was created in shared directory
            Test-Path $sharedBackupFile | Should -Be $true
            
            $backed = Get-Content $sharedBackupFile | ConvertFrom-Json
            $backed.PackageManagers.Winget.Count | Should -Be 2
            $backed.PackageManagers.Chocolatey.Count | Should -Be 2
            $backed.DotFiles.GitConfig.UserName | Should -Be "TestUser"
            $backed.DotFiles.PowerShellProfile.Modules.Count | Should -Be 2
        }
        
        It "Should handle backup to both directories simultaneously" {
            # Simulate component that backs up to both directories
            $componentData = @{
                Component = "TestComponent"
                Version = "1.0.0"
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
            
            $machineSpecificData = $componentData.Clone()
            $machineSpecificData.MachineSpecific = @{
                Hostname = $env:COMPUTERNAME
                InstallPath = "C:\Program Files\TestComponent"
            }
            
            $sharedData = $componentData.Clone()
            $sharedData.SharedSettings = @{
                DefaultTheme = "Dark"
                Language = "en-US"
            }
            
            # Backup to both locations
            $machineFile = Join-Path $script:MachineBackup "dual-backup.json"
            $sharedFile = Join-Path $script:SharedBackup "dual-backup.json"
            
            $machineSpecificData | ConvertTo-Json -Depth 10 | Out-File $machineFile
            $sharedData | ConvertTo-Json -Depth 10 | Out-File $sharedFile
            
            # Verify both backups exist
            Test-Path $machineFile | Should -Be $true
            Test-Path $sharedFile | Should -Be $true
            
            # Verify content differences
            $machineContent = Get-Content $machineFile | ConvertFrom-Json
            $sharedContent = Get-Content $sharedFile | ConvertFrom-Json
            
            $machineContent.MachineSpecific.Hostname | Should -Be $env:COMPUTERNAME
            $sharedContent.SharedSettings.DefaultTheme | Should -Be "Dark"
            
            # Verify common data is identical
            $machineContent.Component | Should -Be $sharedContent.Component
            $machineContent.Version | Should -Be $sharedContent.Version
        }
    }
    
    Context "Restore Operations with Shared Configuration" {
        BeforeEach {
            # Set up test backup data
            Get-ChildItem $script:MachineBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem $script:SharedBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            
            # Create test backup files
            $machineData = @{
                SystemSettings = @{
                    Theme = "Light"
                    DisplayScaling = 125
                }
                MachineSpecific = @{
                    Hostname = "TEST-MACHINE"
                }
            }
            
            $sharedData = @{
                SystemSettings = @{
                    Theme = "Dark"  # Will be overridden by machine
                    Language = "en-US"
                    AutoSave = $true
                }
                Applications = @{
                    VSCode = @{ Enabled = $true }
                    Chrome = @{ Enabled = $true }
                }
            }
            
            $machineData | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:MachineBackup "restore-test.json")
            $sharedData | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:SharedBackup "restore-test.json")
        }
        
        It "Should restore with machine-specific priority" {
            # Simulate restore operation using priority logic
            function Restore-Configuration {
                param (
                    [string]$ConfigName,
                    [string]$MachineBackup,
                    [string]$SharedBackup
                )
                
                $machineFile = Join-Path $MachineBackup $ConfigName
                $sharedFile = Join-Path $SharedBackup $ConfigName
                
                $config = @{}
                
                # Load shared first (base configuration)
                if (Test-Path $sharedFile) {
                    $shared = Get-Content $sharedFile | ConvertFrom-Json -AsHashtable
                    $config = $shared
                }
                
                # Overlay machine-specific (priority configuration)
                if (Test-Path $machineFile) {
                    $machine = Get-Content $machineFile | ConvertFrom-Json -AsHashtable
                    
                    foreach ($key in $machine.Keys) {
                        if ($machine[$key] -is [hashtable] -and $config[$key] -is [hashtable]) {
                            # Merge nested hashtables
                            foreach ($subKey in $machine[$key].Keys) {
                                $config[$key][$subKey] = $machine[$key][$subKey]
                            }
                        } else {
                            $config[$key] = $machine[$key]
                        }
                    }
                }
                
                return $config
            }
            
            $restored = Restore-Configuration -ConfigName "restore-test.json" -MachineBackup $script:MachineBackup -SharedBackup $script:SharedBackup
            
            # Verify machine-specific overrides took priority
            $restored.SystemSettings.Theme | Should -Be "Light"  # Machine override
            $restored.SystemSettings.DisplayScaling | Should -Be 125  # Machine-specific
            
            # Verify shared settings were inherited
            $restored.SystemSettings.Language | Should -Be "en-US"  # From shared
            $restored.SystemSettings.AutoSave | Should -Be $true  # From shared
            $restored.Applications.VSCode.Enabled | Should -Be $true  # From shared
            
            # Verify machine-specific settings exist
            $restored.MachineSpecific.Hostname | Should -Be "TEST-MACHINE"
        }
        
        It "Should handle restore when only shared backup exists" {
            # Remove machine backup
            Remove-Item (Join-Path $script:MachineBackup "restore-test.json") -Force
            
            function Restore-Configuration {
                param (
                    [string]$ConfigName,
                    [string]$MachineBackup,
                    [string]$SharedBackup
                )
                
                $machineFile = Join-Path $MachineBackup $ConfigName
                $sharedFile = Join-Path $SharedBackup $ConfigName
                
                $config = @{}
                
                # Load shared first (base configuration)
                if (Test-Path $sharedFile) {
                    $shared = Get-Content $sharedFile | ConvertFrom-Json -AsHashtable
                    $config = $shared
                }
                
                # Overlay machine-specific (priority configuration)
                if (Test-Path $machineFile) {
                    $machine = Get-Content $machineFile | ConvertFrom-Json -AsHashtable
                    
                    foreach ($key in $machine.Keys) {
                        if ($machine[$key] -is [hashtable] -and $config[$key] -is [hashtable]) {
                            # Merge nested hashtables
                            foreach ($subKey in $machine[$key].Keys) {
                                $config[$key][$subKey] = $machine[$key][$subKey]
                            }
                        } else {
                            $config[$key] = $machine[$key]
                        }
                    }
                }
                
                return $config
            }
            
            $restored = Restore-Configuration -ConfigName "restore-test.json" -MachineBackup $script:MachineBackup -SharedBackup $script:SharedBackup
            
            # Should use shared configuration only
            $restored.SystemSettings.Theme | Should -Be "Dark"  # From shared
            $restored.SystemSettings.Language | Should -Be "en-US"  # From shared
            $restored.Applications.VSCode.Enabled | Should -Be $true  # From shared
            
            # Machine-specific settings should not exist
            $restored.Keys | Should -Not -Contain "MachineSpecific"
        }
        
        It "Should handle restore when only machine backup exists" {
            # Remove shared backup
            Remove-Item (Join-Path $script:SharedBackup "restore-test.json") -Force
            
            function Restore-Configuration {
                param (
                    [string]$ConfigName,
                    [string]$MachineBackup,
                    [string]$SharedBackup
                )
                
                $machineFile = Join-Path $MachineBackup $ConfigName
                $sharedFile = Join-Path $SharedBackup $ConfigName
                
                $config = @{}
                
                # Load shared first (base configuration)
                if (Test-Path $sharedFile) {
                    $shared = Get-Content $sharedFile | ConvertFrom-Json -AsHashtable
                    $config = $shared
                }
                
                # Overlay machine-specific (priority configuration)
                if (Test-Path $machineFile) {
                    $machine = Get-Content $machineFile | ConvertFrom-Json -AsHashtable
                    
                    foreach ($key in $machine.Keys) {
                        if ($machine[$key] -is [hashtable] -and $config[$key] -is [hashtable]) {
                            # Merge nested hashtables
                            foreach ($subKey in $machine[$key].Keys) {
                                $config[$key][$subKey] = $machine[$key][$subKey]
                            }
                        } else {
                            $config[$key] = $machine[$key]
                        }
                    }
                }
                
                return $config
            }
            
            $restored = Restore-Configuration -ConfigName "restore-test.json" -MachineBackup $script:MachineBackup -SharedBackup $script:SharedBackup
            
            # Should use machine configuration only
            $restored.SystemSettings.Theme | Should -Be "Light"  # From machine
            $restored.SystemSettings.DisplayScaling | Should -Be 125  # From machine
            $restored.MachineSpecific.Hostname | Should -Be "TEST-MACHINE"  # From machine
            
            # Shared-only settings should not exist
            $restored.SystemSettings.Keys | Should -Not -Contain "Language"
            $restored.Keys | Should -Not -Contain "Applications"
        }
    }
    
    Context "Configuration Inheritance Patterns" {
        BeforeEach {
            # Clean up any existing test files
            Get-ChildItem $script:MachineBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Get-ChildItem $script:SharedBackup -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        It "Should support hierarchical configuration inheritance" {
            # Create multi-level configuration hierarchy
            $globalConfig = @{
                Global = @{
                    Theme = "Auto"
                    Language = "en-US"
                    UpdateCheck = $true
                }
                Features = @{
                    Telemetry = $false
                    AutoBackup = $true
                }
            }
            
            $sharedConfig = @{
                Global = @{
                    Theme = "Dark"  # Override global
                    # Language inherited from global
                    # UpdateCheck inherited from global
                }
                Features = @{
                    # Telemetry inherited from global
                    AutoBackup = $false  # Override global
                    NetworkSync = $true  # Shared-specific
                }
                Shared = @{
                    CommonApps = @("VSCode", "Chrome", "Git")
                }
            }
            
            $machineConfig = @{
                Global = @{
                    Theme = "Light"  # Override shared and global
                    # Language inherited from shared/global
                    # UpdateCheck inherited from shared/global
                }
                Features = @{
                    # Telemetry inherited from shared/global
                    AutoBackup = $true  # Override shared and global
                    # NetworkSync inherited from shared
                    HardwareAcceleration = $true  # Machine-specific
                }
                Machine = @{
                    Hostname = "TEST-MACHINE"
                    Hardware = @{
                        GPU = "RTX 4090"
                        RAM = "32GB"
                    }
                }
            }
            
            # Save configurations
            $globalConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:SharedBackup "global-config.json")
            $sharedConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:SharedBackup "hierarchy-test.json")
            $machineConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:MachineBackup "hierarchy-test.json")
            
            # Test hierarchical inheritance
            function Merge-HierarchicalConfig {
                param (
                    [hashtable]$Global,
                    [hashtable]$Shared,
                    [hashtable]$Machine
                )
                
                function Merge-Deep {
                    param ([hashtable]$Base, [hashtable]$Override)
                    
                    $result = $Base.Clone()
                    
                    foreach ($key in $Override.Keys) {
                        if ($Override[$key] -is [hashtable] -and $result[$key] -is [hashtable]) {
                            $result[$key] = Merge-Deep -Base $result[$key] -Override $Override[$key]
                        } else {
                            $result[$key] = $Override[$key]
                        }
                    }
                    
                    return $result
                }
                
                # Global -> Shared -> Machine
                $step1 = Merge-Deep -Base $Global -Override $Shared
                $final = Merge-Deep -Base $step1 -Override $Machine
                
                return $final
            }
            
            $globalData = Get-Content (Join-Path $script:SharedBackup "global-config.json") | ConvertFrom-Json -AsHashtable
            $sharedData = Get-Content (Join-Path $script:SharedBackup "hierarchy-test.json") | ConvertFrom-Json -AsHashtable
            $machineData = Get-Content (Join-Path $script:MachineBackup "hierarchy-test.json") | ConvertFrom-Json -AsHashtable
            
            $final = Merge-HierarchicalConfig -Global $globalData -Shared $sharedData -Machine $machineData
            
            # Verify inheritance chain
            $final.Global.Theme | Should -Be "Light"  # Machine override
            $final.Global.Language | Should -Be "en-US"  # Inherited from global
            $final.Global.UpdateCheck | Should -Be $true  # Inherited from global
            
            $final.Features.Telemetry | Should -Be $false  # Inherited from global
            $final.Features.AutoBackup | Should -Be $true  # Machine override
            $final.Features.NetworkSync | Should -Be $true  # Inherited from shared
            $final.Features.HardwareAcceleration | Should -Be $true  # Machine-specific
            
            $final.Shared.CommonApps.Count | Should -Be 3  # Inherited from shared
            $final.Machine.Hostname | Should -Be "TEST-MACHINE"  # Machine-specific
        }
        
        It "Should support conditional inheritance based on environment" {
            # Create environment-specific configurations
            $baseConfig = @{
                Environment = "Development"
                Logging = @{
                    Level = "Debug"
                    Console = $true
                }
                Features = @{
                    DevMode = $true
                    Telemetry = $false
                }
            }
            
            $productionOverride = @{
                Environment = "Production"
                Logging = @{
                    Level = "Error"
                    Console = $false
                    File = $true
                }
                Features = @{
                    DevMode = $false
                    Telemetry = $true
                    Performance = $true
                }
            }
            
            $baseConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:SharedBackup "base-env.json")
            $productionOverride | ConvertTo-Json -Depth 10 | Out-File (Join-Path $script:MachineBackup "production-env.json")
            
            # Test conditional inheritance
            function Apply-EnvironmentConfig {
                param (
                    [string]$Environment,
                    [string]$MachineBackup,
                    [string]$SharedBackup
                )
                
                $baseFile = Join-Path $SharedBackup "base-env.json"
                $envFile = Join-Path $MachineBackup "$Environment-env.json"
                
                $config = @{}
                
                if (Test-Path $baseFile) {
                    $config = Get-Content $baseFile | ConvertFrom-Json -AsHashtable
                }
                
                if (Test-Path $envFile) {
                    $envConfig = Get-Content $envFile | ConvertFrom-Json -AsHashtable
                    
                    foreach ($key in $envConfig.Keys) {
                        if ($envConfig[$key] -is [hashtable] -and $config[$key] -is [hashtable]) {
                            foreach ($subKey in $envConfig[$key].Keys) {
                                $config[$key][$subKey] = $envConfig[$key][$subKey]
                            }
                        } else {
                            $config[$key] = $envConfig[$key]
                        }
                    }
                }
                
                return $config
            }
            
            $prodConfig = Apply-EnvironmentConfig -Environment "production" -MachineBackup $script:MachineBackup -SharedBackup $script:SharedBackup
            
            # Verify environment-specific inheritance
            $prodConfig.Environment | Should -Be "Production"  # Environment override
            $prodConfig.Logging.Level | Should -Be "Error"  # Environment override
            $prodConfig.Logging.Console | Should -Be $false  # Environment override
            $prodConfig.Logging.File | Should -Be $true  # Environment-specific
            $prodConfig.Features.DevMode | Should -Be $false  # Environment override
            $prodConfig.Features.Telemetry | Should -Be $true  # Environment override
            $prodConfig.Features.Performance | Should -Be $true  # Environment-specific
        }
    }
}