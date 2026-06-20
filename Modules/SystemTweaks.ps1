# ============================================================================
# MODULE: System Tweaks
# Privacy, telemetry, UI, dark mode, SSD, power, network, desktop, etc.
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[System Tweaks] Applying registry tweaks..." "SECTION"
Write-Rationale 'SystemTweaks'

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

# Disable telemetry services (routed through helper for manifest tracking)
@("DiagTrack", "dmwappushservice", "lfsvc", "Fax") | ForEach-Object {
    Disable-ServiceDryRun -ServiceName $_
}

# Disable Copilot, Cortana, Recall
Write-Log "  Disabling Copilot, Cortana, Recall..." "INFO"
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures" -Value 1

# ============================================================================
# WINDOWS 11 24H2/25H2 BLOAT (New in v1.1.0)
# ============================================================================
Write-Log "  Disabling Windows 11 24H2/25H2 bloat..." "INFO"

# --- Disable Windows Recall (AI screenshot feature) thoroughly ---
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "TurnOffSavingSnapshots" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "TurnOffSavingSnapshots" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "AllowRecallEnablement" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableRecall" -Value 0
if (-not $DryRun) {
    $recallFeature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -EA 0
    if ($recallFeature -and $recallFeature.State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -EA 0 | Out-Null
    }
}

# --- 26H1+ AI feature controls (Click to Do, Settings Agent, Agent Workspaces) ---
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSettingsAgent" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentConnectors" -Value 2
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentWorkspaces" -Value 2
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableRemoteAgentConnectors" -Value 2
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableRecallDataProviders" -Value 1

# --- Disable Paint AI features (Cocreator, Image Creator, Generative Fill) ---
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Paint" -Name "DisableImageCreator" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Paint" -Name "DisableGenerativeFill" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Paint" -Name "DisableCocreator" -Value 1

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
# Remove Windows Backup app AppX
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

Write-Log "  24H2/25H2 bloat disabled" "SUCCESS"

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

# Taskbar & UI
Write-Log "  Applying taskbar & UI tweaks..." "INFO"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_AccountNotifications" -Value 0

# Search icon and label on taskbar (0=hidden, 1=icon only, 2=search box, 3=icon+label)
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 3

# Combine taskbar buttons when taskbar is full (0=always, 1=when full, 2=never)
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarGlomLevel" -Value 1

# Dark mode (skip if config overrides DarkMode to $false)
$applyDarkMode = if ($script:configOverrides.ContainsKey('DarkMode')) { $script:configOverrides.DarkMode } else { $true }
if ($applyDarkMode) {
    Write-Log "  Enabling dark mode..." "INFO"
    Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
    Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
} else {
    Write-Log "  Dark mode: SKIPPED (DarkMode=false in config)" "INFO"
}

# Remove Microsoft Store pin from taskbar
if (-not $DryRun) {
    $taskbandPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    Remove-ItemProperty -Path $taskbandPath -Name "Favorites" -Force -EA 0
    Remove-ItemProperty -Path $taskbandPath -Name "FavoritesResolve" -Force -EA 0
}
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "HubMode" -Value 1

# Classic context menu
if (-not $DryRun) {
    reg add "HKCU\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /f 2>$null | Out-Null
}

# Disable GameDVR
Write-Log "  Disabling GameDVR..." "INFO"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0
Set-Reg -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0

# Disable Sticky Keys popup
Write-Log "  Disabling Sticky Keys..." "INFO"
Set-Reg -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "506" -Type "String"
Set-Reg -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Value "58" -Type "String"
Set-Reg -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122" -Type "String"

# Verbose logon
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Value 1

# Remove 3D Objects, Gallery, Home from Explorer
if (-not $DryRun) {
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -EA 0
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" -Recurse -EA 0
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" -Recurse -EA 0
}

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

# ============================================================================
# PERFORMANCE TWEAKS
# ============================================================================
Write-Log "  Applying performance tweaks..." "INFO"

if (-not $DryRun) {
    # High performance power plan (will be overridden later based on hardware)
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null

    # Disable hibernation on desktops only (laptops need it for battery)
    if (-not $script:isLaptop) {
        powercfg /hibernate off 2>$null
    }
}

# Disable background apps globally
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2

# Disable reserved storage
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0

# ============================================================================
# ANNOYANCE FIXES
# ============================================================================
Write-Log "  Disabling Windows nags & popups..." "INFO"

