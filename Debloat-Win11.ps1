#Requires -RunAsAdministrator
#Requires -Version 5.1

# ============================================================================
# WINDOWS 11 COMPLETE DEBLOAT SCRIPT v2.3.2
# Includes: App removal, Office nuclear scrub, OEM cleanup, registry tweaks
# Production ready - unattended deployment on new or existing PCs
# ============================================================================

param(
    [string]$LogDir = "$env:ProgramData\Debloat-Win11\Logs",
    [switch]$DryRun,
    [switch]$SkipOfficeRemoval,
    [switch]$SkipOneDriveRemoval,
    [switch]$KeepDefender,
    [string]$UndoFile,
    [string]$ConfigPath,
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$Silent,
    [switch]$Explain,
    [string]$RestoreApp,
    [string[]]$DiffManifests,
    [string]$WimPath,
    [int]$WimIndex = 1,
    [string]$MountDir = "C:\Debloat-WIM-Mount",
    [switch]$CheckDrift,
    [switch]$AllUsers
)

# ============================================================================
# VALIDATE MUTUALLY EXCLUSIVE FLAGS
# ============================================================================
if ($UndoFile -and $DryRun) {
    Write-Host "ERROR: -UndoFile and -DryRun cannot be used together" -ForegroundColor Red
    exit 2
}

# Explain mode: forces DryRun + prints rationale for each planned change
if ($Explain) { $DryRun = [switch]::new($true) }

# ============================================================================
# DRIFT DETECTION MODE - Report registry values that were reset by Windows Update
# ============================================================================
if ($CheckDrift) {
    $driftChecks = @(
        # Privacy & Telemetry
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Expected = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Expected = 0 }
        # AI & Copilot
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Expected = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableSettingsAgent'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAgentWorkspaces'; Expected = 2 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAgentConnectors'; Expected = 2 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableRemoteAgentConnectors'; Expected = 2 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableRecallDataProviders'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallExport'; Expected = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'TurnOffSavingSnapshots'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Paint'; Name = 'DisableCocreator'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Paint'; Name = 'DisableImageCreator'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\WindowsNotepad'; Name = 'DisableAIFeatures'; Expected = 1 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Expected = 0 }
        # Consumer features & ads
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Expected = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'ContentDeliveryAllowed'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'FeatureManagementEnabled'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Expected = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Expected = 0 }
        # Search & Bing
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Expected = 1 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Expected = 0 }
        # Widgets & UI
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Expected = 0 }
        # Edge telemetry
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Expected = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeCopilotEnabled'; Expected = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled'; Expected = 0 }
        # Security
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Expected = 0 }
    )

    Write-Host "=== DRIFT DETECTION ===" -ForegroundColor Yellow
    $drifted = 0; $ok = 0; $missing = 0
    foreach ($check in $driftChecks) {
        $current = Get-ItemProperty -Path $check.Path -Name $check.Name -EA 0
        if ($null -eq $current) {
            Write-Host "  MISSING: $($check.Path)\$($check.Name) (expected $($check.Expected))" -ForegroundColor Red
            $missing++
        } elseif ($current.$($check.Name) -ne $check.Expected) {
            Write-Host "  DRIFTED: $($check.Path)\$($check.Name) = $($current.$($check.Name)) (expected $($check.Expected))" -ForegroundColor Yellow
            $drifted++
        } else {
            $ok++
        }
    }
    Write-Host ""
    Write-Host "  OK: $ok | Drifted: $drifted | Missing: $missing" -ForegroundColor $(if ($drifted + $missing -gt 0) { 'Yellow' } else { 'Green' })
    if ($drifted + $missing -gt 0) {
        Write-Host "  Re-run the script to re-apply drifted settings." -ForegroundColor Cyan
    } else {
        Write-Host "  All checked settings are intact." -ForegroundColor Green
    }
    Write-Host "=== DRIFT CHECK COMPLETE ===" -ForegroundColor Yellow
    exit 0
}

$script:phaseRationale = @{
    SystemTweaks = "Disables telemetry, ads, and tracking. Applies UI preferences (dark mode, classic context menu). Configures Windows Update deferrals."
    AppX         = "Removes 80+ pre-installed consumer/OEM apps that consume disk, RAM, and bandwidth. Preserves essential utilities (Calculator, Notepad, Terminal, etc.)."
    OEM          = "Removes manufacturer bloatware (Dell, HP, Lenovo, ASUS, Acer, MSI, Razer) including services, scheduled tasks, folders, and registry entries."
    OneDrive     = "Removes OneDrive if no account is signed in and no files exist. Skipped automatically when in use."
    Office       = "Removes Office if no license is detected and no Office apps are running. Skipped automatically when in use."
    Edge         = "Applies 100+ Edge Group Policy settings to disable telemetry, Copilot, shopping, and ads. Sets Google as default search. Installs uBlock Origin."
    Firewall     = "Imports file/printer sharing rules. Additional vendor rules available via -ConfigPath."
    Privacy      = "Clears browser caches, diagnostic logs, thumbnail cache, and recent files. Event-log clearing is opt-in via -ConfigPath."
    Services     = "Disables 30+ telemetry, gaming, and unused services. Preserves critical services (IPv6, USB detection, biometrics, proxy)."
    Power        = "Sets hardware-aware power plan: High Performance for desktops, Balanced with smart battery for laptops."
    Network      = "Sets Private network profile, disables Nagle's algorithm for lower latency, enables network discovery."
    StartMenu    = "Clears Start Menu suggestions and pinned bloatware tiles."
}

function Write-Rationale {
    param([string]$Phase)
    if ($Explain -and $script:phaseRationale.ContainsKey($Phase)) {
        Write-Log "  WHY: $($script:phaseRationale[$Phase])" "INFO"
    }
}

# ============================================================================
# UNDO MODE - Replay a prior manifest to reverse changes
# ============================================================================
if ($UndoFile) {
    if (!(Test-Path $UndoFile)) {
        Write-Host "ERROR: Undo manifest not found: $UndoFile" -ForegroundColor Red
        exit 2
    }
    $undoManifest = Get-Content $UndoFile -Raw | ConvertFrom-Json
    Write-Host "=== UNDO MODE ===" -ForegroundColor Yellow
    Write-Host "Reversing changes from: $($undoManifest.timestamp)" -ForegroundColor Cyan
    Write-Host "Manifest version: $($undoManifest.version)" -ForegroundColor Cyan
    Write-Host ""

    # Undo registry changes (reverse order)
    $regChanges = @($undoManifest.changes.registry_set)
    [array]::Reverse($regChanges)
    $undoneReg = 0
    foreach ($entry in $regChanges) {
        if ($null -eq $entry.old_value) {
            # Key did not exist before; remove it
            if (Test-Path $entry.path) {
                $existing = Get-ItemProperty -Path $entry.path -Name $entry.name -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    Remove-ItemProperty -Path $entry.path -Name $entry.name -Force -ErrorAction SilentlyContinue
                    $undoneReg++
                }
            }
        } else {
            # Restore old value
            if (!(Test-Path $entry.path)) { New-Item -Path $entry.path -Force | Out-Null }
            $type = if ($entry.type) { $entry.type } else { 'DWord' }
            Set-ItemProperty -Path $entry.path -Name $entry.name -Value $entry.old_value -Type $type -Force -ErrorAction SilentlyContinue
            $undoneReg++
        }
    }
    Write-Host "  Registry entries restored: $undoneReg" -ForegroundColor Green

    # Re-enable services (supports both old string-only and new object manifests)
    $undoneServices = 0
    foreach ($svcEntry in $undoManifest.changes.services_disabled) {
        $svcName = if ($svcEntry -is [string]) { $svcEntry } else { $svcEntry.name }
        $startType = if ($svcEntry -is [string] -or -not $svcEntry.original_startup_type) { 'Manual' } else { $svcEntry.original_startup_type }
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $svcName -StartupType $startType -ErrorAction SilentlyContinue
            Start-Service -Name $svcName -ErrorAction SilentlyContinue
            $undoneServices++
        }
    }
    Write-Host "  Services re-enabled: $undoneServices" -ForegroundColor Green

    # Re-enable tasks
    $undoneTasks = 0
    foreach ($taskName in $undoManifest.changes.tasks_disabled) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            $task | Enable-ScheduledTask -ErrorAction SilentlyContinue
            $undoneTasks++
        }
    }
    Write-Host "  Scheduled tasks re-enabled: $undoneTasks" -ForegroundColor Green

    # Note: AppX packages cannot be trivially re-installed; inform the user
    $removedApps = @($undoManifest.changes.appx_removed)
    if ($removedApps.Count -gt 0) {
        Write-Host ""
        Write-Host "  NOTE: $($removedApps.Count) AppX packages were removed and cannot be auto-restored." -ForegroundColor Yellow
        Write-Host "  Use 'winget install <package>' or the Microsoft Store to reinstall:" -ForegroundColor Yellow
        foreach ($app in $removedApps) {
            Write-Host "    - $app" -ForegroundColor White
        }
    }

    # Warn about irrecoverable deletions tracked in manifest
    $deletedFolders = @($undoManifest.changes.folders_deleted)
    if ($deletedFolders.Count -gt 0) {
        Write-Host ""
        Write-Host "  NOTE: $($deletedFolders.Count) folders were deleted and cannot be auto-restored:" -ForegroundColor Yellow
        foreach ($f in $deletedFolders) { Write-Host "    - $f" -ForegroundColor White }
    }
    $deletedRegKeys = @($undoManifest.changes.registry_deleted)
    if ($deletedRegKeys.Count -gt 0) {
        Write-Host ""
        Write-Host "  NOTE: $($deletedRegKeys.Count) registry keys were deleted and cannot be auto-restored:" -ForegroundColor Yellow
        foreach ($r in $deletedRegKeys) { Write-Host "    - $r" -ForegroundColor White }
    }
    $deletedServices = @($undoManifest.changes.services_deleted)
    if ($deletedServices.Count -gt 0) {
        Write-Host ""
        Write-Host "  NOTE: $($deletedServices.Count) services were deleted (sc.exe delete) and cannot be auto-restored:" -ForegroundColor Yellow
        foreach ($s in $deletedServices) { Write-Host "    - $s" -ForegroundColor White }
    }

    Write-Host ""
    Write-Host "=== UNDO COMPLETE ===" -ForegroundColor Green
    Write-Host "Restart recommended to apply all restored settings." -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# RESTORE APP MODE - Reinstall a removed AppX package via winget
