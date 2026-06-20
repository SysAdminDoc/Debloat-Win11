#Requires -RunAsAdministrator
#Requires -Version 5.1

# ============================================================================
# WINDOWS 11 COMPLETE DEBLOAT SCRIPT v2.0.0
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
    [switch]$Silent
)

# ============================================================================
# VALIDATE MUTUALLY EXCLUSIVE FLAGS
# ============================================================================
if ($UndoFile -and $DryRun) {
    Write-Host "ERROR: -UndoFile and -DryRun cannot be used together" -ForegroundColor Red
    exit 2
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

    # Re-enable services
    $undoneServices = 0
    foreach ($svcName in $undoManifest.changes.services_disabled) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
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

    Write-Host ""
    Write-Host "=== UNDO COMPLETE ===" -ForegroundColor Green
    Write-Host "Restart recommended to apply all restored settings." -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# CONFIG FILE SUPPORT
# ============================================================================
# Merge external .psd1 config into the session, overriding built-in arrays
$script:configOverrides = @{}
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
    version   = 'v2.0.0'
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
        $script:manifest.changes.services_disabled.Add($ServiceName) | Out-Null
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
# STARTUP BANNER
# ============================================================================
Write-Log "=== WINDOWS DEBLOAT v2.0.0 STARTING ===" "INFO"
if ($DryRun) { Write-Log "*** DRY RUN MODE - No changes will be made ***" "WARNING" }
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
Write-Log "[System Tweaks] Applying registry tweaks..." "SECTION"

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

# Disable telemetry services
if (-not $DryRun) {
    @("DiagTrack", "dmwappushservice", "lfsvc", "Fax") | ForEach-Object {
        Stop-Service -Name $_ -Force -EA 0
        Set-Service -Name $_ -StartupType Disabled -EA 0
    }
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
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentConnectors" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentWorkspaces" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableRemoteAgentConnectors" -Value 1

# --- Disable Microsoft Copilot thoroughly (registry + AppX) ---
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\Shell\Copilot" -Name "IsCopilotAvailable" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Value 0
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotCDPPageContext" -Value 0
Remove-AppxDryRun -Pattern '*Microsoft.Copilot*'
Remove-AppxDryRun -Pattern '*Microsoft.Windows.Ai.Copilot.Provider*'

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
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
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

# Disable Widgets
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0

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

# Dark mode
Write-Log "  Enabling dark mode..." "INFO"
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0

# Remove Microsoft Store pin from taskbar
if (-not $DryRun) {
    $taskbandPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    Remove-ItemProperty -Path $taskbandPath -Name "Favorites" -Force -EA 0
    Remove-ItemProperty -Path $taskbandPath -Name "FavoritesResolve" -Force -EA 0
}
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0
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

# OOBE & Nag Screens
Write-Log "  Disabling OOBE & nag screens..." "INFO"
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" -Name "DisablePrivacyExperience" -Value 1
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name "DisablePrivacyExperience" -Value 1
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

# Lock Screen Notifications
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" -Value 0
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" -Value 0

# Exclude drivers from Windows Update
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Value 1

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
            # Don't disable entirely, but ensure SSD optimization mode
            Write-Log "  Configuring defrag for SSD optimization..." "INFO"
        }

        # Ensure TRIM is enabled
        fsutil behavior set DisableDeleteNotify 0 | Out-Null
        Write-Log "  TRIM enabled" "INFO"

        # Disable Superfetch/SysMain on SSD (not needed, reduces writes)
        Stop-Service -Name 'SysMain' -Force -EA 0
        Set-Service -Name 'SysMain' -StartupType Disabled -EA 0
        Write-Log "  Superfetch disabled (not needed on SSD)" "INFO"

        # Disable last access timestamp (reduces writes)
        fsutil behavior set disablelastaccess 1 | Out-Null
        Write-Log "  Last access timestamp disabled" "INFO"
    } else {
        Write-Log "  [DRY RUN] Would enable TRIM, disable Superfetch, disable last access timestamp" "INFO"
    }

    # Disable Prefetch on SSD
    Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnablePrefetcher" -Value 0
    Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnableSuperfetch" -Value 0
    Write-Log "  Prefetch disabled (not needed on SSD)" "INFO"

    Write-Log "  SSD optimizations applied" "SUCCESS"
} else {
    Write-Log "[HDD] Keeping HDD-optimized settings..." "SECTION"
    if (-not $DryRun) {
        # Keep Superfetch enabled for HDD
        Set-Service -Name 'SysMain' -StartupType Automatic -EA 0
        Start-Service -Name 'SysMain' -EA 0
    }
    Write-Log "  Superfetch enabled (improves HDD performance)" "INFO"
}

# ============================================================================
# WINDOWS UPDATE CONTROL (Active Hours & Deferrals)
# ============================================================================
Write-Log "[Windows Update] Configuring update behavior..." "SECTION"

# Set active hours to prevent auto-restart during work (6 AM - 11 PM)
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursStart" -Value 6
Set-Reg -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "ActiveHoursEnd" -Value 23
Write-Log "  Active hours: 6 AM - 11 PM (no auto-restart)" "INFO"

# Disable auto-restart with logged on users
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Value 1

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

Write-Log "  Windows Update configured" "SUCCESS"

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
if ([int]$osBuild -ge 22000) {
    Write-Log "[Widgets] Removing Windows 11 Widgets..." "SECTION"

    # Disable Widgets
    Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
    Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0

    # Remove Widgets package
    Remove-AppxDryRun -Pattern '*WebExperience*'
    Remove-AppxDryRun -Pattern '*MicrosoftWindows.Client.WebExperience*'
    if (-not $DryRun) {
        Get-AppxProvisionedPackage -Online -EA 0 | Where-Object { $_.DisplayName -match 'WebExperience' } | Remove-AppxProvisionedPackage -Online -EA 0
    }

    Write-Log "  Widgets removed" "SUCCESS"
}

