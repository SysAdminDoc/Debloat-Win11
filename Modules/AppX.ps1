# ============================================================================
# MODULE: AppX Package Removal
# Phase 1: Remove bloatware AppX packages (user + provisioned)
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[AppX] Removing bloatware packages..." "SECTION"
Write-Rationale 'AppX'
if ($script:isLTSC) {
    Write-Log "  LTSC edition: most consumer AppX packages are not present -- removals will be no-ops" "INFO"
}

# Allow config file to override; fall back to the canonical list from the orchestrator
$removePatterns = if ($script:configOverrides.ContainsKey('RemovePatterns')) { $script:configOverrides.RemovePatterns } else { $script:defaultRemovePatterns }

foreach ($pattern in $removePatterns) {
    Remove-AppxDryRun -Pattern $pattern
}

# Explicit Xbox/Gaming removal (Xbox Live, Gaming Services)
Remove-AppxDryRun -Pattern '*Xbox*'
Remove-AppxDryRun -Pattern '*Gaming*'

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

# Set RemoveDefaultMicrosoftStorePackages policy on Enterprise/Education 24H2+
# This Microsoft-supported policy blocks reinstallation after Windows Update
if ($editionId -match 'Enterprise|Education' -and [int]$osBuild -ge 26100) {
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
    Set-Reg -Path $policyPath -Name "RemoveDefaultMicrosoftStorePackages" -Value 1
    $pfnPath = "$policyPath\RemoveDefaultMicrosoftStorePackages"
    if (-not $DryRun -and !(Test-Path $pfnPath)) { New-Item -Path $pfnPath -Force | Out-Null }
    $storePfns = @(
        'Clipchamp.Clipchamp_yxz26nhyzhsrt',
        'Microsoft.BingNews_8wekyb3d8bbwe',
        'Microsoft.BingSearch_8wekyb3d8bbwe',
        'Microsoft.BingWeather_8wekyb3d8bbwe',
        'Microsoft.Copilot_8wekyb3d8bbwe',
        'Microsoft.Windows.Ai.Copilot.Provider_8wekyb3d8bbwe',
        'Microsoft.Edge.GameAssist_8wekyb3d8bbwe',
        'Microsoft.GamingApp_8wekyb3d8bbwe',
        'Microsoft.GetHelp_8wekyb3d8bbwe',
        'Microsoft.Getstarted_8wekyb3d8bbwe',
        'Microsoft.M365Companions_8wekyb3d8bbwe',
        'Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe',
        'Microsoft.MicrosoftSolitaireCollection_8wekyb3d8bbwe',
        'Microsoft.OutlookForWindows_8wekyb3d8bbwe',
        'Microsoft.PCManager_8wekyb3d8bbwe',
        'Microsoft.StartExperiencesApp_8wekyb3d8bbwe',
        'Microsoft.Todos_8wekyb3d8bbwe',
        'Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe',
        'Microsoft.Windows.AIHub_8wekyb3d8bbwe',
        'Microsoft.Windows.DevHome_8wekyb3d8bbwe',
        'Microsoft.WindowsBackup_8wekyb3d8bbwe',
        'Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe',
        'MicrosoftWindows.Client.FileExp_cw5n1h2txyewy',
        'MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy',
        'MicrosoftWindows.CrossDevice_cw5n1h2txyewy',
        'MSTeams_8wekyb3d8bbwe',
        'Microsoft.Xbox.TCUI_8wekyb3d8bbwe',
        'Microsoft.XboxGamingOverlay_8wekyb3d8bbwe',
        'Microsoft.XboxIdentityProvider_8wekyb3d8bbwe',
        'Microsoft.XboxSpeechToTextOverlay_8wekyb3d8bbwe',
        'Microsoft.ZuneMusic_8wekyb3d8bbwe'
    )
    $invalidPfns = $storePfns | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9.]+_[A-Za-z0-9]+$' }
    if ($invalidPfns.Count -gt 0) {
        Write-Log "  WARNING: RemoveDefaultMicrosoftStorePackages PFN validation failed: $($invalidPfns -join ', ')" "WARNING"
    }
    $dynamicRemovalList = $storePfns -join '&#x0D;&#x0A;'
    $storeRemovalCspPayload = "<enabled/><data id=""DynamicRemovalList"" value=""$dynamicRemovalList""/>"
    Write-Log "  RemoveDefaultMicrosoftStorePackages CSP payload: $storeRemovalCspPayload" "INFO"
    Write-Log "  WARNING: Do not deploy both GPO registry and Intune OMA-URI payloads for RemoveDefaultMicrosoftStorePackages on the same device" "WARNING"
    $idx = 1
    foreach ($pfn in $storePfns) {
        Set-Reg -Path $pfnPath -Name "$idx" -Value $pfn -Type "String"
        $idx++
    }
    if (-not $DryRun) {
        $writtenPfns = 1..$storePfns.Count | ForEach-Object {
            $entry = Get-ItemProperty -Path $pfnPath -Name "$_" -EA 0
            if ($entry) { $entry."$_" }
        }
        if (@($writtenPfns).Count -ne $storePfns.Count) {
            Write-Log "  WARNING: RemoveDefaultMicrosoftStorePackages registry validation wrote $(@($writtenPfns).Count)/$($storePfns.Count) PFNs" "WARNING"
        } else {
            Write-Log "  RemoveDefaultMicrosoftStorePackages registry validation passed ($($storePfns.Count) PFNs)" "INFO"
        }
    } else {
        Write-Log "  [DRY RUN] Would validate RemoveDefaultMicrosoftStorePackages registry shape after writing $($storePfns.Count) PFNs" "INFO"
    }
    Write-Log "  RemoveDefaultMicrosoftStorePackages policy set ($($storePfns.Count) packages)" "INFO"
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
