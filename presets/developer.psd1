# Developer Preset - Aggressive debloat for development workstations
# Preserves: Terminal, WSL, PowerShell, VS Code integrations
# Removes: Everything consumer/gaming/OEM + Office + OneDrive + Copilot
# Usage: .\Debloat-Win11.ps1 -ConfigPath .\presets\developer.psd1

@{
    RemovePatterns = @(
        # Consumer/Entertainment
        '*Clipchamp*',
        '*Microsoft.549981C3F5F10*',
        '*Microsoft.BingFinance*',
        '*Microsoft.BingNews*',
        '*Microsoft.BingSports*',
        '*Microsoft.BingWeather*',
        '*Microsoft.BingSearch*',
        '*Microsoft.Copilot*',
        '*Microsoft.Windows.Ai.Copilot.Provider*',
        '*Microsoft.GamingApp*',
        '*Microsoft.GetHelp*',
        '*Microsoft.Getstarted*',
        '*Microsoft.Messaging*',
        '*Microsoft.Microsoft3DViewer*',
        '*Microsoft.MicrosoftOfficeHub*',
        '*Microsoft.MicrosoftSolitaireCollection*',
        '*Microsoft.MixedReality*',
        '*Microsoft.Office.OneNote*',
        '*Microsoft.OneConnect*',
        '*Microsoft.OutlookForWindows*',
        '*Microsoft.People*',
        '*Microsoft.PowerAutomateDesktop*',
        '*Microsoft.Print3D*',
        '*Microsoft.3DBuilder*',
        '*Microsoft.SkypeApp*',
        '*Microsoft.Todos*',
        '*Microsoft.Wallet*',
        '*Microsoft.WindowsCamera*',
        '*Microsoft.WindowsBackup*',
        '*Microsoft.windowscommunicationsapps*',
        '*Microsoft.WindowsFeedbackHub*',
        '*Microsoft.WindowsMaps*',
        '*Microsoft.YourPhone*',
        '*Microsoft.ZuneMusic*',
        '*Microsoft.ZuneVideo*',
        '*Microsoft.Edge.GameAssist*',
        '*Microsoft.WidgetsPlatformRuntime*',
        '*MicrosoftWindows.Client.FileExp*',
        '*MicrosoftCorporationII.MicrosoftFamily*',
        '*MicrosoftWindows.Client.WebExperience*',
        '*MicrosoftWindows.CrossDevice*',
        '*MicrosoftTeams*',
        '*MSTeams*',
        '*Microsoft.PCManager*',
        '*Microsoft.Windows.AIHub*',
        '*Microsoft.M365Companions*',
        '*Microsoft.StartExperiencesApp*',
        # Gaming
        '*Microsoft.Xbox*',
        '*Microsoft.XboxApp*',
        '*Microsoft.XboxGameOverlay*',
        '*Microsoft.XboxGamingOverlay*',
        '*Microsoft.XboxIdentityProvider*',
        '*Microsoft.XboxSpeechToTextOverlay*',
        '*Microsoft.Xbox.TCUI*',
        '*Microsoft.GamingServices*',
        # Social/Consumer
        '*Disney*', '*Spotify*', '*Facebook*', '*Instagram*',
        '*TikTok*', '*Netflix*', '*Amazon*', '*Twitter*',
        '*LinkedInforWindows*', '*CandyCrush*', '*BubbleWitch*',
        '*FarmVille*', '*RoyalRevolt*', '*Sway*',
        # OEM (all)
        '*AppUp.Intel*', '*Intel*GraphicsExperience*', '*Intel*Optane*',
        '*HPInc*', '*HPPrinterControl*', '*HPSupportAssistant*',
        '*LenovoCompanion*', '*LenovoCorporation*',
        '*DolbyLaboratories*', '*WavesAudio*', '*RealtekAudio*',
        '*ASUS*', '*Acer*', '*MSI*', '*Razer*'
        # PRESERVED: Terminal, Calculator, Notepad, Paint, Snipping Tool, Photos, Quick Assist,
        #            Sticky Notes, Alarms, Sound Recorder, Windows.DevHome (useful for devs)
    )

    DefenderExclusions = @()

    EdgeBookmarks = @(
        @{ name = "Google"; url = "https://www.google.com" }
    )
}
