# TODO

- decouple initialization, setup, and common env/code from Load-Environment (remove Load-Environment?)
  - Install just installs
  - Initialize ONLY: a. tries to find config
                     b. reads config if availabl
                     c. ask if you want to reconfig or configs
                     d. asks about cloud, and multiple cloud paths
                     e. rest of config file fields optionally
                     f. ends with no errors, installs, script loading, etc. never happening
  - Setup script to try to orchestrate all setup (ask to run each script, etc.)
- Make a wsl diff system from a base
- wsl Linux updates and saving needs lots of work
- Add chezmoi and syncthing and other common backup tool
