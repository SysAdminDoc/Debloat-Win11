# ============================================================================
# MODULE: Service Cleanup + Temp File Cleanup
# Disable bloatware services + clear temp files
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
if (Test-PhaseEnabled 'Services') {
Write-Log "[Cleanup] Disabling bloatware services..." "SECTION"
Write-Rationale 'Services'

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
    'IsoEnvBroker',                 # Isolated Environment Broker (Agent Workspaces)

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
    foreach ($svcName in $servicesToDisable) {
        $svcObj = Get-Service -Name $svcName -EA 0
        if ($svcObj) {
            $script:manifest.changes.services_disabled.Add(@{
                name = $svcName
                original_startup_type = $svcObj.StartType.ToString()
            }) | Out-Null
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
