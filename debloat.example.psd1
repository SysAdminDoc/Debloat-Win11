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

@{
    # AppX packages to remove (wildcard patterns)
    # Uncomment and modify to override the built-in list
    # RemovePatterns = @(
    #     '*Clipchamp*',
    #     '*Microsoft.BingNews*',
    #     '*Microsoft.BingSports*',
    #     '*Microsoft.BingWeather*',
    #     '*Microsoft.BingSearch*',
    #     '*Microsoft.GamingApp*',
    #     '*Microsoft.GetHelp*',
    #     '*Microsoft.Getstarted*',
    #     '*Microsoft.MicrosoftSolitaireCollection*',
    #     '*Microsoft.People*',
    #     '*Microsoft.WindowsFeedbackHub*',
    #     '*Microsoft.ZuneMusic*',
    #     '*Microsoft.ZuneVideo*',
    #     '*Disney*',
    #     '*Spotify*',
    #     '*Facebook*',
    #     '*TikTok*',
    #     '*Netflix*'
    # )

    # Services to disable
    # Uncomment and modify to override the built-in list
    # ServicesToDisable = @(
    #     'DiagTrack',
    #     'dmwappushservice',
    #     'DPS',
    #     'WerSvc',
    #     'MapsBroker',
    #     'Fax',
    #     'RemoteRegistry'
    # )

    # Defender folder exclusions
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
    # Default disables IE, PS v2, WMP, XPS, SMB1, Work Folders
    # FeaturesToDisable = @(
    #     'Internet-Explorer-Optional-amd64',
    #     'MicrosoftWindowsPowerShellV2Root',
    #     'MicrosoftWindowsPowerShellV2',
    #     'SMB1Protocol',
    #     'SMB1Protocol-Client',
    #     'SMB1Protocol-Server'
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
}
