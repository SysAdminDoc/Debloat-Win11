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

foreach ($svc in $servicesToDisable) {
    # Sequential execution keeps each service result and verification tied to its snapshot.
    Disable-ServiceDryRun -ServiceName $svc
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
# TEMP FILE CLEANUP (runs with Privacy phase)
# ============================================================================
if (Test-PhaseEnabled 'Privacy') {
Write-Log "[Cleanup] Clearing temp files..." "SECTION"
$allowTempCleanup = Test-IrreversibleOperationAllowed -Name 'Temporary file cleanup'

if ($DryRun) {
    $tempCleanupResult = Invoke-TrackedOperation -Name 'Temporary file cleanup' -Action 'Delete temp, prefetch, update, and delivery caches' -Scope 'Mixed' -Operation { }
    Write-Log "  [DRY RUN] Would clear temp, prefetch, WU cache, and delivery optimization cache" "INFO"
} elseif ($allowTempCleanup) {
    $tempCleanupResult = Invoke-TrackedOperation -Name 'Temporary file cleanup' -Action 'Delete temp, prefetch, update, and delivery caches' -Scope 'Mixed' -Operation {
        @(
            "$env:TEMP\*",
            "C:\Windows\Temp\*",
            "C:\Windows\SoftwareDistribution\Download\*",
            "C:\Windows\Prefetch\*",
            "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\*"
        ) | ForEach-Object {
            Get-ChildItem -Path $_ -Force -EA 0 | Remove-Item -Recurse -Force -EA Stop
        }

        $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA Stop | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
        foreach ($userProf in $userProfiles) {
            Get-ChildItem -Path "$($userProf.FullName)\AppData\Local\Temp\*" -Force -EA 0 | Remove-Item -Recurse -Force -EA Stop
        }

        Stop-Service -Name wuauserv -Force -EA Stop
    } | Out-Null
} else {
    $tempCleanupResult = $false
    Write-Log "  Temp file cleanup skipped (explicit approval required)" "WARNING"
}

if ($tempCleanupResult -and -not $DryRun) { Write-Log "  Temp files cleared" "SUCCESS" }
} else { Write-Log "[Cleanup] Temp cleanup SKIPPED (Privacy phase excluded)" "INFO" }