# Disable "New apps can open this file type" notifications
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoNewAppAlert" -Value 1

# Reduce SmartScreen prompts (keep protection)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Warn" -Type "String"

# Disable "Look for app in Store" prompts
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoUseStoreOpenWith" -Value 1

# Disable auto-play
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 1

# Disable people icon on taskbar
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0

# Disable meet now
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Value 1

# ============================================================================
# EXPLORER TWEAKS
# ============================================================================
Write-Log "  Applying Explorer tweaks..." "INFO"

# Open to "This PC" instead of Quick Access
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1

# Disable recent files in Quick Access
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0

# Unpin default folders from Quick Access
if (-not $DryRun) {
    $shell = New-Object -ComObject Shell.Application
    $quickAccess = $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}")
    $foldersToUnpin = @('Desktop', 'Downloads', 'Documents', 'Pictures', 'Music', 'Videos')
    $quickAccess.Items() | ForEach-Object {
        if ($foldersToUnpin -contains $_.Name) {
            $_.InvokeVerb("unpinfromhome")
        }
    }

    # Clear Quick Access recent items database
    $quickAccessDB = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
    Remove-Item "$quickAccessDB\f01b4d95cf55d32a.automaticDestinations-ms" -Force -EA 0
}

# Show full path in title bar
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Value 1

# Expand to current folder in nav pane
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneExpandToCurrentFolder" -Value 1

# Show all folders in nav pane
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -Value 1

# Disable Aero Shake
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisallowShaking" -Value 1

# ============================================================================
# WINDOWS UPDATE CONTROL
# ============================================================================
Write-Log "  Configuring Windows Update..." "INFO"

# Disable auto-restart during active hours
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1

# Set active hours (6am to 11pm)
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursStart" -Value 6
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursEnd" -Value 23

# Disable delivery optimization (P2P updates)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0

# Disable preview builds
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ManagePreviewBuilds" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ManagePreviewBuildsPolicyValue" -Value 0

# Defer feature updates by 365 days (security updates still apply)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value 365
Write-Log "  Feature updates deferred 365 days" "INFO"

# Defer quality updates by 4 days (gives time to catch bad updates)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdates" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdatesPeriodInDays" -Value 4
Write-Log "  Quality updates deferred 4 days" "INFO"

# Disable seeker updates (don't auto-download optional updates)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "SetDisableUXWUAccess" -Value 0

# Notify before download/install (don't auto-install)
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 2

Write-Log "  System tweaks applied" "SUCCESS"

# ============================================================================
# SSD OPTIMIZATION (If SSD detected)
# ============================================================================
if ($script:isSSD) {
    Write-Log "[SSD] Applying SSD optimizations..." "SECTION"

    if (-not $DryRun) {
        # Disable scheduled defrag on SSD (Windows should do this automatically but ensure it)
        $defragTask = Get-ScheduledTask -TaskName "ScheduledDefrag" -EA 0
        if ($defragTask) {
            Write-Log "  Configuring defrag for SSD optimization..." "INFO"
        }

        # Ensure TRIM is enabled
        fsutil behavior set DisableDeleteNotify 0 | Out-Null
        Write-Log "  TRIM enabled" "INFO"

        # Disable last access timestamp (reduces writes)
        fsutil behavior set disablelastaccess 1 | Out-Null
        Write-Log "  Last access timestamp disabled" "INFO"
    } else {
        Write-Log "  [DRY RUN] Would enable TRIM, disable last access timestamp" "INFO"
    }

    # Disable Superfetch/SysMain on SSD (routed through helper for manifest tracking)
    Disable-ServiceDryRun -ServiceName 'SysMain'
    Write-Log "  Superfetch disabled (not needed on SSD)" "INFO"

    # Disable Prefetch on SSD
    Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnablePrefetcher" -Value 0
    Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnableSuperfetch" -Value 0
    Write-Log "  Prefetch disabled (not needed on SSD)" "INFO"

    Write-Log "  SSD optimizations applied" "SUCCESS"
} else {
    Write-Log "[HDD] Keeping HDD-optimized settings..." "SECTION"
    if (-not $DryRun) {
        Set-Service -Name 'SysMain' -StartupType Automatic -EA 0
        Start-Service -Name 'SysMain' -EA 0
    }
    Write-Log "  Superfetch enabled (improves HDD performance)" "INFO"
}

