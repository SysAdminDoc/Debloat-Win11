# ============================================================================
# SystemTweaks sub-module: UI, Taskbar, Explorer, Desktop, Notifications
# Dot-sourced by SystemTweaks.ps1 -- runs in caller's scope
# ============================================================================

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
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 3
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

# ============================================================================
# EXPLORER TWEAKS
# ============================================================================
Write-Log "  Applying Explorer tweaks..." "INFO"
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0

if (-not $DryRun) {
    $shell = New-Object -ComObject Shell.Application
    $quickAccess = $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}")
    $foldersToUnpin = @('Desktop', 'Downloads', 'Documents', 'Pictures', 'Music', 'Videos')
    $quickAccess.Items() | ForEach-Object {
        if ($foldersToUnpin -contains $_.Name) { $_.InvokeVerb("unpinfromhome") }
    }
    $quickAccessDB = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
    Remove-Item "$quickAccessDB\f01b4d95cf55d32a.automaticDestinations-ms" -Force -EA 0
}

Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneExpandToCurrentFolder" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisallowShaking" -Value 1

# ============================================================================
# START MENU CLEANUP (Unpin Bloatware Tiles)
# ============================================================================
Write-Log "[Start Menu] Cleaning pinned items..." "SECTION"
if (-not $DryRun) {
    $startLayoutPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
    if (Test-Path $startLayoutPath) {
        Get-ChildItem "$startLayoutPath\*windows.data.unifiedtile*" -EA 0 | Remove-Item -Recurse -Force -EA 0
        Get-ChildItem "$startLayoutPath\*windows.data.taskmgr*" -EA 0 | Remove-Item -Recurse -Force -EA 0
    }
}
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "FeatureManagementEnabled" -Value 0
Write-Log "  Start Menu cleaned" "SUCCESS"

# ============================================================================
# FILE EXPLORER CLEANUP (Remove Clutter)
# ============================================================================
Write-Log "[Explorer] Removing Explorer clutter..." "SECTION"
Set-Reg -Path "HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" -Name "System.IsPinnedToNameSpaceTree" -Value 0
Set-Reg -Path "HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" -Name "System.IsPinnedToNameSpaceTree" -Value 0
if (-not $DryRun) {
    @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
    ) | ForEach-Object { Remove-Item $_ -Recurse -Force -EA 0 }
}
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSyncProviderNotifications" -Value 0
if ([int]$osBuild -ge 22000) {
    Set-Reg -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type "String"
    Write-Log "  Restored classic context menu (Windows 11)" "INFO"
}
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0
Write-Log "  Explorer cleanup complete" "SUCCESS"

# ============================================================================
# WIDGETS REMOVAL (Windows 11)
# ============================================================================
if ([int]$osBuild -ge 22000 -and -not $script:isLTSC) {
    Write-Log "[Widgets] Removing Windows 11 Widgets..." "SECTION"
    Remove-AppxDryRun -Pattern '*WebExperience*'
    Remove-AppxDryRun -Pattern '*MicrosoftWindows.Client.WebExperience*'
    Write-Log "  Widgets removed" "SUCCESS"
}

# ============================================================================
# DESKTOP CLEANUP
# ============================================================================
Write-Log "[Desktop] Cleaning desktop shortcuts..." "SECTION"
if (-not $DryRun) {
    @(
        "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
        "$env:USERPROFILE\Desktop\Microsoft Edge.lnk",
        "$env:PUBLIC\Desktop\Microsoft Store.lnk",
        "$env:USERPROFILE\Desktop\Microsoft Store.lnk"
    ) | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Force -EA 0 } }
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
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" -Value 0
Write-Log "  Lock screen configured" "SUCCESS"

# ============================================================================
# SNAP ASSIST & WINDOW MANAGEMENT
# ============================================================================
Write-Log "[Windows] Configuring snap assist..." "SECTION"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapBar" -Value 0
Set-Reg -Path "HKCU:\Control Panel\Desktop" -Name "WindowArrangementActive" -Value 1
Write-Log "  Snap assist configured" "SUCCESS"

# ============================================================================
# NOTIFICATION CLEANUP
# ============================================================================
Write-Log "[Notifications] Disabling notification spam..." "SECTION"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount" -Name "FocusAssistStateChanged" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 1
$annoyingNotifiers = @(
    'Windows.SystemToast.Suggested',
    'Windows.SystemToast.HelloFace',
    'Microsoft.Windows.Cortana_cw5n1h2txyewy!CortanaUI',
    'Microsoft.WindowsStore_8wekyb3d8bbwe!App'
)
foreach ($notifier in $annoyingNotifiers) {
    Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\$notifier" -Name "Enabled" -Value 0
}
Write-Log "  Notifications configured" "SUCCESS"

# ============================================================================
# WINDOWS INK & TOUCH
# ============================================================================
Write-Log "[Input] Disabling Windows Ink workspace..." "SECTION"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -Name "AllowWindowsInkWorkspace" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -Name "AllowSuggestedAppsInWindowsInkWorkspace" -Value 0
Set-Reg -Path "HKCU:\Control Panel\Cursors" -Name "ContactVisualization" -Value 0
Set-Reg -Path "HKCU:\Control Panel\Cursors" -Name "GestureVisualization" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Input\TIPC" -Name "Enabled" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Value 0
Write-Log "  Input settings configured" "SUCCESS"
