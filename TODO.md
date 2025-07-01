# TODO

## Features

- Convert backup/restore scripts to templates/states
- Clean up verb practices and naming for gallery release
- Secure encrypted key/file options with password prompts
- private ssh key and cert logic
- optional file encryption
- optional heavily filtered/limited user directory rsync in windows and wsl

## Testing

- Mocks
  - Make sure that various cloud drives are mocked and we test their code paths in configuration and use
  - More windows like mock app and home directory trees
  - Tests for games and winget/chocolatey backup mocks and restore from json
- WSL backup/restore
  - Emulate both ssh and wsl cli calls into Linux
  - Make sure that chezmoi works in wsl
  - Test system, npm, python, etc. packaging backup/restore
- Registry calls
  - Make sure registry calls in scripts are same as mocks
  - Make sure we gracefully handle missing registry to backup
  - Make sure we gracefully handle restoration in empty paths
- General restoration
  - Make sure we handle system restoration and shared configuration blended
  - Make sure the local or remote chezmoi repo works
  - Secure key/file encryption test
- Merge all testing - setup ci in github to match new unit and integration in docker, push to main