# ============================================================================
# STARTUP APPS CLEANUP (Common Bloatware Auto-Starts)
# ============================================================================
Write-Log "[Startup] Cleaning startup items..." "SECTION"

# Registry Run keys to clean (HKCU)
$startupBloat = @(
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
)

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

    # Allow config file to override Defender exclusions
    $defenderExclusions = if ($script:configOverrides.ContainsKey('DefenderExclusions')) { $script:configOverrides.DefenderExclusions } else { @(
        "C:\images",
        "C:\MTU",
        "C:\Maven",
        "C:\Program Files\Voyance",
        "C:\Program Files\VPACS",
        "C:\Program Files\Minipacs",
        "C:\ProgramData\Voyance",
        "C:\ProgramData\VPACS",
        "C:\ProgramData\Minipacs",
        "C:\drtech",
        "C:\ecali1"
    ) }

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

if (-not $DryRun) {
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
}

Write-Log "  Context menu cleaned" "SUCCESS"

# ============================================================================
# DISABLE WINDOWS OPTIONAL FEATURES
# ============================================================================
Write-Log "[Optional Features] Disabling legacy features..." "SECTION"

$featuresToDisable = @(
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
)

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
} else { Write-Log "[System Tweaks] SKIPPED (phase excluded)" "INFO" }

# ============================================================================
# PHASE 1: REMOVE APPX PACKAGES (USER + PROVISIONED)
# ============================================================================
Update-Phase "AppX Package Removal"
if (Test-PhaseEnabled 'AppX') {
Write-Log "[Phase 1/7] Removing bloatware packages..." "SECTION"

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
} else { Write-Log "[Phase 1/7] AppX removal SKIPPED (phase excluded)" "INFO" }