# ============================================================================
if ($RestoreApp) {
    $wingetCmd = Get-Command 'winget' -EA 0
    if (-not $wingetCmd) {
        Write-Host "ERROR: winget is not installed. Use the Microsoft Store to reinstall apps manually." -ForegroundColor Red
        exit 2
    }

    Write-Host "=== RESTORE APP MODE ===" -ForegroundColor Yellow
    Write-Host "Searching for: $RestoreApp" -ForegroundColor Cyan

    $searchResult = & winget search $RestoreApp --accept-source-agreements 2>&1
    Write-Host $($searchResult | Out-String)

    Write-Host ""
    Write-Host "Installing: $RestoreApp" -ForegroundColor Cyan
    & winget install $RestoreApp --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "=== RESTORE COMPLETE ===" -ForegroundColor Green
        exit 0
    } else {
        Write-Host ""
        Write-Host "=== RESTORE FAILED (exit code $LASTEXITCODE) ===" -ForegroundColor Red
        Write-Host "Try the Microsoft Store or run: winget install --id <exact-id>" -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================================
# DIFF MANIFESTS MODE - Compare two undo manifests
# ============================================================================
if ($DiffManifests) {
    if ($DiffManifests.Count -ne 2) {
        Write-Host "ERROR: -DiffManifests requires exactly 2 manifest paths" -ForegroundColor Red
        exit 2
    }
    foreach ($mf in $DiffManifests) {
        if (!(Test-Path $mf)) {
            Write-Host "ERROR: Manifest not found: $mf" -ForegroundColor Red
            exit 2
        }
    }

    $m1 = Get-Content $DiffManifests[0] -Raw | ConvertFrom-Json
    $m2 = Get-Content $DiffManifests[1] -Raw | ConvertFrom-Json

    Write-Host "=== MANIFEST DIFF ===" -ForegroundColor Yellow
    Write-Host "  A: $($m1.timestamp) ($($DiffManifests[0] | Split-Path -Leaf))" -ForegroundColor Cyan
    Write-Host "  B: $($m2.timestamp) ($($DiffManifests[1] | Split-Path -Leaf))" -ForegroundColor Cyan
    Write-Host ""

    # Compare registry changes
    $regA = @{}; $m1.changes.registry_set | ForEach-Object { $regA["$($_.path)\$($_.name)"] = $_.new_value }
    $regB = @{}; $m2.changes.registry_set | ForEach-Object { $regB["$($_.path)\$($_.name)"] = $_.new_value }

    $allKeys = ($regA.Keys + $regB.Keys) | Sort-Object -Unique
    $regDiffs = 0
    foreach ($key in $allKeys) {
        $inA = $regA.ContainsKey($key); $inB = $regB.ContainsKey($key)
        if ($inA -and -not $inB) {
            Write-Host "  - REG (A only): $key = $($regA[$key])" -ForegroundColor Red
            $regDiffs++
        } elseif (-not $inA -and $inB) {
            Write-Host "  + REG (B only): $key = $($regB[$key])" -ForegroundColor Green
            $regDiffs++
        } elseif ($regA[$key] -ne $regB[$key]) {
            Write-Host "  ~ REG (changed): $key  A=$($regA[$key]) -> B=$($regB[$key])" -ForegroundColor Yellow
            $regDiffs++
        }
    }
    if ($regDiffs -eq 0) { Write-Host "  Registry: identical" -ForegroundColor Gray }

    # Compare services (handle both string-only and object manifest formats)
    $svcNamesA = @($m1.changes.services_disabled | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
    $svcNamesB = @($m2.changes.services_disabled | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
    $svcOnlyA = $svcNamesA | Where-Object { $svcNamesB -notcontains $_ }
    $svcOnlyB = $svcNamesB | Where-Object { $svcNamesA -notcontains $_ }
    if ($svcOnlyA) { $svcOnlyA | ForEach-Object { Write-Host "  - SVC (A only): $_" -ForegroundColor Red } }
    if ($svcOnlyB) { $svcOnlyB | ForEach-Object { Write-Host "  + SVC (B only): $_" -ForegroundColor Green } }
    if (-not $svcOnlyA -and -not $svcOnlyB) { Write-Host "  Services: identical" -ForegroundColor Gray }

    # Compare AppX
    $appA = @($m1.changes.appx_removed); $appB = @($m2.changes.appx_removed)
    $appOnlyA = $appA | Where-Object { $appB -notcontains $_ }
    $appOnlyB = $appB | Where-Object { $appA -notcontains $_ }
    if ($appOnlyA) { $appOnlyA | ForEach-Object { Write-Host "  - APP (A only): $_" -ForegroundColor Red } }
    if ($appOnlyB) { $appOnlyB | ForEach-Object { Write-Host "  + APP (B only): $_" -ForegroundColor Green } }
    if (-not $appOnlyA -and -not $appOnlyB) { Write-Host "  AppX: identical" -ForegroundColor Gray }

    # Compare tasks
    $taskA = @($m1.changes.tasks_disabled); $taskB = @($m2.changes.tasks_disabled)
    $taskOnlyA = $taskA | Where-Object { $taskB -notcontains $_ }
    $taskOnlyB = $taskB | Where-Object { $taskA -notcontains $_ }
    if ($taskOnlyA) { $taskOnlyA | ForEach-Object { Write-Host "  - TASK (A only): $_" -ForegroundColor Red } }
    if ($taskOnlyB) { $taskOnlyB | ForEach-Object { Write-Host "  + TASK (B only): $_" -ForegroundColor Green } }
    if (-not $taskOnlyA -and -not $taskOnlyB) { Write-Host "  Tasks: identical" -ForegroundColor Gray }

    Write-Host ""
    Write-Host "=== DIFF COMPLETE ===" -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# CANONICAL APPX REMOVE PATTERNS (shared between live mode and WIM mode)
# ============================================================================
$script:defaultRemovePatterns = @(
    '*Clipchamp*',
    '*Microsoft.3DBuilder*',
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
    '*Microsoft.SkypeApp*',
    '*Microsoft.Todos*',
    '*Microsoft.Wallet*',
    '*Microsoft.Windows.DevHome*',
    '*Microsoft.WindowsBackup*',
    '*Microsoft.WindowsCamera*',
    '*Microsoft.windowscommunicationsapps*',
    '*Microsoft.WindowsFeedbackHub*',
    '*Microsoft.WindowsMaps*',
    '*Microsoft.Xbox*',
    '*Microsoft.XboxApp*',
    '*Microsoft.XboxGameOverlay*',
    '*Microsoft.XboxGamingOverlay*',
    '*Microsoft.XboxIdentityProvider*',
    '*Microsoft.XboxSpeechToTextOverlay*',
    '*Microsoft.Xbox.TCUI*',
    '*Microsoft.GamingServices*',
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
    '*ASUS*',
    '*ASUSPCAssistant*',
    '*ArmouryCrate*',
    '*MyASUS*',
    '*ROGLiveService*',
    '*Acer*',
    '*AcerCare*',
    '*AcerCollection*',
    '*AcerIncorporated*',
    '*AcerQuickAccess*',
    '*MSI*',
    '*MysticLight*',
    '*DragonCenter*',
    '*MSIAfterburner*',
    '*Razer*',
    '*RazerInc*',
    '*RazerCortex*',
    '*RazerSynapse*',
    '*Microsoft.PCManager*',
    '*Microsoft.Windows.AIHub*',
    '*Microsoft.M365Companions*',
    '*Microsoft.StartExperiencesApp*'
)

# ============================================================================
# WIM IMAGE MODE - Offline debloat of a mounted Windows image
# ============================================================================
if ($WimPath) {
    if (!(Test-Path $WimPath)) {
        Write-Host "ERROR: WIM file not found: $WimPath" -ForegroundColor Red
        exit 2
    }

    Write-Host "=== WIM IMAGE MODE ===" -ForegroundColor Yellow
    Write-Host "  Image: $WimPath (Index $WimIndex)" -ForegroundColor Cyan
    Write-Host "  Mount: $MountDir" -ForegroundColor Cyan

    if (!(Test-Path $MountDir)) { New-Item -Path $MountDir -ItemType Directory -Force | Out-Null }

    Write-Host "`n  Mounting image..." -ForegroundColor Gray
    $mountResult = Mount-WindowsImage -ImagePath $WimPath -Index $WimIndex -Path $MountDir -EA 0
    if (-not $mountResult) {
        Write-Host "ERROR: Failed to mount WIM image" -ForegroundColor Red
        exit 2
    }
    Write-Host "  Mounted successfully" -ForegroundColor Green

    # Remove provisioned AppX packages from the offline image
    Write-Host "`n  Removing provisioned AppX packages..." -ForegroundColor Gray
    $provPkgs = Get-AppxProvisionedPackage -Path $MountDir -EA 0
    $removePatterns = $script:defaultRemovePatterns
    $removed = 0
    foreach ($pkg in $provPkgs) {
        foreach ($pattern in $removePatterns) {
            if ($pkg.DisplayName -like $pattern -or $pkg.PackageName -like $pattern) {
                Remove-AppxProvisionedPackage -Path $MountDir -PackageName $pkg.PackageName -EA 0 | Out-Null
                Write-Host "    Removed: $($pkg.DisplayName)" -ForegroundColor DarkGray
                $removed++
                break
            }
        }
    }
    Write-Host "  Removed $removed provisioned packages" -ForegroundColor Green

    # Apply registry tweaks to the offline Default user hive
    Write-Host "`n  Applying offline registry tweaks..." -ForegroundColor Gray
    $offlineHive = "$MountDir\Users\Default\NTUSER.DAT"
    if (Test-Path $offlineHive) {
        $hiveName = "HKU\OfflineWIM"
        reg load $hiveName $offlineHive 2>$null
        if ($LASTEXITCODE -eq 0) {
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SilentInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v ContentDeliveryAllowed /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v OemPreInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v PreInstalledAppsEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v FeatureManagementEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f 2>$null | Out-Null
            reg add "$hiveName\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null
            [gc]::Collect()
            Start-Sleep -Milliseconds 500
            reg unload $hiveName 2>$null
            Write-Host "  Default user hive configured" -ForegroundColor Green
        }
    }

    # Apply HKLM tweaks to the offline SOFTWARE hive
    $offlineSW = "$MountDir\Windows\System32\config\SOFTWARE"
    if (Test-Path $offlineSW) {
        $swHive = "HKU\OfflineSW"
        reg load $swHive $offlineSW 2>$null
        if ($LASTEXITCODE -eq 0) {
            reg add "$swHive\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$swHive\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f 2>$null | Out-Null
            reg add "$swHive\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>$null | Out-Null
            reg add "$swHive\Policies\Microsoft\Windows\WindowsAI" /v DisableAIDataAnalysis /t REG_DWORD /d 1 /f 2>$null | Out-Null
            reg add "$swHive\Policies\Microsoft\Windows\WindowsAI" /v AllowRecallEnablement /t REG_DWORD /d 0 /f 2>$null | Out-Null
            reg add "$swHive\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f 2>$null | Out-Null
            reg add "$swHive\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f 2>$null | Out-Null
            [gc]::Collect()
            Start-Sleep -Milliseconds 500
            reg unload $swHive 2>$null
            Write-Host "  System policies configured" -ForegroundColor Green
        }
    }

    # Unmount and commit
    Write-Host "`n  Unmounting and saving image..." -ForegroundColor Gray
    Dismount-WindowsImage -Path $MountDir -Save -EA 0 | Out-Null
    Write-Host "  Image saved successfully" -ForegroundColor Green

    Write-Host ""
    Write-Host "=== WIM DEBLOAT COMPLETE ===" -ForegroundColor Green
    Write-Host "  Removed: $removed AppX packages" -ForegroundColor White
    Write-Host "  Applied: privacy, telemetry, UI, OOBE, and AI policy tweaks" -ForegroundColor White
    Write-Host "  Image ready for deployment via DISM, MDT, or WDS" -ForegroundColor Cyan
    exit 0
}

# ============================================================================
# CONFIG FILE SUPPORT
# ============================================================================
# Merge external .psd1 config into the session, overriding built-in arrays
$script:configOverrides = @{}
$script:validConfigKeys = @('RemovePatterns','ServicesToDisable','DefenderExclusions','EdgeBookmarks',
                            'StartupBloat','TasksToDisable','FeaturesToDisable','FirewallRules',
                            'DarkMode','OemExclude','ClearEventLogs')
if ($ConfigPath) {
    if (!(Test-Path $ConfigPath)) {
        Write-Host "ERROR: Config file not found: $ConfigPath" -ForegroundColor Red
        exit 2
    }
    try {
        $script:configOverrides = Import-PowerShellDataFile -Path $ConfigPath
    } catch {
        Write-Host "ERROR: Failed to parse config file: $_" -ForegroundColor Red
        exit 2
    }
    foreach ($key in $script:configOverrides.Keys) {
        if ($script:validConfigKeys -notcontains $key) {
            Write-Host "WARNING: Unknown config key '$key' in $ConfigPath. Valid keys: $($script:validConfigKeys -join ', ')" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# PHASE SELECTION
# ============================================================================
# Valid phases for -Only / -Skip
$script:validPhases = @('AppX','OEM','OneDrive','Office','Edge','Firewall','Privacy',
                        'Services','SystemTweaks','Power','Network','StartMenu')

if ($Only -and $Skip) {
    Write-Host "ERROR: -Only and -Skip cannot be used together" -ForegroundColor Red
    exit 2
}

function Test-PhaseEnabled {
    param([string]$Phase)
    if ($Only) { return ($Only -contains $Phase) }
    if ($Skip) { return ($Skip -notcontains $Phase) }
    return $true
}

# Validate phase names
foreach ($p in ($Only + $Skip)) {
    if ($p -and $script:validPhases -notcontains $p) {
        Write-Host "ERROR: Unknown phase '$p'. Valid phases: $($script:validPhases -join ', ')" -ForegroundColor Red
        exit 2
    }
}

$ErrorActionPreference = "SilentlyContinue"
$script:exitCode = 0
$script:startTime = Get-Date

# ============================================================================
# PROGRESS TRACKING
# ============================================================================
$script:totalPhases = 12
$script:currentPhase = 0
function Update-Phase {
    param([string]$PhaseName)
    $script:currentPhase++
    if (-not $Silent -and [Environment]::UserInteractive) {
        $pct = [int](($script:currentPhase / $script:totalPhases) * 100)
        Write-Progress -Activity "Debloat-Win11" -Status "$PhaseName" -PercentComplete $pct
    }
}

# ============================================================================
# COUNTERS & UNDO MANIFEST
# ============================================================================
$script:counters = @{
    AppxRemoved       = 0
    OfficeRemoved     = 0
    OEMCleaned        = 0
    ServicesDisabled   = 0
    TasksDisabled      = 0
    RegistryTweaks     = 0
    DiskBefore         = 0
    DiskAfter          = 0
}

$script:manifest = @{
    timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    version   = 'v2.3.2'
    dryrun    = $DryRun.IsPresent
    changes   = @{
        appx_removed       = [System.Collections.ArrayList]@()
        services_disabled  = [System.Collections.ArrayList]@()
        services_deleted   = [System.Collections.ArrayList]@()
        tasks_disabled     = [System.Collections.ArrayList]@()
        registry_set       = [System.Collections.ArrayList]@()
        registry_deleted   = [System.Collections.ArrayList]@()
        folders_deleted    = [System.Collections.ArrayList]@()
    }
}

# ============================================================================
# LOGGING SETUP
# ============================================================================
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$logFile = "$LogDir\Debloat-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
$manifestFile = "$LogDir\Debloat-Manifest-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"

# Register EventLog source for SIEM/compliance (idempotent)
$script:eventLogSource = 'Debloat-Win11'
if (-not [System.Diagnostics.EventLog]::SourceExists($script:eventLogSource)) {
    try { New-EventLog -LogName 'Application' -Source $script:eventLogSource -EA Stop } catch {}
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($DryRun) { "[DRY RUN] " } else { "" }
    $logEntry = "[$timestamp] [$Level] $prefix$Message"
    Add-Content -Path $logFile -Value $logEntry -EA 0

    # Write key events to Windows Event Log for SIEM forwarding
    if ($Level -eq 'ERROR') {
        Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 9001 -EntryType Error -Message "$prefix$Message" -EA 0
    } elseif ($Level -eq 'SECTION') {
        Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 1001 -EntryType Information -Message "$prefix$Message" -EA 0
    }

    if ($Silent) { if ($Level -eq 'ERROR') { $script:exitCode = 1 }; return }

    switch ($Level) {
        "INFO"    { Write-Host "$prefix$Message" -ForegroundColor Cyan }
        "SUCCESS" { Write-Host "$prefix$Message" -ForegroundColor Green }
        "WARNING" { Write-Host "$prefix$Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "$prefix$Message" -ForegroundColor Red; $script:exitCode = 1 }
        "SECTION" { Write-Host "`n$prefix$Message" -ForegroundColor Yellow }
        default   { Write-Host "$prefix$Message" }
    }
}

# ============================================================================
# DRY RUN AWARE HELPERS
# ============================================================================
# Wraps Set-Reg to track registry changes and support DryRun
function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")

    # Capture old value for manifest
    $oldValue = $null
    if (Test-Path $Path) {
        $existing = Get-ItemProperty -Path $Path -Name $Name -EA 0
        if ($existing) { $oldValue = $existing.$Name }
    }

    $script:manifest.changes.registry_set.Add(@{
        path      = $Path
        name      = $Name
        old_value = $oldValue
        new_value = $Value
        type      = $Type
    }) | Out-Null
    $script:counters.RegistryTweaks++

    if ($DryRun) { return }

    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -EA 0
}

# Cache all packages once at start of AppX phase for performance
$script:allAppxPackages = $null
$script:allProvisionedPackages = $null

function Remove-AppxDryRun {
    param([string]$Pattern)

    # Lazy-init: query once, filter many
    if ($null -eq $script:allAppxPackages) {
        $script:allAppxPackages = @(Get-AppxPackage -AllUsers 2>$null)
        $script:allProvisionedPackages = @(Get-AppxProvisionedPackage -Online 2>$null)
    }

    $pkgs = $script:allAppxPackages | Where-Object { $_.Name -like $Pattern }
    $provPkgs = $script:allProvisionedPackages | Where-Object { $_.DisplayName -like $Pattern -or $_.PackageName -like $Pattern }

    foreach ($pkg in $pkgs) {
        $script:manifest.changes.appx_removed.Add($pkg.Name) | Out-Null
        $script:counters.AppxRemoved++
        if (-not $DryRun) {
            $pkg | Remove-AppxPackage -AllUsers 2>$null
        }
    }
    foreach ($pkg in $provPkgs) {
        $displayName = $pkg.DisplayName
        if ($displayName -and ($script:manifest.changes.appx_removed -notcontains $displayName)) {
            $script:manifest.changes.appx_removed.Add($displayName) | Out-Null
        }
        if (-not $DryRun) {
            $pkg | Remove-AppxProvisionedPackage -Online 2>$null
        }
    }
}

function Disable-ServiceDryRun {
    param([string]$ServiceName)
    $svc = Get-Service -Name $ServiceName -EA 0
    if ($svc) {
        $script:manifest.changes.services_disabled.Add(@{
            name = $ServiceName
            original_startup_type = $svc.StartType.ToString()
        }) | Out-Null
        $script:counters.ServicesDisabled++
        if (-not $DryRun) {
            Stop-Service -Name $ServiceName -Force -EA 0
            Set-Service -Name $ServiceName -StartupType Disabled -EA 0
        }
    }
}

function Disable-TaskDryRun {
    param([string]$TaskName)
    $tasks = Get-ScheduledTask -TaskName $TaskName -EA 0
    foreach ($task in $tasks) {
        $script:manifest.changes.tasks_disabled.Add($task.TaskName) | Out-Null
        $script:counters.TasksDisabled++
        if (-not $DryRun) {
            $task | Stop-ScheduledTask -EA 0
            $task | Disable-ScheduledTask -EA 0
        }
    }
}

# ============================================================================
# CONCURRENT EXECUTION GUARD
# ============================================================================
$script:lockFile = "$LogDir\Debloat-Win11.lock"
if (Test-Path $script:lockFile) {
    $lockContent = Get-Content $script:lockFile -Raw -EA 0
    Write-Log "ERROR: Another instance is already running (lock: $lockContent). Aborting." "ERROR"
    exit 2
}
try {
    "PID=$PID Started=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')" | Set-Content $script:lockFile -Force -EA Stop
} catch {
    Write-Log "ERROR: Could not create lock file: $_" "ERROR"
    exit 2
}
# Ensure lockfile is cleaned up on exit (normal or abnormal)
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Remove-Item $script:lockFile -Force -EA 0
} | Out-Null

# ============================================================================
# STARTUP BANNER
# ============================================================================
Write-Log "=== WINDOWS DEBLOAT v2.3.2 STARTING ===" "INFO"
if ($Explain) { Write-Log "*** EXPLAIN MODE - Showing rationale for each phase, no changes will be made ***" "WARNING" }
elseif ($DryRun) { Write-Log "*** DRY RUN MODE - No changes will be made ***" "WARNING" }
Write-Log "Log file: $logFile" "INFO"

# Capture initial disk space for summary
$systemDriveInit = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -EA 0
if ($systemDriveInit) {
    $script:counters.DiskBefore = $systemDriveInit.FreeSpace
}

# ============================================================================
# WINDOWS VERSION CHECK
# ============================================================================
$osVersion = [System.Environment]::OSVersion.Version
$osBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA 0).CurrentBuild
$osName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA 0).ProductName

Write-Log "[Pre-Check] Windows version: $osName (Build $osBuild)" "INFO"

# Require Windows 10 (build 10240+) or Windows 11 (build 22000+)
if ($osVersion.Major -lt 10) {
    Write-Log "ERROR: This script requires Windows 10 or later" "ERROR"
    exit 2
}

# Detect Enterprise LTSC editions (lack Store apps, Copilot, consumer features)
$script:isLTSC = $false
$editionId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA 0).EditionID
if ($editionId -match 'EnterpriseS|IoTEnterpriseS|ServerRdsh') {
    $script:isLTSC = $true
    Write-Log "[Pre-Check] Enterprise LTSC/IoT edition detected -- consumer-app phases will be skipped" "WARNING"
}

# ============================================================================
# DOMAIN AWARENESS CHECK
# ============================================================================
$script:isDomainJoined = $false
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -EA 0

if ($computerSystem.PartOfDomain) {
    $script:isDomainJoined = $true
    $domainName = $computerSystem.Domain
    Write-Log "[Pre-Check] Domain-joined PC: $domainName" "INFO"
    Write-Log "  Some settings may be overridden by Group Policy" "WARNING"
} else {
    Write-Log "[Pre-Check] Workgroup PC (not domain-joined)" "INFO"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================
Write-Log "[Pre-Flight] Running system checks..." "INFO"

# Check available disk space (warn if < 5GB free)
$systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -EA 0
if ($systemDrive) {
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
    Write-Log "  Disk space: $freeSpaceGB GB free of $totalSpaceGB GB" "INFO"
    if ($freeSpaceGB -lt 5) {
        Write-Log "  WARNING: Low disk space may cause issues" "WARNING"
    }
}

# Check for pending reboot
$pendingReboot = $false
$rebootKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
)
foreach ($key in $rebootKeys) {
    if (Test-Path $key) { $pendingReboot = $true; break }
}
if ($pendingReboot) {
    Write-Log "  Pending reboot detected - some changes may require additional reboot" "WARNING"
} else {
    Write-Log "  No pending reboot" "INFO"
}

# Check for problematic states that could cause failures
$windowsSetupRunning = Get-Process -Name 'SetupHost','SetupPrep' -EA 0
if ($windowsSetupRunning) {
    Write-Log "ERROR: Windows Setup is currently running (Feature Update in progress). Aborting." "ERROR"
    exit 2
}

# Check for pending Feature Update staging
$featureUpdatePending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe"
$setupInProgress = Test-Path "$env:SystemDrive\`$WINDOWS.~BT\Sources\SetupPlatform.ini"
if ($featureUpdatePending -or $setupInProgress) {
    Write-Log "  Feature Update is staged/pending - proceed with caution" "WARNING"
}

# Check for active MSIX staging (AppX installations in progress)
$msixStaging = Get-Process -Name 'MicrosoftEdgeUpdate','AppInstaller' -EA 0
if ($msixStaging) {
    Write-Log "  MSIX/AppX staging in progress - waiting 10 seconds" "WARNING"
    Start-Sleep -Seconds 10
}

# Check RAM
$totalRAM = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 1)
Write-Log "  Total RAM: $totalRAM GB" "INFO"

# Check for Windows S Mode (restricts AppX removal)
$script:isSMode = $false
$sModePol = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -EA 0
if ($sModePol -and $sModePol.SkuPolicyRequired -eq 1) {
    $script:isSMode = $true
    Write-Log "ERROR: Windows is running in S Mode. AppX removal and sideloading are restricted." "ERROR"
    Write-Log "  Switch out of S Mode in Settings > System > Activation before running this script." "ERROR"
    exit 2
}

# Check Tamper Protection status (affects Defender changes)
$script:tamperProtectionOn = $false
$tpStatus = Get-MpComputerStatus -EA 0
if ($tpStatus -and $tpStatus.IsTamperProtected) {
    $script:tamperProtectionOn = $true
    Write-Log "  Tamper Protection: ENABLED - Defender exclusion changes may not persist" "WARNING"
} else {
    Write-Log "  Tamper Protection: Disabled or not detected" "INFO"
}

# Report VBS/HVCI status
$vbsStatus = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -EA 0
if ($vbsStatus) {
    $vbsRunning = $vbsStatus.VirtualizationBasedSecurityStatus -eq 2
    $hvciRunning = 1 -in @($vbsStatus.SecurityServicesRunning)
    Write-Log "  VBS: $(if ($vbsRunning) { 'Running' } else { 'Not running' }) | HVCI: $(if ($hvciRunning) { 'Running' } else { 'Not running' })" "INFO"
} else {
    Write-Log "  VBS/HVCI: Status not available" "INFO"
}

# Check Smart App Control status (may block unsigned scripts)
$sacPol = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name "VerifiedAndReputablePolicyState" -EA 0
if ($sacPol -and $sacPol.VerifiedAndReputablePolicyState -eq 2) {
    Write-Log "  Smart App Control: ENFORCEMENT MODE - unsigned scripts may be blocked" "WARNING"
    Write-Log "  Run 'Unblock-File Debloat-Win11.ps1' if downloaded from the internet" "WARNING"
}

# Inform Enterprise/Education users about native RemoveDefaultMicrosoftStorePackages policy
if ($editionId -match 'Enterprise|Education' -and [int]$osBuild -ge 26100) {
    Write-Log "  NOTE: Enterprise/Education 24H2+ supports native RemoveDefaultMicrosoftStorePackages policy via GPO/Intune" "INFO"
}

# ============================================================================
# SSD DETECTION & OPTIMIZATION
# ============================================================================
Write-Log "[Pre-Check] Detecting storage type..." "INFO"
$script:isSSD = $false

# Get physical disk media type
$physicalDisks = Get-PhysicalDisk -EA 0
foreach ($disk in $physicalDisks) {
    if ($disk.MediaType -eq 'SSD' -or $disk.MediaType -eq 'NVMe') {
        $script:isSSD = $true
        break
    }
}

# Fallback: Check if disk has no seek penalty (SSD indicator)
if (-not $script:isSSD) {
    $diskDrive = Get-CimInstance -ClassName Win32_DiskDrive -EA 0 | Select-Object -First 1
    if ($diskDrive) {
        # Check via TRIM support (SSDs support TRIM)
        $defragAnalysis = Get-CimInstance -Namespace "root\microsoft\windows\storage" -ClassName "MSFT_PhysicalDisk" -EA 0 | Select-Object -First 1
        if ($defragAnalysis.MediaType -eq 4) { $script:isSSD = $true }
    }
}

if ($script:isSSD) {
    Write-Log "  Storage: SSD detected - will apply SSD optimizations" "SUCCESS"
} else {
    Write-Log "  Storage: HDD detected - will apply HDD optimizations" "INFO"
}

# ============================================================================
# CREATE SYSTEM RESTORE POINT
# ============================================================================
Write-Log "[Safety] Creating System Restore Point..." "SECTION"
if ($DryRun) {
    Write-Log "  [DRY RUN] Would create restore point" "INFO"
} else {
    try {
        Enable-ComputerRestore -Drive "C:\" -EA 0
        Checkpoint-Computer -Description "Pre-Debloat $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS" -EA Stop
        Write-Log "  Restore point created" "SUCCESS"
    } catch {
        Write-Log "  Could not create restore point (may already exist today)" "WARNING"
    }
}

# ============================================================================
# PRE-DEBLOAT: DISABLE INTERFERING SERVICES
# ============================================================================
Write-Log "[Pre-Debloat] Disabling interfering services..." "SECTION"

if ($DryRun) {
    Write-Log "  [DRY RUN] Would stop Windows Update, Windows Search, SysMain" "INFO"
} else {
    # Windows Update
    Write-Log "  Stopping Windows Update..." "INFO"
    Stop-Service -Name 'wuauserv' -Force -EA 0
    Set-Service -Name 'wuauserv' -StartupType Disabled -EA 0
    Stop-Process -Name 'WaaSMedicAgent', 'UsoClient', 'wuauclt', 'WUDFHost' -Force -EA 0

    # Windows Search
    Write-Log "  Stopping Windows Search..." "INFO"
    Stop-Service -Name 'WSearch' -Force -EA 0
    Set-Service -Name 'WSearch' -StartupType Disabled -EA 0
    Stop-Process -Name 'SearchIndexer', 'SearchHost', 'SearchApp' -Force -EA 0

    # SysMain (Superfetch)
    Write-Log "  Stopping SysMain..." "INFO"
    Stop-Service -Name 'SysMain' -Force -EA 0
    Set-Service -Name 'SysMain' -StartupType Disabled -EA 0

    Write-Log "  Services disabled" "SUCCESS"
}

# ============================================================================
# HARDWARE DETECTION (Laptop vs Desktop)
# ============================================================================
Write-Log "[Pre-Check] Detecting hardware type..." "SECTION"
$script:isLaptop = $false
$script:hasBattery = $false
$script:chassisType = "Unknown"

# Detect chassis type (laptop, desktop, tablet, etc.)
$chassis = Get-CimInstance -ClassName Win32_SystemEnclosure -EA 0 | Select-Object -ExpandProperty ChassisTypes
# Chassis types: 3=Desktop, 4=Low Profile Desktop, 5=Pizza Box, 6=Mini Tower, 7=Tower
#                8=Portable, 9=Laptop, 10=Notebook, 11=Hand Held, 12=Docking Station
#                13=All in One, 14=Sub Notebook, 15=Space-Saving, 16=Lunch Box
#                17=Main System Chassis, 18=Expansion Chassis, 19=SubChassis
#                20=Bus Expansion Chassis, 21=Peripheral Chassis, 22=RAID Chassis
#                23=Rack Mount Chassis, 24=Sealed-Case PC, 30=Tablet, 31=Convertible, 32=Detachable
$laptopTypes = @(8, 9, 10, 11, 14, 30, 31, 32)
$desktopTypes = @(3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24)

foreach ($type in $chassis) {
    if ($laptopTypes -contains $type) {
        $script:isLaptop = $true
        $script:chassisType = "Laptop/Portable"
        break
    } elseif ($desktopTypes -contains $type) {
        $script:chassisType = "Desktop"
    }
}

# Double-check with battery presence
$battery = Get-CimInstance -ClassName Win32_Battery -EA 0
if ($battery) {
    $script:hasBattery = $true
    # If we have a battery but didn't detect laptop, assume laptop
    if (-not $script:isLaptop) {
        $script:isLaptop = $true
        $script:chassisType = "Laptop (battery detected)"
    }
}

# Get system info for display
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -EA 0
$manufacturer = $computerSystem.Manufacturer
$model = $computerSystem.Model

if ($script:isLaptop) {
    Write-Log "  Hardware: $script:chassisType" "INFO"
    Write-Log "  System: $manufacturer $model" "INFO"
    Write-Log "  Battery: Present" "INFO"
    Write-Log "  Power settings will be optimized for LAPTOP" "SUCCESS"
} else {
    Write-Log "  Hardware: $script:chassisType" "INFO"
    Write-Log "  System: $manufacturer $model" "INFO"
    Write-Log "  Battery: Not present" "INFO"
    Write-Log "  Power settings will be optimized for WORKSTATION" "SUCCESS"
}

# ============================================================================
# ONEDRIVE USAGE CHECK (determines if OneDrive should be preserved)
# ============================================================================
Write-Log "[Pre-Check] Checking OneDrive status..." "SECTION"
$script:onedriveInUse = $false

if ($SkipOneDriveRemoval) {
    $script:onedriveInUse = $true
    Write-Log "  OneDrive removal skipped (-SkipOneDriveRemoval)" "INFO"
} else {
    # Check for OneDrive accounts in registry
    $personalAccount = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Personal" -EA 0
    $businessAccount = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1" -EA 0

    if ($personalAccount.UserEmail) {
        $script:onedriveInUse = $true
        Write-Log "  OneDrive in use: Personal account ($($personalAccount.UserEmail))" "INFO"
    }
    if ($businessAccount.UserEmail) {
        $script:onedriveInUse = $true
        Write-Log "  OneDrive in use: Business account ($($businessAccount.UserEmail))" "INFO"
    }

    # Check if OneDrive folder has files
    $onedriveFolder = "$env:USERPROFILE\OneDrive"
    if ((Test-Path $onedriveFolder) -and -not $script:onedriveInUse) {
        $fileCount = (Get-ChildItem $onedriveFolder -Recurse -File -EA 0 | Measure-Object).Count
        if ($fileCount -gt 0) {
            $script:onedriveInUse = $true
            Write-Log "  OneDrive in use: Folder contains $fileCount files" "INFO"
        }
    }
}

if ($script:onedriveInUse) {
    Write-Log "  OneDrive will be PRESERVED" "SUCCESS"
} else {
    Write-Log "  OneDrive not in use - will be removed" "INFO"
}

# ============================================================================
# OFFICE USAGE CHECK (determines if Office should be preserved)
# ============================================================================
Write-Log "[Pre-Check] Checking Office status..." "SECTION"
$script:officeInUse = $false

if ($SkipOfficeRemoval) {
    $script:officeInUse = $true
    Write-Log "  Office removal skipped (-SkipOfficeRemoval)" "INFO"
} else {
    # Check for Office 365 / Microsoft 365 subscription (ClickToRun)
    $clickToRun = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -EA 0
    if ($clickToRun.ProductReleaseIds) {
        $o365Products = @('O365ProPlusRetail', 'O365BusinessRetail', 'O365HomePremRetail', 'O365SmallBusPremRetail')
        foreach ($product in $o365Products) {
            if ($clickToRun.ProductReleaseIds -match $product) {
                $script:officeInUse = $true
                Write-Log "  Office 365 subscription detected: $product" "INFO"
                break
            }
        }
    }

    # Check for standalone Office installations
    $officeVersions = @('16.0', '15.0')  # Office 2016/2019/2021 and Office 2013
    foreach ($ver in $officeVersions) {
        $officeKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\$ver\Common\InstallRoot" -EA 0
        if ($officeKey.Path -and (Test-Path $officeKey.Path)) {
            # Check if any Office app has been used recently (within 30 days)
            $recentUse = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Office\$ver\Common\Roaming\Identities\*" -EA 0
            if ($recentUse) {
                $script:officeInUse = $true
                Write-Log "  Office $ver installation in use" "INFO"
                break
            }
        }
    }

    # Check for running Office processes (indicates active use)
    # Includes OneNote 2016, Visio, Project, Access alongside core apps
    $officeProcesses = Get-Process -Name 'WINWORD','EXCEL','POWERPNT','OUTLOOK','ONENOTE','MSPUB','MSACCESS','VISIO','WINPROJ' -EA 0
    if ($officeProcesses) {
        $script:officeInUse = $true
        $runningNames = ($officeProcesses | Select-Object -ExpandProperty Name -Unique) -join ', '
        Write-Log "  Office apps currently running: $runningNames" "INFO"
    }

    # Check for OneNote 2016 standalone (separate install from Office suite)
    if (-not $script:officeInUse) {
        $oneNote2016 = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\16.0\OneNote\InstallRoot" -EA 0
        if ($oneNote2016.Path -and (Test-Path $oneNote2016.Path)) {
            $script:officeInUse = $true
            Write-Log "  OneNote 2016 standalone detected" "INFO"
        }
    }

    # Check for Visio or Project standalone installations
    if (-not $script:officeInUse) {
        foreach ($appKey in @('Visio', 'Project')) {
            $appInstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\16.0\$appKey\InstallRoot" -EA 0
            if ($appInstall.Path -and (Test-Path $appInstall.Path)) {
                $script:officeInUse = $true
                Write-Log "  $appKey standalone detected" "INFO"
                break
            }
        }
    }
}

if ($script:officeInUse) {
    Write-Log "  Office will be PRESERVED" "SUCCESS"
} else {
    Write-Log "  Office not in use - will be removed" "INFO"
}

# ============================================================================
# SYSTEM TWEAKS
# ============================================================================
Update-Phase "System Tweaks"

if (Test-PhaseEnabled 'SystemTweaks') {
. "$PSScriptRoot\Modules\SystemTweaks.ps1"
} else { Write-Log "[System Tweaks] SKIPPED (phase excluded)" "INFO" }


# ============================================================================
# PHASE 1: REMOVE APPX PACKAGES (USER + PROVISIONED)
# ============================================================================
Update-Phase "AppX Package Removal"

if (Test-PhaseEnabled 'AppX') {
. "$PSScriptRoot\Modules\AppX.ps1"
} else { Write-Log "[AppX] AppX removal SKIPPED (phase excluded)" "INFO" }


# ============================================================================
# PHASE 2: OEM BLOATWARE CLEANUP (Dell, Intel, HP, Lenovo)
# ============================================================================
Update-Phase "OEM Cleanup"

if (Test-PhaseEnabled 'OEM') {
. "$PSScriptRoot\Modules\OEM.ps1"
} else { Write-Log "[OEM] OEM cleanup SKIPPED (phase excluded)" "INFO" }


# ============================================================================
# PHASE 2C: ONEDRIVE REMOVAL
# ============================================================================
Update-Phase "OneDrive Removal"

if (-not (Test-PhaseEnabled 'OneDrive')) {
    Write-Log "[OneDrive] OneDrive SKIPPED (phase excluded)" "INFO"
} elseif ($script:onedriveInUse) {
    Write-Log "[OneDrive] OneDrive - SKIPPED (in use)" "SECTION"
} else {
. "$PSScriptRoot\Modules\OneDrive.ps1"
}


# ============================================================================
# PHASE 3: OFFICE NUCLEAR REMOVAL (Skip uninstallers, delete everything)
# ============================================================================
Update-Phase "Office Removal"

if (-not (Test-PhaseEnabled 'Office')) {
    Write-Log "[Office] Office SKIPPED (phase excluded)" "INFO"
} elseif ($script:officeInUse) {
    Write-Log "[Office] Office - SKIPPED (in use)" "SECTION"
} else {
. "$PSScriptRoot\Modules\Office.ps1"
}


# ============================================================================
# DISABLE BLOATWARE SERVICES
# ============================================================================
Update-Phase "Service Cleanup"

. "$PSScriptRoot\Modules\Services.ps1"


# ============================================================================
# PHASE 5: EDGE DEBLOAT
# ============================================================================
Update-Phase "Edge Configuration"

if (Test-PhaseEnabled 'Edge') {
. "$PSScriptRoot\Modules\Edge.ps1"
} else { Write-Log "[Edge] Edge SKIPPED (phase excluded)" "INFO" }


# ============================================================================
# PHASE 6: FIREWALL RULES
# ============================================================================
Update-Phase "Firewall Rules"

if (Test-PhaseEnabled 'Firewall') {
. "$PSScriptRoot\Modules\Firewall.ps1"
} else { Write-Log "[Firewall] Firewall SKIPPED (phase excluded)" "INFO" }


# ============================================================================
# PHASE 7: PRIVACY CLEANUP
# ============================================================================
Update-Phase "Privacy Cleanup"

if (Test-PhaseEnabled 'Privacy') {
. "$PSScriptRoot\Modules\Privacy.ps1"
} else { Write-Log "[Privacy] Privacy SKIPPED (phase excluded)" "INFO" }


# ============================================================================
# OPTIONAL: WINGET APP UPDATES (keeps surviving apps current)
# ============================================================================
$wingetPath = Get-Command 'winget' -EA 0
if ($wingetPath) {
    Write-Log "[Updates] Updating surviving apps via winget..." "SECTION"
    if (-not $DryRun) {
        $wingetResult = & winget upgrade --all --silent --include-unknown --accept-source-agreements --accept-package-agreements 2>&1
        $upgraded = ($wingetResult | Select-String 'Successfully installed').Count
        Write-Log "  winget: $upgraded packages updated" "SUCCESS"
    } else {
        Write-Log "  [DRY RUN] Would run: winget upgrade --all --silent --include-unknown" "INFO"
    }
} else {
    Write-Log "[Updates] winget not found -- skipping app updates" "INFO"
}

# Complete progress bar
if (-not $Silent -and [Environment]::UserInteractive) {
    Write-Progress -Activity "Debloat-Win11" -Completed
}

# ============================================================================
# POST-DEBLOAT: RE-ENABLE ESSENTIAL SERVICES
# ============================================================================
Write-Log "[Post-Debloat] Re-enabling essential services..." "SECTION"

if (-not $DryRun) {
    # Windows Update
    Write-Log "  Re-enabling Windows Update..." "INFO"
    Set-Service -Name 'wuauserv' -StartupType Manual -EA 0
    Start-Service -Name 'wuauserv' -EA 0

    # Windows Search
    Write-Log "  Re-enabling Windows Search..." "INFO"
    Set-Service -Name 'WSearch' -StartupType Automatic -EA 0
    Start-Service -Name 'WSearch' -EA 0
}

Write-Log "  Services re-enabled" "SUCCESS"

# ============================================================================
# REGISTER POST-UPDATE MAINTENANCE TASK
# ============================================================================
Write-Log "[Maintenance] Registering post-update scheduled task..." "SECTION"
$maintainScript = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Debloat-Win11-Maintain.ps1'
if (Test-Path $maintainScript) {
    if (-not $DryRun) {
        $taskName = 'Debloat-Win11-PostUpdate'
        $existingTask = Get-ScheduledTask -TaskName $taskName -EA 0
        if (-not $existingTask) {
            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$maintainScript`""
            # Trigger on WU completion (Event ID 19 = installation complete) + daily fallback
            $wuTrigger = New-ScheduledTaskTrigger -Daily -At '03:00'
            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $wuTrigger -Principal $principal -Settings $settings -Description 'Re-applies privacy/telemetry tweaks after Windows Update resets them' -EA 0 | Out-Null
            # Add event-based trigger for WU completion (supplements the daily trigger)
            $taskXml = (Get-ScheduledTask -TaskName $taskName -EA 0).Xml
            if ($taskXml) {
                $wuEventTrigger = @"
  <EventTrigger>
    <Enabled>true</Enabled>
    <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-WindowsUpdateClient/Operational"&gt;&lt;Select Path="Microsoft-Windows-WindowsUpdateClient/Operational"&gt;*[System[EventID=19]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
  </EventTrigger>
"@
                $taskXml = $taskXml -replace '(</Triggers>)', "$wuEventTrigger`$1"
                Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force -EA 0 | Out-Null
            }
            Write-Log "  Scheduled task '$taskName' registered (WU-completion + daily 3AM)" "SUCCESS"
        } else {
            Write-Log "  Scheduled task '$taskName' already exists" "INFO"
        }
    } else {
        Write-Log "  [DRY RUN] Would register post-update maintenance task" "INFO"
    }
} else {
    Write-Log "  Debloat-Win11-Maintain.ps1 not found alongside script, skipping task registration" "WARNING"
}

# ============================================================================
# RESTART EXPLORER (Apply UI changes immediately)
# ============================================================================
Write-Log "[Finalizing] Restarting Explorer..." "SECTION"
if (-not $DryRun) {
    Stop-Process -Name explorer -Force -EA 0
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
}
Write-Log "  Explorer restarted" "SUCCESS"

# ============================================================================
# WRITE UNDO MANIFEST
# ============================================================================
try {
    $manifestJson = $script:manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($manifestFile, $manifestJson, [System.Text.Encoding]::UTF8)
    Write-Log "Undo manifest: $manifestFile" "INFO"
} catch {
    Write-Log "Could not write undo manifest" "WARNING"
}

# Write registry version stamp for Intune native detection
if (-not $DryRun) {
    $regStampPath = "HKLM:\SOFTWARE\Debloat-Win11"
    if (!(Test-Path $regStampPath)) { New-Item -Path $regStampPath -Force | Out-Null }
    Set-ItemProperty -Path $regStampPath -Name "Version" -Value "v2.3.2" -Type String -Force -EA 0
    Set-ItemProperty -Path $regStampPath -Name "LastRun" -Value (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') -Type String -Force -EA 0
    Set-ItemProperty -Path $regStampPath -Name "ManifestPath" -Value $manifestFile -Type String -Force -EA 0
}

# ============================================================================
# GENERATE STANDALONE REVERT SCRIPT
# ============================================================================
$revertFile = "$LogDir\Debloat-Revert-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').ps1"
try {
    $revertLines = [System.Collections.ArrayList]@()
    $revertLines.Add('#Requires -RunAsAdministrator') | Out-Null
    $revertLines.Add("# Auto-generated revert script from Debloat-Win11 v2.3.2") | Out-Null
    $revertLines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $revertLines.Add('$ErrorActionPreference = "SilentlyContinue"') | Out-Null
    $revertLines.Add('') | Out-Null

    $regEntries = @($script:manifest.changes.registry_set)
    [array]::Reverse($regEntries)
    foreach ($entry in $regEntries) {
        if ($null -eq $entry.old_value) {
            $revertLines.Add("Remove-ItemProperty -Path '$($entry.path)' -Name '$($entry.name)' -Force -EA 0") | Out-Null
        } else {
            $type = if ($entry.type) { $entry.type } else { 'DWord' }
            $revertLines.Add("if (!(Test-Path '$($entry.path)')) { New-Item -Path '$($entry.path)' -Force | Out-Null }") | Out-Null
            $revertLines.Add("Set-ItemProperty -Path '$($entry.path)' -Name '$($entry.name)' -Value $($entry.old_value) -Type $type -Force -EA 0") | Out-Null
        }
    }
    $revertLines.Add('') | Out-Null

    foreach ($svcEntry in $script:manifest.changes.services_disabled) {
        $sName = if ($svcEntry -is [string]) { $svcEntry } else { $svcEntry.name }
        $sType = if ($svcEntry -is [string]) { 'Manual' } else { $svcEntry.original_startup_type }
        $revertLines.Add("Set-Service -Name '$sName' -StartupType $sType -EA 0") | Out-Null
        $revertLines.Add("Start-Service -Name '$sName' -EA 0") | Out-Null
    }
    $revertLines.Add('') | Out-Null

    foreach ($taskName in $script:manifest.changes.tasks_disabled) {
        $revertLines.Add("Get-ScheduledTask -TaskName '$taskName' -EA 0 | Enable-ScheduledTask -EA 0") | Out-Null
    }
    $revertLines.Add('') | Out-Null
    $revertLines.Add('Write-Host "Revert complete. Restart recommended." -ForegroundColor Green') | Out-Null

    $revertContent = $revertLines -join "`r`n"
    [System.IO.File]::WriteAllText($revertFile, $revertContent, [System.Text.Encoding]::UTF8)
    Write-Log "Revert script: $revertFile" "INFO"
} catch {
    Write-Log "Could not generate revert script" "WARNING"
}

# ============================================================================
# HTML REPORT (self-contained single file)
# ============================================================================
$htmlReportFile = "$LogDir\Debloat-Report-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').html"
try {
    $dryLabel = if ($DryRun) { " (DRY RUN)" } else { "" }
    $regRows = ($script:manifest.changes.registry_set | ForEach-Object {
        "<tr><td>$($_.path)</td><td>$($_.name)</td><td>$($_.old_value)</td><td>$($_.new_value)</td></tr>"
    }) -join "`n"
    $svcRows = ($script:manifest.changes.services_disabled | ForEach-Object {
        $sName = if ($_ -is [string]) { $_ } else { $_.name }
        $sOrig = if ($_ -is [string]) { 'Unknown' } else { $_.original_startup_type }
        "<tr><td>$sName</td><td>Disabled (was $sOrig)</td></tr>"
    }) -join "`n"
    $appRows = ($script:manifest.changes.appx_removed | ForEach-Object { "<tr><td>$_</td></tr>" }) -join "`n"
    $taskRows = ($script:manifest.changes.tasks_disabled | ForEach-Object { "<tr><td>$_</td><td>Disabled</td></tr>" }) -join "`n"

    $htmlContent = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Debloat-Win11 Report$dryLabel</title>
<style>
body{font-family:system-ui,sans-serif;background:#1e1e2e;color:#cdd6f4;margin:2em;line-height:1.5}
h1{color:#89b4fa}h2{color:#a6e3a1;border-bottom:1px solid #45475a;padding-bottom:.3em;margin-top:1.5em}
table{border-collapse:collapse;width:100%;margin:.5em 0}
th,td{text-align:left;padding:6px 10px;border:1px solid #45475a;font-size:13px}
th{background:#313244;color:#89b4fa}tr:nth-child(even){background:#181825}
.stat{font-size:1.1em;margin:.3em 0}.stat b{color:#f9e2af}
</style></head><body>
<h1>Debloat-Win11 Report$dryLabel</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Host: $env:COMPUTERNAME | OS: $osName (Build $osBuild)</p>
<div class="stat"><b>AppX Removed:</b> $($script:counters.AppxRemoved) | <b>Services Disabled:</b> $($script:counters.ServicesDisabled) | <b>Tasks Disabled:</b> $($script:counters.TasksDisabled) | <b>Registry Tweaks:</b> $($script:counters.RegistryTweaks)</div>

<h2>Registry Changes ($($script:manifest.changes.registry_set.Count))</h2>
<table><tr><th>Path</th><th>Name</th><th>Old Value</th><th>New Value</th></tr>
$regRows
</table>

<h2>Services Disabled ($($script:manifest.changes.services_disabled.Count))</h2>
<table><tr><th>Service</th><th>Action</th></tr>
$svcRows
</table>

<h2>AppX Packages Removed ($($script:manifest.changes.appx_removed.Count))</h2>
<table><tr><th>Package</th></tr>
$appRows
</table>

<h2>Scheduled Tasks Disabled ($($script:manifest.changes.tasks_disabled.Count))</h2>
<table><tr><th>Task</th><th>Action</th></tr>
$taskRows
</table>

</body></html>
"@
    [System.IO.File]::WriteAllText($htmlReportFile, $htmlContent, [System.Text.Encoding]::UTF8)
    Write-Log "HTML report: $htmlReportFile" "INFO"
} catch {
    Write-Log "Could not generate HTML report" "WARNING"
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================
$endTime = Get-Date
$runtime = $endTime - $script:startTime
$runtimeStr = "{0}m {1}s" -f [int]$runtime.TotalMinutes, $runtime.Seconds

# Calculate disk space recovered
$systemDriveEnd = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -EA 0
$diskRecovered = "N/A"
if ($systemDriveEnd -and $script:counters.DiskBefore -gt 0) {
    $recoveredBytes = $systemDriveEnd.FreeSpace - $script:counters.DiskBefore
    if ($recoveredBytes -gt 0) {
        $diskRecovered = "~{0:N1} GB" -f ($recoveredBytes / 1GB)
    } else {
        $diskRecovered = "< 0.1 GB"
    }
}

$dryLabel = if ($DryRun) { " (DRY RUN)" } else { "" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "DEBLOAT SUMMARY$dryLabel" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ("  AppX Packages Removed:     {0}" -f $script:counters.AppxRemoved) -ForegroundColor White
Write-Host ("  Office Components Removed: {0}" -f $script:counters.OfficeRemoved) -ForegroundColor White
Write-Host ("  OEM Apps Cleaned:          {0}" -f $script:counters.OEMCleaned) -ForegroundColor White
Write-Host ("  Services Disabled:         {0}" -f $script:counters.ServicesDisabled) -ForegroundColor White
Write-Host ("  Tasks Disabled:            {0}" -f $script:counters.TasksDisabled) -ForegroundColor White
Write-Host ("  Registry Tweaks Applied:   {0}" -f $script:counters.RegistryTweaks) -ForegroundColor White
Write-Host ("  Disk Space Recovered:      {0}" -f $diskRecovered) -ForegroundColor White
Write-Host ("  Runtime:                   {0}" -f $runtimeStr) -ForegroundColor White
Write-Host ("  Log File:                  {0}" -f $logFile) -ForegroundColor White
Write-Host ("  Undo Manifest:             {0}" -f $manifestFile) -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan

# Log the summary too
Write-Log "=== DEBLOAT COMPLETE ===" "INFO"
Write-Log "AppX: $($script:counters.AppxRemoved) | Services: $($script:counters.ServicesDisabled) | Tasks: $($script:counters.TasksDisabled) | Registry: $($script:counters.RegistryTweaks)" "INFO"
Write-Log "Exit code: $script:exitCode" "INFO"

# Write completion event to EventLog
$summaryMsg = "Debloat-Win11 v2.3.2 completed. AppX=$($script:counters.AppxRemoved) Services=$($script:counters.ServicesDisabled) Tasks=$($script:counters.TasksDisabled) Registry=$($script:counters.RegistryTweaks) Disk=$diskRecovered Runtime=$runtimeStr ExitCode=$script:exitCode"
$evtType = if ($script:exitCode -eq 0) { 'Information' } else { 'Warning' }
Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 1000 -EntryType $evtType -Message $summaryMsg -EA 0

# Collect crash dump if errors occurred (opt-in diagnostic bundle)
if ($script:exitCode -ne 0) {
    $crashTs = Get-Date -Format 'yyyyMMdd-HHmmss'
    $crashDir = "$env:TEMP\Debloat-Win11-crash-$crashTs"
    $crashZip = "$env:TEMP\Debloat-Win11-crash-$crashTs.zip"
    try {
        New-Item -Path $crashDir -ItemType Directory -Force | Out-Null
        if (Test-Path $logFile) { Copy-Item $logFile $crashDir -EA 0 }
        if (Test-Path $manifestFile) { Copy-Item $manifestFile $crashDir -EA 0 }
        $sysInfo = @{
            ComputerName = $env:COMPUTERNAME
            OSName       = $osName
            Build        = $osBuild
            EditionId    = $editionId
            IsLTSC       = $script:isLTSC
            IsLaptop     = $script:isLaptop
            IsSSD        = $script:isSSD
            RAM_GB       = $totalRAM
            ExitCode     = $script:exitCode
            Timestamp    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        }
        $sysInfo | ConvertTo-Json | Set-Content "$crashDir\system-info.json" -EA 0
        Compress-Archive -Path "$crashDir\*" -DestinationPath $crashZip -Force -EA 0
        Remove-Item $crashDir -Recurse -Force -EA 0
        Write-Log "Crash dump saved: $crashZip" "WARNING"
        Write-Log "  Attach this file to bug reports -- it is never uploaded automatically." "INFO"
    } catch {
        Write-Log "Could not create crash dump" "WARNING"
    }
}

Write-Host "`nRestart recommended to apply all changes." -ForegroundColor Yellow

# Clean up lockfile
Remove-Item $script:lockFile -Force -EA 0

exit $script:exitCode