# ============================================================================
# START MENU CLEANUP (Unpin Bloatware Tiles)
# ============================================================================
Write-Log "[Start Menu] Cleaning pinned items..." "SECTION"

if (-not $DryRun) {
    # Windows 11 Start Menu layout cleanup
    $startLayoutPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
    if (Test-Path $startLayoutPath) {
        # Clear Start Menu suggestions
        Get-ChildItem "$startLayoutPath\*windows.data.unifiedtile*" -EA 0 | Remove-Item -Recurse -Force -EA 0
        Get-ChildItem "$startLayoutPath\*windows.data.taskmgr*" -EA 0 | Remove-Item -Recurse -Force -EA 0
    }
}

# FeatureManagementEnabled not covered by the comprehensive CDM block above
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "FeatureManagementEnabled" -Value 0

Write-Log "  Start Menu cleaned" "SUCCESS"

# ============================================================================
# FILE EXPLORER CLEANUP (Remove Clutter)
# ============================================================================
Write-Log "[Explorer] Removing Explorer clutter..." "SECTION"

# Remove Gallery from navigation pane (Windows 11)
Set-Reg -Path "HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" -Name "System.IsPinnedToNameSpaceTree" -Value 0

# Remove Home from navigation pane
Set-Reg -Path "HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" -Name "System.IsPinnedToNameSpaceTree" -Value 0

# Remove 3D Objects folder from This PC
if (-not $DryRun) {
    @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
    ) | ForEach-Object { Remove-Item $_ -Recurse -Force -EA 0 }
}
Write-Log "  Removed 3D Objects folder" "INFO"

# Disable OneDrive ads in Explorer
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSyncProviderNotifications" -Value 0
Write-Log "  Disabled OneDrive ads in Explorer" "INFO"

# Disable "Show more options" (restore Windows 10 context menu on Win11)
# Only apply on Windows 11
if ([int]$osBuild -ge 22000) {
    Set-Reg -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type "String"
    Write-Log "  Restored classic context menu (Windows 11)" "INFO"
}

# Disable ads/tips in Settings app
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0

Write-Log "  Explorer cleanup complete" "SUCCESS"

# ============================================================================
# WIDGETS REMOVAL (Windows 11)
# ============================================================================
if ([int]$osBuild -ge 22000 -and -not $script:isLTSC) {
    Write-Log "[Widgets] Removing Windows 11 Widgets..." "SECTION"

    # Remove Widgets package (Remove-AppxDryRun handles both user and provisioned)
    Remove-AppxDryRun -Pattern '*WebExperience*'
    Remove-AppxDryRun -Pattern '*MicrosoftWindows.Client.WebExperience*'

    Write-Log "  Widgets removed" "SUCCESS"
}

# ============================================================================
# STARTUP APPS CLEANUP (Common Bloatware Auto-Starts)
# ============================================================================
Write-Log "[Startup] Cleaning startup items..." "SECTION"

# Registry Run keys to clean (HKCU)
$startupBloat = if ($script:configOverrides.ContainsKey('StartupBloat')) { $script:configOverrides.StartupBloat } else { @(
    'Spotify',
    'Discord',
    'Steam',
    'EpicGamesLauncher',
    'AdobeGCInvoker*',
    'Adobe Creative Cloud',
    'CCXProcess',
    'AdobeAAMUpdater*',
    'iTunesHelper',
    'Skype*',
    'CiscoMeetingDaemon',
    'com.squirrel*',
    'GoogleUpdate*',
    'Opera*',
    'Brave*',
    'CCleaner*',
    'DropboxUpdate',
    'Lync',
    'CyberLink*'
    # REMOVED: 'Microsoft Teams' - may be needed for business
    # REMOVED: 'Zoom' - may be needed for business
    # REMOVED: 'Update*' - too aggressive, could remove legitimate updaters
) }

