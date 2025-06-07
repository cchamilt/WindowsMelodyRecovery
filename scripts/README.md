# Scripts Directory

This directory contains utility scripts for repository maintenance and development.

## Available Scripts

### `Update-GitHubUsername.ps1`

Updates GitHub username references throughout the repository files. Useful when:
- Forking the repository to your own GitHub account
- Changing your GitHub username
- Setting up the repository for a different organization

**Usage:**
```powershell
# Update from current username to new username
.\scripts\Update-GitHubUsername.ps1 -OldUsername "cchamilt" -NewUsername "yournewusername"

# Preview changes without applying them
.\scripts\Update-GitHubUsername.ps1 -OldUsername "cchamilt" -NewUsername "yournewusername" -WhatIf
```

**What it updates:**
- GitHub Actions badge URLs in README.md
- Repository links in documentation
- Issue and discussion links
- Project board links

**Files processed:**
- `README.md`
- `.github/README.md`
- `docs/CONTRIBUTING.md` (if exists)
- `docs/INSTALLATION.md` (if exists)

## For Contributors

When contributing to this repository, you typically don't need to run these scripts unless you're:
1. Forking the repository for your own use
2. Setting up a development environment with different GitHub references
3. Helping to maintain the repository structure

## For Forkers

If you've forked this repository and want to update all the GitHub references to point to your fork:

1. **Update GitHub username references:**
   ```powershell
   .\scripts\Update-GitHubUsername.ps1 -OldUsername "cchamilt" -NewUsername "yourusername"
   ```

2. **Commit the changes:**
   ```powershell
   git add .
   git commit -m "Update GitHub username references for fork"
   git push origin main
   ```

3. **Verify badges work:**
   - Check that GitHub Actions badges show correctly in your README
   - Verify that all links point to your repository

This ensures that all documentation, badges, and links point to your forked repository instead of the original. 
