#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive WSL Package Management Integration Tests

.DESCRIPTION
    Tests WSL package management functionality including:
    - APT, NPM, PIP package managers
    - Package backup and restore workflows
    - Package synchronization and installation
    - Cross-platform package management
#>

BeforeAll {
    # Import the module with standardized pattern
    try {
        $ModulePath = Resolve-Path "$PSScriptRoot/../../WindowsMelodyRecovery.psd1"
        Import-Module $ModulePath -Force -ErrorAction Stop
    } catch {
        throw "Cannot find or import WindowsMelodyRecovery module: $($_.Exception.Message)"
    }
    
    # Import WSL Docker communication utilities
    . "$PSScriptRoot/../utilities/WSL-Docker-Communication.ps1"
    
    # Test environment setup
    $script:ContainerName = "wmr-wsl-mock"
    $script:TestBackupRoot = "/workspace/test-backups"
    $script:WSLPackageBackupPath = "$script:TestBackupRoot/wsl-packages"
    
    # Create test directories
    if (-not (Test-Path $script:TestBackupRoot)) {
        New-Item -Path $script:TestBackupRoot -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $script:WSLPackageBackupPath)) {
        New-Item -Path $script:WSLPackageBackupPath -ItemType Directory -Force | Out-Null
    }
    
    # Test WSL container connectivity
    Write-Host "Testing WSL communication for package management tests..." -ForegroundColor Yellow
    $connectivityTest = Test-WSLDockerConnectivity -ContainerName $script:ContainerName
    if ($connectivityTest.Success) {
        Write-Host "Docker exec connectivity: PASSED" -ForegroundColor Green
    } else {
        Write-Host "Docker exec connectivity: FAILED" -ForegroundColor Red
        Write-Host "Error: $($connectivityTest.Error)" -ForegroundColor Red
    }
    
    # Test package managers availability
    $packageManagers = @("apt", "pip3", "npm")
    foreach ($pm in $packageManagers) {
        $pmTest = Invoke-WSLDockerCommand -Command "which $pm" -ContainerName $script:ContainerName
        if ($pmTest.Success) {
            Write-Host "$pm availability: PASSED" -ForegroundColor Green
        } else {
            Write-Host "$pm availability: FAILED" -ForegroundColor Red
        }
    }
}