if (-not $DryRun) {
    $runKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    foreach ($item in $startupBloat) {
        Get-ItemProperty $runKey -EA 0 | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -like $item } | ForEach-Object {
                Remove-ItemProperty -Path $runKey -Name $_.Name -Force -EA 0
                Write-Log "    Removed: $($_.Name)" "INFO"
            }
        }
    }

    # Also clean HKLM Run (system-wide)
    $runKeyLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    foreach ($item in $startupBloat) {
        Get-ItemProperty $runKeyLM -EA 0 | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -like $item } | ForEach-Object {
                Remove-ItemProperty -Path $runKeyLM -Name $_.Name -Force -EA 0
                Write-Log "    Removed (system): $($_.Name)" "INFO"
            }
        }
    }

    # Clean WOW6432Node Run
    $runKeyWow = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    foreach ($item in $startupBloat) {
        Get-ItemProperty $runKeyWow -EA 0 | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -like $item } | ForEach-Object {
                Remove-ItemProperty -Path $runKeyWow -Name $_.Name -Force -EA 0
            }
        }
    }

    # Disable OneDrive startup if not in use
    if (-not $script:onedriveInUse) {
        Remove-ItemProperty -Path $runKey -Name "OneDrive" -Force -EA 0
        Remove-ItemProperty -Path $runKey -Name "OneDriveSetup" -Force -EA 0
        Write-Log "    Removed: OneDrive (not in use)" "INFO"
    }

    # Clean Startup folder shortcuts
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $startupBloatFiles = @(
        '*Spotify*', '*Discord*', '*Steam*', '*Epic*', '*Adobe*', '*CCleaner*',
        '*Skype*', '*Dropbox*'
        # REMOVED: '*Zoom*', '*Teams*', '*Slack*' - may be needed for business
    )
    foreach ($pattern in $startupBloatFiles) {
        Get-ChildItem $startupFolder -Filter $pattern -EA 0 | Remove-Item -Force -EA 0
    }
} else {
    Write-Log "  [DRY RUN] Would clean startup registry keys and shortcuts" "INFO"
}

Write-Log "  Startup items cleaned" "SUCCESS"

# ============================================================================
# NOTIFICATION CLEANUP (More Comprehensive)
# ============================================================================
Write-Log "[Notifications] Disabling notification spam..." "SECTION"

# Disable Focus Assist notifications about apps
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount" -Name "FocusAssistStateChanged" -Value 0

# Disable notification center promotions
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 1

# But disable specific annoying notification sources (NOT security)
$annoyingNotifiers = @(
    'Windows.SystemToast.Suggested',
    'Windows.SystemToast.HelloFace',
    'Microsoft.Windows.Cortana_cw5n1h2txyewy!CortanaUI',
    'Microsoft.WindowsStore_8wekyb3d8bbwe!App'
)
foreach ($notifier in $annoyingNotifiers) {
    $notifierPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\$notifier"
    Set-Reg -Path $notifierPath -Name "Enabled" -Value 0
}

Write-Log "  Notifications configured" "SUCCESS"

# ============================================================================
# WINDOWS DEFENDER EXCLUSIONS (Medical Imaging Paths)
# ============================================================================
if (-not $KeepDefender) {
    Write-Log "[Defender] Adding folder exclusions..." "SECTION"
    if ($script:tamperProtectionOn) {
        Write-Log "  WARNING: Tamper Protection is enabled -- exclusions may be silently rejected" "WARNING"
    }

    # Allow config file to override Defender exclusions (empty by default; use -ConfigPath for vendor-specific paths)
    $defenderExclusions = if ($script:configOverrides.ContainsKey('DefenderExclusions')) { $script:configOverrides.DefenderExclusions } else { @() }

    if (-not $DryRun) {
        foreach ($path in $defenderExclusions) {
            Add-MpPreference -ExclusionPath $path -EA 0
        }
    } else {
        Write-Log "  [DRY RUN] Would add $($defenderExclusions.Count) Defender exclusions" "INFO"
    }
    Write-Log "  Defender exclusions added" "SUCCESS"
} else {
    Write-Log "[Defender] Skipped (-KeepDefender)" "SECTION"
}

# ============================================================================
# POWER SETTINGS (Hardware-Aware)
# ============================================================================
Write-Log "[Power] Configuring power settings..." "SECTION"

