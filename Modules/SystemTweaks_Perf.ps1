# ============================================================================
# SystemTweaks sub-module: Performance, SSD/HDD, Windows Update, Startup, Power, Network
# Dot-sourced by SystemTweaks.ps1 -- runs in caller's scope
# ============================================================================

# ============================================================================
# PERFORMANCE TWEAKS
# ============================================================================
Write-Log "  Applying performance tweaks..." "INFO"

if (-not $DryRun) {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    if (-not $script:isLaptop) { powercfg /hibernate off 2>$null }
}

Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0

# ============================================================================
# ANNOYANCE FIXES
# ============================================================================
Write-Log "  Disabling Windows nags & popups..." "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoNewAppAlert" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Warn" -Type "String"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoUseStoreOpenWith" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 1
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -Value 1

# ============================================================================
# WINDOWS UPDATE CONTROL
# ============================================================================
Write-Log "  Configuring Windows Update..." "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursStart" -Value 6
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursEnd" -Value 23
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ManagePreviewBuilds" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ManagePreviewBuildsPolicyValue" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdates" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value 365
Write-Log "  Feature updates deferred 365 days" "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdates" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferQualityUpdatesPeriodInDays" -Value 4
Write-Log "  Quality updates deferred 4 days" "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "SetDisableUXWUAccess" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 2

Write-Log "  System tweaks applied" "SUCCESS"

# ============================================================================
# SSD OPTIMIZATION (If SSD detected)
# ============================================================================
if ($script:isSSD) {
    Write-Log "[SSD] Applying SSD optimizations..." "SECTION"
    if (-not $DryRun) {
        $defragTask = Get-ScheduledTask -TaskName "ScheduledDefrag" -EA 0
        if ($defragTask) { Write-Log "  Configuring defrag for SSD optimization..." "INFO" }
        fsutil behavior set DisableDeleteNotify 0 | Out-Null
        Write-Log "  TRIM enabled" "INFO"
        fsutil behavior set disablelastaccess 1 | Out-Null
        Write-Log "  Last access timestamp disabled" "INFO"
    } else {
        Write-Log "  [DRY RUN] Would enable TRIM, disable last access timestamp" "INFO"
    }
    Disable-ServiceDryRun -ServiceName 'SysMain'
    Write-Log "  Superfetch disabled (not needed on SSD)" "INFO"
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
# STARTUP APPS CLEANUP (Common Bloatware Auto-Starts)
# ============================================================================
Write-Log "[Startup] Cleaning startup items..." "SECTION"

$startupBloat = if ($script:configOverrides.ContainsKey('StartupBloat')) { $script:configOverrides.StartupBloat } else { @(
    'Spotify', 'Discord', 'Steam', 'EpicGamesLauncher', 'AdobeGCInvoker*',
    'Adobe Creative Cloud', 'CCXProcess', 'AdobeAAMUpdater*', 'iTunesHelper',
    'Skype*', 'CiscoMeetingDaemon', 'com.squirrel*', 'GoogleUpdate*',
    'Opera*', 'Brave*', 'CCleaner*', 'DropboxUpdate', 'Lync', 'CyberLink*'
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
    $runKeyLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    foreach ($item in $startupBloat) {
        Get-ItemProperty $runKeyLM -EA 0 | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -like $item } | ForEach-Object {
                Remove-ItemProperty -Path $runKeyLM -Name $_.Name -Force -EA 0
                Write-Log "    Removed (system): $($_.Name)" "INFO"
            }
        }
    }
    $runKeyWow = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    foreach ($item in $startupBloat) {
        Get-ItemProperty $runKeyWow -EA 0 | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -like $item } | ForEach-Object {
                Remove-ItemProperty -Path $runKeyWow -Name $_.Name -Force -EA 0
            }
        }
    }
    if (-not $script:onedriveInUse) {
        Remove-ItemProperty -Path $runKey -Name "OneDrive" -Force -EA 0
        Remove-ItemProperty -Path $runKey -Name "OneDriveSetup" -Force -EA 0
        Write-Log "    Removed: OneDrive (not in use)" "INFO"
    }
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    @('*Spotify*', '*Discord*', '*Steam*', '*Epic*', '*Adobe*', '*CCleaner*', '*Skype*', '*Dropbox*') | ForEach-Object {
        Get-ChildItem $startupFolder -Filter $_ -EA 0 | Remove-Item -Force -EA 0
    }
} else {
    Write-Log "  [DRY RUN] Would clean startup registry keys and shortcuts" "INFO"
}
Write-Log "  Startup items cleaned" "SUCCESS"

# ============================================================================
# WINDOWS DEFENDER EXCLUSIONS
# ============================================================================
if (-not $KeepDefender) {
    Write-Log "[Defender] Adding folder exclusions..." "SECTION"
    if ($script:tamperProtectionOn) {
        Write-Log "  WARNING: Tamper Protection is enabled -- exclusions may be silently rejected" "WARNING"
    }
    $defenderExclusions = if ($script:configOverrides.ContainsKey('DefenderExclusions')) { $script:configOverrides.DefenderExclusions } else { @() }
    if (-not $DryRun) {
        foreach ($path in $defenderExclusions) { Add-MpPreference -ExclusionPath $path -EA 0 }
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
        powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /setacvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0
        powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 900
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
        powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
        powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1
        powercfg /setdcvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 600
        powercfg /setdcvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 300
        powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 900
        powercfg /setdcvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 3600
        powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 1
        powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 2
        powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469 5
        powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 8183ba9a-e910-48da-8769-14ae6dc1170a 10
        powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 1
        powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 1
    } else {
        Write-Log "  Applying WORKSTATION power profile..." "INFO"
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /setacvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0
        powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 1800
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
        powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 3
        powercfg /setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 94ac6d29-73ce-41a6-809f-6363ba21b47e 0
    }
    powercfg /setactive SCHEME_CURRENT
} else {
    Write-Log "  [DRY RUN] Would configure power settings for $(if ($script:isLaptop) { 'LAPTOP' } else { 'WORKSTATION' })" "INFO"
}

Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0
Write-Log "  Power settings configured" "SUCCESS"

# ============================================================================
# NETWORK OPTIMIZATION
# ============================================================================
Write-Log "[Network] Optimizing network settings..." "SECTION"
if (-not $DryRun) {
    Get-NetConnectionProfile -EA 0 | Set-NetConnectionProfile -NetworkCategory Private -EA 0
    $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $tcpParams -EA 0 | ForEach-Object {
        Set-Reg -Path $_.PSPath -Name "TcpAckFrequency" -Value 1
        Set-Reg -Path $_.PSPath -Name "TCPNoDelay" -Value 1
    }
    netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes 2>$null
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 2>$null
} else {
    Write-Log "  [DRY RUN] Would set Private profile, disable Nagle's, enable discovery" "INFO"
}
Write-Log "  Network settings optimized" "SUCCESS"
