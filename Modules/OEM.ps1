# ============================================================================
# MODULE: OEM Cleanup
# Phase 2: OEM bloatware removal (Dell, HP, Lenovo, ASUS, Acer, MSI, Razer)
# Includes nuclear clean, bloat scheduled tasks, OEM registry
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[OEM] Removing OEM bloatware..." "SECTION"
Write-Rationale 'OEM'

# Intel chipset/driver services and processes that must NOT be killed
$script:oemSafeIntelPattern = 'igfx|IntelAudio|Intel.*Driver|Intel.*Chipset|IntcDAud|IntcOED|IntelManagementEngine|imesrv|jhi_service|LMS'
$script:oemMatchPattern = 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer'

# Config-driven OEM manufacturer exclusion
$script:oemExclude = if ($script:configOverrides.ContainsKey('OemExclude')) { $script:configOverrides.OemExclude } else { @() }

function Test-OemTarget {
    param([string]$Name, [string]$DisplayName)
    if ($script:oemExclude.Count -gt 0) {
        foreach ($excl in $script:oemExclude) {
            if ($Name -match $excl -or $DisplayName -match $excl) { return $false }
        }
    }
    $isOem = ($Name -match $script:oemMatchPattern -or $DisplayName -match $script:oemMatchPattern)
    $isSafe = ($Name -match $script:oemSafeIntelPattern -or $DisplayName -match $script:oemSafeIntelPattern)
    return ($isOem -and -not $isSafe)
}

Write-Log "  Disabling OEM services..." "INFO"
$oemServices = @(Get-Service | Where-Object { Test-OemTarget $_.Name $_.DisplayName })
$script:counters.OEMCleaned += $oemServices.Count
if (-not $DryRun) {
    foreach ($svc in $oemServices) {
        Stop-Service -Name $svc.Name -Force -EA 0
        Set-Service -Name $svc.Name -StartupType Disabled -EA 0
    }

    Write-Log "  Killing OEM processes..." "INFO"
    Get-Process -EA 0 | Where-Object { Test-OemTarget $_.Name ($_.Path -replace '.*\\','') } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -EA 0
    }
}

# AppX removal (routed through Remove-AppxDryRun for DryRun + manifest tracking)
$oemAppxPatterns = @('*Dell*','*DB6EA5DB*','*HONHAIPRECISION*','*Intel*','*AppUp*','*HPInc*','*Lenovo*','*Dolby*','*Realtek*','*Waves*')
foreach ($pattern in $oemAppxPatterns) {
    Remove-AppxDryRun -Pattern $pattern
}
if (-not $DryRun) {
    Get-Package *Dell* 2>$null | Uninstall-Package -Force 2>$null
    Get-Package *Intel* 2>$null | Uninstall-Package -Force 2>$null
}

Write-Log "  OEM AppX packages removed" "SUCCESS"

# ============================================================================
# PHASE 2B: OEM NUCLEAR CLEAN (Skip uninstallers, delete everything)
# ============================================================================
Write-Log "[OEM] OEM Nuclear Clean..." "SECTION"