if (-not $DryRun) {
    if ($script:isLaptop) {
        Write-Log "  Applying LAPTOP power profile..." "INFO"

        # Use Balanced power plan for laptops (better battery life)
        powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null

        # === AC (Plugged In) Settings ===
        # USB selective suspend: Disabled on AC (prevent device disconnects when plugged in)
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0

        # Hard disk timeout on AC: Never (0)
        powercfg /setacvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0

        # Monitor timeout on AC: 15 minutes (900 seconds)
        powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 900

        # Sleep on AC: Never (0) - workstation behavior when plugged in
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0

        # Hibernate on AC: Never (0)
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0

        # Lid close action on AC: Do nothing (0)
        powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0

        # === DC (Battery) Settings ===
        # USB selective suspend: Enabled on battery (save power)
        powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1

        # Hard disk timeout on battery: 10 minutes (600 seconds)
        powercfg /setdcvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 600

        # Monitor timeout on battery: 5 minutes (300 seconds)
        powercfg /setdcvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 300

        # Sleep on battery: 15 minutes (900 seconds)
        powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 900

        # Hibernate on battery: 60 minutes (3600 seconds)
        powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 3600

        # Lid close action on battery: Sleep (1)
        powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 1

        # Critical battery action: Hibernate (2)
        powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 2

        # Critical battery level: 5%
        powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469 5

        # Low battery level: 10%
        powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 8183ba9a-e910-48da-8769-14ae6dc1170a 10

        # Power button action: Sleep (1) for both AC and DC
        powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 1
        powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 1

    } else {
        Write-Log "  Applying WORKSTATION power profile..." "INFO"

        # Use High Performance power plan for desktops
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null

        # Disable USB selective suspend (prevents USB device disconnects)
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0

        # Hard disk timeout: Never (0)
        powercfg /setacvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0

        # Monitor timeout: 30 minutes (1800 seconds)
        powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 1800

        # Sleep: Never (0)
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0

        # Hibernate: Never (0)
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0

        # Power button action: Shut down (3)
        powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 3

        # Disable hybrid sleep (can cause issues on workstations)
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 94ac6d29-73ce-41a6-809f-6363ba21b47e 0
    }

    # Apply changes
    powercfg /setactive SCHEME_CURRENT
} else {
    Write-Log "  [DRY RUN] Would configure power settings for $(if ($script:isLaptop) { 'LAPTOP' } else { 'WORKSTATION' })" "INFO"
}

# Disable fast startup (can cause issues with dual-boot and driver loading)
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0

Write-Log "  Power settings configured" "SUCCESS"

# ============================================================================
# NETWORK OPTIMIZATION
# ============================================================================
Write-Log "[Network] Optimizing network settings..." "SECTION"

if (-not $DryRun) {
    # Set network profile to Private (for file sharing)
    Get-NetConnectionProfile -EA 0 | Set-NetConnectionProfile -NetworkCategory Private -EA 0

    # Disable Nagle's algorithm for lower latency (useful for DICOM)
    $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $tcpParams -EA 0 | ForEach-Object {
        Set-Reg -Path $_.PSPath -Name "TcpAckFrequency" -Value 1
        Set-Reg -Path $_.PSPath -Name "TCPNoDelay" -Value 1
    }

    # Enable network discovery and file sharing for private networks
    netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes 2>$null
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 2>$null
} else {
    Write-Log "  [DRY RUN] Would set Private profile, disable Nagle's, enable discovery" "INFO"
}

Write-Log "  Network settings optimized" "SUCCESS"

# ============================================================================
# DESKTOP CLEANUP
# ============================================================================
Write-Log "[Desktop] Cleaning desktop shortcuts..." "SECTION"

if (-not $DryRun) {
    # Remove Edge shortcut from desktop
    @(
        "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
        "$env:USERPROFILE\Desktop\Microsoft Edge.lnk",
        "$env:PUBLIC\Desktop\Microsoft Store.lnk",
        "$env:USERPROFILE\Desktop\Microsoft Store.lnk"
    ) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force -EA 0 }
    }

    # Remove OEM shortcuts from desktop
    Get-ChildItem "$env:PUBLIC\Desktop\*.lnk" -EA 0 | ForEach-Object {
        $target = (New-Object -COM WScript.Shell).CreateShortcut($_.FullName).TargetPath
        if ($target -match 'Dell|HP|Lenovo|ASUS|Acer|MSI|Razer|McAfee|Norton|ExpressVPN|Dropbox') {
            Remove-Item $_.FullName -Force -EA 0
        }
    }
}

Write-Log "  Desktop cleaned" "SUCCESS"

# ============================================================================
# LOCK SCREEN & SPOTLIGHT CLEANUP
# ============================================================================
Write-Log "[Lock Screen] Disabling ads and spotlight..." "SECTION"

