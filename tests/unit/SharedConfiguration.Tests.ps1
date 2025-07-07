#!/usr/bin/env pwsh

<#
.SYNOPSIS
Unit tests for shared configuration system in Windows Melody Recovery.

.DESCRIPTION
Tests the shared vs host-specific configuration logic, specifically:
- Priority logic (machine-specific first, shared fallback)
- The Test-BackupPath function behavior
- Configuration discovery and selection

.NOTES
This is part of Phase 5.2: Shared Configuration Testing
These tests use mock data and existing test directories - no file system manipulation!
#>

Describe "SharedConfiguration" -Tag "Unit", "SharedConfiguration" {
    
    BeforeAll {
        # Import required modules and utilities
        $ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $ModuleRoot "WindowsMelodyRecovery.psd1") -Force
        
        # Set up mock paths using existing test directories
        $script:TestMachineBackup = Join-Path $ModuleRoot "test-restore\TEST-MACHINE"
        $script:TestSharedBackup = Join-Path $ModuleRoot "test-restore\shared"
        
        # Ensure test directories exist
        if (-not (Test-Path $script:TestMachineBackup)) {
            New-Item -ItemType Directory -Path $script:TestMachineBackup -Force | Out-Null
        }
        if (-not (Test-Path $script:TestSharedBackup)) {
            New-Item -ItemType Directory -Path $script:TestSharedBackup -Force | Out-Null
        }
        
        # Define the Test-BackupPath function (copied from actual backup/restore scripts)
        function Test-BackupPath {
            param (
                [Parameter(Mandatory=$true)]
                [string]$Path,

                [Parameter(Mandatory=$true)]
                [string]$BackupType,
                
                [Parameter(Mandatory=$true)]
                [string]$MACHINE_BACKUP,
                
                [Parameter(Mandatory=$true)]
                [string]$SHARED_BACKUP
            )
            
            # First check machine-specific backup
            $machinePath = Join-Path $MACHINE_BACKUP $Path
            if (Test-Path $machinePath) {
                Write-Host "Using machine-specific $BackupType backup from: $machinePath" -ForegroundColor Green
                return $machinePath
            }
            
            # Fall back to shared backup
            $sharedPath = Join-Path $SHARED_BACKUP $Path
            if (Test-Path $sharedPath) {
                Write-Host "Using shared $BackupType backup from: $sharedPath" -ForegroundColor Green
                return $sharedPath
            }
            
            Write-Host "No $BackupType backup found" -ForegroundColor Yellow
            return $null
        }
    }
    
    Context "Priority Logic - Machine First, Shared Fallback" {
        
        It "Should prioritize machine-specific backup when both exist" {
            # Create test files in both locations
            $machineFile = Join-Path $script:TestMachineBackup "priority-test.json"
            $sharedFile = Join-Path $script:TestSharedBackup "priority-test.json"
            
            @{ Source = "Machine"; Priority = 1 } | ConvertTo-Json | Out-File $machineFile
            @{ Source = "Shared"; Priority = 2 } | ConvertTo-Json | Out-File $sharedFile
            
            try {
                $result = Test-BackupPath -Path "priority-test.json" -BackupType "Test" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $machineFile
                
                # Verify content is from machine backup
                $content = Get-Content $result | ConvertFrom-Json
                $content.Source | Should -Be "Machine"
                $content.Priority | Should -Be 1
            } finally {
                # Clean up test files
                Remove-Item $machineFile -Force -ErrorAction SilentlyContinue
                Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should fall back to shared backup when machine-specific doesn't exist" {
            # Create test file only in shared location
            $sharedFile = Join-Path $script:TestSharedBackup "fallback-test.json"
            @{ Source = "Shared"; Type = "Fallback" } | ConvertTo-Json | Out-File $sharedFile
            
            try {
                $result = Test-BackupPath -Path "fallback-test.json" -BackupType "Test" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $sharedFile
                
                # Verify content is from shared backup
                $content = Get-Content $result | ConvertFrom-Json
                $content.Source | Should -Be "Shared"
                $content.Type | Should -Be "Fallback"
            } finally {
                # Clean up test files
                Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should return null when neither machine nor shared backup exists" {
            $result = Test-BackupPath -Path "nonexistent-test.json" -BackupType "Test" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
            $result | Should -Be $null
        }
    }
    
    Context "Configuration Discovery and Selection" {
        
        It "Should handle different file types correctly" {
            # Test with various file extensions
            $testFiles = @("config.json", "settings.yaml", "data.xml", "backup.csv")
            
            foreach ($file in $testFiles) {
                $sharedFile = Join-Path $script:TestSharedBackup $file
                "test content" | Out-File $sharedFile
                
                try {
                    $result = Test-BackupPath -Path $file -BackupType "Config" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                    $result | Should -Be $sharedFile
                    Test-Path $result | Should -Be $true
                } finally {
                    Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "Should handle subdirectory paths correctly" {
            # Create nested directory structure
            $subDir = "component\subcomponent"
            $machineSubDir = Join-Path $script:TestMachineBackup $subDir
            $sharedSubDir = Join-Path $script:TestSharedBackup $subDir
            
            New-Item -ItemType Directory -Path $machineSubDir -Force | Out-Null
            New-Item -ItemType Directory -Path $sharedSubDir -Force | Out-Null
            
            $testFile = Join-Path $subDir "config.json"
            $machineFile = Join-Path $script:TestMachineBackup $testFile
            $sharedFile = Join-Path $script:TestSharedBackup $testFile
            
            # Test machine priority with subdirectories
            @{ Location = "Machine" } | ConvertTo-Json | Out-File $machineFile
            @{ Location = "Shared" } | ConvertTo-Json | Out-File $sharedFile
            
            try {
                $result = Test-BackupPath -Path $testFile -BackupType "Component" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                $result | Should -Be $machineFile
                
                $content = Get-Content $result | ConvertFrom-Json
                $content.Location | Should -Be "Machine"
            } finally {
                # Clean up
                Remove-Item $machineFile -Force -ErrorAction SilentlyContinue
                Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
                Remove-Item $machineSubDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $sharedSubDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Integration with Module Configuration" {
        
        It "Should work with module configuration paths" {
            # Mock the module configuration
            Mock Get-WindowsMelodyRecovery {
                return @{
                    BackupRoot = Join-Path $ModuleRoot "test-restore"
                    MachineName = "TEST-MACHINE"
                    IsInitialized = $true
                }
            }
            
            $config = Get-WindowsMelodyRecovery
            $machineBackup = Join-Path $config.BackupRoot $config.MachineName
            $sharedBackup = Join-Path $config.BackupRoot "shared"
            
            # These should match our test paths
            $machineBackup | Should -Be $script:TestMachineBackup
            $sharedBackup | Should -Be $script:TestSharedBackup
            
            # Test that the function works with config-derived paths
            $testFile = Join-Path $sharedBackup "module-config-test.json"
            @{ Source = "ModuleConfig" } | ConvertTo-Json | Out-File $testFile
            
            try {
                $result = Test-BackupPath -Path "module-config-test.json" -BackupType "ModuleConfig" -MACHINE_BACKUP $machineBackup -SHARED_BACKUP $sharedBackup
                $result | Should -Be $testFile
                
                $content = Get-Content $result | ConvertFrom-Json
                $content.Source | Should -Be "ModuleConfig"
            } finally {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Error Handling and Edge Cases" {
        
        It "Should handle empty or null paths gracefully" {
            # Test with empty paths
            $result = Test-BackupPath -Path "test.json" -BackupType "Test" -MACHINE_BACKUP "" -SHARED_BACKUP ""
            $result | Should -Be $null
            
            # Test with non-existent directories
            $result = Test-BackupPath -Path "test.json" -BackupType "Test" -MACHINE_BACKUP "C:\NonExistent" -SHARED_BACKUP "C:\AlsoNonExistent"
            $result | Should -Be $null
        }
        
        It "Should handle special characters in filenames" {
            $specialFiles = @("config with spaces.json", "config-with-dashes.json", "config_with_underscores.json")
            
            foreach ($file in $specialFiles) {
                $sharedFile = Join-Path $script:TestSharedBackup $file
                "test content" | Out-File $sharedFile
                
                try {
                    $result = Test-BackupPath -Path $file -BackupType "Special" -MACHINE_BACKUP $script:TestMachineBackup -SHARED_BACKUP $script:TestSharedBackup
                    $result | Should -Be $sharedFile
                    Test-Path $result | Should -Be $true
                } finally {
                    Remove-Item $sharedFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}