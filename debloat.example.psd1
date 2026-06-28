# Debloat-Win11 Configuration File
# Usage: .\Debloat-Win11.ps1 -ConfigPath .\debloat.psd1
#
# Any key defined here overrides the built-in default.
# Remove or comment out sections you do not need to customize.
#
# Available overridable keys:
#   RemovePatterns      - AppX packages to remove (wildcard patterns)
#   ServicesToDisable   - Windows services to disable
#   DefenderExclusions  - Folder paths to exclude from Defender scanning
#   EdgeBookmarks       - Bookmarks to add to Edge (array of @{name; url} hashtables)
#   StartupBloat        - Startup registry entries to remove (wildcard patterns)
#   TasksToDisable      - Scheduled task names to disable (wildcard patterns)
#   FeaturesToDisable   - Windows optional features to disable
#   FirewallRules       - Tab-delimited CSV string defining firewall rules
#   DarkMode            - $true (default) to apply dark mode, $false to preserve user theme
#   OemExclude          - Manufacturer names to exclude from OEM nuclear cleanup (e.g., @('Dell','HP'))
#   ClearEventLogs      - Event log names to clear; default empty keeps audit/SIEM evidence

@{
    # AppX packages to remove (wildcard patterns)
    # Risk: Safe -- consumer apps, no system dependencies
    # Uncomment and modify to override the built-in list
    # RemovePatterns = @(
    #     '*Clipchamp*',              # Safe: video editor
    #     '*Microsoft.BingNews*',     # Safe: consumer news
    #     '*Microsoft.BingSports*',   # Safe: consumer sports
    #     '*Microsoft.BingWeather*',  # Safe: consumer weather
    #     '*Microsoft.BingSearch*',   # Safe: Bing integration
    #     '*Microsoft.Windows.Ai.Copilot.Provider*',  # Safe: Copilot provider
    #     '*Microsoft.GamingApp*',    # Safe: Xbox companion
    #     '*Microsoft.GetHelp*',      # Safe: help app
    #     '*Microsoft.Getstarted*',   # Safe: tips app
    #     '*Microsoft.MicrosoftSolitaireCollection*',  # Safe: games
    #     '*Microsoft.People*',       # Safe: contacts (may break Mail)
    #     '*Microsoft.WindowsFeedbackHub*',  # Safe: feedback
    #     '*Microsoft.WindowsBackup*', # Safe: backup nag app
    #     '*MicrosoftWindows.Client.FileExp*', # Safe: consumer File Explorer extension
    #     '*Microsoft.ZuneMusic*',    # Safe: Groove Music
    #     '*Microsoft.ZuneVideo*',    # Safe: Movies & TV
    #     '*Disney*',                 # Safe: third-party
    #     '*Spotify*',                # Safe: third-party
    #     '*Facebook*',               # Safe: third-party
    #     '*TikTok*',                 # Safe: third-party
    #     '*Netflix*'                 # Safe: third-party
    # )

    # Services to disable
    # Risk: Caution -- disabling the wrong service can break functionality
    # Uncomment and modify to override the built-in list
    # ServicesToDisable = @(
    #     'DiagTrack',       # Safe: telemetry
    #     'dmwappushservice', # Safe: WAP push
    #     'DPS',             # Caution: disables auto-troubleshooting
    #     'WerSvc',          # Safe: error reporting to Microsoft
    #     'MapsBroker',      # Safe: offline maps
    #     'Fax',             # Safe: fax service
    #     'RemoteRegistry'   # Safe: security improvement
    # )

    # Defender folder exclusions
    # Risk: Caution -- excluded paths bypass real-time scanning
    # Default is empty -- add paths specific to your deployment
    # DefenderExclusions = @(
    #     "C:\images",
    #     "C:\YourApp"
    # )

    # Edge bookmarks
    # Default is Google only -- add vendor-specific links
    # EdgeBookmarks = @(
    #     @{ name = "Google"; url = "https://www.google.com" }
    #     @{ name = "Support Portal"; url = "https://support.example.com" }
    # )

    # Startup bloat entries to remove from registry Run keys (wildcard patterns)
    # Risk: Safe -- only affects auto-start, apps still launchable manually
    # Default removes Spotify, Discord, Steam, Adobe, etc. while preserving Teams/Zoom/Slack
    # StartupBloat = @(
    #     'Spotify',
    #     'Discord',
    #     'Steam',
    #     'EpicGamesLauncher',
    #     'AdobeGCInvoker*',
    #     'Adobe Creative Cloud',
    #     'CCXProcess',
    #     'AdobeAAMUpdater*',
    #     'iTunesHelper',
    #     'GoogleUpdate*'
    # )

    # Scheduled tasks to disable (task names, wildcards supported)
    # Risk: Safe -- telemetry/diagnostic tasks; Caution for Edge update tasks (stops auto-updates)
    # Default disables Xbox, Edge update, telemetry, CEIP, feedback, maps tasks
    # TasksToDisable = @(
    #     'XblGameSaveTask',
    #     'MicrosoftEdgeUpdateTaskMachineCore*',
    #     'MicrosoftEdgeUpdateTaskMachineUA*',
    #     'Consolidator',
    #     'UsbCeip',
    #     'Microsoft Compatibility Appraiser'
    # )

    # Windows optional features to disable
    # Risk: Safe for SMB1/PS v2/IE (security improvements); Caution for WMP (some apps depend on it)
    # Default disables IE, PS v2, WMP, XPS, SMB1, Work Folders
    # FeaturesToDisable = @(
    #     'Internet-Explorer-Optional-amd64',   # Safe: security risk
    #     'MicrosoftWindowsPowerShellV2Root',   # Safe: security risk
    #     'MicrosoftWindowsPowerShellV2',       # Safe: security risk
    #     'SMB1Protocol',                        # Safe: security risk
    #     'SMB1Protocol-Client',                 # Safe: security risk
    #     'SMB1Protocol-Server'                  # Safe: security risk
    # )

    # Firewall rules (tab-delimited CSV string with header row)
    # Default imports file/printer sharing rules
    # FirewallRules = @"
    # Name	DisplayName	Direction	Action	Protocol	LocalPort	RemotePort	Program
    # Custom-Rule-1	My Custom Rule	Inbound	Allow	TCP	8080	Any	System
    # "@

    # Dark mode (default: $true -- applies dark theme to apps and system)
    # Set to $false to preserve user's existing theme preferences
    # DarkMode = $true

    # OEM manufacturer exclusion (default: none -- all detected OEM bloat is removed)
    # Add manufacturer names to skip during OEM nuclear cleanup
    # Useful when you need Dell BIOS utilities, HP Sure Click, etc.
    # OemExclude = @('Dell', 'HP')

    # Event logs to clear during Privacy cleanup
    # Risk: Caution -- clearing event logs removes audit/SIEM evidence from managed devices
    # Default is empty; specify exact log names only when required by your deployment policy
    # ClearEventLogs = @(
    #     'Application',
    #     'System'
    # )
}