# Disable Windows Spotlight (CDM keys handled in comprehensive block above)
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1

# Disable lock screen app notifications
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" -Value 0

Write-Log "  Lock screen configured" "SUCCESS"

# ============================================================================
# SNAP ASSIST & WINDOW MANAGEMENT
# ============================================================================
Write-Log "[Windows] Configuring snap assist..." "SECTION"

# Disable Snap Assist suggestions (annoying popup when snapping windows)
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0

# Disable snap fly-out (Windows 11 snap layouts on hover)
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0

# Disable snap bar (edge snap)
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapBar" -Value 0

# Keep basic snap functionality working
Set-Reg -Path "HKCU:\Control Panel\Desktop" -Name "WindowArrangementActive" -Value 1

Write-Log "  Snap assist configured" "SUCCESS"

# ============================================================================
# WINDOWS INK & TOUCH
# ============================================================================
Write-Log "[Input] Disabling Windows Ink workspace..." "SECTION"

# Disable Windows Ink Workspace
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -Name "AllowWindowsInkWorkspace" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -Name "AllowSuggestedAppsInWindowsInkWorkspace" -Value 0

# Disable pen and touch feedback
Set-Reg -Path "HKCU:\Control Panel\Cursors" -Name "ContactVisualization" -Value 0
Set-Reg -Path "HKCU:\Control Panel\Cursors" -Name "GestureVisualization" -Value 0

# Disable typing insights and personalization
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Input\TIPC" -Name "Enabled" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Value 0

Write-Log "  Input settings configured" "SUCCESS"

# ============================================================================
# SECURITY HARDENING
# ============================================================================
Write-Log "[Security] Applying security settings..." "SECTION"

# Disable Remote Assistance
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowFullControl" -Value 0

# Disable AutoRun/AutoPlay for all drives
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255

# Disable WDigest plaintext credential caching
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -Value 0

# Restrict NTLM to NTLMv2 only
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5

# Disable anonymous SAM enumeration
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 1
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1

# Enable PowerShell script block logging
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1

Write-Log "  Security settings applied" "SUCCESS"

# ============================================================================
# TIME SYNCHRONIZATION
# ============================================================================
Write-Log "[Time] Configuring time sync..." "SECTION"

if (-not $DryRun) {
    # Enable Windows Time service
    Set-Service -Name 'W32Time' -StartupType Automatic -EA 0
    Start-Service -Name 'W32Time' -EA 0

    # Force time sync
    w32tm /resync /force 2>$null

    # Set NTP server (use default Windows time server)
    w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:yes /update 2>$null
}

Write-Log "  Time sync configured" "SUCCESS"

# ============================================================================
# DISABLE DRIVER UPDATES VIA WINDOWS UPDATE
# ============================================================================
Write-Log "[Drivers] Disabling driver updates via Windows Update..." "SECTION"

# Exclude drivers from Windows Update
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0

# Disable automatic device driver downloads
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1

Write-Log "  Driver updates disabled" "SUCCESS"

# ============================================================================
# DEFAULT USER PROFILE CLEANUP (For new user accounts)
# ============================================================================
Write-Log "[Default Profile] Configuring default user settings..." "SECTION"

if (-not $DryRun) {
    $defaultUserReg = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $defaultUserReg) {
        $hiveName = "HKU\DefaultUserClean"
        reg load $hiveName $defaultUserReg 2>$null
        if ($LASTEXITCODE -eq 0) {
            # Apply same tweaks to default user profile
            # Privacy
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null

            # Explorer
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f 2>$null

            # Search
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 3 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f 2>$null

            # Dark mode
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>$null

            # Input personalization
            reg add "$hiveName\SOFTWARE\Microsoft\InputPersonalization" /v RestrictImplicitTextCollection /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\InputPersonalization" /v RestrictImplicitInkCollection /t REG_DWORD /d 1 /f 2>$null

            # OOBE: suppress privacy/setup prompts for new user profiles
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-310093Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v ContentDeliveryAllowed /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v OemPreInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v FeatureManagementEnabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null

            [gc]::Collect()
            Start-Sleep -Milliseconds 500
            reg unload $hiveName 2>$null
            Write-Log "  Default profile configured" "SUCCESS"
        } else {
            Write-Log "  Could not load default profile" "INFO"
        }
    } else {
        Write-Log "  Default profile not found" "INFO"
    }
} else {
    Write-Log "  [DRY RUN] Would configure default user profile" "INFO"
}

