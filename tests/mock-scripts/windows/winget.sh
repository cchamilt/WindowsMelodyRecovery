#!/bin/bash
# Mock Windows winget command for testing

case "$1" in
    "list")
        echo "Name                           Id                    Version      Available Source"
        echo "---------------------------------------------------------------------------------"
        echo "Microsoft Visual Studio Code   Microsoft.VisualStudioCode  1.85.0   1.85.1    winget"
        echo "Google Chrome                  Google.Chrome               120.0    120.1     winget"
        echo "Steam                          Valve.Steam                 3.0      3.1       winget"
        echo "Epic Games Launcher            EpicGames.EpicGamesLauncher 15.0     15.1      winget"
        echo "GOG Galaxy                     GOG.Galaxy                  2.0      2.1       winget"
        echo "EA App                         ElectronicArts.EADesktop    12.0     12.1      winget"
        ;;
    "export")
        OUTPUT="$2"
        if [ -z "$OUTPUT" ]; then
            OUTPUT="winget-export.json"
        fi
        
        cat > "$OUTPUT" << 'EOF'
{
  "$schema": "https://aka.ms/winget-packages.schema.2.0.json",
  "CreationDate": "2024-01-01T00:00:00.000-00:00",
  "Sources": [
    {
      "Packages": [
        {
          "PackageIdentifier": "Microsoft.VisualStudioCode",
          "Version": "1.85.0"
        },
        {
          "PackageIdentifier": "Google.Chrome",
          "Version": "120.0"
        },
        {
          "PackageIdentifier": "Valve.Steam",
          "Version": "3.0"
        },
        {
          "PackageIdentifier": "EpicGames.EpicGamesLauncher",
          "Version": "15.0"
        },
        {
          "PackageIdentifier": "GOG.Galaxy",
          "Version": "2.0"
        },
        {
          "PackageIdentifier": "ElectronicArts.EADesktop",
          "Version": "12.0"
        }
      ],
      "SourceDetails": {
        "Argument": "https://cdn.winget.microsoft.com/cache",
        "Identifier": "Microsoft.Winget.Source_8wekyb3d8bbwe",
        "Name": "winget",
        "Type": "Microsoft.PreIndexed.Package"
      }
    }
  ]
}
EOF
        echo "Exported package list to $OUTPUT"
        ;;
    "import")
        INPUT="$2"
        if [ -f "$INPUT" ]; then
            echo "Installing packages from $INPUT..."
            echo "Successfully installed Microsoft.VisualStudioCode"
            echo "Successfully installed Google.Chrome"
            echo "Successfully installed Valve.Steam"
            echo "Successfully installed EpicGames.EpicGamesLauncher"
            echo "Successfully installed GOG.Galaxy"
            echo "Successfully installed ElectronicArts.EADesktop"
        else
            echo "Error: Import file not found"
            exit 1
        fi
        ;;
    "install")
        PACKAGE="$2"
        echo "Installing $PACKAGE..."
        sleep 1
        echo "Successfully installed $PACKAGE"
        ;;
    "uninstall")
        PACKAGE="$2"
        echo "Uninstalling $PACKAGE..."
        sleep 1
        echo "Successfully uninstalled $PACKAGE"
        ;;
    "search")
        QUERY="$2"
        echo "Searching for: $QUERY"
        echo "Name                           Id                    Version   Source"
        echo "--------------------------------------------------------------------"
        echo "Mock Search Result             Mock.Package          1.0.0     winget"
        ;;
    "upgrade")
        echo "Checking for upgrades..."
        echo "Name                           Id                    Version   Available"
        echo "-----------------------------------------------------------------------"
        echo "Google Chrome                  Google.Chrome         120.0     120.1"
        echo "Steam                          Valve.Steam           3.0       3.1"
        ;;
    *)
        echo "Mock winget command"
        echo "Usage: winget [list|export|import|install|uninstall|search|upgrade] ..."
        exit 1
        ;;
esac 