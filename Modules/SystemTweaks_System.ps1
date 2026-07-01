# ============================================================================
# SystemTweaks sub-module: Security, Time, Drivers, Profiles, Context Menu, Features, AllUsers
# Dot-sourced by SystemTweaks.ps1 -- runs in caller's scope
# ============================================================================

# ============================================================================
# SECURITY HARDENING
# ============================================================================
Write-Log "[Security] Applying security settings..." "SECTION"
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowFullControl" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -Value 0
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 1
Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1
Write-Log "  Security settings applied" "SUCCESS"

# ============================================================================
# TIME SYNCHRONIZATION
# ============================================================================
Write-Log "[Time] Configuring time sync..." "SECTION"
if (-not $DryRun) {
    Set-Service -Name 'W32Time' -StartupType Automatic -EA 0
    Start-Service -Name 'W32Time' -EA 0
    w32tm /resync /force 2>$null
    w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:yes /update 2>$null
}
Write-Log "  Time sync configured" "SUCCESS"

# ============================================================================
# DISABLE DRIVER UPDATES VIA WINDOWS UPDATE
# ============================================================================
Write-Log "[Drivers] Disabling driver updates via Windows Update..." "SECTION"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0
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
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 3 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\InputPersonalization" /v RestrictImplicitTextCollection /t REG_DWORD /d 1 /f 2>$null
            reg add "$hiveName\SOFTWARE\Microsoft\InputPersonalization" /v RestrictImplicitInkCollection /t REG_DWORD /d 1 /f 2>$null
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

    @('.bmp','.gif','.jpg','.jpeg','.png','.tif','.tiff') | ForEach-Object {
        reg delete "HKLM\SOFTWARE\Classes\SystemFileAssociations\$_\Shell\3D Edit" /f 2>$null
    }
    reg delete "HKLM\SOFTWARE\Classes\AppX43ber29p0nx6h3tj30w3pdbsqxqaxgjy\Shell\ShellEdit" /f 2>$null
    reg delete "HKCR\*\shellex\ContextMenuHandlers\ModernSharing" /f 2>$null
    @('HKCR\*', 'HKCR\Directory\Background', 'HKCR\Directory', 'HKCR\Drive') | ForEach-Object {
        reg delete "$_\shellex\ContextMenuHandlers\Sharing" /f 2>$null
    }
    reg delete "HKCR\Folder\ShellEx\ContextMenuHandlers\Library Location" /f 2>$null
    @('HKCR\AllFilesystemObjects', 'HKCR\CLSID\{450D8FBA-AD25-11D0-98A8-0800361B1103}', 'HKCR\Directory', 'HKCR\Drive') | ForEach-Object {
        reg delete "$_\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}" /f 2>$null
    }
    reg delete "HKCR\*\shell\pintohomefile" /f 2>$null
    @('HKCR\exefile', 'HKCR\batfile', 'HKCR\cmdfile', 'HKCR\Msi.Package') | ForEach-Object {
        reg delete "$_\shellex\ContextMenuHandlers\Compatibility" /f 2>$null
    }
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
    'Internet-Explorer-Optional-amd64',
    'MicrosoftWindowsPowerShellV2Root',
    'MicrosoftWindowsPowerShellV2',
    'MediaPlayback',
    'WindowsMediaPlayer',
    'WorkFolders-Client',
    'Printing-XPSServices-Features',
    'SMB1Protocol',
    'SMB1Protocol-Client',
    'SMB1Protocol-Server'
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

    $hkcuDataFile = Join-Path $PSScriptRoot 'HkcuTweaks.psd1'
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
