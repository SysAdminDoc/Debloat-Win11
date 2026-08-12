#Requires -RunAsAdministrator
#Requires -Version 5.1

# ============================================================================
# WINDOWS 11 COMPLETE DEBLOAT SCRIPT v2.3.11
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
    [ValidateSet('Text','Json','Csv')]
    [string]$OutputFormat = 'Text',
    [switch]$Explain,
    [string]$RestoreApp,
    [string]$RestoreSource,
    [string]$RestoreVersion,
    [string[]]$DiffManifests,
    [string]$WimPath,
    [int]$WimIndex = 1,
    [string]$MountDir = "C:\Debloat-WIM-Mount",
    [switch]$CheckDrift,
    [switch]$AllUsers,
    [switch]$UpdateApps,
    [switch]$AllowUnsupportedPlatform,
    [switch]$AllowIrreversibleChanges
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

$script:policyCatalogFile = Join-Path $PSScriptRoot 'Modules\PolicyCatalog.psd1'
try {
    $script:policyCatalog = Import-PowerShellDataFile -Path $script:policyCatalogFile
} catch {
    Write-Host "ERROR: Policy catalog failed to load: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
if ($script:policyCatalog.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$script:policyCatalog.CatalogVersion)) {
    Write-Host "ERROR: Policy catalog schema/version is unsupported: $($script:policyCatalog.SchemaVersion)/$($script:policyCatalog.CatalogVersion)" -ForegroundColor Red
    exit 2
}
if (@($script:policyCatalog.RuntimeMatrix).Count -eq 0) {
    Write-Host 'ERROR: Policy catalog has no supported runtime matrix' -ForegroundColor Red
    exit 2
}
$script:profileHelperFile = Join-Path $PSScriptRoot 'tools\ProfileHive.ps1'
try {
    if (-not (Test-Path $script:profileHelperFile)) { throw "Profile helper not found: $script:profileHelperFile" }
    . $script:profileHelperFile
} catch {
    Write-Host "ERROR: Profile helper failed to load: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
$script:windowsAiPolicies = @($script:policyCatalog.Policies)
$script:hkcuTweaks = @($script:policyCatalog.HkcuTweaks)
$script:actionCatalog = @($script:policyCatalog.Actions)
$catalogErrors = [System.Collections.ArrayList]@()
$validRegistryTypes = @('DWord','QWord','String','ExpandString','MultiString','Binary')
foreach ($policy in $script:windowsAiPolicies) {
    if ($policy.Scope -notin @('Device','User') -or [string]::IsNullOrWhiteSpace([string]$policy.Path) -or [string]::IsNullOrWhiteSpace([string]$policy.Name)) {
        $catalogErrors.Add("Invalid policy scope/path/name: $($policy | Out-String)") | Out-Null
    }
    if ($policy.Type -notin $validRegistryTypes) { $catalogErrors.Add("Invalid policy type '$($policy.Type)' for $($policy.Name)") | Out-Null }
    if ($policy.ApplyByDefault -isnot [bool]) { $catalogErrors.Add("Policy $($policy.Name) must declare boolean ApplyByDefault") | Out-Null }
}
foreach ($tweak in $script:hkcuTweaks) {
    if ($tweak.Scope -ne 'User' -or [string]::IsNullOrWhiteSpace([string]$tweak.Path) -or [string]::IsNullOrWhiteSpace([string]$tweak.Name)) {
        $catalogErrors.Add("Invalid HKCU tweak scope/path/name: $($tweak | Out-String)") | Out-Null
    }
    if ($tweak.Type -notin $validRegistryTypes) { $catalogErrors.Add("Invalid HKCU tweak type '$($tweak.Type)' for $($tweak.Name)") | Out-Null }
}
foreach ($action in $script:actionCatalog) {
    if ([string]::IsNullOrWhiteSpace([string]$action.Name) -or [string]::IsNullOrWhiteSpace([string]$action.Phase)) {
        $catalogErrors.Add('Action metadata requires Name and Phase') | Out-Null
    }
    if ($action.Risk -notin @('Low','Medium','High','Critical')) { $catalogErrors.Add("Invalid action risk '$($action.Risk)' for $($action.Name)") | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$action.Scope)) { $catalogErrors.Add("Action $($action.Name) requires Scope metadata") | Out-Null }
    if ($action.SupportedBuildMin -isnot [int] -or $action.SupportedBuildMin -lt 1) { $catalogErrors.Add("Action $($action.Name) requires a positive SupportedBuildMin") | Out-Null }
    if (@($action.SupportedEditions).Count -eq 0) { $catalogErrors.Add("Action $($action.Name) requires SupportedEditions metadata") | Out-Null }
    if (@($action.SupportedArchitectures).Count -eq 0) { $catalogErrors.Add("Action $($action.Name) requires SupportedArchitectures metadata") | Out-Null }
    if ($action.DefaultEnabled -isnot [bool] -or $action.RequiresApproval -isnot [bool]) { $catalogErrors.Add("Action $($action.Name) requires boolean DefaultEnabled and RequiresApproval metadata") | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$action.Rollback)) { $catalogErrors.Add("Action $($action.Name) requires Rollback metadata") | Out-Null }
}
$runtimeMatrixErrors = [System.Collections.ArrayList]@()
foreach ($runtime in @($script:policyCatalog.RuntimeMatrix)) {
    if ([string]::IsNullOrWhiteSpace([string]$runtime.Name) -or [int]$runtime.MinimumBuild -lt 1 -or @($runtime.SupportedEditions).Count -eq 0 -or @($runtime.SupportedArchitectures).Count -eq 0) {
        $runtimeMatrixErrors.Add('Every runtime matrix entry requires Name, positive MinimumBuild, SupportedEditions, and SupportedArchitectures') | Out-Null
    }
}
$runtimeNames = @($script:policyCatalog.RuntimeMatrix | ForEach-Object Name | Group-Object | Where-Object Count -gt 1)
if ($runtimeNames.Count -gt 0) { $runtimeMatrixErrors.Add('Runtime matrix names must be unique') | Out-Null }
$actionPhaseDuplicates = $script:actionCatalog | ForEach-Object Phase | Group-Object | Where-Object Count -gt 1
foreach ($duplicate in $actionPhaseDuplicates) { $catalogErrors.Add("Duplicate action metadata phase '$($duplicate.Name)'") | Out-Null }
$expectedActionPhases = @('AppX','OEM','OneDrive','Office','Edge','Firewall','Privacy','Services','SystemTweaks','Power','Network','StartMenu','Updates')
foreach ($expectedPhase in $expectedActionPhases) {
    if (@($script:actionCatalog | Where-Object Phase -eq $expectedPhase).Count -ne 1) { $catalogErrors.Add("Action catalog must contain exactly one entry for phase '$expectedPhase'") | Out-Null }
}
$duplicatePolicies = $script:windowsAiPolicies | ForEach-Object { "$($_.Scope)|$($_.Path)|$($_.Name)" } | Group-Object | Where-Object Count -gt 1
foreach ($duplicate in $duplicatePolicies) { $catalogErrors.Add("Duplicate policy catalog key '$($duplicate.Name)'") | Out-Null }
if ($catalogErrors.Count -gt 0) {
    Write-Host "ERROR: Policy catalog validation failed:" -ForegroundColor Red
    $catalogErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 2
}
if ($runtimeMatrixErrors.Count -gt 0) {
    Write-Host 'ERROR: Runtime matrix validation failed:' -ForegroundColor Red
    $runtimeMatrixErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 2
}

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
    foreach ($policy in ($script:windowsAiPolicies | Where-Object { $_.ApplyByDefault -ne $false })) {
        $root = if ($policy.Scope -eq 'User') { 'HKCU' } else { 'HKLM' }
        $driftChecks += @{ Path = ('{0}:\{1}' -f $root, $policy.Path); Name = $policy.Name; Expected = $policy.Value }
    }

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
    Write-Host "  Checked: $($driftChecks.Count) | OK: $ok | Drifted: $drifted | Missing: $missing" -ForegroundColor $(if ($drifted + $missing -gt 0) { 'Yellow' } else { 'Green' })
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
    Network      = "Preserves network profiles by default; optional Nagle/discovery/file-sharing changes are explicit and limited to Domain/Private."
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
            Set-DebloatRegistryProperty -Path $entry.path -Name $entry.name -Value $entry.old_value -Type $type -ErrorAction SilentlyContinue
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
    if ($RestoreApp -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') {
        Write-Host "ERROR: -RestoreApp requires an exact WinGet package Id (letters, digits, dot, underscore, or hyphen)" -ForegroundColor Red
        exit 2
    }
    if ($RestoreSource -and $RestoreSource -match '[\r\n]') { Write-Host 'ERROR: -RestoreSource cannot contain newlines' -ForegroundColor Red; exit 2 }
    if ($RestoreVersion -and $RestoreVersion -match '[\r\n]') { Write-Host 'ERROR: -RestoreVersion cannot contain newlines' -ForegroundColor Red; exit 2 }

    New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $restoreReportPath = Join-Path $LogDir ("Debloat-Restore-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $restoreReport = [ordered]@{
        schema_version = 1
        mode = 'RestoreApp'
        package_id = $RestoreApp
        source = if ($RestoreSource) { $RestoreSource } else { 'default' }
        requested_version = if ($RestoreVersion) { $RestoreVersion } else { 'latest' }
        exact_id = $true
        pre_version = 'Unknown'
        post_version = 'Unknown'
        return_code = $null
        status = 'Failed'
        output = @{}
    }
    Write-Host "=== RESTORE APP MODE ===" -ForegroundColor Yellow
    Write-Host "Exact package Id: $RestoreApp" -ForegroundColor Cyan
    $showArgs = @('show', '--id', $RestoreApp, '--exact', '--accept-source-agreements', '--disable-interactivity')
    if ($RestoreSource) { $showArgs += @('--source', $RestoreSource) }
    $showOutput = @(& winget @showArgs 2>&1)
    $showExitCode = $LASTEXITCODE
    $restoreReport.output.show = @($showOutput)
    if ($showExitCode -ne 0) {
        $restoreReport.return_code = $showExitCode
        $restoreReport.status = 'UnknownPackage'
        Write-WingetReport -Path $restoreReportPath -Report $restoreReport
        Write-Host "ERROR: Exact WinGet package Id was not found (exit code $showExitCode). Report: $restoreReportPath" -ForegroundColor Red
        exit 1
    }
    $beforeRestore = Get-WingetPackageSnapshot -PackageId $RestoreApp -Source $RestoreSource
    $restoreReport.pre_version = $beforeRestore.Version
    $installArgs = @('install', '--id', $RestoreApp, '--exact', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($RestoreSource) { $installArgs += @('--source', $RestoreSource) }
    if ($RestoreVersion) { $installArgs += @('--version', $RestoreVersion) }
    Write-Host "Installing exact package Id: $RestoreApp" -ForegroundColor Cyan
    $installOutput = @(& winget @installArgs 2>&1)
    $installExitCode = $LASTEXITCODE
    $restoreReport.output.install = @($installOutput)
    $afterRestore = Get-WingetPackageSnapshot -PackageId $RestoreApp -Source $RestoreSource
    $restoreReport.post_version = $afterRestore.Version
    $restoreReport.return_code = $installExitCode
    $restoreReport.status = if ($installExitCode -eq 0 -and $afterRestore.Found) { 'Complete' } else { 'Failed' }
    Write-WingetReport -Path $restoreReportPath -Report $restoreReport
    if ($restoreReport.status -eq 'Complete') {
        Write-Host "=== RESTORE COMPLETE ===" -ForegroundColor Green
        Write-Host "  Version: $($restoreReport.pre_version) -> $($restoreReport.post_version) | Report: $restoreReportPath" -ForegroundColor White
        exit 0
    }
    Write-Host "=== RESTORE FAILED (exit code $installExitCode) ===" -ForegroundColor Red
    Write-Host "  Report: $restoreReportPath" -ForegroundColor Yellow
    exit 1
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
# CONFIG FILE SUPPORT
# ============================================================================
# Merge external .psd1 config into the session, overriding built-in arrays
$script:configOverrides = @{}
$script:configSchema = $script:policyCatalog.ConfigSchema
$script:validConfigKeys = @($script:configSchema.Keys)
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
    $configErrors = [System.Collections.ArrayList]@()
    foreach ($key in $script:configOverrides.Keys) {
        if ($script:validConfigKeys -notcontains $key) {
            $configErrors.Add("Unknown config key '$key'. Valid keys: $($script:validConfigKeys -join ', ')") | Out-Null
            continue
        }
        $schema = $script:configSchema[$key]
        $value = $script:configOverrides[$key]
        switch ($schema.Type) {
            'Boolean' {
                if ($value -isnot [bool]) { $configErrors.Add("$key must be a Boolean") | Out-Null }
            }
            'String' {
                if ($value -isnot [string]) { $configErrors.Add("$key must be a String") | Out-Null }
            }
            'Enum' {
                if ($value -isnot [string] -or $schema.Values -notcontains $value) { $configErrors.Add("$key must be one of: $($schema.Values -join ', ')") | Out-Null }
            }
            'StringArray' {
                if ($value -is [string] -or $value -isnot [System.Collections.IEnumerable]) {
                    $configErrors.Add("$key must be an array of strings") | Out-Null
                } else {
                    foreach ($element in @($value)) {
                        if ($element -isnot [string] -or ($schema.ElementPattern -and [string]$element -notmatch $schema.ElementPattern)) {
                            $configErrors.Add("$key contains an invalid string value '$element'") | Out-Null
                        }
                    }
                }
            }
            'BookmarkArray' {
                if ($value -is [string] -or $value -isnot [System.Collections.IEnumerable]) {
                    $configErrors.Add("$key must be an array of bookmark objects") | Out-Null
                } else {
                    foreach ($bookmark in @($value)) {
                        $uri = $null
                        $validUri = [Uri]::TryCreate([string]$bookmark.url, [UriKind]::Absolute, [ref]$uri)
                        if ($bookmark -isnot [hashtable] -or [string]::IsNullOrWhiteSpace([string]$bookmark.name) -or -not $validUri -or $uri.Scheme -notin @('http','https')) {
                            $configErrors.Add("$key contains a bookmark with a missing name or HTTP(S) URL") | Out-Null
                        }
                    }
                }
            }
            'PackageArray' {
                if ($value -is [string] -or $value -isnot [System.Collections.IEnumerable]) {
                    $configErrors.Add("$key must be an array of package specification objects") | Out-Null
                } else {
                    foreach ($package in @($value)) {
                        $packageId = [string]$package.Id
                        $validId = $package -is [hashtable] -and $packageId -match '^[A-Za-z0-9][A-Za-z0-9._-]+$'
                        if (-not $validId) {
                            $configErrors.Add("$key contains an invalid exact package Id '$packageId'") | Out-Null
                            continue
                        }
                        if ($package.ContainsKey('Source') -and $package.Source -isnot [string]) { $configErrors.Add("$key package $packageId has a non-string Source") | Out-Null }
                        if ($package.ContainsKey('Version') -and $package.Version -isnot [string]) { $configErrors.Add("$key package $packageId has a non-string Version") | Out-Null }
                    }
                }
            }
        }
    }
    if ($configErrors.Count -gt 0) {
        Write-Host "ERROR: Config validation failed:" -ForegroundColor Red
        $configErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 2
    }
}