if (-not $DryRun) {
    # Kill all OEM processes again (in case any respawned)
    Get-Process -EA 0 | Where-Object { Test-OemTarget $_.Name ($_.Path -replace '.*\\','') } | Stop-Process -Force -EA 0

    # Delete OEM folders - Program Files
    Write-Log "  Nuking OEM folders..." "INFO"

    # Take ownership and delete stubborn ProgramData folders
    @(
        "$env:ProgramData\Dell",
        "$env:ProgramData\Waves",
        "C:\dell",
        "C:\langpacks"
    ) | ForEach-Object {
        if (Test-Path $_) {
            $script:manifest.changes.folders_deleted.Add($_) | Out-Null
            takeown /F $_ /R /A /D Y 2>$null | Out-Null
            icacls $_ /grant Administrators:F /T /C /Q 2>$null | Out-Null
            Remove-Item $_ -Recurse -Force -EA 0
        }
    }

    # Delete Dell Start Menu folder
    $dellStartMenu = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Dell"
    if (Test-Path $dellStartMenu) {
        $script:manifest.changes.folders_deleted.Add($dellStartMenu) | Out-Null
        Remove-Item $dellStartMenu -Recurse -Force -EA 0
    }

    # Delete other OEM Start Menu folders
    @(
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\HP",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Lenovo",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\ASUS",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Acer",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\MSI",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Razer"
    ) | ForEach-Object {
        if (Test-Path $_) { $script:manifest.changes.folders_deleted.Add($_) | Out-Null; Remove-Item $_ -Recurse -Force -EA 0 }
    }

    # Clear Accessibility shortcuts (common location)
    $accessibilityCommon = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Accessibility"
    if (Test-Path $accessibilityCommon) {
        Remove-Item "$accessibilityCommon\*" -Recurse -Force -EA 0
    }

    @(
        "$env:ProgramFiles\Dell",
        "$env:ProgramFiles\DellTPad",
        "${env:ProgramFiles(x86)}\Dell",
        "${env:ProgramFiles(x86)}\Dell Digital Delivery Services",
        "$env:ProgramData\DellTechHub",
        "$env:LOCALAPPDATA\Dell",
        "$env:APPDATA\Dell",
        "$env:ProgramFiles\Intel",
        "${env:ProgramFiles(x86)}\Intel",
        "$env:ProgramData\Intel",
        "$env:LOCALAPPDATA\Intel",
        "$env:ProgramFiles\HP",
        "${env:ProgramFiles(x86)}\HP",
        "${env:ProgramFiles(x86)}\Hewlett-Packard",
        "$env:ProgramData\HP",
        "$env:ProgramData\Hewlett-Packard",
        "$env:LOCALAPPDATA\HP",
        "$env:ProgramFiles\Lenovo",
        "${env:ProgramFiles(x86)}\Lenovo",
        "$env:ProgramData\Lenovo",
        "$env:LOCALAPPDATA\Lenovo",
        "$env:ProgramFiles\Realtek",
        "${env:ProgramFiles(x86)}\Realtek",
        "$env:ProgramData\Realtek",
        "$env:ProgramFiles\Waves",
        "${env:ProgramFiles(x86)}\Waves",
        # ASUS
        "$env:ProgramFiles\ASUS",
        "${env:ProgramFiles(x86)}\ASUS",
        "$env:ProgramData\ASUS",
        "$env:LOCALAPPDATA\ASUS",
        "$env:ProgramFiles\ARMOURY CRATE",
        "${env:ProgramFiles(x86)}\ARMOURY CRATE",
        "$env:ProgramData\ASUS\ARMOURY CRATE",
        # Acer
        "$env:ProgramFiles\Acer",
        "${env:ProgramFiles(x86)}\Acer",
        "$env:ProgramData\Acer",
        "$env:LOCALAPPDATA\Acer",
        # MSI
        "$env:ProgramFiles\MSI",
        "${env:ProgramFiles(x86)}\MSI",
        "$env:ProgramData\MSI",
        "$env:LOCALAPPDATA\MSI",
        "$env:ProgramFiles\Dragon Center",
        "${env:ProgramFiles(x86)}\Dragon Center",
        # Razer
        "$env:ProgramFiles\Razer",
        "${env:ProgramFiles(x86)}\Razer",
        "$env:ProgramData\Razer",
        "$env:LOCALAPPDATA\Razer"
    ) | ForEach-Object {
        if (Test-Path $_) {
            $script:manifest.changes.folders_deleted.Add($_) | Out-Null
            Remove-Item $_ -Recurse -Force -EA 0
        }
    }

    # Delete OEM folders - All user profiles
    $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
    foreach ($userProf in $userProfiles) {
        @(
            "$($userProf.FullName)\AppData\Local\Dell",
            "$($userProf.FullName)\AppData\Roaming\Dell",
            "$($userProf.FullName)\AppData\Local\DellTechHub",
            "$($userProf.FullName)\AppData\Local\Intel",
            "$($userProf.FullName)\AppData\Roaming\Intel",
            "$($userProf.FullName)\AppData\Local\HP",
            "$($userProf.FullName)\AppData\Roaming\HP",
            "$($userProf.FullName)\AppData\Local\Lenovo",
            "$($userProf.FullName)\AppData\Roaming\Lenovo"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
        }

        # Clear Accessibility shortcuts
        $accessibilityPath = "$($userProf.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Accessibility"
        if (Test-Path $accessibilityPath) {
            Remove-Item "$accessibilityPath\*" -Recurse -Force -EA 0
        }
    }

    # Delete OEM services (preserving Intel chipset/driver services)
    Write-Log "  Nuking OEM services..." "INFO"
    Get-Service | Where-Object { Test-OemTarget $_.Name $_.DisplayName } | ForEach-Object {
        $script:manifest.changes.services_deleted.Add($_.Name) | Out-Null
        Stop-Service -Name $_.Name -Force -EA 0
        sc.exe delete $_.Name 2>$null
    }

    # Disable WavesSvc64 specifically
    if (Get-Service -Name 'WavesSvc64' -EA 0) {
        $script:manifest.changes.services_deleted.Add('WavesSvc64') | Out-Null
    }
    Stop-Service -Name 'WavesSvc64' -Force -EA 0
    Set-Service -Name 'WavesSvc64' -StartupType Disabled -EA 0
    sc.exe delete 'WavesSvc64' 2>$null

    # Delete OEM scheduled tasks
    Write-Log "  Nuking OEM scheduled tasks..." "INFO"
    Get-ScheduledTask -EA 0 | Where-Object { $_.TaskName -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer' -or $_.TaskPath -match 'dell|intel|hp|lenovo|realtek|waves|asus|acer|msi|razer' } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -EA 0
    }
} else {
    Write-Log "  [DRY RUN] Would nuke OEM folders, services, tasks, and registry" "INFO"
}

