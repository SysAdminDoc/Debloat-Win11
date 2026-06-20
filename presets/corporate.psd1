# Corporate Preset - Conservative debloat for business workstations
# Preserves: Office, Teams, OneDrive, Zoom, Slack
# Removes: Gaming, social media, consumer apps, OEM bloat
# Usage: .\Debloat-Win11.ps1 -ConfigPath .\presets\corporate.psd1

@{
    RemovePatterns = @(
        # Consumer/Entertainment
        '*Clipchamp*',
        '*Microsoft.BingFinance*',
        '*Microsoft.BingNews*',
        '*Microsoft.BingSports*',
        '*Microsoft.BingWeather*',
        '*Microsoft.BingSearch*',
        '*Microsoft.GamingApp*',
        '*Microsoft.GetHelp*',
        '*Microsoft.Getstarted*',
        '*Microsoft.MicrosoftSolitaireCollection*',
        '*Microsoft.MixedReality*',
        '*Microsoft.Print3D*',
        '*Microsoft.3DBuilder*',
        '*Microsoft.Microsoft3DViewer*',
        '*Microsoft.Wallet*',
        '*Microsoft.Windows.DevHome*',
        '*Microsoft.WindowsFeedbackHub*',
        '*Microsoft.ZuneMusic*',
        '*Microsoft.ZuneVideo*',
        '*Microsoft.Edge.GameAssist*',
        '*Microsoft.WidgetsPlatformRuntime*',
        '*MicrosoftWindows.Client.WebExperience*',
        '*Microsoft.PCManager*',
        '*Microsoft.Windows.AIHub*',
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
        '*Disney*',
        '*Spotify*',
        '*Facebook*',
        '*Instagram*',
        '*TikTok*',
        '*Netflix*',
        '*Amazon*',
        '*Twitter*',
        '*LinkedInforWindows*',
        '*CandyCrush*',
        '*BubbleWitch*',
        '*FarmVille*',
        '*RoyalRevolt*',
        '*Sway*',
        # OEM
        '*HPInc*', '*HPPrinterControl*', '*HPPrivacySettings*', '*HPSupportAssistant*',
        '*LenovoCompanion*', '*LenovoCorporation*', '*LenovoUtility*',
        '*DolbyLaboratories*', '*WavesAudio*',
        '*ASUS*', '*ArmouryCrate*', '*MyASUS*',
        '*Acer*', '*AcerCare*',
        '*MSI*', '*MysticLight*', '*DragonCenter*',
        '*Razer*', '*RazerInc*'
        # PRESERVED: Office, Teams, OneDrive, Outlook, Copilot (enterprise tool), People, Skype
    )

    ServicesToDisable = @(
        'DiagTrack',
        'dmwappushservice',
        'DPS',
        'WdiSystemHost',
        'WdiServiceHost',
        'InventorySvc',
        'XblAuthManager',
        'XblGameSave',
        'XboxGipSvc',
        'XboxNetApiSvc',
        'GamingServices',
        'GamingServicesNet',
        'lfsvc',
        'Fax',
        'WMPNetworkSvc',
        'WerSvc',
        'wisvc',
        'RetailDemo',
        'MapsBroker',
        'RemoteRegistry',
        'WalletService',
        'WSAIFabricSvc'
        # PRESERVED: DoSvc (Delivery Optimization - needed for WSUS), CDPSvc (corporate device sync)
    )

    DefenderExclusions = @()

    EdgeBookmarks = @(
        @{ name = "Google"; url = "https://www.google.com" }
    )
}