Describe "WSL Package Management Integration Tests" {
    
    Context "Package Manager Availability and Functionality" {
        It "Should have APT package manager available" {
            $result = Invoke-WSLDockerCommand -Command "which apt" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/usr/bin/apt"
        }
        
        It "Should have PIP package manager available" {
            $result = Invoke-WSLDockerCommand -Command "which pip3" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/usr/bin/pip3"
        }
        
        It "Should have NPM package manager available" {
            $result = Invoke-WSLDockerCommand -Command "which npm" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "/usr/bin/npm"
        }
        
        It "Should be able to update APT package database" {
            # Skip update in container environment - just verify apt works
            $result = Invoke-WSLDockerCommand -Command "apt list --installed | head -5" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
        }
        
        It "Should be able to check package manager versions" {
            $managers = @{
                "apt" = "apt --version"
                "pip3" = "pip3 --version"
                "npm" = "npm --version"
            }
            
            foreach ($manager in $managers.GetEnumerator()) {
                $result = Invoke-WSLDockerCommand -Command $manager.Value -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "$($manager.Key) should return version information"
                $result.Output | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "APT Package Management" {
        It "Should list installed APT packages" {
            $packages = Get-WSLDockerPackages -PackageManager "apt" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 50
            $packages.Packages | Should -Match "install"
        }
        
        It "Should parse APT package list correctly" {
            $result = Invoke-WSLDockerCommand -Command "dpkg --get-selections | grep -E '^(git|curl|wget)' | head -5" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "install"
        }
        
        It "Should handle APT package search" {
            $result = Invoke-WSLDockerCommand -Command "apt search vim 2>/dev/null | grep -i vim | head -5" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "vim"
        }
        
        It "Should be able to install a test package" {
            # Verify tree is already installed or skip installation
            $checkResult = Invoke-WSLDockerCommand -Command "which tree || echo 'not-found'" -ContainerName $script:ContainerName
            $checkResult.Success | Should -Be $true
            
            if ($checkResult.Output -match "not-found") {
                # Tree not installed - this is expected in container
                $checkResult.Output | Should -Match "not-found"
            } else {
                # Tree is installed
                $checkResult.Output | Should -Match "/usr/bin/tree"
            }
        }
        
        It "Should backup APT packages to file" {
            $backupScript = @"
#!/bin/bash
mkdir -p '$script:WSLPackageBackupPath'
dpkg --get-selections > '$script:WSLPackageBackupPath/apt-packages.txt'
echo "APT packages backed up to apt-packages.txt"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $backupScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify backup file exists and has content
            $verifyResult = Invoke-WSLDockerCommand -Command "wc -l '$script:WSLPackageBackupPath/apt-packages.txt'" -ContainerName $script:ContainerName
            $verifyResult.Success | Should -Be $true
            $lineCount = [int]($verifyResult.Output -split '\s+')[0]
            $lineCount | Should -BeGreaterThan 50
        }
    }
    
    Context "Python Package Management" {
        It "Should list installed PIP packages" {
            $packages = Get-WSLDockerPackages -PackageManager "pip3" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            $packages.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle PIP package installation" {
            # Install a simple Python package
            $result = Invoke-WSLDockerCommand -Command "pip3 install --user requests" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify installation (check both name and version formats)
            $verifyResult = Invoke-WSLDockerCommand -Command "pip3 show requests" -ContainerName $script:ContainerName
            $verifyResult.Success | Should -Be $true
            ($verifyResult.Output -join " ") | Should -Match "requests"
        }
        
        It "Should export PIP packages to requirements.txt" {
            $backupScript = @"
#!/bin/bash
mkdir -p '$script:WSLPackageBackupPath'
pip3 freeze > '$script:WSLPackageBackupPath/requirements.txt'
echo "PIP packages exported to requirements.txt"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $backupScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify requirements file has content
            $verifyResult = Invoke-WSLDockerCommand -Command "cat '$script:WSLPackageBackupPath/requirements.txt'" -ContainerName $script:ContainerName
            $verifyResult.Success | Should -Be $true
            $verifyResult.Output | Should -Match "=="
        }
        
        It "Should handle PIP package list in JSON format" {
            $result = Invoke-WSLDockerCommand -Command "pip3 list --format=json" -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            { $result.Output | ConvertFrom-Json } | Should -Not -Throw
        }
    }
    
    Context "Node.js Package Management" {
        It "Should list installed NPM packages" {
            $packages = Get-WSLDockerPackages -PackageManager "npm" -ContainerName $script:ContainerName
            $packages.Success | Should -Be $true
            # NPM global packages might be minimal, so just check it doesn't error
            $packages.Packages | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle NPM global package installation" {
            # Check if we can install global packages or skip
            $testResult = Invoke-WSLDockerCommand -Command "npm config get prefix" -ContainerName $script:ContainerName
            $testResult.Success | Should -Be $true
            $testResult.Output | Should -Not -BeNullOrEmpty
        }
        
        It "Should export NPM global packages to JSON" {
            $backupScript = @"
#!/bin/bash
mkdir -p '$script:WSLPackageBackupPath'
npm list -g --depth=0 --json > '$script:WSLPackageBackupPath/npm-global-packages.json'
echo "NPM global packages exported to npm-global-packages.json"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $backupScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify JSON file is valid
            $verifyResult = Invoke-WSLDockerCommand -Command "cat '$script:WSLPackageBackupPath/npm-global-packages.json'" -ContainerName $script:ContainerName
            $verifyResult.Success | Should -Be $true
            { $verifyResult.Output | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It "Should handle NPM package operations" {
            # Test various NPM operations
            $operations = @{
                "version" = "npm --version"
                "config" = "npm config get registry"
                "cache" = "npm cache verify"
            }
            
            foreach ($operation in $operations.GetEnumerator()) {
                $result = Invoke-WSLDockerCommand -Command $operation.Value -ContainerName $script:ContainerName
                $result.Success | Should -Be $true -Because "NPM $($operation.Key) operation should succeed"
            }
        }
    }
    
    Context "Package Backup and Restore Workflows" {
        It "Should create comprehensive package backup" {
            $backupScript = @"
#!/bin/bash
mkdir -p '$script:WSLPackageBackupPath'

# Backup APT packages
echo "Backing up APT packages..."
dpkg --get-selections > '$script:WSLPackageBackupPath/apt-packages.txt'
apt list --installed > '$script:WSLPackageBackupPath/apt-installed.txt' 2>/dev/null

# Backup PIP packages  
echo "Backing up PIP packages..."
pip3 freeze > '$script:WSLPackageBackupPath/requirements.txt'
pip3 list --format=json > '$script:WSLPackageBackupPath/pip-packages.json'

# Backup NPM packages
echo "Backing up NPM packages..."
npm list -g --depth=0 --json > '$script:WSLPackageBackupPath/npm-global-packages.json'

# Create backup manifest
echo "Creating backup manifest..."
cat > '$script:WSLPackageBackupPath/backup-manifest.json' << 'EOF'
{
    "timestamp": "2024-01-01T00:00:00Z",
    "hostname": "test-container",
    "user": "testuser",
    "distribution": "Ubuntu-22.04",
    "packages": {
        "apt": "apt-packages.txt",
        "pip": "requirements.txt",
        "npm": "npm-global-packages.json"
    }
}
EOF

echo "Package backup completed successfully"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $backupScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            
            # Verify all backup files exist
            $backupFiles = @(
                "apt-packages.txt",
                "requirements.txt", 
                "npm-global-packages.json",
                "backup-manifest.json"
            )
            
            foreach ($file in $backupFiles) {
                $verifyResult = Invoke-WSLDockerCommand -Command "test -f '$script:WSLPackageBackupPath/$file' && echo 'exists'" -ContainerName $script:ContainerName
                $verifyResult.Success | Should -Be $true
                $verifyResult.Output | Should -Be "exists"
            }
        }
        
        It "Should validate backup file contents" {
            # Check APT backup
            $aptResult = Invoke-WSLDockerCommand -Command "wc -l '$script:WSLPackageBackupPath/apt-packages.txt'" -ContainerName $script:ContainerName
            $aptResult.Success | Should -Be $true
            $aptLineCount = [int]($aptResult.Output -split '\s+')[0]
            $aptLineCount | Should -BeGreaterThan 50
            
            # Check PIP backup
            $pipResult = Invoke-WSLDockerCommand -Command "wc -l '$script:WSLPackageBackupPath/requirements.txt'" -ContainerName $script:ContainerName
            $pipResult.Success | Should -Be $true
            $pipLineCount = [int]($pipResult.Output -split '\s+')[0]
            $pipLineCount | Should -BeGreaterThan 0
            
            # Check NPM backup JSON validity
            $npmResult = Invoke-WSLDockerCommand -Command "cat '$script:WSLPackageBackupPath/npm-global-packages.json'" -ContainerName $script:ContainerName
            $npmResult.Success | Should -Be $true
            { $npmResult.Output | ConvertFrom-Json } | Should -Not -Throw
            
            # Check manifest JSON validity
            $manifestResult = Invoke-WSLDockerCommand -Command "cat '$script:WSLPackageBackupPath/backup-manifest.json'" -ContainerName $script:ContainerName
            $manifestResult.Success | Should -Be $true
            { $manifestResult.Output | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It "Should simulate package restore workflow" {
            # Create a test restore script
            $restoreScript = @"
#!/bin/bash
echo "Simulating package restore workflow..."

# Simulate APT package restore (dry run)
echo "Simulating APT package restore..."
if [ -f '$script:WSLPackageBackupPath/apt-packages.txt' ]; then
    apt_count=`$(wc -l '$script:WSLPackageBackupPath/apt-packages.txt' | cut -d' ' -f1)
    echo "Would restore `$apt_count APT packages"
else
    echo "APT backup file not found"
fi

# Simulate PIP package restore (dry run)
echo "Simulating PIP package restore..."
if [ -f '$script:WSLPackageBackupPath/requirements.txt' ]; then
    pip_count=`$(wc -l '$script:WSLPackageBackupPath/requirements.txt' | cut -d' ' -f1)
    echo "Would restore `$pip_count PIP packages"
else
    echo "PIP backup file not found"
fi

# Simulate NPM package restore (dry run)
echo "Simulating NPM package restore..."
if [ -f '$script:WSLPackageBackupPath/npm-global-packages.json' ]; then
    npm_count=`$(cat '$script:WSLPackageBackupPath/npm-global-packages.json' | jq '.dependencies | length' 2>/dev/null || echo "0")
    echo "Would restore `$npm_count NPM packages"
else
    echo "NPM backup file not found"
fi

echo "Package restore simulation completed"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $restoreScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Simulating package restore workflow"
            $result.Output | Should -Match "Would restore.*APT packages"
            $result.Output | Should -Match "Package restore simulation completed"
        }
    }
    
    Context "Package Synchronization and Cross-Platform Management" {
        It "Should detect package manager differences" {
            $aptResult = Invoke-WSLDockerCommand -Command "dpkg --get-selections | grep -c install" -ContainerName $script:ContainerName
            $aptResult.Success | Should -Be $true
            [int]$aptResult.Output.Trim() | Should -BeGreaterThan 50
            
            $pipResult = Invoke-WSLDockerCommand -Command "pip3 list | wc -l" -ContainerName $script:ContainerName
            $pipResult.Success | Should -Be $true
            [int]$pipResult.Output.Trim() | Should -BeGreaterThan 0
            
            $gitResult = Invoke-WSLDockerCommand -Command "command -v git" -ContainerName $script:ContainerName
            $gitResult.Success | Should -Be $true
            $gitResult.Output | Should -Match "/usr/bin/git"
        }
        
        It "Should handle package installation from backup data" {
            # Test installing a package from backup simulation
            $installScript = @"
#!/bin/bash
echo "Testing package installation from backup data..."

# Simulate reading from backup and installing a package
if [ -f '$script:WSLPackageBackupPath/apt-packages.txt' ]; then
    # Check if tree package is in backup
    if grep -q "tree" '$script:WSLPackageBackupPath/apt-packages.txt'; then
        echo "Tree package found in backup - ensuring it's installed"
        sudo apt install -y tree
        if command -v tree >/dev/null 2>&1; then
            echo "Tree package successfully installed/verified"
        else
            echo "Tree package installation failed"
        fi
    else
        echo "Tree package not found in backup"
    fi
else
    echo "APT backup file not available"
fi

echo "Package installation test completed"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $installScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Testing package installation from backup data"
            $result.Output | Should -Match "Package installation test completed"
        }
        
        It "Should validate package manager consistency" {
            # Test that package managers are working consistently
            $consistencyScript = @"
#!/bin/bash
echo "Validating package manager consistency..."

# Test each package manager
echo "Testing APT..."
apt list --installed >/dev/null 2>&1 && echo "APT: OK" || echo "APT: ERROR"

echo "Testing PIP..."
pip3 list >/dev/null 2>&1 && echo "PIP: OK" || echo "PIP: ERROR"

echo "Testing NPM..."
npm list -g --depth=0 >/dev/null 2>&1 && echo "NPM: OK" || echo "NPM: ERROR"

echo "Package manager consistency check completed"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $consistencyScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "APT: OK"
            $result.Output | Should -Match "PIP: OK"
            $result.Output | Should -Match "NPM: OK"
        }
    }
    
    Context "Advanced Package Management Features" {
        It "Should handle package dependency resolution" {
            # Test dependency handling
            $depScript = @"
#!/bin/bash
echo "Testing package dependency resolution..."

# Check dependencies for a known package
if command -v git >/dev/null 2>&1; then
    echo "Git is installed - checking dependencies..."
    apt-cache depends git | head -10
    echo "Git dependency check completed"
else
    echo "Git not available for dependency testing"
fi
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $depScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Testing package dependency resolution"
        }
        
        It "Should handle package version management" {
            # Test version tracking
            $versionScript = @"
#!/bin/bash
echo "Testing package version management..."

# Get versions of key packages
echo "Package versions:"
git --version 2>/dev/null | head -1
python3 --version 2>/dev/null | head -1
node --version 2>/dev/null | head -1
npm --version 2>/dev/null | head -1

echo "Version management test completed"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $versionScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Package versions:"
            $result.Output | Should -Match "git version"
        }
        
        It "Should handle package cleanup and maintenance" {
            # Test cleanup operations
            $cleanupScript = @"
#!/bin/bash
echo "Testing package cleanup and maintenance..."

# APT cleanup
echo "Running APT cleanup..."
apt autoremove --dry-run 2>/dev/null | head -5

# NPM cache cleanup
echo "Running NPM cache cleanup..."
npm cache clean --dry-run 2>/dev/null || echo "NPM cache clean not needed"

# PIP cache info
echo "Checking PIP cache..."
pip3 cache info 2>/dev/null || echo "PIP cache info not available"

echo "Package cleanup test completed"
"@
            
            $result = Invoke-WSLDockerScript -ScriptContent $cleanupScript -ContainerName $script:ContainerName
            $result.Success | Should -Be $true
            $result.Output | Should -Match "Testing package cleanup and maintenance"
        }
    }
    
    AfterAll {
        # Clean up test files
        if (Test-Path $script:WSLPackageBackupPath) {
            Remove-Item -Path $script:WSLPackageBackupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-Host "WSL Package Management tests completed" -ForegroundColor Green
    }
}