# Disabling bloat scheduled tasks
Write-Log "  Disabling bloat scheduled tasks..." "INFO"
$tasksToDisable = if ($script:configOverrides.ContainsKey('TasksToDisable')) { $script:configOverrides.TasksToDisable } else { @(
    # Xbox
    'XblGameSaveTask',
    # Edge
    'MicrosoftEdgeUpdateTaskMachineCore*',
    'MicrosoftEdgeUpdateTaskMachineUA*',
    # Device Setup
    'PostponeDeviceSetupToast*',
    'RNIdle Task',
    'BitLocker MDM policy Refresh',
    # Customer Experience Improvement Program (CEIP)
    'Consolidator',
    'UsbCeip',
    'Microsoft Compatibility Appraiser',
    'ProgramDataUpdater',
    'KernelCeipTask',
    'AitAgent',
    # Application Experience
    'StartupAppTask',
    'CleanupTemporaryState',
    'DsSvcCleanup',
    'PcaPatchDbTask',
    'SdbinstMergeDbTask',
    # Telemetry & Diagnostics
    'QueueReporting',
    'Proxy',
    'FamilySafetyMonitor',
    'FamilySafetyRefresh',
    'FamilySafetyUpload',
    # Maps
    'MapsToastTask',
    'MapsUpdateTask',
    # Cloud Experience Host
    'CreateObjectTask',
    # Feedback
    'Uploader',
    'DmClient',
    'DmClientOnScenarioDownload',
    # Windows Error Reporting
    'QueueReporting',
    # Speech
    'SpeechModelDownloadTask',
    # App prelaunch
    'Pre-staged app cleanup'
) }
# Only disable OneDrive tasks if OneDrive not in use
if (-not $script:onedriveInUse) {
    $tasksToDisable += @('OneDrive Reporting Task*', 'OneDrive Standalone Update Task*', 'OneDrive Startup Task*')
}
foreach ($taskPattern in $tasksToDisable) {
    Disable-TaskDryRun -TaskName $taskPattern
}