try {
    $script:policyCatalogHash = (Get-FileHash -LiteralPath $script:policyCatalogFile -Algorithm SHA256 -ErrorAction Stop).Hash
    $script:configurationHash = 'none'
    if ($ConfigPath) {
        $script:configurationHash = (Get-FileHash -LiteralPath (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).Path -Algorithm SHA256 -ErrorAction Stop).Hash
    }
} catch {
    Write-Host "ERROR: Could not fingerprint policy catalog/configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

function Get-ActionMetadata {
    param([Parameter(Mandatory)][string]$Phase)
    return $script:actionCatalog | Where-Object { $_.Phase -eq $Phase } | Select-Object -First 1
}

function Write-ActionPlan {
    param([Parameter(Mandatory)][string]$Phase)
    $action = Get-ActionMetadata -Phase $Phase
    if (-not $action) { return }
    $actionText = "  ACTION: $($action.Name) | Risk=$($action.Risk) | Scope=$($action.Scope) | MinBuild=$($action.SupportedBuildMin) | Rollback=$($action.Rollback) | Approval=$($action.RequiresApproval)"
    Write-Log $actionText 'INFO'
    if ($Explain) {
        Write-Log "  PREREQUISITES: $($action.Prerequisites -join '; ')" 'INFO'
        Write-Log "  DEPENDENCIES: $(if (@($action.Dependencies).Count) { $action.Dependencies -join '; ' } else { 'None' })" 'INFO'
        Write-Log "  SUPPORTED EDITIONS: $($action.SupportedEditions -join ', ')" 'INFO'
    }
}

# WIM helpers are defined before the WIM branch so every native DISM/registry
# operation has checked status and the report can describe partial failures.
function Add-WimReportOperation {
    param([string]$Name, [string]$Status, [string]$Detail)
    if ($script:wimReport) {
        $script:wimReport.operations += [ordered]@{
            name = $Name
            status = $Status
            detail = $Detail
        }
    }
}

function Open-WimRegistryHive {
    param([Parameter(Mandatory)][string]$HiveName, [Parameter(Mandatory)][string]$HiveFile)

    & reg load $HiveName $HiveFile 2>$null | Out-Null
    $loadExitCode = $LASTEXITCODE
    if ($loadExitCode -ne 0) {
        Add-WimReportOperation -Name "Load $HiveName" -Status 'Failed' -Detail "reg load exit code $loadExitCode"
        throw "Could not load offline hive $HiveFile (reg load exit code $loadExitCode)"
    }
    $registryPath = "Registry::HKEY_USERS\$($HiveName -replace '^HKU\\','')"
    if (-not (Test-Path $registryPath)) {
        Add-WimReportOperation -Name "Load $HiveName" -Status 'Failed' -Detail 'Hive path was not available after reg load'
        throw "Offline hive $HiveName was not available after loading"
    }
    Add-WimReportOperation -Name "Load $HiveName" -Status 'Succeeded' -Detail $HiveFile
    return [pscustomobject]@{ HiveName = $HiveName; RegistryPath = $registryPath; Loaded = $true }
}

function Close-WimRegistryHive {
    param([Parameter(Mandatory)][psobject]$Session)

    [gc]::Collect()
    Start-Sleep -Milliseconds 500
    & reg unload $Session.HiveName 2>$null | Out-Null
    $unloadExitCode = $LASTEXITCODE
    if ($unloadExitCode -ne 0) {
        Add-WimReportOperation -Name "Unload $($Session.HiveName)" -Status 'Failed' -Detail "reg unload exit code $unloadExitCode"
        throw "Could not unload offline hive $($Session.HiveName) (reg unload exit code $unloadExitCode)"
    }
    $Session.Loaded = $false
    Add-WimReportOperation -Name "Unload $($Session.HiveName)" -Status 'Succeeded' -Detail $null
}

function Set-WimRegistryValue {
    param(
        [Parameter(Mandatory)][string]$HiveRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )

    $registryPath = "Registry::HKEY_USERS\$HiveRoot\$RelativePath"
    Set-DebloatRegistryProperty -Path $registryPath -Name $Name -Value $Value -Type $Type -ErrorAction Stop
    $current = Get-ItemProperty -Path $registryPath -Name $Name -ErrorAction Stop
    if ($null -eq $current -or $current.$Name -ne $Value) {
        throw "Offline registry verification failed for $HiveRoot\$RelativePath\$Name"
    }
    $script:wimReport.registry_values_applied++
}

function Get-WingetPackageSnapshot {
    param([Parameter(Mandatory)][string]$PackageId, [string]$Source)

    $args = @('list', '--id', $PackageId, '--exact', '--disable-interactivity')
    if ($Source) { $args += @('--source', $Source) }
    $output = @(& winget @args 2>&1)
    $exitCode = $LASTEXITCODE
    $version = 'NotInstalled'
    $escapedId = [regex]::Escape($PackageId)
    foreach ($line in $output) {
        if ([string]$line -match "\s$escapedId\s+(?<version>[^\s]+)") {
            $version = [string]$Matches.version
            break
        }
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
        Version = $version
        Found = ($version -ne 'NotInstalled')
    }
}

function Write-WingetReport {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Report)
    try {
        $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
    } catch {
        Write-Host "WARNING: Could not write WinGet report: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================================
# WIM IMAGE MODE - Offline debloat of a mounted Windows image
# ============================================================================
if ($WimPath) {
    $wimReportFile = $null
    $wimReport = [ordered]@{
        schema_version = 1
        mode = 'WIM'
        image_path = $WimPath
        image_index = $WimIndex
        mount_path = $MountDir
        catalog_version = [string]$script:policyCatalog.CatalogVersion
        image_name = $null
        image_version = $null
        host_build = [Environment]::OSVersion.Version.Build
        status = 'ValidationFailed'
        commit_status = 'NotStarted'
        packages_removed = 0
        registry_values_applied = 0
        operations = @()
    }
    $script:wimReport = $wimReport
    $wimFailure = $null
    $wimMounted = $false
    $wimSave = $false
    $wimCommitRequested = $false
    $defaultHiveLoaded = $false
    $softwareHiveLoaded = $false
    $defaultHiveSession = $null
    $softwareHiveSession = $null
    $removed = 0

    function Write-WimReport {
        if (-not $wimReportFile) { return }
        try {
            $script:wimReport | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $wimReportFile -Encoding UTF8
        } catch {
            Write-Host "WARNING: Could not write WIM report: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    try {
        if (!(Test-Path -LiteralPath $WimPath -PathType Leaf)) {
            throw "WIM file not found: $WimPath"
        }
        if ($WimIndex -lt 1) { throw "WIM index must be 1 or greater" }
        if ([string]::IsNullOrWhiteSpace($MountDir)) { throw 'Mount directory cannot be empty' }
        $resolvedWimPath = (Resolve-Path -LiteralPath $WimPath -ErrorAction Stop).Path
        $resolvedMountDir = [System.IO.Path]::GetFullPath($MountDir)
        $mountRoot = [System.IO.Path]::GetPathRoot($resolvedMountDir)
        if ($resolvedMountDir.TrimEnd('\') -ieq $mountRoot.TrimEnd('\')) { throw "Mount directory cannot be a drive root: $resolvedMountDir" }
        $wimReport.image_path = $resolvedWimPath
        $wimReport.mount_path = $resolvedMountDir

        foreach ($requiredCommand in @('Get-WindowsImage','Mount-WindowsImage','Dismount-WindowsImage','Get-AppxProvisionedPackage','Remove-AppxProvisionedPackage')) {
            if (-not (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) {
                throw "Required DISM command is unavailable: $requiredCommand"
            }
        }
        $imageInfo = @(Get-WindowsImage -ImagePath $resolvedWimPath -Index $WimIndex -ErrorAction Stop)
        if ($imageInfo.Count -ne 1) { throw "WIM index $WimIndex was not found in $resolvedWimPath" }
        $wimReport.image_name = [string]$imageInfo[0].ImageName
        $wimReport.image_version = [string]$imageInfo[0].Version
        if (-not [Environment]::Is64BitOperatingSystem -and [string]$imageInfo[0].Architecture -match '64') {
            throw 'The selected image architecture requires a 64-bit host'
        }
        $mountedImages = @(Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { ([string]$_.MountDir).TrimEnd('\') -ieq $resolvedMountDir.TrimEnd('\') })
        if ($mountedImages.Count -gt 0) { throw "Mount directory is already registered with DISM: $resolvedMountDir" }
        if (Test-Path -LiteralPath $resolvedMountDir -PathType Leaf) { throw "Mount path is a file: $resolvedMountDir" }
        if (-not (Test-Path -LiteralPath $resolvedMountDir)) {
            New-Item -Path $resolvedMountDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } elseif (@(Get-ChildItem -LiteralPath $resolvedMountDir -Force -ErrorAction Stop).Count -gt 0) {
            throw "Mount directory must be empty before mounting: $resolvedMountDir"
        }
        New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $wimReportFile = Join-Path $LogDir ("Debloat-WIM-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

        Write-Host "=== WIM IMAGE MODE ===" -ForegroundColor Yellow
        Write-Host "  Image: $resolvedWimPath (Index $WimIndex)" -ForegroundColor Cyan
        Write-Host "  Image name: $($wimReport.image_name)" -ForegroundColor Cyan
        Write-Host "  Mount: $resolvedMountDir" -ForegroundColor Cyan
        Write-Host "  Catalog: $($wimReport.catalog_version)" -ForegroundColor Cyan

        if (-not $DryRun -and -not $AllowIrreversibleChanges) {
            $wimReport.status = 'Blocked'
            $wimReport.commit_status = 'NotAuthorized'
            Write-Host "ERROR: WIM changes require -AllowIrreversibleChanges (use -DryRun to preview)" -ForegroundColor Red
            Write-WimReport
            exit 2
        }
        if ($DryRun) {
            $wimReport.status = 'Planned'
            $wimReport.commit_status = 'NotRequested'
            $removePatterns = if ($script:configOverrides.ContainsKey('RemovePatterns')) { @($script:configOverrides.RemovePatterns) } else { @($script:defaultRemovePatterns) }
            Write-Host "  [DRY RUN] Would remove provisioned packages matching $($removePatterns.Count) configured patterns" -ForegroundColor Gray
            Write-Host "  [DRY RUN] Would apply $(@(Get-DebloatUserRegistryChecks -Policies $script:windowsAiPolicies -Tweaks $script:hkcuTweaks).Count) user catalog values and device policy catalog values" -ForegroundColor Gray
            Write-WimReport
            exit 0
        }
    } catch {
        $wimFailure = $_.Exception.Message
        $wimReport.status = 'ValidationFailed'
        $wimReport.commit_status = 'NotStarted'
        Write-Host "ERROR: WIM validation failed: $wimFailure" -ForegroundColor Red
        Write-WimReport
        exit 2
    }

    try {
    Write-Host "`n  Mounting image..." -ForegroundColor Gray
    $mountResult = Mount-WindowsImage -ImagePath $resolvedWimPath -Index $WimIndex -Path $resolvedMountDir -EA Stop
    if (-not $mountResult) {
        throw "Failed to mount WIM image"
    }
    $wimMounted = $true
    $script:wimReport.status = 'Mounted'
    Add-WimReportOperation -Name 'Mount image' -Status 'Succeeded' -Detail "index=$WimIndex"
    Write-Host "  Mounted successfully" -ForegroundColor Green

    # Remove provisioned AppX packages from the offline image
    Write-Host "`n  Removing provisioned AppX packages..." -ForegroundColor Gray
    $provPkgs = @(Get-AppxProvisionedPackage -Path $resolvedMountDir -ErrorAction Stop)
    $removePatterns = if ($script:configOverrides.ContainsKey('RemovePatterns')) { @($script:configOverrides.RemovePatterns) } else { @($script:defaultRemovePatterns) }
    foreach ($pkg in $provPkgs) {
        foreach ($pattern in $removePatterns) {
            if ($pkg.DisplayName -like $pattern -or $pkg.PackageName -like $pattern) {
                Remove-AppxProvisionedPackage -Path $resolvedMountDir -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                Write-Host "    Removed: $($pkg.DisplayName)" -ForegroundColor DarkGray
                $removed++
                break
            }
        }
    }
    $remainingPackages = @(Get-AppxProvisionedPackage -Path $resolvedMountDir -ErrorAction Stop)
    foreach ($remaining in $remainingPackages) {
        if (@($removePatterns | Where-Object { $remaining.DisplayName -like $_ -or $remaining.PackageName -like $_ }).Count -gt 0) {
            throw "Provisioned package remained after removal: $($remaining.PackageName)"
        }
    }
    $script:wimReport.packages_removed = $removed
    Add-WimReportOperation -Name 'Remove provisioned packages' -Status 'Succeeded' -Detail "removed=$removed"
    Write-Host "  Removed $removed provisioned packages" -ForegroundColor Green

    # Apply the shared user catalog to the offline Default user hive.
    Write-Host "`n  Applying offline Default user registry catalog..." -ForegroundColor Gray
    $offlineHive = "$resolvedMountDir\Users\Default\NTUSER.DAT"
    if (-not (Test-Path $offlineHive)) { throw "Offline Default user hive not found: $offlineHive" }
    $defaultHiveSession = Open-WimRegistryHive -HiveName 'HKU\OfflineWIM' -HiveFile $offlineHive
    try {
        $defaultHiveLoaded = $true
        $userChecks = @(Get-DebloatUserRegistryChecks -Policies $script:windowsAiPolicies -Tweaks $script:hkcuTweaks)
        foreach ($check in $userChecks) {
            Set-WimRegistryValue -HiveRoot 'OfflineWIM' -RelativePath $check.Path -Name $check.Name -Value $check.Expected -Type $check.Type
        }
        Add-WimReportOperation -Name 'Apply user policy catalog' -Status 'Succeeded' -Detail "values=$($userChecks.Count)"
    } finally {
        if ($defaultHiveSession -and $defaultHiveSession.Loaded) {
            Close-WimRegistryHive -Session $defaultHiveSession
            $defaultHiveLoaded = $false
            $defaultHiveSession = $null
        }
    }
    Write-Host "  Default user catalog configured" -ForegroundColor Green

    # Apply baseline and catalog device policies to the offline SOFTWARE hive.
    $offlineSW = "$resolvedMountDir\Windows\System32\config\SOFTWARE"
    if (-not (Test-Path $offlineSW)) { throw "Offline SOFTWARE hive not found: $offlineSW" }
    $softwareHiveSession = Open-WimRegistryHive -HiveName 'HKU\OfflineSW' -HiveFile $offlineSW
    try {
        $softwareHiveLoaded = $true
        $deviceChecks = @(
            @{ Path = 'Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Type = 'DWord' }
            @{ Path = 'Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord' }
            @{ Path = 'Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Type = 'DWord' }
            @{ Path = 'Policies\Microsoft\Windows\OOBE'; Name = 'DisablePrivacyExperience'; Value = 1; Type = 'DWord' }
            @{ Path = 'Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Value = 0; Type = 'DWord' }
        )
        foreach ($policy in ($script:windowsAiPolicies | Where-Object { $_.Scope -eq 'Device' -and $_.ApplyByDefault -ne $false })) {
            $relativePolicyPath = [string]$policy.Path -replace '^SOFTWARE\\', ''
            $deviceChecks += @{ Path = $relativePolicyPath; Name = $policy.Name; Value = $policy.Value; Type = $policy.Type }
        }
        foreach ($check in $deviceChecks) {
            Set-WimRegistryValue -HiveRoot 'OfflineSW' -RelativePath $check.Path -Name $check.Name -Value $check.Value -Type $check.Type
        }
        Add-WimReportOperation -Name 'Apply device policy catalog' -Status 'Succeeded' -Detail "values=$($deviceChecks.Count)"
        Write-Host "  System policy catalog configured" -ForegroundColor Green
    } finally {
        if ($softwareHiveSession -and $softwareHiveSession.Loaded) {
            Close-WimRegistryHive -Session $softwareHiveSession
            $softwareHiveLoaded = $false
            $softwareHiveSession = $null
        }
    }

    $wimCommitRequested = $true
    } catch {
        $wimFailure = $_.Exception.Message
        $wimCommitRequested = $false
        $wimSave = $false
        $script:wimReport.status = 'Failed'
        $script:wimReport.commit_status = 'DiscardRequired'
        Add-WimReportOperation -Name 'WIM transaction' -Status 'Failed' -Detail $wimFailure
        Write-Host "ERROR: WIM mode failed: $wimFailure" -ForegroundColor Red
    } finally {
        if ($defaultHiveSession -and $defaultHiveSession.Loaded) {
            try {
                Close-WimRegistryHive -Session $defaultHiveSession
                $defaultHiveLoaded = $false
                $defaultHiveSession = $null
            } catch {
                $wimCommitRequested = $false
                $wimSave = $false
                $wimFailure = $_.Exception.Message
                Add-WimReportOperation -Name 'Unload HKU\OfflineWIM' -Status 'Failed' -Detail $wimFailure
            }
        }
        if ($softwareHiveSession -and $softwareHiveSession.Loaded) {
            try {
                Close-WimRegistryHive -Session $softwareHiveSession
                $softwareHiveLoaded = $false
                $softwareHiveSession = $null
            } catch {
                $wimCommitRequested = $false
                $wimSave = $false
                $wimFailure = $_.Exception.Message
                Add-WimReportOperation -Name 'Unload HKU\OfflineSW' -Status 'Failed' -Detail $wimFailure
            }
        }
        if ($wimMounted) {
            if ($wimCommitRequested) {
                Write-Host "`n  Unmounting and saving image..." -ForegroundColor Gray
                try {
                    Dismount-WindowsImage -Path $resolvedMountDir -Save -ErrorAction Stop | Out-Null
                    $remainingMounts = @(Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { ([string]$_.MountDir).TrimEnd('\') -ieq $resolvedMountDir.TrimEnd('\') })
                    if ($remainingMounts.Count -gt 0) { throw 'DISM still reports the image as mounted after save' }
                    $wimMounted = $false
                    $wimSave = $true
                    $script:wimReport.status = 'Complete'
                    $script:wimReport.commit_status = 'Saved'
                    Add-WimReportOperation -Name 'Save and dismount image' -Status 'Succeeded' -Detail $null
                    Write-Host "  Image saved successfully" -ForegroundColor Green
                } catch {
                    $wimSave = $false
                    $wimCommitRequested = $false
                    $wimFailure = "Save failed: $($_.Exception.Message)"
                    $script:wimReport.status = 'Failed'
                    $script:wimReport.commit_status = 'SaveFailed'
                    Add-WimReportOperation -Name 'Save and dismount image' -Status 'Failed' -Detail $wimFailure
                    Write-Host "  Save failed; attempting discard..." -ForegroundColor Yellow
                    try {
                        Dismount-WindowsImage -Path $resolvedMountDir -Discard -ErrorAction Stop | Out-Null
                        $remainingMounts = @(Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { ([string]$_.MountDir).TrimEnd('\') -ieq $resolvedMountDir.TrimEnd('\') })
                        if ($remainingMounts.Count -gt 0) { throw 'DISM still reports the image as mounted after discard' }
                        $wimMounted = $false
                        $script:wimReport.commit_status = 'SaveFailedDiscarded'
                        Add-WimReportOperation -Name 'Discard failed save' -Status 'Succeeded' -Detail $null
                    } catch {
                        $wimFailure = "$wimFailure; discard failed: $($_.Exception.Message)"
                        $script:wimReport.commit_status = 'SaveAndDiscardFailed'
                        Add-WimReportOperation -Name 'Discard failed save' -Status 'Failed' -Detail $_.Exception.Message
                    }
                }
            } else {
                Write-Host "`n  Unmounting and discarding failed WIM changes..." -ForegroundColor Yellow
                try {
                    Dismount-WindowsImage -Path $resolvedMountDir -Discard -ErrorAction Stop | Out-Null
                    $remainingMounts = @(Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { ([string]$_.MountDir).TrimEnd('\') -ieq $resolvedMountDir.TrimEnd('\') })
                    if ($remainingMounts.Count -gt 0) { throw 'DISM still reports the image as mounted after discard' }
                    $wimMounted = $false
                    $script:wimReport.commit_status = 'Discarded'
                    Add-WimReportOperation -Name 'Discard failed transaction' -Status 'Succeeded' -Detail $null
                } catch {
                    $wimFailure = if ($wimFailure) { "$wimFailure; discard failed: $($_.Exception.Message)" } else { "Discard failed: $($_.Exception.Message)" }
                    $script:wimReport.commit_status = 'DiscardFailed'
                    Add-WimReportOperation -Name 'Discard failed transaction' -Status 'Failed' -Detail $_.Exception.Message
                }
            }
        }
        if ($wimMounted) { $script:wimReport.status = 'Failed'; $script:wimReport.commit_status = 'MountStillActive' }
        Write-WimReport
    }

    if (-not $wimSave) { exit 2 }

    Write-Host ""
    Write-Host "=== WIM DEBLOAT COMPLETE ===" -ForegroundColor Green
    Write-Host "  Removed: $removed AppX packages" -ForegroundColor White
    Write-Host "  Applied: $($script:wimReport.registry_values_applied) catalog registry values" -ForegroundColor White
    Write-Host "  Report: $wimReportFile" -ForegroundColor White
    Write-Host "  Image ready for deployment via DISM, MDT, or WDS" -ForegroundColor Cyan
    exit 0
}

# ============================================================================
# PHASE SELECTION
# ============================================================================
# Valid phases for -Only / -Skip
$script:validPhases = @('AppX','OEM','OneDrive','Office','Edge','Firewall','Privacy',
                        'Services','SystemTweaks','Power','Network','StartMenu','Updates')

if ($Only -and $Skip) {
    Write-Host "ERROR: -Only and -Skip cannot be used together" -ForegroundColor Red
    exit 2
}

function Test-SystemTweaksSelected {
    if ($Only) {
        return ($Only -contains 'SystemTweaks' -or
            @($Only | Where-Object { $_ -in @('Power','Network','StartMenu') }).Count -gt 0)
    }
    return (-not ($Skip -and $Skip -contains 'SystemTweaks'))
}

function Test-SystemTweaksCoreSelected {
    if (-not (Test-SystemTweaksSelected)) { return $false }
    if ($Only) { return ($Only -contains 'SystemTweaks') }
    return $true
}

function Test-SystemTweakEnabled {
    param([string]$SubPhase)
    if (-not (Test-SystemTweaksSelected)) { return $false }
    if ($Only) { return ($Only -contains 'SystemTweaks' -or $Only -contains $SubPhase) }
    if ($Skip) { return ($Skip -notcontains 'SystemTweaks' -and $Skip -notcontains $SubPhase) }
    return $true
}

function Test-PhaseEnabled {
    param([string]$Phase)
    if ($Phase -eq 'SystemTweaks') { return (Test-SystemTweaksSelected) }
    if ($Phase -eq 'Updates') {
        return ($UpdateApps -or ($Only -and $Only -contains 'Updates')) -and (-not ($Skip -and $Skip -contains 'Updates'))
    }
    if ($Only) { return ($Only -contains $Phase) }
    if ($Skip) { return ($Skip -notcontains $Phase) }
    return $true
}

function Test-AnyPhaseSelected {
    if ($Only) { return @($Only | Where-Object { $_ -in $script:validPhases }).Count -gt 0 }
    return $true
}

function Test-PreDebloatEnabled {
    foreach ($phase in @('AppX','OEM','OneDrive','Office','Services','Privacy')) {
        if (Test-PhaseEnabled $phase) { return $true }
    }
    return (Test-SystemTweaksCoreSelected)
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
$script:totalPhases = 13
$script:currentPhase = 0
function Update-Phase {
    param([string]$PhaseName)
    $script:currentPhase++
    $phaseMap = @{
        'System Tweaks' = 'SystemTweaks'
        'AppX Package Removal' = 'AppX'
        'OEM Cleanup' = 'OEM'
        'OneDrive Removal' = 'OneDrive'
        'Office Removal' = 'Office'
        'Service Cleanup' = 'Services'
        'Edge Configuration' = 'Edge'
        'Firewall Rules' = 'Firewall'
        'Privacy Cleanup' = 'Privacy'
        'App Updates' = 'Updates'
    }
    if ($phaseMap.ContainsKey($PhaseName)) { Write-ActionPlan -Phase $phaseMap[$PhaseName] }
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
    OperationsAttempted = 0
    OperationsSucceeded = 0
    OperationsFailed    = 0
    OperationsSkipped   = 0
    DiskBefore         = 0
    DiskAfter          = 0
}

$script:manifest = @{
    schema_version = 2
    timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    version   = 'v2.3.11'
    correlation_id = [guid]::NewGuid().ToString()
    dryrun    = $DryRun.IsPresent
    catalog   = [ordered]@{
        policy_catalog_version = [string]$script:policyCatalog.CatalogVersion
        policy_catalog_schema = [int]$script:policyCatalog.SchemaVersion
        policy_catalog_hash = $script:policyCatalogHash
    }
    configuration = [ordered]@{
        supplied = [bool]$ConfigPath
        config_hash = $script:configurationHash
    }
    observability = [ordered]@{
        schema_version = 1
        redaction_policy = 'Crash bundles redact usernames, computer names, profile roots, well-known data roots, and secret-like key/value pairs; operational manifests remain local audit records.'
        log_retention_per_type = 50
        summary_format = 'json'
    }
    scope = [ordered]@{
        user_policy = if ($AllUsers) { 'AllUsers' } else { 'CurrentUser' }
        machine = 'Machine'
        all_users = $AllUsers.IsPresent
    }
    selection = [ordered]@{
        only = if ($Only) { @($Only) } else { @() }
        skip = if ($Skip) { @($Skip) } else { @() }
    }
    action_plan = [System.Collections.ArrayList]@()
    runtime   = [ordered]@{
        os_build = $null
        edition = $null
        architecture = $null
        supported = $null
        support_matrix = $null
        override = $false
        override_reason = $null
    }
    safety    = [ordered]@{
        irreversible_changes_allowed = $AllowIrreversibleChanges.IsPresent
        approval_switch = '-AllowIrreversibleChanges'
    }
    changes   = @{
        appx_removed       = [System.Collections.ArrayList]@()
        services_disabled  = [System.Collections.ArrayList]@()
        services_deleted   = [System.Collections.ArrayList]@()
        tasks_disabled     = [System.Collections.ArrayList]@()
        registry_set       = [System.Collections.ArrayList]@()
        registry_deleted   = [System.Collections.ArrayList]@()
        folders_deleted    = [System.Collections.ArrayList]@()
        firewall_rules     = [System.Collections.ArrayList]@()
        package_operations = [System.Collections.ArrayList]@()
        operations         = [System.Collections.ArrayList]@()
    }
}

# ============================================================================
# LOGGING SETUP
# ============================================================================
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$runStamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$runShortId = $script:manifest.correlation_id.Substring(0, 8)
$logFile = "$LogDir\Debloat-$runStamp-$runShortId.log"
$manifestFile = "$LogDir\Debloat-Manifest-$runStamp-$runShortId.json"
$summaryFile = "$LogDir\Debloat-Summary-$runStamp-$runShortId.json"
$htmlReportFile = "$LogDir\Debloat-Report-$runStamp-$runShortId.html"
$script:manifest.artifacts = [ordered]@{
    log = $logFile
    manifest = $manifestFile
    summary = $summaryFile
    html_report = $htmlReportFile
}

function Invoke-DebloatLogRetention {
    param([Parameter(Mandatory)][string]$Directory, [int]$KeepPerType = 50)
    $patterns = @('Debloat-*.log', 'Debloat-Manifest-*.json', 'Debloat-Summary-*.json', 'Debloat-Report-*.html', 'Debloat-Restore-*.json', 'Debloat-WIM-Report-*.json')
    foreach ($pattern in $patterns) {
        $files = @(Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($files.Count -le $KeepPerType) { continue }
        foreach ($oldFile in @($files | Select-Object -Skip $KeepPerType)) {
            Remove-Item -LiteralPath $oldFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-DebloatLogRetention -Directory $LogDir -KeepPerType ([int]$script:manifest.observability.log_retention_per_type)

# Register EventLog source for SIEM/compliance (idempotent)
$script:eventLogSource = 'Debloat-Win11'
if (-not [System.Diagnostics.EventLog]::SourceExists($script:eventLogSource)) {
    try { New-EventLog -LogName 'Application' -Source $script:eventLogSource -EA Stop } catch {}
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = if ($DryRun) { "[DRY RUN] " } else { "" }
    $correlation = if ($script:manifest.correlation_id) { "[$($script:manifest.correlation_id)] " } else { '' }
    $logEntry = "[$timestamp] [$Level] $correlation$prefix$Message"
    Add-Content -Path $logFile -Value $logEntry -EA 0

    # Write key events to Windows Event Log for SIEM forwarding
    if ($Level -eq 'ERROR') {
        Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 9001 -EntryType Error -Message "$prefix$Message" -EA 0
    } elseif ($Level -eq 'SECTION') {
        Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 1001 -EntryType Information -Message "$prefix$Message" -EA 0
    }

    if ($Silent -or $OutputFormat -ne 'Text' -or -not [Environment]::UserInteractive) { if ($Level -eq 'ERROR') { $script:exitCode = 1 }; return }

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
function Register-OperationResult {
    param(
        [string]$Name,
        [string]$Action,
        [string]$Scope = 'Machine',
        [ValidateSet('Planned','Succeeded','Failed','Skipped')]
        [string]$Status,
        [string]$ErrorMessage
    )

    $entry = [ordered]@{
        name       = $Name
        action     = $Action
        scope      = $Scope
        status     = $Status
        timestamp  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    }
    if ($ErrorMessage) { $entry.error = $ErrorMessage }
    $script:manifest.changes.operations.Add($entry) | Out-Null
    if ($Status -ne 'Planned') { $script:counters.OperationsAttempted++ }
    switch ($Status) {
        'Succeeded' { $script:counters.OperationsSucceeded++ }
        'Failed'    { $script:counters.OperationsFailed++; $script:exitCode = 1 }
        'Skipped'   { $script:counters.OperationsSkipped++ }
    }
}

function ConvertTo-DebloatRedactedText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    $redacted = $Text
    $knownRoots = @(
        @{ Value = $env:USERPROFILE; Token = '<USERPROFILE>' }
        @{ Value = $env:ProgramData; Token = '<PROGRAMDATA>' }
        @{ Value = $env:TEMP; Token = '<TEMP>' }
        @{ Value = $env:TMP; Token = '<TEMP>' }
    )
    foreach ($root in $knownRoots) {
        if (-not [string]::IsNullOrWhiteSpace([string]$root.Value)) {
            $redacted = $redacted -replace [regex]::Escape([string]$root.Value), [string]$root.Token
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:USERNAME)) { $redacted = $redacted -replace [regex]::Escape([string]$env:USERNAME), '<USERNAME>' }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:COMPUTERNAME)) { $redacted = $redacted -replace [regex]::Escape([string]$env:COMPUTERNAME), '<COMPUTERNAME>' }
    $redacted = [regex]::Replace($redacted, '(?i)((?:password|passwd|token|secret|api[_-]?key)\s*[:=]\s*)("[^"]*"|''[^'']*''|[^,\s}\r\n]+)', '$1<REDACTED>')
    return $redacted
}

function Write-DebloatRedactedFile {
    param([Parameter(Mandatory)][string]$SourcePath, [Parameter(Mandatory)][string]$DestinationPath)
    try {
        $sourceText = [System.IO.File]::ReadAllText($SourcePath)
        $redactedText = ConvertTo-DebloatRedactedText -Text $sourceText
        [System.IO.File]::WriteAllText($DestinationPath, $redactedText, [System.Text.Encoding]::UTF8)
        return $true
    } catch {
        return $false
    }
}

function Register-OperationFailure {
    param([string]$Name, [string]$Action, [string]$Scope = 'Machine', [object]$ErrorRecord)
    $message = if ($ErrorRecord) { [string]$ErrorRecord.Exception.Message } else { 'Operation failed' }
    Register-OperationResult -Name $Name -Action $Action -Scope $Scope -Status 'Failed' -ErrorMessage $message
    Write-Log "  Operation failed [$Name]: $message" "ERROR"
}

function Invoke-TrackedOperation {
    param(
        [string]$Name,
        [string]$Action,
        [string]$Scope = 'Machine',
        [scriptblock]$Operation,
        [scriptblock]$Verification,
        [switch]$RunDuringDryRun
    )

    if ($DryRun -and -not $RunDuringDryRun) {
        Register-OperationResult -Name $Name -Action $Action -Scope $Scope -Status 'Planned'
        return $true
    }

    try {
        $ErrorActionPreference = 'Stop'
        $operationResult = & $Operation
        if ($operationResult -is [bool] -and -not $operationResult) { throw 'Operation returned a failure result' }
        if ($Verification) {
            $verified = & $Verification
            if ($verified -is [bool] -and -not $verified) { throw 'Post-operation verification failed' }
        }
        $status = if ($DryRun) { 'Planned' } else { 'Succeeded' }
        Register-OperationResult -Name $Name -Action $Action -Scope $Scope -Status $status
        return $true
    } catch {
        Register-OperationFailure -Name $Name -Action $Action -Scope $Scope -ErrorRecord $_
        return $false
    }
}

function Remove-TrackedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Scope = 'Mixed',
        [switch]$Recurse,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $operationName = if ($Name) { $Name } else { $Path }
    $removed = Invoke-TrackedOperation -Name $operationName -Action 'Delete file or folder' -Scope $Scope -Operation {
        Remove-Item -LiteralPath $Path -Recurse:$Recurse -Force -EA Stop
    } -Verification {
        -not (Test-Path -LiteralPath $Path)
    }
    if ($removed -and -not ($script:manifest.changes.folders_deleted -contains $Path)) {
        $script:manifest.changes.folders_deleted.Add($Path) | Out-Null
    }
    return $removed
}

function Test-IrreversibleOperationAllowed {
    param([string]$Name)

    if ($DryRun -or $AllowIrreversibleChanges) { return $true }

    Register-OperationResult -Name $Name -Action 'Blocked irreversible operation' -Scope 'Mixed' -Status 'Skipped'
    Write-Log "[$Name] SKIPPED: irreversible changes require -AllowIrreversibleChanges (use -DryRun to preview)" "WARNING"
    return $false
}

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

    if ($DryRun) {
        Register-OperationResult -Name "$Path\$Name" -Action 'Set registry value' -Scope $(if ([string]$Path -like 'HKCU:*') { 'CurrentUser' } else { 'Machine' }) -Status 'Planned'
        return
    }

    try {
        if (!(Test-Path $Path)) { New-Item -Path $Path -Force -EA Stop | Out-Null }
        Set-DebloatRegistryProperty -Path $Path -Name $Name -Value $Value -Type $Type -EA Stop
        $current = Get-ItemProperty -Path $Path -Name $Name -EA Stop
        if ($current.$Name -ne $Value) { throw "Registry verification returned '$($current.$Name)' instead of '$Value'" }
        Register-OperationResult -Name "$Path\$Name" -Action 'Set registry value' -Scope $(if ([string]$Path -like 'HKCU:*') { 'CurrentUser' } else { 'Machine' }) -Status 'Succeeded'
    } catch {
        Register-OperationFailure -Name "$Path\$Name" -Action 'Set registry value' -Scope $(if ([string]$Path -like 'HKCU:*') { 'CurrentUser' } else { 'Machine' }) -ErrorRecord $_
    }
}

# Cache all packages once at start of AppX phase for performance
$script:allAppxPackages = $null
$script:allProvisionedPackages = $null

function Add-AppxManifestEntry {
    param([string]$PackageName)

    if ([string]::IsNullOrWhiteSpace($PackageName)) { return $false }
    if ($script:manifest.changes.appx_removed -contains $PackageName) { return $false }

    $script:manifest.changes.appx_removed.Add($PackageName) | Out-Null
    $script:counters.AppxRemoved++
    return $true
}

function Remove-AppxDryRun {
    param(
        [string]$Pattern,
        [switch]$AllowOutsideAppX
    )

    if (-not $AllowOutsideAppX -and -not (Test-PhaseEnabled 'AppX')) {
        Register-OperationResult -Name "AppX removal: $Pattern" -Action 'Skipped because AppX phase is not selected' -Scope 'Mixed' -Status 'Skipped'
        Write-Log "[AppX] '$Pattern' skipped because the AppX phase is not selected" "INFO"
        return
    }

    if (-not (Test-IrreversibleOperationAllowed -Name "AppX removal: $Pattern")) { return }

    # Lazy-init: query once, filter many
    if ($null -eq $script:allAppxPackages) {
        $script:allAppxPackages = @(Get-AppxPackage -AllUsers 2>$null)
        $script:allProvisionedPackages = @(Get-AppxProvisionedPackage -Online 2>$null)
    }

    $pkgs = $script:allAppxPackages | Where-Object { $_.Name -like $Pattern }
    $provPkgs = $script:allProvisionedPackages | Where-Object { $_.DisplayName -like $Pattern -or $_.PackageName -like $Pattern }

    foreach ($pkg in $pkgs) {
        Add-AppxManifestEntry -PackageName $pkg.Name | Out-Null
        if (-not $DryRun) {
            try {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
                Register-OperationResult -Name $pkg.Name -Action 'Remove AppX package' -Scope 'AllUsers' -Status 'Succeeded'
            } catch {
                Register-OperationFailure -Name $pkg.Name -Action 'Remove AppX package' -Scope 'AllUsers' -ErrorRecord $_
            }
        } else {
            Register-OperationResult -Name $pkg.Name -Action 'Remove AppX package' -Scope 'AllUsers' -Status 'Planned'
        }
    }
    foreach ($pkg in $provPkgs) {
        $packageName = if (-not [string]::IsNullOrWhiteSpace([string]$pkg.DisplayName)) { [string]$pkg.DisplayName } else { [string]$pkg.PackageName }
        Add-AppxManifestEntry -PackageName $packageName | Out-Null
        if (-not $DryRun) {
            try {
                $pkg | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                Register-OperationResult -Name $packageName -Action 'Remove provisioned AppX package' -Scope 'Provisioned' -Status 'Succeeded'
            } catch {
                Register-OperationFailure -Name $packageName -Action 'Remove provisioned AppX package' -Scope 'Provisioned' -ErrorRecord $_
            }
        } else {
            Register-OperationResult -Name $packageName -Action 'Remove provisioned AppX package' -Scope 'Provisioned' -Status 'Planned'
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
            try {
                Stop-Service -Name $ServiceName -Force -EA Stop
                Set-Service -Name $ServiceName -StartupType Disabled -EA Stop
                $updated = Get-Service -Name $ServiceName -EA Stop
                if ($updated.StartType.ToString() -ne 'Disabled') { throw "Service startup type remained '$($updated.StartType)'" }
                Register-OperationResult -Name $ServiceName -Action 'Disable service' -Scope 'Machine' -Status 'Succeeded'
            } catch {
                Register-OperationFailure -Name $ServiceName -Action 'Disable service' -Scope 'Machine' -ErrorRecord $_
            }
        } else {
            Register-OperationResult -Name $ServiceName -Action 'Disable service' -Scope 'Machine' -Status 'Planned'
        }
    }
}

function Disable-TaskDryRun {
    param([string]$TaskName)
    $tasks = Get-ScheduledTask -TaskName $TaskName -EA 0
    foreach ($task in $tasks) {
        $script:manifest.changes.tasks_disabled.Add($task.TaskName) | Out-Null
        $script:counters.TasksDisabled++
        if ($DryRun) {
            Register-OperationResult -Name $task.TaskName -Action 'Disable scheduled task' -Scope 'Machine' -Status 'Planned'
        } else {
            try {
                $task | Stop-ScheduledTask -EA Stop
                $task | Disable-ScheduledTask -EA Stop
                $updated = Get-ScheduledTask -TaskName $task.TaskName -EA Stop
                if ($updated.State -eq 'Ready' -and $updated.Settings.Enabled) { throw 'Scheduled task remained enabled' }
                Register-OperationResult -Name $task.TaskName -Action 'Disable scheduled task' -Scope 'Machine' -Status 'Succeeded'
            } catch {
                Register-OperationFailure -Name $task.TaskName -Action 'Disable scheduled task' -Scope 'Machine' -ErrorRecord $_
            }
        }
    }
}

# ============================================================================
# CONCURRENT EXECUTION GUARD
# ============================================================================
$script:lockFile = "$LogDir\Debloat-Win11.lock"
if (Test-Path $script:lockFile) {
    $lockContent = Get-Content $script:lockFile -Raw -EA 0
    $staleLock = $false
    if ($lockContent -match 'PID=(\d+)') {
        $lockPid = [int]$Matches[1]
        $lockProc = Get-Process -Id $lockPid -EA 0
        if (-not $lockProc) { $staleLock = $true }
    } else {
        $staleLock = $true
    }
    if ($staleLock) {
        Write-Log "Removing stale lock file from a previous crashed run" "WARNING"
        Remove-Item $script:lockFile -Force -EA 0
    } else {
        Write-Log "ERROR: Another instance is already running (lock: $lockContent). Aborting." "ERROR"
        exit 2
    }
}
try {
    "PID=$PID Started=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')" | Set-Content $script:lockFile -Force -EA Stop
} catch {
    Write-Log "ERROR: Could not create lock file: $_" "ERROR"
    exit 2
}
$lockFilePath = $script:lockFile
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Remove-Item $lockFilePath -Force -EA 0
} | Out-Null

# ============================================================================
# STARTUP BANNER
# ============================================================================
Write-Log "=== WINDOWS DEBLOAT v2.3.11 STARTING ===" "INFO"
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

$osBuildNumber = 0
if (-not [int]::TryParse([string]$osBuild, [ref]$osBuildNumber)) {
    Write-Log "ERROR: Windows build number could not be determined" "ERROR"
    exit 2
}
$architecture = if ($env:PROCESSOR_ARCHITEW6432) { [string]$env:PROCESSOR_ARCHITEW6432 } else { [string]$env:PROCESSOR_ARCHITECTURE }
$architecture = switch -Regex ($architecture.ToLowerInvariant()) {
    'amd64|x64' { 'x64'; break }
    'arm64' { 'arm64'; break }
    default { 'x86' }
}
$script:manifest.runtime.os_build = $osBuildNumber
$script:manifest.runtime.edition = [string]$editionId
$script:manifest.runtime.architecture = $architecture
$runtimeDefinition = @($script:policyCatalog.RuntimeMatrix | Where-Object { $_.Name -eq 'WindowsClient' }) | Select-Object -First 1
$runtimeSupportReasons = [System.Collections.ArrayList]@()
if (-not $runtimeDefinition) {
    $runtimeSupportReasons.Add('catalog has no WindowsClient runtime definition') | Out-Null
} else {
    $script:manifest.runtime.support_matrix = [string]$runtimeDefinition.Name
    if ($osBuildNumber -lt [int]$runtimeDefinition.MinimumBuild) { $runtimeSupportReasons.Add("build $osBuildNumber is below supported minimum $($runtimeDefinition.MinimumBuild)") | Out-Null }
    if (@($runtimeDefinition.SupportedEditions) -notcontains [string]$editionId) { $runtimeSupportReasons.Add("edition $editionId is not in the supported runtime matrix") | Out-Null }
    if (@($runtimeDefinition.SupportedArchitectures) -notcontains $architecture) { $runtimeSupportReasons.Add("architecture $architecture is not in the supported runtime matrix") | Out-Null }
}
$runtimeSupported = $runtimeSupportReasons.Count -eq 0
$script:manifest.runtime.supported = $runtimeSupported
$supportErrors = [System.Collections.ArrayList]@()
foreach ($action in $script:actionCatalog) {
    $selected = Test-PhaseEnabled -Phase $action.Phase
    $editionSupported = (@($action.SupportedEditions) -contains 'AnyClient' -and $runtimeDefinition -and @($runtimeDefinition.SupportedEditions) -contains [string]$editionId) -or @($action.SupportedEditions) -contains $editionId
    $architectureSupported = @($action.SupportedArchitectures) -contains $architecture
    $effectiveBuildMin = [int]$action.SupportedBuildMin
    if ($runtimeDefinition -and [int]$runtimeDefinition.MinimumBuild -gt $effectiveBuildMin) { $effectiveBuildMin = [int]$runtimeDefinition.MinimumBuild }
    $buildSupported = $osBuildNumber -ge $effectiveBuildMin
    $supported = $runtimeSupported -and $buildSupported -and $editionSupported -and $architectureSupported
    $reason = if (-not $runtimeSupported) { $runtimeSupportReasons -join '; ' } elseif (-not $buildSupported) { "build $osBuildNumber is below $effectiveBuildMin" } elseif (-not $editionSupported) { "edition $editionId is not supported" } elseif (-not $architectureSupported) { "architecture $architecture is not supported" } else { $null }
    $script:manifest.action_plan.Add([ordered]@{
        name = $action.Name
        phase = $action.Phase
        selected = $selected
        supported = $supported
        risk = $action.Risk
        scope = $action.Scope
        prerequisites = @($action.Prerequisites)
        dependencies = @($action.Dependencies)
        rollback = $action.Rollback
        requires_approval = [bool]$action.RequiresApproval
        supported_build_min = $effectiveBuildMin
        supported_editions = @($action.SupportedEditions)
        supported_architectures = @($action.SupportedArchitectures)
        reason = $reason
    }) | Out-Null
    if ($selected -and -not $supported) { $supportErrors.Add("$($action.Name): $reason") | Out-Null }
}
$script:manifest.runtime.override = $false
if ($supportErrors.Count -gt 0) {
    $script:manifest.runtime.supported = $false
    $script:manifest.runtime.override_reason = $supportErrors -join '; '
    if (-not $AllowUnsupportedPlatform) {
        Write-Log 'ERROR: Selected actions are outside the supported build/edition/architecture matrix:' 'ERROR'
        $supportErrors | ForEach-Object { Write-Log "  $_" 'ERROR' }
        Write-Log 'Use -AllowUnsupportedPlatform only for an explicit, noncompliant override.' 'ERROR'
        exit 2
    }
    $script:manifest.runtime.override = $true
    Write-Log 'WARNING: Unsupported platform override accepted; this run will remain noncompliant.' 'WARNING'
    $supportErrors | ForEach-Object { Write-Log "  OVERRIDE: $_" 'WARNING' }
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
if (-not (Test-AnyPhaseSelected)) {
    Register-OperationResult -Name 'System Restore Point' -Action 'Create restore point' -Scope 'Machine' -Status 'Skipped' -ErrorMessage 'No execution phase selected'
    Write-Log "  Restore point skipped because no execution phase is selected" "INFO"
} elseif ($DryRun) {
    Register-OperationResult -Name 'System Restore Point' -Action 'Create restore point' -Scope 'Machine' -Status 'Planned'
    Write-Log "  [DRY RUN] Would create restore point" "INFO"
} else {
    try {
        Enable-ComputerRestore -Drive "C:\" -EA 0
        Checkpoint-Computer -Description "Pre-Debloat $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS" -EA Stop
        Register-OperationResult -Name 'System Restore Point' -Action 'Create restore point' -Scope 'Machine' -Status 'Succeeded'
        Write-Log "  Restore point created" "SUCCESS"
    } catch {
        Register-OperationResult -Name 'System Restore Point' -Action 'Create restore point' -Scope 'Machine' -Status 'Skipped' -ErrorMessage $_.Exception.Message
        Write-Log "  Could not create restore point (may already exist today)" "WARNING"
    }
}

# ============================================================================
# PRE-DEBLOAT: DISABLE INTERFERING SERVICES
# ============================================================================
if (Test-PreDebloatEnabled) {
    $script:interferingServicesDisabled = $true
    Write-Log "[Pre-Debloat] Disabling interfering services..." "SECTION"

    if ($DryRun) {
        Write-Log "  [DRY RUN] Would stop Windows Update, Windows Search, SysMain" "INFO"
    } else {
        # Windows Update
        Write-Log "  Stopping Windows Update..." "INFO"
        Invoke-TrackedOperation -Name 'wuauserv' -Action 'Disable pre-debloat service' -Scope 'Machine' -Operation {
            Stop-Service -Name 'wuauserv' -Force -EA Stop
            Set-Service -Name 'wuauserv' -StartupType Disabled -EA Stop
            Get-Process -Name 'WaaSMedicAgent', 'UsoClient', 'wuauclt', 'WUDFHost' -EA 0 | Stop-Process -Force -EA Stop
        } -Verification {
            (Get-Service -Name 'wuauserv' -EA Stop).StartType.ToString() -eq 'Disabled'
        } | Out-Null

        # Windows Search
        Write-Log "  Stopping Windows Search..." "INFO"
        Invoke-TrackedOperation -Name 'WSearch' -Action 'Disable pre-debloat service' -Scope 'Machine' -Operation {
            Stop-Service -Name 'WSearch' -Force -EA Stop
            Set-Service -Name 'WSearch' -StartupType Disabled -EA Stop
            Get-Process -Name 'SearchIndexer', 'SearchHost', 'SearchApp' -EA 0 | Stop-Process -Force -EA Stop
        } -Verification {
            (Get-Service -Name 'WSearch' -EA Stop).StartType.ToString() -eq 'Disabled'
        } | Out-Null

        # SysMain (Superfetch)
        Write-Log "  Stopping SysMain..." "INFO"
        Invoke-TrackedOperation -Name 'SysMain' -Action 'Disable pre-debloat service' -Scope 'Machine' -Operation {
            Stop-Service -Name 'SysMain' -Force -EA Stop
            Set-Service -Name 'SysMain' -StartupType Disabled -EA Stop
        } -Verification {
            (Get-Service -Name 'SysMain' -EA Stop).StartType.ToString() -eq 'Disabled'
        } | Out-Null

        Write-Log "  Services disabled" "SUCCESS"
    }
} else {
    $script:interferingServicesDisabled = $false
    Write-Log "[Pre-Debloat] Interfering services SKIPPED (not required by selected plan)" "INFO"
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
Update-Phase "App Updates"
$wingetPath = Get-Command 'winget' -EA 0
if ($wingetPath -and (Test-PhaseEnabled 'Updates')) {
    Write-Log "[Updates] Updating only catalog-selected packages via winget..." "SECTION"
    $packageUpdates = if ($script:configOverrides.ContainsKey('PackageUpdates')) { @($script:configOverrides.PackageUpdates) } else { @() }
    if ($packageUpdates.Count -eq 0) {
        Register-OperationResult -Name 'WinGet package updates' -Action 'Upgrade configured exact package IDs' -Scope 'Machine' -Status 'Skipped' -ErrorMessage 'No PackageUpdates entries were selected'
        Write-Log "  App updates skipped: add exact PackageUpdates entries to ConfigPath" "WARNING"
    }
    foreach ($packageSpec in $packageUpdates) {
        $packageId = [string]$packageSpec.Id
        $packageSource = if ($packageSpec.ContainsKey('Source')) { [string]$packageSpec.Source } else { $null }
        $targetVersion = if ($packageSpec.ContainsKey('Version')) { [string]$packageSpec.Version } else { $null }
        $beforePackage = Get-WingetPackageSnapshot -PackageId $packageId -Source $packageSource
        $packageRecord = [ordered]@{
            id = $packageId
            source = if ($packageSource) { $packageSource } else { 'default' }
            requested_version = if ($targetVersion) { $targetVersion } else { 'latest' }
            exact_id = $true
            before_version = $beforePackage.Version
            after_version = 'Unknown'
            return_code = $null
            status = 'Planned'
            reason = $null
        }
        if (-not $beforePackage.Found) {
            $packageRecord.status = 'Skipped'
            $packageRecord.reason = 'Exact package ID is not installed or was not returned by winget list'
            $script:manifest.changes.package_operations.Add($packageRecord) | Out-Null
            Register-OperationResult -Name "WinGet:$packageId" -Action 'Upgrade exact package ID' -Scope 'Machine' -Status 'Skipped' -ErrorMessage $packageRecord.reason
            Write-Log "  Skipped ${packageId}: not installed or not discoverable" "WARNING"
            continue
        }
        $upgradeArgs = @('upgrade', '--id', $packageId, '--exact', '--silent', '--disable-interactivity', '--accept-source-agreements', '--accept-package-agreements')
        if ($packageSource) { $upgradeArgs += @('--source', $packageSource) }
        if ($targetVersion) { $upgradeArgs += @('--version', $targetVersion) }
        if ($DryRun) {
            $packageRecord.status = 'Planned'
            $script:manifest.changes.package_operations.Add($packageRecord) | Out-Null
            Register-OperationResult -Name "WinGet:$packageId" -Action 'Upgrade exact package ID' -Scope 'Machine' -Status 'Planned'
            Write-Log "  [DRY RUN] Would run: winget $($upgradeArgs -join ' ')" "INFO"
            continue
        }
        $script:lastWingetExitCode = $null
        $script:lastWingetAfter = $null
        $wingetUpdated = Invoke-TrackedOperation -Name "WinGet:$packageId" -Action 'Upgrade exact package ID' -Scope 'Machine' -Operation {
            $script:lastWingetResult = @(& winget @upgradeArgs 2>&1)
            $script:lastWingetExitCode = $LASTEXITCODE
            if ($script:lastWingetExitCode -ne 0) { throw "winget exited with code $script:lastWingetExitCode" }
        } -Verification {
            $script:lastWingetAfter = Get-WingetPackageSnapshot -PackageId $packageId -Source $packageSource
            $script:lastWingetAfter.Found
        }
        $packageRecord.return_code = if ($script:lastWingetExitCode -ne $null) { $script:lastWingetExitCode } else { 1 }
        $packageRecord.after_version = if ($script:lastWingetAfter) { $script:lastWingetAfter.Version } else { 'Unknown' }
        $packageRecord.status = if ($wingetUpdated) { 'Succeeded' } else { 'Failed' }
        if (-not $wingetUpdated) { $packageRecord.reason = 'WinGet upgrade failed; see operation error' }
        $script:manifest.changes.package_operations.Add($packageRecord) | Out-Null
    }
} else {
    if (-not $wingetPath) {
        Write-Log "[Updates] winget not found -- skipping app updates" "INFO"
    } else {
        Write-Log "[Updates] App updates skipped (use -UpdateApps or -Only Updates to opt in)" "INFO"
    }
}

# Complete progress bar
if (-not $Silent -and [Environment]::UserInteractive) {
    Write-Progress -Activity "Debloat-Win11" -Completed
}

# ============================================================================
# POST-DEBLOAT: RE-ENABLE ESSENTIAL SERVICES
# ============================================================================
if ($script:interferingServicesDisabled) {
    Write-Log "[Post-Debloat] Re-enabling essential services..." "SECTION"

    if (-not $DryRun) {
        # Windows Update
        Write-Log "  Re-enabling Windows Update..." "INFO"
        Invoke-TrackedOperation -Name 'wuauserv' -Action 'Re-enable post-debloat service' -Scope 'Machine' -Operation {
            Set-Service -Name 'wuauserv' -StartupType Manual -EA Stop
            Start-Service -Name 'wuauserv' -EA Stop
        } -Verification {
            (Get-Service -Name 'wuauserv' -EA Stop).StartType.ToString() -eq 'Manual'
        } | Out-Null

        # Windows Search
        Write-Log "  Re-enabling Windows Search..." "INFO"
        Invoke-TrackedOperation -Name 'WSearch' -Action 'Re-enable post-debloat service' -Scope 'Machine' -Operation {
            Set-Service -Name 'WSearch' -StartupType Automatic -EA Stop
            Start-Service -Name 'WSearch' -EA Stop
        } -Verification {
            (Get-Service -Name 'WSearch' -EA Stop).StartType.ToString() -eq 'Automatic'
        } | Out-Null
    }

    Write-Log "  Services re-enabled" "SUCCESS"
} else {
    Write-Log "[Post-Debloat] Essential service restart SKIPPED (no pre-debloat service changes)" "INFO"
}

# ============================================================================
# REGISTER POST-UPDATE MAINTENANCE TASK
# ============================================================================
if (Test-SystemTweaksCoreSelected) {
Write-Log "[Maintenance] Registering post-update scheduled task..." "SECTION"
$maintainScript = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Debloat-Win11-Maintain.ps1'
if (Test-Path $maintainScript) {
    $taskName = 'Debloat-Win11-PostUpdate'
    $existingTask = Get-ScheduledTask -TaskName $taskName -EA 0
    if (-not $existingTask) {
        $taskRegistered = Invoke-TrackedOperation -Name $taskName -Action 'Register post-update maintenance task' -Scope 'Machine' -Operation {
            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$maintainScript`""
            # Trigger on WU completion (Event ID 19 = installation complete) + daily fallback
            $wuTrigger = New-ScheduledTaskTrigger -Daily -At '03:00'
            $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $wuTrigger -Principal $principal -Settings $settings -Description 'Re-applies privacy/telemetry tweaks after Windows Update resets them' -EA Stop | Out-Null
            # Add event-based trigger for WU completion (supplements the daily trigger)
            $taskXml = (Get-ScheduledTask -TaskName $taskName -EA Stop).Xml
            if ($taskXml) {
                $wuEventTrigger = @"
  <EventTrigger>
    <Enabled>true</Enabled>
    <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-WindowsUpdateClient/Operational"&gt;&lt;Select Path="Microsoft-Windows-WindowsUpdateClient/Operational"&gt;*[System[EventID=19]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
  </EventTrigger>
"@
                $taskXml = $taskXml -replace '(</Triggers>)', "$wuEventTrigger`$1"
                Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force -EA Stop | Out-Null
            }
        } -Verification {
            $registeredTask = Get-ScheduledTask -TaskName $taskName -EA Stop
            $null -ne $registeredTask
        }
        if ($taskRegistered -and -not $DryRun) {
            Write-Log "  Scheduled task '$taskName' registered (WU-completion + daily 3AM)" "SUCCESS"
        }
    } else {
        Register-OperationResult -Name $taskName -Action 'Register post-update maintenance task' -Scope 'Machine' -Status 'Skipped' -ErrorMessage 'Task already exists'
        Write-Log "  Scheduled task '$taskName' already exists" "INFO"
    }
    if ($DryRun -and -not $existingTask) {
        Write-Log "  [DRY RUN] Would register post-update maintenance task" "INFO"
    }
} else {
    Write-Log "  Debloat-Win11-Maintain.ps1 not found alongside script, skipping task registration" "WARNING"
}
} else {
    Write-Log "[Maintenance] Scheduled task SKIPPED (SystemTweaks core not selected)" "INFO"
}

# ============================================================================
# RESTART EXPLORER (Apply UI changes immediately)
# ============================================================================
if ($script:systemTweaksCoreSelected -or (Test-SystemTweakEnabled 'StartMenu')) {
    Write-Log "[Finalizing] Restarting Explorer..." "SECTION"
    $explorerRestarted = Invoke-TrackedOperation -Name 'Explorer' -Action 'Restart Explorer shell' -Scope 'CurrentUser' -Operation {
        Get-Process -Name explorer -EA 0 | Stop-Process -Force -EA Stop
        Start-Sleep -Seconds 2
        Start-Process explorer.exe -EA Stop
    } -Verification {
        $null -ne (Get-Process -Name explorer -EA Stop)
    }
    if ($explorerRestarted -and -not $DryRun) {
        Write-Log "  Explorer restart processed" "SUCCESS"
    } elseif ($DryRun) {
        Write-Log "  [DRY RUN] Would restart Explorer" "INFO"
    }
} else {
    Write-Log "[Finalizing] Explorer restart SKIPPED (UI phases not selected)" "INFO"
}

# ============================================================================
# WRITE UNDO MANIFEST
# ============================================================================
$unsupportedRollback = [System.Collections.ArrayList]@()
if (@($script:manifest.changes.appx_removed).Count -gt 0) { $unsupportedRollback.Add('AppX packages require reinstall or Store recovery') | Out-Null }
if (@($script:manifest.changes.folders_deleted).Count -gt 0) { $unsupportedRollback.Add('Deleted files and folders are not restorable from the manifest') | Out-Null }
if (@($script:manifest.changes.registry_deleted).Count -gt 0) { $unsupportedRollback.Add('Deleted registry keys require a saved export or manual recovery') | Out-Null }
if (@($script:manifest.changes.services_deleted).Count -gt 0) { $unsupportedRollback.Add('Deleted services require product-specific reinstallation') | Out-Null }
if (@($script:manifest.changes.firewall_rules).Count -gt 0) { $unsupportedRollback.Add('Replaced firewall rules are snapshotted for audit but not yet auto-restored') | Out-Null }
$script:manifest.rollback = [ordered]@{
    schema_version = 1
    generated_revert_script = $true
    unsupported = @($unsupportedRollback)
    status = if ($unsupportedRollback.Count -gt 0) { 'Partial' } else { 'Complete' }
}
$script:manifest.status = if ($DryRun) { 'Planned' } elseif ($script:exitCode -eq 0) { 'Complete' } else { 'Incomplete' }

# Stamp completion only after all selected operations have reported. The stamp
# itself is tracked so a failed compliance marker cannot look like a success.
$stampStatus = if ($DryRun) { 'Planned' } elseif ($script:exitCode -eq 0) { 'Complete' } else { 'Incomplete' }
if ($DryRun) {
    Invoke-TrackedOperation -Name 'Completion registry stamp' -Action 'Record run status and manifest path' -Scope 'Machine' -Operation { } | Out-Null
} else {
    $stampResult = Invoke-TrackedOperation -Name 'Completion registry stamp' -Action 'Record run status and manifest path' -Scope 'Machine' -Operation {
        $regStampPath = "HKLM:\SOFTWARE\Debloat-Win11"
        if (!(Test-Path $regStampPath)) { New-Item -Path $regStampPath -Force -EA Stop | Out-Null }
        Set-DebloatRegistryProperty -Path $regStampPath -Name "Version" -Value "v2.3.11" -Type String -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "Status" -Value $stampStatus -Type String -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "ManifestPath" -Value $manifestFile -Type String -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "ManifestSchemaVersion" -Value ([int]$script:manifest.schema_version) -Type DWord -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "CatalogHash" -Value $script:policyCatalogHash -Type String -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "ConfigHash" -Value $script:configurationHash -Type String -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "Scope" -Value ([string]$script:manifest.scope.user_policy) -Type String -EA Stop
        Set-DebloatRegistryProperty -Path $regStampPath -Name "LastRun" -Value (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') -Type String -EA Stop
    } -Verification {
        $stamp = Get-ItemProperty -Path "HKLM:\SOFTWARE\Debloat-Win11" -EA Stop
        $stamp.Status -eq $stampStatus
    }
    if (-not $stampResult) { $script:manifest.status = 'Incomplete' }
}
$script:manifest.operation_summary = [ordered]@{
    attempted = $script:counters.OperationsAttempted
    succeeded = $script:counters.OperationsSucceeded
    failed    = $script:counters.OperationsFailed
    skipped   = $script:counters.OperationsSkipped
}
try {
    $manifestJson = $script:manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($manifestFile, $manifestJson, [System.Text.Encoding]::UTF8)
    Write-Log "Undo manifest: $manifestFile" "INFO"
} catch {
    Write-Log "Could not write undo manifest" "WARNING"
}

# ============================================================================
# GENERATE STANDALONE REVERT SCRIPT
# ============================================================================
$revertFile = "$LogDir\Debloat-Revert-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').ps1"
$script:manifest.artifacts.revert = $revertFile
try {
    $revertLines = [System.Collections.ArrayList]@()
    $revertLines.Add('#Requires -RunAsAdministrator') | Out-Null
    $revertLines.Add("# Auto-generated revert script from Debloat-Win11 v2.3.11") | Out-Null
    $revertLines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $revertLines.Add('$ErrorActionPreference = "SilentlyContinue"') | Out-Null
    $revertLines.Add('$revertExitCode = 0') | Out-Null
    if ($unsupportedRollback.Count -gt 0) {
        $revertLines.Add('Write-Warning "This manifest contains changes that cannot be automatically restored:"') | Out-Null
        foreach ($unsupportedReason in $unsupportedRollback) {
            $revertLines.Add(('Write-Warning "' + $unsupportedReason + '"')) | Out-Null
        }
        $revertLines.Add('$revertExitCode = 2') | Out-Null
    }
    $revertLines.Add('') | Out-Null

    $regEntries = @($script:manifest.changes.registry_set)
    [array]::Reverse($regEntries)
    foreach ($entry in $regEntries) {
        $escapedPath = $entry.path -replace "'","''"
        $escapedName = $entry.name -replace "'","''"
        if ($null -eq $entry.old_value) {
            $revertLines.Add("Remove-ItemProperty -Path '$escapedPath' -Name '$escapedName' -Force -EA 0") | Out-Null
        } else {
            $type = if ($entry.type) { $entry.type } else { 'DWord' }
            $escapedValue = if ($type -eq 'String') { "'$($entry.old_value -replace "'","''")'" } else { $entry.old_value }
            $revertLines.Add("if (!(Test-Path '$escapedPath')) { New-Item -Path '$escapedPath' -Force | Out-Null }") | Out-Null
            $revertLines.Add("New-ItemProperty -Path '$escapedPath' -Name '$escapedName' -Value $escapedValue -PropertyType $type -Force -EA 0 | Out-Null") | Out-Null
        }
    }
    $revertLines.Add('') | Out-Null

    foreach ($svcEntry in $script:manifest.changes.services_disabled) {
        $sName = if ($svcEntry -is [string]) { $svcEntry } else { $svcEntry.name }
        $sType = if ($svcEntry -is [string]) { 'Manual' } else { $svcEntry.original_startup_type }
        $escapedSvc = $sName -replace "'","''"
        $revertLines.Add("Set-Service -Name '$escapedSvc' -StartupType $sType -EA 0") | Out-Null
        $revertLines.Add("Start-Service -Name '$escapedSvc' -EA 0") | Out-Null
    }
    $revertLines.Add('') | Out-Null

    foreach ($taskName in $script:manifest.changes.tasks_disabled) {
        $escapedTask = $taskName -replace "'","''"
        $revertLines.Add("Get-ScheduledTask -TaskName '$escapedTask' -EA 0 | Enable-ScheduledTask -EA 0") | Out-Null
    }
    $revertLines.Add('') | Out-Null
    $revertLines.Add('if ($revertExitCode -eq 0) { Write-Host "Revert complete. Restart recommended." -ForegroundColor Green } else { Write-Warning "Revert completed with unsupported changes; manual recovery is required."; exit $revertExitCode }') | Out-Null

    $revertContent = $revertLines -join "`r`n"
    [System.IO.File]::WriteAllText($revertFile, $revertContent, [System.Text.Encoding]::UTF8)
    Write-Log "Revert script: $revertFile" "INFO"
} catch {
    Write-Log "Could not generate revert script" "WARNING"
}

# ============================================================================
# HTML REPORT (self-contained single file)
# ============================================================================
try {
    $dryLabel = if ($DryRun) { " (DRY RUN)" } else { "" }
    function ConvertTo-HtmlCell {
        param($Value)
        if ($null -eq $Value) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }
    $regRows = ($script:manifest.changes.registry_set | ForEach-Object {
        $path = ConvertTo-HtmlCell $_.path
        $name = ConvertTo-HtmlCell $_.name
        $oldValue = ConvertTo-HtmlCell $_.old_value
        $newValue = ConvertTo-HtmlCell $_.new_value
        "<tr><td>$path</td><td>$name</td><td>$oldValue</td><td>$newValue</td></tr>"
    }) -join "`n"
    $svcRows = ($script:manifest.changes.services_disabled | ForEach-Object {
        $sName = if ($_ -is [string]) { $_ } else { $_.name }
        $sOrig = if ($_ -is [string]) { 'Unknown' } else { $_.original_startup_type }
        $serviceName = ConvertTo-HtmlCell $sName
        $serviceAction = ConvertTo-HtmlCell "Disabled (was $sOrig)"
        "<tr><td>$serviceName</td><td>$serviceAction</td></tr>"
    }) -join "`n"
    $appRows = ($script:manifest.changes.appx_removed | ForEach-Object {
        $appName = ConvertTo-HtmlCell $_
        "<tr><td>$appName</td></tr>"
    }) -join "`n"
    $taskRows = ($script:manifest.changes.tasks_disabled | ForEach-Object {
        $taskName = ConvertTo-HtmlCell $_
        "<tr><td>$taskName</td><td>Disabled</td></tr>"
    }) -join "`n"
    $operationRows = ($script:manifest.changes.operations | ForEach-Object {
        $operationName = ConvertTo-HtmlCell $_.name
        $operationAction = ConvertTo-HtmlCell $_.action
        $operationScope = ConvertTo-HtmlCell $_.scope
        $operationStatus = ConvertTo-HtmlCell $_.status
        $operationError = ConvertTo-HtmlCell $_.error
        "<tr><td>$operationName</td><td>$operationAction</td><td>$operationScope</td><td>$operationStatus</td><td>$operationError</td></tr>"
    }) -join "`n"
    $packageRows = ($script:manifest.changes.package_operations | ForEach-Object {
        $packageId = ConvertTo-HtmlCell $_.id
        $packageSource = ConvertTo-HtmlCell $_.source
        $requestedVersion = ConvertTo-HtmlCell $_.requested_version
        $beforeVersion = ConvertTo-HtmlCell $_.before_version
        $afterVersion = ConvertTo-HtmlCell $_.after_version
        $packageStatus = ConvertTo-HtmlCell $_.status
        $returnCode = ConvertTo-HtmlCell $_.return_code
        $packageReason = ConvertTo-HtmlCell $_.reason
        "<tr><td>$packageId</td><td>$packageSource</td><td>$requestedVersion</td><td>$beforeVersion</td><td>$afterVersion</td><td>$packageStatus</td><td>$returnCode</td><td>$packageReason</td></tr>"
    }) -join "`n"
    $rollbackRows = ($unsupportedRollback | ForEach-Object {
        "<tr><td>$(ConvertTo-HtmlCell $_)</td></tr>"
    }) -join "`n"
    $hostCell = ConvertTo-HtmlCell $env:COMPUTERNAME
    $osCell = ConvertTo-HtmlCell $osName
    $buildCell = ConvertTo-HtmlCell $osBuild
    $correlationCell = ConvertTo-HtmlCell $script:manifest.correlation_id

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
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Host: $hostCell | OS: $osCell (Build $buildCell) | Correlation: $correlationCell</p>
<div class="stat"><b>Run Status:</b> $(ConvertTo-HtmlCell $script:manifest.status) | <b>Operations Attempted:</b> $($script:counters.OperationsAttempted) | <b>Succeeded:</b> $($script:counters.OperationsSucceeded) | <b>Failed:</b> $($script:counters.OperationsFailed) | <b>Skipped:</b> $($script:counters.OperationsSkipped)</div>
<div class="stat"><b>AppX Removed:</b> $($script:counters.AppxRemoved) | <b>Services Disabled:</b> $($script:counters.ServicesDisabled) | <b>Tasks Disabled:</b> $($script:counters.TasksDisabled) | <b>Registry Tweaks:</b> $($script:counters.RegistryTweaks)</div>

<h2>Operation Results ($($script:manifest.changes.operations.Count))</h2>
<table><tr><th>Operation</th><th>Action</th><th>Scope</th><th>Status</th><th>Error</th></tr>
$operationRows
</table>

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

<h2>Package Operations ($($script:manifest.changes.package_operations.Count))</h2>
<table><tr><th>Id</th><th>Source</th><th>Requested</th><th>Before</th><th>After</th><th>Status</th><th>Return Code</th><th>Reason</th></tr>
$packageRows
</table>

<h2>Unsupported Rollback Items ($($unsupportedRollback.Count))</h2>
<table><tr><th>Limitation</th></tr>
$rollbackRows
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

if ($OutputFormat -eq 'Text') {
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
    Write-Host ("  Operations Attempted:       {0}" -f $script:counters.OperationsAttempted) -ForegroundColor White
    Write-Host ("  Operations Succeeded:       {0}" -f $script:counters.OperationsSucceeded) -ForegroundColor White
    Write-Host ("  Operations Failed:          {0}" -f $script:counters.OperationsFailed) -ForegroundColor $(if ($script:counters.OperationsFailed -gt 0) { 'Red' } else { 'White' })
    Write-Host ("  Operations Skipped:         {0}" -f $script:counters.OperationsSkipped) -ForegroundColor White
    Write-Host ("  Run Status:                 {0}" -f $script:manifest.status) -ForegroundColor $(if ($script:manifest.status -eq 'Complete' -or $script:manifest.status -eq 'Planned') { 'Green' } else { 'Red' })
    Write-Host ("  Disk Space Recovered:      {0}" -f $diskRecovered) -ForegroundColor White
    Write-Host ("  Runtime:                   {0}" -f $runtimeStr) -ForegroundColor White
    Write-Host ("  Log File:                  {0}" -f $logFile) -ForegroundColor White
    Write-Host ("  Undo Manifest:             {0}" -f $manifestFile) -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Cyan
}

# Log the summary too
Write-Log "=== DEBLOAT COMPLETE ===" "INFO"
Write-Log "AppX: $($script:counters.AppxRemoved) | Services: $($script:counters.ServicesDisabled) | Tasks: $($script:counters.TasksDisabled) | Registry: $($script:counters.RegistryTweaks)" "INFO"
Write-Log "Operations: attempted=$($script:counters.OperationsAttempted) succeeded=$($script:counters.OperationsSucceeded) failed=$($script:counters.OperationsFailed) skipped=$($script:counters.OperationsSkipped) status=$($script:manifest.status)" "INFO"
Write-Log "Exit code: $script:exitCode" "INFO"

$summaryPayload = [ordered]@{
    schema_version = 1
    product = 'Debloat-Win11'
    version = $script:manifest.version
    correlation_id = $script:manifest.correlation_id
    timestamp = $script:manifest.timestamp
    status = $script:manifest.status
    dryrun = $script:manifest.dryrun
    scope = $script:manifest.scope
    runtime = $script:manifest.runtime
    operation_summary = $script:manifest.operation_summary
    operations = @($script:manifest.changes.operations)
    package_operations = @($script:manifest.changes.package_operations)
    counts = [ordered]@{
        appx_removed = $script:counters.AppxRemoved
        office_removed = $script:counters.OfficeRemoved
        oem_cleaned = $script:counters.OEMCleaned
        services_disabled = $script:counters.ServicesDisabled
        tasks_disabled = $script:counters.TasksDisabled
        registry_tweaks = $script:counters.RegistryTweaks
        package_operations = @($script:manifest.changes.package_operations).Count
    }
    rollback_unsupported = @($unsupportedRollback)
    artifacts = $script:manifest.artifacts
}
try {
    [System.IO.File]::WriteAllText($summaryFile, ($summaryPayload | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
    $script:manifest.observability.summary_path = $summaryFile
    $script:manifest.observability.correlation_id = $script:manifest.correlation_id
    [System.IO.File]::WriteAllText($manifestFile, ($script:manifest | ConvertTo-Json -Depth 12), [System.Text.Encoding]::UTF8)
} catch {
    Write-Log "Could not write structured summary artifacts: $($_.Exception.Message)" "WARNING"
}

if ($OutputFormat -eq 'Json') {
    Write-Output ($summaryPayload | ConvertTo-Json -Depth 10 -Compress)
} elseif ($OutputFormat -eq 'Csv') {
    $csvPayload = [ordered]@{
        version = $summaryPayload.version
        correlation_id = $summaryPayload.correlation_id
        status = $summaryPayload.status
        dryrun = $summaryPayload.dryrun
        scope = $summaryPayload.scope.user_policy
        os_build = $summaryPayload.runtime.os_build
        edition = $summaryPayload.runtime.edition
        architecture = $summaryPayload.runtime.architecture
        operations_attempted = $summaryPayload.operation_summary.attempted
        operations_succeeded = $summaryPayload.operation_summary.succeeded
        operations_failed = $summaryPayload.operation_summary.failed
        operations_skipped = $summaryPayload.operation_summary.skipped
        summary_file = $summaryFile
    }
    Write-Output (($csvPayload | ConvertTo-Csv -NoTypeInformation) -join "`n")
}

# Write completion event to EventLog
$summaryMsg = "Debloat-Win11 v2.3.11 status=$($script:manifest.status). AppX=$($script:counters.AppxRemoved) Services=$($script:counters.ServicesDisabled) Tasks=$($script:counters.TasksDisabled) Registry=$($script:counters.RegistryTweaks) OperationsFailed=$($script:counters.OperationsFailed) Disk=$diskRecovered Runtime=$runtimeStr ExitCode=$script:exitCode"
$evtType = if ($script:exitCode -eq 0) { 'Information' } else { 'Warning' }
Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 1000 -EntryType $evtType -Message $summaryMsg -EA 0

# Collect crash dump if errors occurred (opt-in diagnostic bundle)
if ($script:exitCode -ne 0) {
    $crashTs = Get-Date -Format 'yyyyMMdd-HHmmss'
    $crashDir = "$env:TEMP\Debloat-Win11-crash-$crashTs"
    $crashZip = "$env:TEMP\Debloat-Win11-crash-$crashTs.zip"
    try {
        New-Item -Path $crashDir -ItemType Directory -Force | Out-Null
        if (Test-Path -LiteralPath $logFile -PathType Leaf) { Write-DebloatRedactedFile -SourcePath $logFile -DestinationPath (Join-Path $crashDir 'log-redacted.log') | Out-Null }
        if (Test-Path -LiteralPath $manifestFile -PathType Leaf) { Write-DebloatRedactedFile -SourcePath $manifestFile -DestinationPath (Join-Path $crashDir 'manifest-redacted.json') | Out-Null }
        $sysInfo = @{
            OSName       = $osName
            Build        = $osBuild
            EditionId    = $editionId
            IsLTSC       = $script:isLTSC
            IsLaptop     = $script:isLaptop
            IsSSD        = $script:isSSD
            RAM_GB       = $totalRAM
            ExitCode     = $script:exitCode
            CorrelationId = $script:manifest.correlation_id
            RedactionPolicy = $script:manifest.observability.redaction_policy
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

if ($OutputFormat -eq 'Text') { Write-Host "`nRestart recommended to apply all changes." -ForegroundColor Yellow }

# Enforce the retention bound after this run's artifacts have been created.
Invoke-DebloatLogRetention -Directory $LogDir -KeepPerType ([int]$script:manifest.observability.log_retention_per_type)

# Clean up lockfile
Remove-Item $script:lockFile -Force -EA 0

exit $script:exitCode
