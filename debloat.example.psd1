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

    # === MEDICAL IMAGING PRESET ===
    # Uncomment the blocks below for medical imaging workstation deployments:

    # DefenderExclusions = @(
    #     "C:\images",
    #     "C:\MTU",
    #     "C:\Maven",
    #     "C:\Program Files\Voyance",
    #     "C:\Program Files\VPACS",
    #     "C:\Program Files\Minipacs",
    #     "C:\ProgramData\Voyance",
    #     "C:\ProgramData\VPACS",
    #     "C:\ProgramData\Minipacs",
    #     "C:\drtech",
    #     "C:\ecali1"
    # )

    # EdgeBookmarks = @(
    #     @{ name = "Support"; url = "https://www.mavenimaging.com/support" }
    #     @{ name = "Patient Image"; url = "https://app.patientimage.ai/login" }
    #     @{ name = "Google"; url = "https://www.google.com" }
    # )
}
