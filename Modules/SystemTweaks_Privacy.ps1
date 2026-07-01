# ============================================================================
# SystemTweaks sub-module: Privacy, Telemetry, AI, Copilot, CDM, OOBE
# Dot-sourced by SystemTweaks.ps1 -- runs in caller's scope
# ============================================================================

# Privacy & Telemetry
Write-Log "  Disabling telemetry & tracking..." "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Deny" -Type "String"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 0

# Disable Copilot, Cortana, Recall
Write-Log "  Disabling Copilot, Cortana, Recall..." "INFO"
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0

# ============================================================================
# WINDOWS 11 24H2/25H2/26H1 BLOAT
# ============================================================================
Write-Log "  Disabling Windows 11 24H2/25H2/26H1 bloat..." "INFO"

# --- Disable WindowsAI policies from shared scope map ---
foreach ($policy in ($script:windowsAiPolicies | Where-Object { $_.ApplyByDefault -ne $false })) {
    $root = if ($policy.Scope -eq 'User') { 'HKCU' } else { 'HKLM' }
    Set-Reg -Path ('{0}:\{1}' -f $root, $policy.Path) -Name $policy.Name -Value $policy.Value -Type $policy.Type
}
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableRecall" -Value 0
if (-not $DryRun) {
    $recallFeature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -EA 0
    if ($recallFeature -and $recallFeature.State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -EA 0 | Out-Null
    }
}

# --- Disable IsoEnvBroker (Agent Workspaces) ---
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Services\IsoEnvBroker" -Name "Enabled" -Value 0

# --- Disable Microsoft Copilot thoroughly (registry + AppX + policy) ---
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\Shell\Copilot" -Name "IsCopilotAvailable" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotCDPPageContext" -Value 0
Remove-AppxDryRun -Pattern '*Microsoft.Copilot*'
Remove-AppxDryRun -Pattern '*Microsoft.Windows.Ai.Copilot.Provider*'
Remove-AppxDryRun -Pattern '*Microsoft.M365Companions*'
Remove-AppxDryRun -Pattern '*Microsoft.Windows.AIHub*'
Remove-AppxDryRun -Pattern '*Microsoft.StartExperiencesApp*'
# RemoveMicrosoftCopilotApp policy (Enterprise/Education only, 24H2+)
if ($editionId -match 'Enterprise|Education' -and [int]$osBuild -ge 26100) {
    Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "RemoveMicrosoftCopilotApp" -Value 1
    Write-Log "  RemoveMicrosoftCopilotApp policy set (Enterprise/Education 24H2+)" "INFO"
}

# --- Block M365 Copilot auto-start ---
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\M365Copilot" -Name "AutoStartDelayEnabled" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\M365Copilot" -Name "IsCompanionWindowAvailable" -Value 0

# --- Block Windows Spotlight suggestions on desktop ---
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{2cc5ca98-6485-489a-8e0b-c62e1ebe953e}" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightOnDesktop" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightOnDesktop" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableSpotlightCollectionOnDesktop" -Value 1

# --- Disable "Suggested Actions" on copy ---
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard" -Name "Disabled" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartClipboard" -Value 0

# --- Disable Windows Backup app nag ---
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsBackup" -Name "DisableBackupUI" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup" -Name "NotificationDisabled" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup" -Name "DisableMonitoring" -Value 1
Remove-AppxDryRun -Pattern '*Microsoft.WindowsBackup*'
Remove-AppxDryRun -Pattern '*MicrosoftWindows.Client.FileExp*'

# --- Remove Microsoft Teams (new) if not in use ---
$teamsRunning = Get-Process -Name 'ms-teams', 'msteams' -EA 0
if (-not $teamsRunning) {
    Remove-AppxDryRun -Pattern '*MSTeams*'
    Remove-AppxDryRun -Pattern '*MicrosoftTeams*'
    Write-Log "    Teams (new) removed" "INFO"
} else {
    Write-Log "    Teams in use - preserved" "INFO"
}

# --- Disable Phone Link auto-start ---
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Mobility" -Name "OptedIn" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableMmx" -Value 0
Remove-AppxDryRun -Pattern '*Microsoft.YourPhone*'
Remove-AppxDryRun -Pattern '*MicrosoftWindows.CrossDevice*'
if (-not $DryRun) {
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PhoneLink" -Force -EA 0
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PhoneLinkAutoStart" -Force -EA 0
}

Write-Log "  24H2/25H2/26H1 bloat disabled" "SUCCESS"

# Disable Bing Search
Write-Log "  Disabling Bing Search..." "INFO"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDynamicSearchBoxEnabled" -Value 0

# Edge Telemetry
Write-Log "  Disabling Edge telemetry..." "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DiagnosticData" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "PersonalizationReportingEnabled" -Value 0

# Consumer Features (auto-install suggested apps)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1

# OOBE & Nag Screens (fresh-OOBE mode: fully suppress setup/privacy prompts)
Write-Log "  Disabling OOBE & nag screens..." "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" -Name "DisablePrivacyExperience" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name "DisablePrivacyExperience" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name "SkipMachineOOBE" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name "SkipUserOOBE" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableFirstLogonAnimation" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications" -Name "EnableAccountNotifications" -Value 0

# Content Delivery Manager (Start Menu Ads)
Write-Log "  Disabling Start Menu ads..." "INFO"
$CDMPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
@("SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled",
  "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled",
  "SubscribedContent-353698Enabled", "SubscribedContent-88000326Enabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled",
  "ContentDeliveryAllowed", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "RotatingLockScreenEnabled",
  "RotatingLockScreenOverlayEnabled") | ForEach-Object {
    Set-Reg -Path $CDMPath -Name $_ -Value 0
}
