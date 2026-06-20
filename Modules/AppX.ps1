# ============================================================================
# MODULE: AppX Package Removal
# Phase 1: Remove bloatware AppX packages (user + provisioned)
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Phase 1/7] Removing bloatware packages..." "SECTION"
Write-Rationale 'AppX'
if ($script:isLTSC) {
    Write-Log "  LTSC edition: most consumer AppX packages are not present -- removals will be no-ops" "INFO"
}

# Allow config file to override the remove patterns
$removePatterns = if ($script:configOverrides.ContainsKey('RemovePatterns')) { $script:configOverrides.RemovePatterns } else { @(
    '*Clipchamp*',
    '*Microsoft.3DBuilder*',
    '*Microsoft.549981C3F5F10*',
    '*Microsoft.BingFinance*',
    '*Microsoft.BingNews*',
    '*Microsoft.BingSports*',
    '*Microsoft.BingWeather*',
    '*Microsoft.BingSearch*',
    '*Microsoft.Copilot*',
    '*Microsoft.GamingApp*',
    '*Microsoft.GetHelp*',
    '*Microsoft.Getstarted*',
    '*Microsoft.Messaging*',
    '*Microsoft.Microsoft3DViewer*',
    '*Microsoft.MicrosoftOfficeHub*',
    '*Microsoft.MicrosoftSolitaireCollection*',
    # KEEP: Sticky Notes - useful and lightweight
    # '*Microsoft.MicrosoftStickyNotes*',
    '*Microsoft.MixedReality*',
    '*Microsoft.Office.OneNote*',
    '*Microsoft.OneConnect*',
    '*Microsoft.OutlookForWindows*',
    '*Microsoft.People*',
    '*Microsoft.PowerAutomateDesktop*',
    '*Microsoft.Print3D*',
    '*Microsoft.SkypeApp*',
    '*Microsoft.Todos*',
    '*Microsoft.Wallet*',
    '*Microsoft.Windows.DevHome*',
    # KEEP: Alarms - useful timer/clock app
    # '*Microsoft.WindowsAlarms*',
    '*Microsoft.WindowsCamera*',
    '*Microsoft.windowscommunicationsapps*',
    '*Microsoft.WindowsFeedbackHub*',
    '*Microsoft.WindowsMaps*',
    # KEEP: Sound Recorder - can be useful
    # '*Microsoft.WindowsSoundRecorder*',
    '*Microsoft.Xbox*',
    '*Microsoft.XboxApp*',
    '*Microsoft.XboxGameOverlay*',
    '*Microsoft.XboxGamingOverlay*',
    '*Microsoft.XboxIdentityProvider*',
    '*Microsoft.XboxSpeechToTextOverlay*',
    '*Microsoft.Xbox.TCUI*',
    '*Microsoft.GamingApp*',
    '*Microsoft.GamingServices*',
    '*Microsoft.YourPhone*',
    '*Microsoft.ZuneMusic*',
    '*Microsoft.ZuneVideo*',
    '*Microsoft.Edge.GameAssist*',
    '*Microsoft.WidgetsPlatformRuntime*',
    '*MicrosoftCorporationII.MicrosoftFamily*',
    # KEEP: QuickAssist - useful for IT support
    # '*MicrosoftCorporationII.QuickAssist*',
    '*MicrosoftWindows.Client.WebExperience*',
    '*MicrosoftWindows.CrossDevice*',
    '*MicrosoftTeams*',
    '*MSTeams*',
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
    '*MicrosoftCorporationII.Windows.RemoteDesktop*',
    '*Microsoft.RemoteDesktop*',
    '*AppUp.Intel*',
    '*Intel*GraphicsExperience*',
    '*Intel*Optane*',
    '*Intel*ManagementandSecurity*',
    '*HPInc*',
    '*HPPrinterControl*',
    '*HPPrivacySettings*',
    '*HPSupportAssistant*',
    '*HPSystemEventUtility*',
    '*LenovoCompanion*',
    '*LenovoCorporation*',
    '*LenovoUtility*',
    '*RealtekAudio*',
    '*RealtekSemiconductor*',
    '*DolbyLaboratories*',
    '*WavesAudio*',
    # ASUS
    '*ASUS*',
    '*ASUSPCAssistant*',
    '*ArmouryCrate*',
    '*MyASUS*',
    '*ROGLiveService*',
    # Acer
    '*Acer*',
    '*AcerCare*',
    '*AcerCollection*',
    '*AcerIncorporated*',
    '*AcerQuickAccess*',
    # MSI
    '*MSI*',
    '*MysticLight*',
    '*DragonCenter*',
    '*MSIAfterburner*',
    # Razer
    '*Razer*',
    '*RazerInc*',
    '*RazerCortex*',
    '*RazerSynapse*',
    # 24H2+ / 26H1+ additions
    '*Microsoft.PCManager*',
    '*Microsoft.Windows.AIHub*',
    '*Microsoft.M365Companions*',
    '*Microsoft.StartExperiencesApp*',
    '*Microsoft.OutlookForWindows*'
) }

foreach ($pattern in $removePatterns) {
    Remove-AppxDryRun -Pattern $pattern
}

# Explicit Xbox/Gaming removal (Xbox Live, Gaming Services)
Remove-AppxDryRun -Pattern '*Xbox*'
Remove-AppxDryRun -Pattern '*Gaming*'
if (-not $DryRun) {
    Get-AppxProvisionedPackage -Online 2>$null | Where-Object { $_.DisplayName -match 'Xbox|Gaming' } | Remove-AppxProvisionedPackage -Online 2>$null
}

# Remove Xbox folders
if (-not $DryRun) {
    @(
        "$env:LOCALAPPDATA\Packages\Microsoft.XboxIdentityProvider*",
        "$env:LOCALAPPDATA\Packages\Microsoft.Xbox*",
        "$env:LOCALAPPDATA\Packages\Microsoft.GamingServices*"
    ) | ForEach-Object {
        Get-Item $_ -EA 0 | Remove-Item -Recurse -Force -EA 0
    }
}

Write-Log "  Bloatware packages removed" "SUCCESS"

# Remove Remote Desktop Connection shortcuts (mstsc is a system component)
if (-not $DryRun) {
    Write-Log "  Removing Remote Desktop shortcuts..." "INFO"
    @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\Remote Desktop Connection.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Windows Accessories\Remote Desktop Connection.lnk",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Accessories\Remote Desktop Connection.lnk"
    ) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force -EA 0 }
    }
}