# ============================================================================
# PHASE 2: OEM BLOATWARE CLEANUP (Dell, Intel, HP, Lenovo)
# ============================================================================
Update-Phase "OEM Cleanup"
if (Test-PhaseEnabled 'OEM') {
Write-Log "[Phase 2/7] Removing OEM bloatware..." "SECTION"

# Intel chipset/driver services and processes that must NOT be killed
$script:oemSafeIntelPattern = 'igfx|IntelAudio|Intel.*Driver|Intel.*Chipset|IntcDAud|IntcOED|IntelManagementEngine|imesrv|jhi_service|LMS'

if (-not $DryRun) {
    # Stop all OEM services and processes FIRST (ensures clean removal)
    Write-Log "  Disabling OEM services..." "INFO"
    Get-Service | Where-Object { ($_.Name -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer' -or $_.DisplayName -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer') -and $_.Name -notmatch $script:oemSafeIntelPattern -and $_.DisplayName -notmatch $script:oemSafeIntelPattern } | ForEach-Object {
        Stop-Service -Name $_.Name -Force -EA 0
        Set-Service -Name $_.Name -StartupType Disabled -EA 0
        $script:counters.OEMCleaned++
    }
    Write-Log "  Killing OEM processes..." "INFO"
    Get-Process -EA 0 | Where-Object { ($_.Name -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer' -or $_.Path -match 'dell|intel|hp|lenovo|realtek|waves|asus|acer|msi|razer') -and $_.Name -notmatch $script:oemSafeIntelPattern } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -EA 0
    }

    # AppX removal
    Get-AppxPackage -AllUsers *Dell* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *DB6EA5DB* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *HONHAIPRECISION* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *Intel* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *AppUp* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *HPInc* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *Lenovo* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *Dolby* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *Realtek* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxPackage -AllUsers *Waves* 2>$null | Remove-AppxPackage -AllUsers 2>$null
    Get-AppxProvisionedPackage -Online 2>$null | Where-Object { $_.DisplayName -match 'Dell|Intel|HP|Lenovo|Dolby|Realtek|Waves' } | Remove-AppxProvisionedPackage -Online 2>$null
    Get-Package *Dell* 2>$null | Uninstall-Package -Force 2>$null
    Get-Package *Intel* 2>$null | Uninstall-Package -Force 2>$null

    Write-Log "  OEM AppX packages removed" "SUCCESS"
} else {
    Write-Log "  [DRY RUN] Would remove OEM services, processes, and AppX packages" "INFO"
    $script:counters.OEMCleaned += 5
}

# ============================================================================
# PHASE 2B: OEM NUCLEAR CLEAN (Skip uninstallers, delete everything)
# ============================================================================
Write-Log "[Phase 2/7] OEM Nuclear Clean..." "SECTION"

if (-not $DryRun) {
    # Kill all OEM processes again (in case any respawned), preserving Intel drivers
    Get-Process -EA 0 | Where-Object { ($_.Name -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer' -or $_.Path -match 'dell|intel|hp|lenovo|realtek|waves|asus|acer|msi|razer') -and $_.Name -notmatch $script:oemSafeIntelPattern } | Stop-Process -Force -EA 0

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
    Get-Service | Where-Object { ($_.Name -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer' -or $_.DisplayName -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer') -and $_.Name -notmatch $script:oemSafeIntelPattern -and $_.DisplayName -notmatch $script:oemSafeIntelPattern } | ForEach-Object {
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
$tasksToDisable = @(
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
)
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

    # Final process kill (preserving Intel chipset/driver processes)
    Get-Process -EA 0 | Where-Object { ($_.Name -match 'dell|intel|hp[^a-z]|lenovo|realtek|waves|asus|acer|msi[^a-z]|razer' -or $_.Path -match 'dell|intel|hp|lenovo|realtek|waves|asus|acer|msi|razer') -and $_.Name -notmatch $script:oemSafeIntelPattern } | Stop-Process -Force -EA 0
}

Write-Log "  OEM nuclear clean complete" "SUCCESS"
} else { Write-Log "[Phase 2/7] OEM cleanup SKIPPED (phase excluded)" "INFO" }

# ============================================================================
# PHASE 2C: ONEDRIVE REMOVAL
# ============================================================================
Update-Phase "OneDrive Removal"
if (-not (Test-PhaseEnabled 'OneDrive')) {
    Write-Log "[Phase 3/7] OneDrive SKIPPED (phase excluded)" "INFO"
} elseif ($script:onedriveInUse) {
    Write-Log "[Phase 3/7] OneDrive - SKIPPED (in use)" "SECTION"
} else {
    Write-Log "[Phase 3/7] Removing OneDrive..." "SECTION"

    if (-not $DryRun) {
        # Kill OneDrive processes
        Stop-Process -Name 'OneDrive', 'OneDriveSetup' -Force -EA 0

        # Run official uninstaller (fast, ~5 seconds)
        $oneDrivePaths = @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )
        foreach ($path in $oneDrivePaths) {
            if (Test-Path $path) {
                Write-Log "  Running OneDrive uninstaller..." "INFO"
                Start-Process $path -ArgumentList '/uninstall' -Wait -WindowStyle Hidden -EA 0
                break
            }
        }

        # Clean OneDrive folders
        @(
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive",
            "$env:USERPROFILE\OneDrive"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
        }

        # Clean OneDrive from all user profiles
        $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
        foreach ($userProf in $userProfiles) {
            @(
                "$($userProf.FullName)\AppData\Local\Microsoft\OneDrive",
                "$($userProf.FullName)\OneDrive"
            ) | ForEach-Object {
                if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
            }
        }

        # Remove OneDrive from Explorer sidebar
        reg delete "HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f 2>$null
        reg delete "HKCR\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f 2>$null
    } else {
        Write-Log "  [DRY RUN] Would uninstall OneDrive, clean folders and registry" "INFO"
    }

    Write-Log "  OneDrive removed" "SUCCESS"
}

# ============================================================================
# PHASE 3: OFFICE NUCLEAR REMOVAL (Skip uninstallers, delete everything)
# ============================================================================
Update-Phase "Office Removal"
if (-not (Test-PhaseEnabled 'Office')) {
    Write-Log "[Phase 4/7] Office SKIPPED (phase excluded)" "INFO"
} elseif ($script:officeInUse) {
    Write-Log "[Phase 4/7] Office - SKIPPED (in use)" "SECTION"
} else {
    Write-Log "[Phase 4/7] Office Nuclear Removal..." "SECTION"

    if (-not $DryRun) {
        # Kill OneNote standalone installs first (all languages) - NUCLEAR
        Write-Log "  Nuking OneNote installations..." "INFO"
        $uninstallPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        foreach ($path in $uninstallPaths) {
            Get-ChildItem $path -EA 0 | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath -EA 0
                if ($props.DisplayName -match 'OneNote') {
                    Write-Log "    Nuking: $($props.DisplayName)" "INFO"
                    $script:counters.OfficeRemoved++
                    # Try MSI uninstall
                    $guid = $_.PSChildName
                    if ($guid -match '^\{') {
                        Start-Process 'msiexec.exe' -ArgumentList "/x$guid /qn /norestart" -Wait -WindowStyle Hidden -EA 0
                    }
                    # Delete registry entry regardless (nuclear)
                    Remove-Item $_.PSPath -Recurse -Force -EA 0
                }
            }
        }

        # Nuke OneNote AppX packages
        Get-AppxPackage -AllUsers *OneNote* -EA 0 | Remove-AppxPackage -AllUsers -EA 0
        Get-AppxProvisionedPackage -Online -EA 0 | Where-Object { $_.DisplayName -match 'OneNote' } | Remove-AppxProvisionedPackage -Online -EA 0

        # Nuke OneNote folders
        @(
            "$env:LOCALAPPDATA\Microsoft\OneNote",
            "$env:APPDATA\Microsoft\OneNote"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
        }

        # Check if Office is installed
        $officeInstalled = (Test-Path "C:\Program Files\Microsoft Office") -or
                           (Test-Path "C:\Program Files (x86)\Microsoft Office") -or
                           (Test-Path "C:\Program Files\Common Files\microsoft shared\ClickToRun")

        if ($officeInstalled) {
            Write-Log "  Office detected - nuking..." "INFO"

            # Kill ALL Office processes
            Write-Log "  Killing Office processes..." "INFO"
            $officeProcs = @(
                'WINWORD','EXCEL','POWERPNT','OUTLOOK','ONENOTE','MSACCESS','MSPUB','VISIO','WINPROJ',
                'lync','Teams','OfficeClickToRun','OfficeC2RClient','AppVShNotify',
                'IntegratedOffice','integrator','FirstRun','setup','communicator','msosync',
                'OneNoteM','GROOVE','INFOPATH','MSTORE','CLVIEW','SELFCERT','msoev','OFFDIAG',
                'ose','ose64','osppsvc','sppsvc','msoidsvc','msoidsvcm','officeclicktorun',
                'officeondemand','msoia','msohtmed','msouc'
            )
            # Only kill OneDrive if not in use
            if (-not $script:onedriveInUse) { $officeProcs += 'OneDrive' }
            $officeProcs | ForEach-Object { Get-Process -Name $_ -EA 0 | Stop-Process -Force -EA 0 }

            # Stop and delete Office services
            Write-Log "  Nuking Office services..." "INFO"
            @('ClickToRunSvc','OfficeSvc','ose','ose64','osppsvc') | ForEach-Object {
                if (Get-Service -Name $_ -EA 0) {
                    $script:manifest.changes.services_deleted.Add($_) | Out-Null
                }
                Stop-Service -Name $_ -Force -EA 0
                Set-Service -Name $_ -StartupType Disabled -EA 0
                sc.exe delete $_ 2>$null
                $script:counters.OfficeRemoved++
            }

            # Delete Office scheduled tasks
            Write-Log "  Nuking Office scheduled tasks..." "INFO"
            Get-ScheduledTask -TaskPath "\Microsoft\Office\*" -EA 0 | Unregister-ScheduledTask -Confirm:$false -EA 0
            @(
                'Office Automatic Updates*','Office ClickToRun*','Office Feature Updates*',
                'Office Serviceability*','OfficeTelemetry*','Office Background*',
                'Office Performance*','Office Subscription*','Office SxS*'
            ) | ForEach-Object {
                Get-ScheduledTask -TaskName $_ -EA 0 | Unregister-ScheduledTask -Confirm:$false -EA 0
            }

            # Nuclear file deletion
            Write-Log "  Nuking Office folders..." "INFO"
            @(
                "C:\Program Files\Microsoft Office",
                "C:\Program Files\Microsoft Office 15",
                "C:\Program Files\Microsoft Office 16",
                "C:\Program Files (x86)\Microsoft Office",
                "C:\Program Files (x86)\Microsoft Office 15",
                "C:\Program Files (x86)\Microsoft Office 16",
                "C:\Program Files\Common Files\microsoft shared\ClickToRun",
                "C:\Program Files\Common Files\microsoft shared\Office15",
                "C:\Program Files\Common Files\microsoft shared\Office16",
                "C:\Program Files (x86)\Common Files\microsoft shared\ClickToRun",
                "C:\Program Files (x86)\Common Files\microsoft shared\Office15",
                "C:\Program Files (x86)\Common Files\microsoft shared\Office16",
                "$env:ProgramData\Microsoft\Office",
                "$env:ProgramData\Microsoft\ClickToRun",
                "$env:LOCALAPPDATA\Microsoft\Office",
                "$env:APPDATA\Microsoft\Office"
            ) | ForEach-Object {
                if (Test-Path $_) {
                    Remove-Item $_ -Recurse -Force -EA 0
                    $script:counters.OfficeRemoved++
                }
            }

            # Delete Office folders from all user profiles
            $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
            foreach ($userProf in $userProfiles) {
                @(
                    "$($userProf.FullName)\AppData\Local\Microsoft\Office",
                    "$($userProf.FullName)\AppData\Roaming\Microsoft\Office"
                ) | ForEach-Object {
                    if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
                }
            }

            # Nuclear registry cleanup
            Write-Log "  Nuking Office registry..." "INFO"
            @(
                "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun",
                "HKLM:\SOFTWARE\Microsoft\Office\15.0",
                "HKLM:\SOFTWARE\Microsoft\Office\16.0",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\ClickToRun",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\15.0",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\16.0",
                "HKCU:\SOFTWARE\Microsoft\Office\15.0",
                "HKCU:\SOFTWARE\Microsoft\Office\16.0"
            ) | ForEach-Object {
                if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
            }

            # Delete Office Add/Remove Programs entries
            @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            ) | ForEach-Object {
                Get-ChildItem $_ -EA 0 | ForEach-Object {
                    $props = Get-ItemProperty $_.PSPath -EA 0
                    if ($props.DisplayName -match 'Microsoft 365|Microsoft Office|Office 16 Click-to-Run') {
                        Remove-Item $_.PSPath -Recurse -Force -EA 0
                    }
                }
            }

            # Clean Office shortcuts
            Write-Log "  Nuking Office shortcuts..." "INFO"
            @(
                "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
                "$env:USERPROFILE\Desktop",
                "$env:PUBLIC\Desktop"
            ) | ForEach-Object {
                Get-ChildItem -Path $_ -Filter "*.lnk" -Recurse -EA 0 | ForEach-Object {
                    $target = (New-Object -COM WScript.Shell).CreateShortcut($_.FullName).TargetPath
                    if ($target -match 'Office|WINWORD|EXCEL|POWERPNT|OUTLOOK|ONENOTE|MSACCESS|ClickToRun') {
                        Remove-Item $_.FullName -Force -EA 0
                    }
                }
            }

            # Clean Office licenses (Office-only; do NOT touch Windows product key)
            Write-Log "  Cleaning Office licenses..." "INFO"
            Get-WmiObject -Query "SELECT * FROM SoftwareLicensingProduct WHERE ApplicationId='0ff1ce15-a989-479d-af46-f275c6370663' AND PartialProductKey IS NOT NULL" -EA 0 | ForEach-Object {
                $_.UninstallProductKey($_.ProductKeyID) 2>$null
            }

            Write-Log "  Office nuclear removal complete" "SUCCESS"
        } else {
            Write-Log "  Office not detected - skipping" "INFO"
        }
    } else {
        Write-Log "  [DRY RUN] Would perform full Office nuclear removal" "INFO"
    }
}

# ============================================================================
# DISABLE BLOATWARE SERVICES
# ============================================================================
Update-Phase "Service Cleanup"
if (Test-PhaseEnabled 'Services') {
Write-Log "[Cleanup] Disabling bloatware services..." "SECTION"

# Allow config file to override the service list
$servicesToDisable = if ($script:configOverrides.ContainsKey('ServicesToDisable')) { $script:configOverrides.ServicesToDisable } else { @(
    # Telemetry & Diagnostics
    'DiagTrack',                    # Diagnostics Tracking
    'dmwappushservice',             # WAP Push Message Routing
    'DPS',                          # Diagnostic Policy Service
    'WdiSystemHost',                # Diagnostic System Host
    'WdiServiceHost',               # Diagnostic Service Host
    'InventorySvc',                 # Inventory and Compatibility Appraisal
    'WaaSMedicSvc',                 # Windows Health and Optimized Experiences

    # Xbox & Gaming
    'XblAuthManager',               # Xbox Live Auth
    'XblGameSave',                  # Xbox Live Game Save
    'XboxGipSvc',                   # Xbox Accessory Management
    'XboxNetApiSvc',                # Xbox Live Networking
    'GamingServices',               # Gaming Services
    'GamingServicesNet',            # Gaming Services Network

    # Unused Features
    'CDPSvc',                       # Connected Devices Platform Service
    'CDPUserSvc',                   # Connected Devices Platform User Service
    'DoSvc',                        # Delivery Optimization
    'TrkWks',                       # Distributed Link Tracking Client
    'NPSMSvc',                      # Now Playing Session Manager Service
    'RmSvc',                        # Radio Management Service
    'OneSyncSvc',                   # Sync Host
    'lmhosts',                      # TCP/IP NetBIOS Helper
    'WSAIFabricSvc',                # Windows AI Fabric Service (Recall, AI Search)

    # Other Bloat
    'lfsvc',                        # Geolocation
    'Fax',                          # Fax
    'WMPNetworkSvc',                # Windows Media Player Network Sharing
    'icssvc',                       # Mobile Hotspot
    'WerSvc',                       # Windows Error Reporting
    'wisvc',                        # Windows Insider Service
    'RetailDemo',                   # Retail Demo
    'MapsBroker',                   # Downloaded Maps Manager
    'PhoneSvc',                     # Phone Service
    'AJRouter',                     # AllJoyn Router
    'WalletService',                # Wallet Service
    'RemoteRegistry',               # Remote Registry
    'WpcMonSvc',                    # Parental Controls
    'SharedAccess',                 # Internet Connection Sharing
    'MessagingService',             # Text Messaging
    'PcaSvc',                       # Program Compatibility Assistant
    'SEMgrSvc',                     # Payments and NFC/SE Manager
    'SmsRouter'                     # Microsoft Windows SMS Router
    # REMOVED: iphlpsvc (IPv6 helper - needed for some networks)
    # REMOVED: ShellHWDetection (USB drive detection)
    # REMOVED: WinHttpAutoProxySvc (enterprise proxy detection)
    # REMOVED: TapiSrv (VoIP/fax may need it)
    # REMOVED: SSDPSRV (UPnP - some medical equipment uses this)
    # REMOVED: WbioSrvc (fingerprint login on laptops)
    # REMOVED: TabletInputService (touch input)
) }

# Parallel service disable on PS7+; sequential fallback on PS5
if ($PSVersionTable.PSVersion.Major -ge 7 -and -not $DryRun) {
    # Parallel path: stop and disable in bulk, then record in manifest
    $servicesToDisable | ForEach-Object -Parallel {
        $svc = Get-Service -Name $_ -EA SilentlyContinue
        if ($svc) {
            Stop-Service -Name $_ -Force -EA SilentlyContinue
            Set-Service -Name $_ -StartupType Disabled -EA SilentlyContinue
        }
    } -ThrottleLimit 8
    # Record in manifest (must be sequential for thread-safe ArrayList)
    foreach ($svc in $servicesToDisable) {
        if (Get-Service -Name $svc -EA 0) {
            $script:manifest.changes.services_disabled.Add($svc) | Out-Null
            $script:counters.ServicesDisabled++
        }
    }
} else {
    foreach ($svc in $servicesToDisable) {
        Disable-ServiceDryRun -ServiceName $svc
    }
}

# Handle per-user services (have _XXXXX suffix)
$perUserServices = @('CDPUserSvc', 'NPSMSvc', 'OneSyncSvc', 'MessagingService', 'PimIndexMaintenanceSvc', 'UnistoreSvc', 'UserDataSvc', 'WpnUserService')
foreach ($baseName in $perUserServices) {
    Get-Service -Name "$baseName*" -EA 0 | ForEach-Object {
        Disable-ServiceDryRun -ServiceName $_.Name
    }
}

Write-Log "  Bloatware services disabled" "SUCCESS"
} else { Write-Log "[Services] SKIPPED (phase excluded)" "INFO" }

# ============================================================================
# TEMP FILE CLEANUP
# ============================================================================
Write-Log "[Cleanup] Clearing temp files..." "SECTION"

if (-not $DryRun) {
    # System temp
    Remove-Item "$env:TEMP\*" -Recurse -Force -EA 0
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -EA 0

    # User temps (all profiles)
    $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
    foreach ($userProf in $userProfiles) {
        Remove-Item "$($userProf.FullName)\AppData\Local\Temp\*" -Recurse -Force -EA 0
    }

    # Windows Update cache
    Stop-Service -Name wuauserv -Force -EA 0
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -EA 0

    # Prefetch
    Remove-Item "C:\Windows\Prefetch\*" -Force -EA 0

    # Delivery Optimization cache
    Remove-Item "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\*" -Recurse -Force -EA 0
} else {
    Write-Log "  [DRY RUN] Would clear temp, prefetch, WU cache, and delivery optimization cache" "INFO"
}

Write-Log "  Temp files cleared" "SUCCESS"

# ============================================================================
# PHASE 5: EDGE DEBLOAT
# ============================================================================
Update-Phase "Edge Configuration"
if (Test-PhaseEnabled 'Edge') {
Write-Log "[Phase 5/7] Configuring Microsoft Edge..." "SECTION"

# Close Edge first
if (-not $DryRun) {
    Stop-Process -Name 'msedge' -Force -EA 0
    Start-Sleep -Seconds 2
}

$edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (!(Test-Path $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }

# Edge Telemetry & Data Collection
Write-Log "  Disabling Edge telemetry..." "INFO"
@{
    "DiagnosticData" = 0; "MetricsReportingEnabled" = 0; "PersonalizationReportingEnabled" = 0
    "SendSiteInfoToImproveServices" = 0; "Edge3PSerpTelemetryEnabled" = 0
    "UserFeedbackAllowed" = 0; "CrashReportingMode" = 0
    "ExperimentationAndConfigurationServiceControl" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Copilot & AI
Write-Log "  Disabling Edge Copilot & AI..." "INFO"
@{
    "HubsSidebarEnabled" = 0; "EdgeCopilotEnabled" = 0; "CopilotPageContext" = 0
    "CopilotCDPPageContext" = 0; "Microsoft365CopilotChatIconEnabled" = 0
    "NewTabPageBingChatEnabled" = 0; "NewTabPageBingAIPromptEnabled" = 0
    "GenAILocalFoundationalModelSettings" = 0; "ComposeInlineEnabled" = 0
    "VisualSearchEnabled" = 0; "QuickSearchShowMiniMenu" = 0
    "EdgeHistoryAISearchEnabled" = 0; "AIGenThemesEnabled" = 0
    "BuiltInAIAPIsEnabled" = 0; "CopilotAddressBarSuggestionsEnabled" = 0
    "EdgeEntraCopilotPageContext" = 0; "CopilotNewTabPageEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Shopping & Promotions
Write-Log "  Disabling Edge shopping & promotions..." "INFO"
@{
    "EdgeShoppingAssistantEnabled" = 0; "EdgeWalletEnabled" = 0; "EdgeWalletCheckoutEnabled" = 0
    "ShowMicrosoftRewards" = 0; "ShowRecommendationsEnabled" = 0
    "SpotlightExperiencesAndRecommendationsEnabled" = 0; "PromotionalTabsEnabled" = 0
    "DefaultBrowserSettingsCampaignEnabled" = 0; "TravelAssistanceEnabled" = 0
    "GamerModeEnabled" = 0; "WebWidgetAllowed" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge New Tab & UI
Write-Log "  Configuring Edge new tab & UI..." "INFO"
@{
    "NewTabPageContentEnabled" = 0; "NewTabPageHideDefaultTopSites" = 1
    "NewTabPageNewsEnabled" = 0; "NewTabPageQuickLinksEnabled" = 0
    "FavoritesBarEnabled" = 1; "TabGroupsEnabled" = 0; "TabGroupsAutoCreate" = 0
    "EdgeCollectionsEnabled" = 0; "EdgeFollowEnabled" = 0; "WorkspacesEnabled" = 0
    "ShowOfficeShortcutInFavoritesBar" = 0; "SplitScreenEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Performance
Write-Log "  Configuring Edge performance..." "INFO"
@{
    "StartupBoostEnabled" = 0; "BackgroundModeEnabled" = 0
    "SleepingTabsEnabled" = 1; "HardwareAccelerationModeEnabled" = 1
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Sync & Sign-In
Write-Log "  Disabling Edge sync & sign-in..." "INFO"
@{
    "SyncDisabled" = 1; "BrowserSignin" = 0; "ImplicitSignInEnabled" = 0
    "SignInCtaOnNtpEnabled" = 0; "LinkedAccountEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Privacy
Write-Log "  Configuring Edge privacy..." "INFO"
@{
    "TrackingPrevention" = 3; "ConfigureDoNotTrack" = 1; "BlockThirdPartyCookies" = 1
    "DefaultGeolocationSetting" = 2; "DefaultNotificationsSetting" = 2
    "AutofillAddressEnabled" = 0; "AutofillCreditCardEnabled" = 0
    "PasswordManagerEnabled" = 0; "SmartScreenEnabled" = 1
    "AutomaticHttpsDefault" = 2; "EnableMediaRouter" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge First Run & Homepage
Write-Log "  Configuring Edge first run & homepage..." "INFO"
@{
    "HideFirstRunExperience" = 1; "PreventFirstRunPage" = 1
    "ShowBrowserMigrationPrompt" = 0; "AutoImportAtFirstRun" = 0
    "HomepageIsNewTabPage" = 0; "ShowHomeButton" = 1; "RestoreOnStartup" = 4
    "DefaultSearchProviderEnabled" = 1; "AddressBarMicrosoftSearchInBingProviderEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Set homepage and search to Google
Set-Reg -Path $edgePolicyPath -Name "HomepageLocation" -Value "https://www.google.com" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "NewTabPageLocation" -Value "https://www.google.com" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "DefaultSearchProviderName" -Value "Google" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "DefaultSearchProviderSearchURL" -Value "https://www.google.com/search?q={searchTerms}" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "DefaultSearchProviderSuggestURL" -Value "https://www.google.com/complete/search?client=chrome&q={searchTerms}" -Type "String"

# Startup URLs
$startupUrlsPath = "$edgePolicyPath\RestoreOnStartupURLs"
if (!(Test-Path $startupUrlsPath)) { New-Item -Path $startupUrlsPath -Force | Out-Null }
Set-Reg -Path $startupUrlsPath -Name "1" -Value "https://www.google.com" -Type "String"

# Force install uBlock Origin
Write-Log "  Installing uBlock Origin..." "INFO"
$forcelistPath = "$edgePolicyPath\ExtensionInstallForcelist"
if (!(Test-Path $forcelistPath)) { New-Item -Path $forcelistPath -Force | Out-Null }
Set-Reg -Path $forcelistPath -Name "1" -Value "odfafepnkmbhccpbejgmiehpchacaeak;https://edge.microsoft.com/extensionwebstorebase/v1/crx" -Type "String"

# Configure Edge bookmarks (Maven support links)
if (-not $DryRun) {
    Write-Log "  Configuring Edge bookmarks..." "INFO"
    $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"

    # Check if Edge profile exists, if not create it by launching Edge
    $edgeProfileExists = (Test-Path "$edgeUserData\Default\Bookmarks") -or (Test-Path "$edgeUserData\Profile 1\Bookmarks")
    if (-not $edgeProfileExists) {
        Write-Log "  Creating Edge profile..." "INFO"
        $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        if (-not (Test-Path $edgePath)) { $edgePath = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }

        if (Test-Path $edgePath) {
            # Launch Edge to create profile
            Start-Process $edgePath -ArgumentList "--no-first-run" -EA 0
            Start-Sleep -Seconds 5

            # Close Edge
            Stop-Process -Name 'msedge' -Force -EA 0
            Start-Sleep -Seconds 2
        }
    }

    if (Test-Path $edgeUserData) {
        $edgeProfiles = Get-ChildItem $edgeUserData -Directory -EA 0 | Where-Object { $_.Name -match '^(Default|Profile)' }
        foreach ($userProf in $edgeProfiles) {
            $bookmarksFile = Join-Path $userProf.FullName "Bookmarks"
            if (Test-Path $bookmarksFile) {
                try {
                    $content = Get-Content $bookmarksFile -Raw -Encoding UTF8 | ConvertFrom-Json

                    # Remove OEM folders (Dell, Import favorites, etc.)
                    if ($content.roots.bookmark_bar.children) {
                        $content.roots.bookmark_bar.children = @($content.roots.bookmark_bar.children | Where-Object {
                            $_.name -notin @('Dell', 'Import favorites', 'Favorites bar', 'Managed favorites', 'HP', 'Lenovo', 'ASUS', 'Acer', 'MSI')
                        })
                    }

                    # Get max ID
                    $script:maxId = 1
                    function Get-MaxBookmarkId($node) {
                        if ($node.id) { $id = [int]$node.id; if ($id -gt $script:maxId) { $script:maxId = $id } }
                        if ($node.children) { foreach ($child in $node.children) { Get-MaxBookmarkId $child } }
                    }
                    Get-MaxBookmarkId $content.roots.bookmark_bar

                    # Maven bookmarks to add
                    $mavenBookmarks = @(
                        @{ name = "Support"; url = "https://www.mavenimaging.com/support" }
                        @{ name = "Patient Image"; url = "https://app.patientimage.ai/login" }
                        @{ name = "Google"; url = "https://www.google.com" }
                    )

                    # Get existing URLs
                    $existingUrls = @{}
                    foreach ($bm in $content.roots.bookmark_bar.children) {
                        if ($bm.url) { $existingUrls[$bm.url.TrimEnd('/').ToLower()] = $true }
                    }

                    # Add new bookmarks
                    $timestamp = [math]::Floor((Get-Date -UFormat %s)) * 1000000
                    $newBookmarks = @()
                    foreach ($bm in $mavenBookmarks) {
                        $normalizedUrl = $bm.url.TrimEnd('/').ToLower()
                        if (-not $existingUrls.ContainsKey($normalizedUrl)) {
                            $script:maxId++
                            $newBookmarks += @{
                                date_added = $timestamp.ToString()
                                date_last_used = "0"
                                guid = [guid]::NewGuid().ToString()
                                id = $script:maxId.ToString()
                                name = $bm.name
                                type = "url"
                                url = $bm.url
                            }
                            $timestamp++
                        }
                    }

                    if ($newBookmarks.Count -gt 0) {
                        $content.roots.bookmark_bar.children = @($newBookmarks) + @($content.roots.bookmark_bar.children)
                        $content.checksum = ""
                        $json = $content | ConvertTo-Json -Depth 100
                        [System.IO.File]::WriteAllText($bookmarksFile, $json, [System.Text.Encoding]::UTF8)
                    }
                } catch { }
            }
        }
    }
}

Write-Log "  Edge configured" "SUCCESS"
} else { Write-Log "[Phase 5/7] Edge SKIPPED (phase excluded)" "INFO" }

# ============================================================================
# PHASE 6: MAVEN FIREWALL RULES
# ============================================================================
Update-Phase "Firewall Rules"
if (Test-PhaseEnabled 'Firewall') {
Write-Log "[Phase 6/7] Importing Maven firewall rules..." "SECTION"

if (-not $DryRun) {
    # Enable firewall on all profiles
    Write-Log "  Enabling Windows Firewall..." "INFO"
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -EA 0

    # Firewall rules CSV data
    $firewallCsv = @"
Name	DisplayName	Direction	Action	Protocol	LocalPort	RemotePort	Program
FPS-NB_Datagram-In-UDP	File and Printer Sharing (NB-Datagram-In)	Inbound	Allow	UDP	138	Any	System
FPS-NB_Name-Out-UDP	File and Printer Sharing (NB-Name-Out)	Outbound	Allow	UDP	Any	137	System
FPS-SMB-In-TCP	File and Printer Sharing (SMB-In)	Inbound	Allow	TCP	445	Any	System
FPS-NB_Session-In-TCP	File and Printer Sharing (NB-Session-In)	Inbound	Allow	TCP	139	Any	System
FPS-NB_Name-In-UDP	File and Printer Sharing (NB-Name-In)	Inbound	Allow	UDP	137	Any	System
FPS-SMB-Out-TCP	File and Printer Sharing (SMB-Out)	Outbound	Allow	TCP	Any	445	System
FPS-NB_Session-Out-TCP	File and Printer Sharing (NB-Session-Out)	Outbound	Allow	TCP	Any	139	System
FPS-NB_Datagram-Out-UDP	File and Printer Sharing (NB-Datagram-Out)	Outbound	Allow	UDP	Any	138	System
FPS-LLMNR-In-UDP	File and Printer Sharing (LLMNR-UDP-In)	Inbound	Allow	UDP	5355	Any	System
FPS-LLMNR-Out-UDP	File and Printer Sharing (LLMNR-UDP-Out)	Outbound	Allow	UDP	Any	5355	System
minipacs-TCP-In	minipacs TCP Inbound	Inbound	Allow	TCP	Any	Any	C:\program files\vpacs\minipacs.exe
minipacs-UDP-In	minipacs UDP Inbound	Inbound	Allow	UDP	Any	Any	C:\program files\vpacs\minipacs.exe
minipacs-Out	minipacs Outbound	Outbound	Allow	Any	Any	Any	C:\program files\vpacs\minipacs.exe
voyance-TCP-In	voyance TCP Inbound	Inbound	Allow	TCP	Any	Any	C:\program files\voyance\voyance.exe
voyance-UDP-In	voyance UDP Inbound	Inbound	Allow	UDP	Any	Any	C:\program files\voyance\voyance.exe
voyance-Out	voyance Outbound	Outbound	Allow	Any	Any	Any	C:\program files\voyance\voyance.exe
DICOM-9001-In	DICOM Port 9001	Inbound	Allow	TCP	9001	Any	System
TeamViewer-Main-Out	TeamViewer	Outbound	Allow	Any	Any	Any	C:\Program Files (x86)\TeamViewer\TeamViewer.exe
TeamViewer-Service-Out	TeamViewer Service	Outbound	Allow	Any	Any	Any	C:\Program Files (x86)\TeamViewer\TeamViewer_Service.exe
Chrome-Out	Google Chrome	Outbound	Allow	Any	Any	Any	C:\program files\google\chrome\application\chrome.exe
Chrome-mDNS-In	Google Chrome mDNS	Inbound	Allow	UDP	5353	Any	C:\Program Files\Google\Chrome\Application\chrome.exe
"@

    Write-Log "  Importing firewall rules..." "INFO"
    $rules = $firewallCsv | ConvertFrom-Csv -Delimiter "`t"
    $successCount = 0

    foreach ($rule in $rules) {
        try {
            # Remove existing rule if present
            Remove-NetFirewallRule -Name $rule.Name -EA 0

            $params = @{
                Name = $rule.Name
                DisplayName = $rule.DisplayName
                Direction = $rule.Direction
                Action = $rule.Action
                Enabled = 'True'
                Profile = 'Private,Public'
            }

            if ($rule.Protocol -and $rule.Protocol -ne 'Any') { $params.Protocol = $rule.Protocol }
            if ($rule.LocalPort -and $rule.LocalPort -ne 'Any') { $params.LocalPort = $rule.LocalPort }
            if ($rule.RemotePort -and $rule.RemotePort -ne 'Any') { $params.RemotePort = $rule.RemotePort }
            if ($rule.Program -and $rule.Program -ne 'System') { $params.Program = $rule.Program }

            New-NetFirewallRule @params -EA Stop | Out-Null
            $successCount++
        } catch { }
    }

    Write-Log "  Imported $successCount firewall rules" "SUCCESS"
} else {
    Write-Log "  [DRY RUN] Would import 21 firewall rules" "INFO"
}
} else { Write-Log "[Phase 6/7] Firewall SKIPPED (phase excluded)" "INFO" }

# ============================================================================
# PHASE 7: PRIVACY CLEANUP
# ============================================================================
Update-Phase "Privacy Cleanup"
if (Test-PhaseEnabled 'Privacy') {
Write-Log "[Phase 7/7] Running privacy cleanup..." "SECTION"

if (-not $DryRun) {
    # Clear browser caches
    Write-Log "  Clearing browser caches..." "INFO"
    @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"
    ) | ForEach-Object {
        if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force -EA 0 }
    }

    # Clear diagnostics logs
    Write-Log "  Clearing diagnostics logs..." "INFO"
    Remove-Item "$env:ProgramData\Microsoft\Diagnosis\*" -Recurse -Force -EA 0
    Remove-Item "$env:LOCALAPPDATA\Diagnostics\*" -Recurse -Force -EA 0

    # Clear thumbnail cache
    Write-Log "  Clearing thumbnail cache..." "INFO"
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\*.db" -Force -EA 0

    # Clear recent files
    Write-Log "  Clearing recent files..." "INFO"
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -EA 0
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -EA 0
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -EA 0

    # Clear event logs
    Write-Log "  Clearing event logs..." "INFO"
    wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
} else {
    Write-Log "  [DRY RUN] Would clear browser caches, diagnostics, thumbnails, recent files, event logs" "INFO"
}

# Disable app usage tracking
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0

Write-Log "  Privacy cleanup complete" "SUCCESS"
} else { Write-Log "[Phase 7/7] Privacy SKIPPED (phase excluded)" "INFO" }

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
$summaryMsg = "Debloat-Win11 v2.0.0 completed. AppX=$($script:counters.AppxRemoved) Services=$($script:counters.ServicesDisabled) Tasks=$($script:counters.TasksDisabled) Registry=$($script:counters.RegistryTweaks) Disk=$diskRecovered Runtime=$runtimeStr ExitCode=$script:exitCode"
$evtType = if ($script:exitCode -eq 0) { 'Information' } else { 'Warning' }
Write-EventLog -LogName 'Application' -Source $script:eventLogSource -EventId 1000 -EntryType $evtType -Message $summaryMsg -EA 0

Write-Host "`nRestart recommended to apply all changes." -ForegroundColor Yellow

exit $script:exitCode