# ============================================================================
# CONTEXT MENU CLEANUP
# ============================================================================
Write-Log "[Context Menu] Removing bloat entries..." "SECTION"

# Back up context menu keys to a .reg file for undoable restoration
$contextMenuBackup = "$LogDir\ContextMenu-Backup-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').reg"
$contextMenuKeys = @(
    'HKCR\*\shellex\ContextMenuHandlers\ModernSharing',
    'HKCR\*\shellex\ContextMenuHandlers\Sharing',
    'HKCR\Folder\ShellEx\ContextMenuHandlers\Library Location',
    'HKCR\*\shell\pintohomefile',
    'HKCR\exefile\shellex\ContextMenuHandlers\Compatibility'
)
if (-not $DryRun) {
    foreach ($key in $contextMenuKeys) {
        reg export $key "$env:TEMP\ctx_export.reg" /y 2>$null
        if ($LASTEXITCODE -eq 0) {
            if (Test-Path $contextMenuBackup) {
                Get-Content "$env:TEMP\ctx_export.reg" | Select-Object -Skip 1 | Add-Content $contextMenuBackup
            } else {
                Copy-Item "$env:TEMP\ctx_export.reg" $contextMenuBackup -Force
            }
        }
        Remove-Item "$env:TEMP\ctx_export.reg" -Force -EA 0
    }
    if (Test-Path $contextMenuBackup) {
        $script:manifest.changes.registry_deleted.Add("BACKUP: $contextMenuBackup") | Out-Null
        Write-Log "  Context menu backup: $contextMenuBackup" "INFO"
    }

    @(
        'HKLM\SOFTWARE\Classes\SystemFileAssociations\*\Shell\3D Edit',
        'HKCR\*\shellex\ContextMenuHandlers\ModernSharing',
        'HKCR\*\shellex\ContextMenuHandlers\Sharing',
        'HKCR\Folder\ShellEx\ContextMenuHandlers\Library Location',
        'HKCR\*\shell\pintohomefile',
        'HKCR\exefile\shellex\ContextMenuHandlers\Compatibility'
    ) | ForEach-Object { $script:manifest.changes.registry_deleted.Add($_) | Out-Null }

    # Remove "Edit with Paint 3D" context menu
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.bmp\Shell\3D Edit" /f 2>$null
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.gif\Shell\3D Edit" /f 2>$null
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.jpg\Shell\3D Edit" /f 2>$null
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.jpeg\Shell\3D Edit" /f 2>$null
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.png\Shell\3D Edit" /f 2>$null
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.tif\Shell\3D Edit" /f 2>$null
    reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\.tiff\Shell\3D Edit" /f 2>$null

    # Remove "Edit with Photos" context menu
    reg delete "HKLM\SOFTWARE\Classes\AppX43ber29p0nx6h3tj30w3pdbsqxqaxgjy\Shell\ShellEdit" /f 2>$null

    # Remove "Share" from context menu
    reg delete "HKCR\*\shellex\ContextMenuHandlers\ModernSharing" /f 2>$null

    # Remove "Give access to" from context menu
    reg delete "HKCR\*\shellex\ContextMenuHandlers\Sharing" /f 2>$null
    reg delete "HKCR\Directory\Background\shellex\ContextMenuHandlers\Sharing" /f 2>$null
    reg delete "HKCR\Directory\shellex\ContextMenuHandlers\Sharing" /f 2>$null
    reg delete "HKCR\Drive\shellex\ContextMenuHandlers\Sharing" /f 2>$null

    # Remove "Include in library" from context menu
    reg delete "HKCR\Folder\ShellEx\ContextMenuHandlers\Library Location" /f 2>$null

    # Remove "Restore previous versions" context menu
    reg delete "HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}" /f 2>$null
    reg delete "HKCR\CLSID\{450D8FBA-AD25-11D0-98A8-0800361B1103}\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}" /f 2>$null
    reg delete "HKCR\Directory\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}" /f 2>$null
    reg delete "HKCR\Drive\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}" /f 2>$null

    # Remove "Add to Favorites" from context menu
    reg delete "HKCR\*\shell\pintohomefile" /f 2>$null

    # Remove "Troubleshoot compatibility" from context menu
    reg delete "HKCR\exefile\shellex\ContextMenuHandlers\Compatibility" /f 2>$null
    reg delete "HKCR\batfile\shellex\ContextMenuHandlers\Compatibility" /f 2>$null
    reg delete "HKCR\cmdfile\shellex\ContextMenuHandlers\Compatibility" /f 2>$null
    reg delete "HKCR\Msi.Package\shellex\ContextMenuHandlers\Compatibility" /f 2>$null

    # Remove "Send to" bloat items
    @(
        "$env:APPDATA\Microsoft\Windows\SendTo\Bluetooth File Transfer.LNK",
        "$env:APPDATA\Microsoft\Windows\SendTo\Fax Recipient.lnk"
    ) | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Force -EA 0 } }
} else {
    Write-Log "  [DRY RUN] Would remove context menu bloat entries" "INFO"
}