# Disable telemetry task paths
@(
    '\Microsoft\Windows\Customer Experience Improvement Program\',
    '\Microsoft\Windows\Application Experience\',
    '\Microsoft\Windows\Feedback\Siuf\',
    '\Microsoft\Windows\Windows Error Reporting\',
    '\Microsoft\Windows\DiskDiagnostic\',
    '\Microsoft\Windows\PI\',
    '\Microsoft\Windows\CloudExperienceHost\'
) | ForEach-Object {
    $tasks = Get-ScheduledTask -TaskPath $_ -EA 0
    foreach ($task in $tasks) {
        $script:manifest.changes.tasks_disabled.Add($task.TaskName) | Out-Null
        $script:counters.TasksDisabled++
        if (-not $DryRun) {
            $task | Stop-ScheduledTask -EA 0
            $task | Disable-ScheduledTask -EA 0
        }
    }
}

# Unregister Xbox scheduled tasks completely
if (-not $DryRun) {
    Get-ScheduledTask -TaskPath '\Microsoft\XblGameSave\' -EA 0 | Unregister-ScheduledTask -Confirm:$false -EA 0
    Get-ScheduledTask -TaskName '*Xbl*' -EA 0 | Unregister-ScheduledTask -Confirm:$false -EA 0
}

if (-not $DryRun) {
    # Delete OEM registry keys - HKLM
    Write-Log "  Nuking OEM registry..." "INFO"
    @(
        'HKLM:\SOFTWARE\Dell',
        'HKLM:\SOFTWARE\DellInc',
        'HKLM:\SOFTWARE\WOW6432Node\Dell',
        'HKLM:\SOFTWARE\WOW6432Node\DellInc',
        'HKLM:\SOFTWARE\Intel',
        'HKLM:\SOFTWARE\WOW6432Node\Intel',
        'HKLM:\SOFTWARE\HP',
        'HKLM:\SOFTWARE\Hewlett-Packard',
        'HKLM:\SOFTWARE\WOW6432Node\HP',
        'HKLM:\SOFTWARE\WOW6432Node\Hewlett-Packard',
        'HKLM:\SOFTWARE\Lenovo',
        'HKLM:\SOFTWARE\WOW6432Node\Lenovo',
        'HKLM:\SOFTWARE\Realtek',
        'HKLM:\SOFTWARE\WOW6432Node\Realtek',
        'HKLM:\SOFTWARE\Waves Audio',
        'HKLM:\SOFTWARE\WOW6432Node\Waves Audio',
        'HKLM:\SOFTWARE\ASUS',
        'HKLM:\SOFTWARE\WOW6432Node\ASUS',
        'HKLM:\SOFTWARE\ASUSTeK',
        'HKLM:\SOFTWARE\WOW6432Node\ASUSTeK',
        'HKLM:\SOFTWARE\Acer',
        'HKLM:\SOFTWARE\WOW6432Node\Acer',
        'HKLM:\SOFTWARE\MSI',
        'HKLM:\SOFTWARE\WOW6432Node\MSI',
        'HKLM:\SOFTWARE\Micro-Star',
        'HKLM:\SOFTWARE\WOW6432Node\Micro-Star',
        'HKLM:\SOFTWARE\Razer',
        'HKLM:\SOFTWARE\WOW6432Node\Razer'
    ) | ForEach-Object {
        if (Test-Path $_) {
            $script:manifest.changes.registry_deleted.Add($_) | Out-Null
            Remove-Item $_ -Recurse -Force -EA 0
        }
    }

    # Delete OEM Add/Remove Programs entries
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($path in $uninstallPaths) {
        Get-ChildItem $path -EA 0 | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -EA 0
            if ($props.DisplayName -match 'Dell|MyDell|Intel|HP Support|HP System|HP Touchpoint|HP JumpStart|HP Customer|Lenovo|Realtek|Waves|ASUS|Armoury|MyASUS|ROG|Acer|AcerCare|MSI|Dragon Center|Mystic Light|Razer|Synapse|Cortex' -and $props.DisplayName -notmatch 'Dell ControlVault|Dell MD Storage|Dell OpenManage|Intel.*Driver|Realtek.*Driver') {
                    Remove-Item $_.PSPath -Recurse -Force -EA 0
            }
        }
    }

    # Delete OEM from all user registry hives
    $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
    foreach ($userProf in $userProfiles) {
        $ntuser = "$($userProf.FullName)\NTUSER.DAT"
        if (Test-Path $ntuser) {
            $hiveName = "HKU\OEMClean_$($userProf.Name)"
            reg load $hiveName $ntuser 2>$null
            if ($LASTEXITCODE -eq 0) {
                reg delete "$hiveName\SOFTWARE\Dell" /f 2>$null
                reg delete "$hiveName\SOFTWARE\DellInc" /f 2>$null
                reg delete "$hiveName\SOFTWARE\Intel" /f 2>$null
                reg delete "$hiveName\SOFTWARE\HP" /f 2>$null
                reg delete "$hiveName\SOFTWARE\Hewlett-Packard" /f 2>$null
                reg delete "$hiveName\SOFTWARE\Lenovo" /f 2>$null
                reg delete "$hiveName\SOFTWARE\Realtek" /f 2>$null
                reg delete "$hiveName\SOFTWARE\Waves Audio" /f 2>$null
                [gc]::Collect()
                Start-Sleep -Milliseconds 100
                reg unload $hiveName 2>$null
            }
        }
    }

    # Delete OEM startup entries
    $startupPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($path in $startupPaths) {
        $props = Get-ItemProperty $path -EA 0
        $props.PSObject.Properties | Where-Object { $_.Value -match 'dell|intel|hp|lenovo|realtek|waves|asus|acer|msi|razer' } | ForEach-Object {
            Remove-ItemProperty -Path $path -Name $_.Name -Force -EA 0
        }
    }

    # Remove specific startup entries (Task Manager startup apps)
    Write-Log "  Removing startup apps..." "INFO"

    # Remove WavesSvc / Waves MaxxAudio from startup
    foreach ($path in $startupPaths) {
        Remove-ItemProperty -Path $path -Name 'WavesSvc64' -Force -EA 0
        Remove-ItemProperty -Path $path -Name 'WavesMaxxAudio' -Force -EA 0
        Remove-ItemProperty -Path $path -Name 'Waves MaxxAudio' -Force -EA 0
    }

    # Remove SecurityHealthSystray from startup
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurityHealth' -Force -EA 0

    # Disable via registry (Task Manager startup apps use this)
    $startupApprovedPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    if (Test-Path $startupApprovedPath) {
        Remove-ItemProperty -Path $startupApprovedPath -Name 'SecurityHealth' -Force -EA 0
        Remove-ItemProperty -Path $startupApprovedPath -Name 'WavesSvc64' -Force -EA 0
    }
    $startupApprovedPath32 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    if (Test-Path $startupApprovedPath32) {
        Remove-ItemProperty -Path $startupApprovedPath32 -Name 'SecurityHealth' -Force -EA 0
        Remove-ItemProperty -Path $startupApprovedPath32 -Name 'WavesSvc64' -Force -EA 0
    }
    $startupApprovedPath32_2 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
    if (Test-Path $startupApprovedPath32_2) {
        Remove-ItemProperty -Path $startupApprovedPath32_2 -Name 'SecurityHealth' -Force -EA 0
        Remove-ItemProperty -Path $startupApprovedPath32_2 -Name 'WavesSvc64' -Force -EA 0
    }

    # Final process kill
    Get-Process -EA 0 | Where-Object { Test-OemTarget $_.Name ($_.Path -replace '.*\\','') } | Stop-Process -Force -EA 0
}

Write-Log "  OEM nuclear clean complete" "SUCCESS"