Write-Log "  Context menu cleaned" "SUCCESS"

# ============================================================================
# DISABLE WINDOWS OPTIONAL FEATURES
# ============================================================================
Write-Log "[Optional Features] Disabling legacy features..." "SECTION"

$featuresToDisable = if ($script:configOverrides.ContainsKey('FeaturesToDisable')) { $script:configOverrides.FeaturesToDisable } else { @(
    'Internet-Explorer-Optional-amd64',   # Internet Explorer mode
    'MicrosoftWindowsPowerShellV2Root',   # PowerShell v2 (security risk)
    'MicrosoftWindowsPowerShellV2',       # PowerShell v2 engine
    'MediaPlayback',                       # Windows Media Player legacy
    'WindowsMediaPlayer',                  # Windows Media Player
    'WorkFolders-Client',                  # Work Folders
    'Printing-XPSServices-Features',       # XPS Viewer
    'SMB1Protocol',                        # SMB v1 (security risk)
    'SMB1Protocol-Client',                 # SMB v1 client
    'SMB1Protocol-Server'                  # SMB v1 server
) }

if (-not $DryRun) {
    foreach ($feature in $featuresToDisable) {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -EA 0
        if ($state -and $state.State -eq 'Enabled') {
            Write-Log "  Disabling $feature..." "INFO"
            Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -EA 0 | Out-Null
        }
    }
} else {
    Write-Log "  [DRY RUN] Would disable $($featuresToDisable.Count) optional features" "INFO"
}

Write-Log "  Optional features configured" "SUCCESS"

# ============================================================================
# ALL-USERS HKCU PROPAGATION (when -AllUsers is set)
# ============================================================================
if ($AllUsers -and -not $DryRun) {
    Write-Log "[AllUsers] Applying HKCU tweaks to all user profiles..." "SECTION"

    # Load shared definitions from Modules/HkcuTweaks.psd1
    $hkcuDataFile = Join-Path $PSScriptRoot 'Modules\HkcuTweaks.psd1'
    if (Test-Path $hkcuDataFile) {
        $hkcuTweaks = & ([scriptblock]::Create((Get-Content $hkcuDataFile -Raw)))
    } else {
        Write-Log "  WARNING: HkcuTweaks.psd1 not found, skipping AllUsers propagation" "WARNING"
        $hkcuTweaks = @()
    }

    $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default User|All Users)$' }
    $appliedCount = 0
    foreach ($userProf in $userProfiles) {
        $ntuser = "$($userProf.FullName)\NTUSER.DAT"
        if (!(Test-Path $ntuser)) { continue }

        $hiveName = "HKU\AllUsers_$($userProf.Name -replace '[^a-zA-Z0-9]','_')"
        reg load $hiveName $ntuser 2>$null
        if ($LASTEXITCODE -ne 0) { continue }

        foreach ($tweak in $hkcuTweaks) {
            reg add "$hiveName\$($tweak.Path)" /v $tweak.Name /t REG_DWORD /d $tweak.Value /f 2>$null | Out-Null
        }

        [gc]::Collect()
        Start-Sleep -Milliseconds 200
        reg unload $hiveName 2>$null
        $appliedCount++
    }
    Write-Log "  Applied HKCU tweaks to $appliedCount user profiles" "SUCCESS"
} elseif ($AllUsers -and $DryRun) {
    $profileCount = (Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default User|All Users)$' }).Count
    Write-Log "  [DRY RUN] Would apply HKCU tweaks to $profileCount user profiles" "INFO"
}
