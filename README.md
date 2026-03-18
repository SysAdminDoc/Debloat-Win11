# Windows 11 Complete Debloat Script

**Version:** 2.0  
**Author:** SysAdminDoc
**Last Updated:** January 2025  
**Lines of Code:** 2,469  
**Compatibility:** Windows 10 (1903+) / Windows 11

---

## Overview

A comprehensive, production-ready PowerShell script designed to debloat, optimize, and configure Windows 10/11 workstations for professional environments. Originally developed for medical imaging workstations but suitable for any business deployment.

This script is **hardware-aware**, **non-destructive to user data**, and **safe for production use**. It detects system configuration (laptop vs desktop, SSD vs HDD, OneDrive/Office usage) and applies appropriate optimizations automatically.

### Why This Script?

| Problem | Solution |
|---------|----------|
| Windows ships with bloatware | Removes 80+ unnecessary apps |
| OEM PCs have manufacturer bloat | Nuclear cleanup of Dell, HP, Lenovo, ASUS, Acer, MSI, Razer |
| Telemetry and ads everywhere | Comprehensive privacy hardening |
| Generic power settings | Hardware-aware optimization (laptop vs desktop, SSD vs HDD) |
| No audit trail | Full logging to `C:\Maven\Logs` |
| Risk of breaking production PCs | Extensive safety testing, preserve in-use apps |

---

## Table of Contents

1. [Features at a Glance](#features-at-a-glance)
2. [Requirements](#requirements)
3. [Quick Start](#quick-start)
4. [Execution Phases](#execution-phases)
5. [Hardware Detection](#hardware-detection)
6. [Safety Features](#safety-features)
7. [Complete Removal List](#complete-removal-list)
8. [Preservation List](#preservation-list)
9. [Registry Modifications](#registry-modifications)
10. [Services Reference](#services-reference)
11. [Logging System](#logging-system)
12. [Exit Codes](#exit-codes)
13. [Deployment Guide](#deployment-guide)
14. [Customization Guide](#customization-guide)
15. [Troubleshooting](#troubleshooting)
16. [Recovery Procedures](#recovery-procedures)
17. [FAQ](#faq)
18. [Changelog](#changelog)

---

## Features at a Glance

### Detection & Safety
- ✅ Windows version verification
- ✅ Domain-joined awareness
- ✅ Disk space check
- ✅ Pending reboot detection
- ✅ SSD vs HDD detection
- ✅ Laptop vs Desktop detection
- ✅ OneDrive usage detection
- ✅ Office license detection
- ✅ Automatic restore point

### Bloatware Removal
- ✅ 80+ AppX packages
- ✅ 6 OEM manufacturers
- ✅ Social media apps
- ✅ Games and trials
- ✅ Xbox components
- ✅ Conditional OneDrive removal
- ✅ Conditional Office removal

### Privacy & Telemetry
- ✅ Windows telemetry
- ✅ Advertising ID
- ✅ Activity history
- ✅ Cortana/Copilot/Recall
- ✅ Bing search
- ✅ Silent app installs
- ✅ Start Menu ads

### Performance
- ✅ SSD-specific optimizations
- ✅ HDD-specific optimizations
- ✅ Background apps disabled
- ✅ Startup cleanup
- ✅ GameDVR disabled
- ✅ Reserved storage disabled

### UI Improvements
- ✅ Dark mode
- ✅ Left-aligned taskbar
- ✅ Classic context menu
- ✅ File extensions visible
- ✅ Hidden files visible
- ✅ Quick Access cleaned
- ✅ Widgets removed

### Power Management
- ✅ Hardware-aware settings
- ✅ Desktop: High Performance
- ✅ Laptop: Balanced with smart battery
- ✅ Fast startup disabled

### Network
- ✅ Nagle's algorithm disabled
- ✅ Private network profile
- ✅ Network discovery enabled
- ✅ Medical imaging firewall rules

### Windows Update
- ✅ Active hours (6 AM - 11 PM)
- ✅ Feature updates deferred 365 days
- ✅ Quality updates deferred 4 days
- ✅ No forced restarts

### Microsoft Edge
- ✅ 100+ policy settings
- ✅ Telemetry disabled
- ✅ Copilot disabled
- ✅ uBlock Origin installed
- ✅ Google as default
- ✅ Maven bookmarks added

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **Operating System** | Windows 10 (1903+) or Windows 11 |
| **PowerShell** | 5.1 or later (included in Windows) |
| **Privileges** | Administrator required |
| **Disk Space** | 5 GB free recommended |
| **Network** | Not required |

---

## Quick Start

### Option 1: Direct Execution
```powershell
# Run PowerShell as Administrator
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Debloat-Win11.ps1
```

### Option 2: One-Liner
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Debloat-Win11.ps1"
```

### Option 3: Remote/Network Share
```batch
powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "\\server\share\Debloat-Win11.ps1"
```

### Option 4: Encoded Command (for MDM)
```powershell
# Generate base64 encoded command
$command = 'Set-Location "C:\Scripts"; .\Debloat-Win11.ps1'
$bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
$encoded = [Convert]::ToBase64String($bytes)
# Use: powershell -EncodedCommand $encoded
```

---

## Execution Phases

The script runs in 7 distinct phases plus pre/post operations:

```
┌─────────────────────────────────────────────────────────────────┐
│  PRE-FLIGHT                                                     │
│  • Windows version check                                        │
│  • Domain detection                                             │
│  • Disk space check                                             │
│  • Pending reboot check                                         │
│  • RAM detection                                                │
│  • SSD/HDD detection                                            │
│  • Laptop/Desktop detection                                     │
│  • OneDrive usage check                                         │
│  • Office license check                                         │
│  • System restore point                                         │
├─────────────────────────────────────────────────────────────────┤
│  SYSTEM TWEAKS                                                  │
│  • Registry privacy settings                                    │
│  • Telemetry disabled                                           │
│  • UI customization                                             │
│  • Performance tweaks                                           │
│  • SSD/HDD optimizations                                        │
│  • Power settings (hardware-aware)                              │
│  • Network optimization                                         │
│  • Windows Update configuration                                 │
│  • Start Menu cleanup                                           │
│  • Notifications disabled                                       │
│  • Defender exclusions (medical imaging paths)                  │
│  • Default user profile configured                              │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 1/7: AppX Package Removal                                │
│  • 80+ bloatware packages                                       │
│  • User packages                                                │
│  • Provisioned packages                                         │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 2/7: OEM Nuclear Cleanup                                 │
│  • Dell, HP, Lenovo, ASUS, Acer, MSI, Razer                    │
│  • Services, tasks, folders, registry                          │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 3/7: OneDrive Removal (Conditional)                      │
│  • Skipped if in use                                            │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 4/7: Office Removal (Conditional)                        │
│  • Skipped if licensed                                          │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 5/7: Microsoft Edge Configuration                        │
│  • 100+ Group Policy settings                                   │
│  • uBlock Origin installation                                   │
│  • Bookmarks configuration                                      │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 6/7: Firewall Rules                                      │
│  • 21 rules for medical imaging                                 │
├─────────────────────────────────────────────────────────────────┤
│  PHASE 7/7: Privacy Cleanup                                     │
│  • Browser cache                                                │
│  • Event logs                                                   │
│  • Diagnostic data                                              │
├─────────────────────────────────────────────────────────────────┤
│  POST-OPERATIONS                                                │
│  • Disable 45+ bloatware services                               │
│  • Re-enable Windows Update                                     │
│  • Re-enable Windows Search                                     │
│  • Restart Explorer                                             │
│  • Log completion                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Hardware Detection

### Laptop vs Desktop

**Detection Method:**
1. Query `Win32_SystemEnclosure.ChassisTypes`
2. Fallback: Check `Win32_Battery` presence

**Chassis Type Mapping:**

| Type IDs | Classification |
|----------|----------------|
| 8, 9, 10, 11, 14 | Laptop/Notebook |
| 30, 31, 32 | Tablet/Convertible |
| 3, 4, 5, 6, 7 | Desktop |
| 13, 15, 16 | All-in-One |
| 17, 23, 24 | Server/Rack |

### Power Settings Applied

**Desktop/Workstation:**
```
Power Plan:       High Performance
USB Suspend:      Disabled
Hard Disk:        Never sleep
Monitor:          30 minutes
Sleep:            Never
Hibernate:        Disabled
Power Button:     Shut Down
Fast Startup:     Disabled
```

**Laptop - AC Power:**
```
Power Plan:       Balanced
USB Suspend:      Disabled
Hard Disk:        Never sleep
Monitor:          15 minutes
Sleep:            Never
Hibernate:        Never
Lid Close:        Do Nothing
```

**Laptop - Battery:**
```
USB Suspend:      Enabled (save power)
Hard Disk:        10 minutes
Monitor:          5 minutes
Sleep:            15 minutes
Hibernate:        60 minutes
Lid Close:        Sleep
Critical Battery: Hibernate at 5%
Low Battery:      Warning at 10%
```

### SSD vs HDD

**Detection Method:**
1. Query `Get-PhysicalDisk` MediaType
2. Fallback: `MSFT_PhysicalDisk` WMI class

**SSD Optimizations:**
- Superfetch (SysMain): **Disabled**
- Prefetch: **Disabled**
- TRIM: **Enabled**
- Last Access Timestamp: **Disabled**

**HDD Optimizations:**
- Superfetch (SysMain): **Enabled** (improves performance)
- Prefetch: **Enabled**

---

## Safety Features

### Why This Script is Production-Safe

| Feature | Description |
|---------|-------------|
| **Restore Point** | Created automatically before changes |
| **OneDrive Detection** | Checks for accounts and files before removal |
| **Office Detection** | Checks for license and running apps before removal |
| **Hardware Detection** | Applies appropriate settings for device type |
| **Service Whitelist** | Critical services are never touched |
| **App Whitelist** | Useful apps are preserved |
| **Logging** | Full audit trail in C:\Maven\Logs |
| **Exit Codes** | Deployment tools can verify success |

### Services Explicitly NOT Disabled

| Service | Why It's Preserved |
|---------|-------------------|
| iphlpsvc | IPv6 connectivity (some networks require it) |
| ShellHWDetection | USB drive auto-detection |
| WinHttpAutoProxySvc | Enterprise proxy auto-discovery |
| SSDPSRV | UPnP discovery (medical devices use this) |
| WbioSrvc | Fingerprint/biometric login |
| TabletInputService | Touch screen and pen input |
| TapiSrv | VoIP and telephony applications |

### Apps Explicitly Preserved

| App | Why It's Preserved |
|-----|-------------------|
| Quick Assist | IT remote support tool |
| Sticky Notes | Lightweight and useful |
| Alarms & Clock | Timer functionality |
| Sound Recorder | Audio recording |
| Calculator | Essential utility |
| Photos | Image viewing |
| Snipping Tool | Screenshot utility |
| Notepad | Text editing |
| Paint | Image editing |
| Terminal | Command line |

### Business App Startup Preserved

The following startup entries are **NOT** removed:
- Microsoft Teams
- Zoom
- Slack
- Cisco WebEx

---

## Complete Removal List

### AppX Packages Removed (80+)

<details>
<summary><b>Click to expand full list</b></summary>

**Microsoft Apps:**
- Clipchamp
- Microsoft.3DBuilder
- Microsoft.549981C3F5F10 (Cortana)
- Microsoft.BingFinance
- Microsoft.BingNews
- Microsoft.BingSports
- Microsoft.BingWeather
- Microsoft.BingSearch
- Microsoft.Copilot
- Microsoft.GamingApp
- Microsoft.GetHelp
- Microsoft.Getstarted
- Microsoft.Messaging
- Microsoft.Microsoft3DViewer
- Microsoft.MicrosoftOfficeHub
- Microsoft.MicrosoftSolitaireCollection
- Microsoft.MixedReality
- Microsoft.Office.OneNote
- Microsoft.OneConnect
- Microsoft.OutlookForWindows
- Microsoft.People
- Microsoft.PowerAutomateDesktop
- Microsoft.Print3D
- Microsoft.SkypeApp
- Microsoft.Todos
- Microsoft.Wallet
- Microsoft.Windows.DevHome
- Microsoft.WindowsCamera
- Microsoft.windowscommunicationsapps
- Microsoft.WindowsFeedbackHub
- Microsoft.WindowsMaps
- Microsoft.Xbox (all variants)
- Microsoft.YourPhone
- Microsoft.ZuneMusic
- Microsoft.ZuneVideo
- Microsoft.Edge.GameAssist
- Microsoft.WidgetsPlatformRuntime
- MicrosoftCorporationII.MicrosoftFamily
- MicrosoftWindows.Client.WebExperience
- MicrosoftWindows.CrossDevice
- MicrosoftTeams

**Third-Party:**
- Disney+
- Spotify
- Facebook
- Instagram
- TikTok
- Netflix
- Amazon
- Twitter
- LinkedIn
- CandyCrush
- BubbleWitch
- FarmVille
- RoyalRevolt
- Sway

**OEM:**
- All Dell apps
- All HP apps
- All Lenovo apps
- All ASUS apps
- All Acer apps
- All MSI apps
- All Razer apps
- Intel Graphics Experience
- Intel Optane
- Realtek Audio Console
- Dolby Access
- Waves Audio

</details>

### Services Disabled (45+)

<details>
<summary><b>Click to expand full list</b></summary>

```
# Telemetry & Diagnostics
DiagTrack                 # Connected User Experiences and Telemetry
dmwappushservice          # WAP Push Message Routing
DPS                       # Diagnostic Policy Service
WdiSystemHost             # Diagnostic System Host
WdiServiceHost            # Diagnostic Service Host
InventorySvc              # Inventory and Compatibility Appraisal
WaaSMedicSvc              # Windows Update Medic Service

# Xbox & Gaming
XblAuthManager            # Xbox Live Auth Manager
XblGameSave               # Xbox Live Game Save
XboxGipSvc                # Xbox Accessory Management
XboxNetApiSvc             # Xbox Live Networking
GamingServices            # Gaming Services
GamingServicesNet         # Gaming Services Network

# Unused Features
CDPSvc                    # Connected Devices Platform
CDPUserSvc                # Connected Devices Platform (per-user)
DoSvc                     # Delivery Optimization
TrkWks                    # Distributed Link Tracking Client
NPSMSvc                   # Now Playing Session Manager
RmSvc                     # Radio Management Service
OneSyncSvc                # Sync Host
lmhosts                   # TCP/IP NetBIOS Helper
WSAIFabricSvc             # Windows Subsystem for Android

# Other Bloat
lfsvc                     # Geolocation Service
Fax                       # Fax Service
WMPNetworkSvc             # Windows Media Player Network Sharing
icssvc                    # Windows Mobile Hotspot
WerSvc                    # Windows Error Reporting
wisvc                     # Windows Insider Service
RetailDemo                # Retail Demo Service
MapsBroker                # Downloaded Maps Manager
PhoneSvc                  # Phone Service
AJRouter                  # AllJoyn Router Service
WalletService             # WalletService
RemoteRegistry            # Remote Registry
WpcMonSvc                 # Parental Controls
SharedAccess              # Internet Connection Sharing
MessagingService          # Text Messaging
PcaSvc                    # Program Compatibility Assistant
SEMgrSvc                  # Payments and NFC/SE Manager
SmsRouter                 # Microsoft Windows SMS Router
```

</details>

### Scheduled Tasks Disabled (30+)

<details>
<summary><b>Click to expand full list</b></summary>

```
# Xbox
XblGameSaveTask

# Edge
MicrosoftEdgeUpdateTaskMachineCore*
MicrosoftEdgeUpdateTaskMachineUA*

# Telemetry
Consolidator
UsbCeip
Microsoft Compatibility Appraiser
ProgramDataUpdater
KernelCeipTask
AitAgent
PcaPatchDbTask
SdbinstMergeDbTask
QueueReporting

# Feedback
Uploader
DmClient
DmClientOnScenarioDownload

# Maps
MapsToastTask
MapsUpdateTask

# Other
StartupAppTask
CleanupTemporaryState
SpeechModelDownloadTask
FamilySafetyMonitor
FamilySafetyRefresh
FamilySafetyUpload
CreateObjectTask

# Task Paths Disabled
\Microsoft\Windows\Customer Experience Improvement Program\*
\Microsoft\Windows\Application Experience\*
\Microsoft\Windows\Feedback\Siuf\*
\Microsoft\Windows\Windows Error Reporting\*
\Microsoft\Windows\DiskDiagnostic\*
\Microsoft\Windows\CloudExperienceHost\*
```

</details>

### Windows Features Disabled

| Feature | Reason |
|---------|--------|
| Internet-Explorer-Optional-amd64 | Legacy, security risk |
| MicrosoftWindowsPowerShellV2Root | Security risk |
| MicrosoftWindowsPowerShellV2 | Security risk |
| MediaPlayback | Legacy Windows Media Player |
| WindowsMediaPlayer | Legacy |
| WorkFolders-Client | Enterprise feature |
| Printing-XPSServices-Features | XPS rarely used |
| SMB1Protocol | Security risk |
| SMB1Protocol-Client | Security risk |
| SMB1Protocol-Server | Security risk |

### Context Menu Items Removed

- Edit with Paint 3D
- Edit with Photos
- Share
- Give access to
- Include in library
- Restore previous versions
- Add to Favorites
- Troubleshoot compatibility
- Bluetooth File Transfer (Send To)
- Fax Recipient (Send To)

### Startup Items Removed

- Spotify
- Discord
- Steam
- Epic Games Launcher
- Adobe GC Invoker
- Adobe Creative Cloud
- Adobe AAM Updater
- iTunes Helper
- Skype
- Cisco Meeting Daemon
- Google Update
- Opera
- Brave
- CCleaner
- Dropbox Update
- Lync
- CyberLink

---

## Preservation List

### Always Preserved

**System Components:**
- Windows Defender
- Windows Firewall
- BitLocker
- Windows Update (configured, not disabled)
- Windows Search (temporarily disabled, re-enabled)
- SmartScreen

**Essential Apps:**
- Calculator
- Notepad
- Paint
- Snipping Tool / Snip & Sketch
- Photos
- Terminal / PowerShell
- File Explorer
- Settings
- Microsoft Store (functional)
- Quick Assist
- Sticky Notes
- Alarms & Clock
- Sound Recorder

### Conditionally Preserved

| Component | Preserved If |
|-----------|--------------|
| OneDrive | Account signed in OR files exist |
| Office | Licensed OR in use OR apps running |
| Teams | Startup entry preserved |
| Zoom | Startup entry preserved |
| Slack | Startup entry preserved |

---

## Registry Modifications

### HKEY_LOCAL_MACHINE

<details>
<summary><b>Click to expand registry details</b></summary>

**Privacy & Telemetry:**
```
SOFTWARE\Policies\Microsoft\Windows\DataCollection
    AllowTelemetry = 0

SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection
    AllowTelemetry = 0

SOFTWARE\Policies\Microsoft\Windows\System
    EnableActivityFeed = 0
    PublishUserActivities = 0

SOFTWARE\Policies\Microsoft\Windows\CloudContent
    DisableWindowsConsumerFeatures = 1
```

**Windows Update:**
```
SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
    DeferFeatureUpdates = 1
    DeferFeatureUpdatesPeriodInDays = 365
    DeferQualityUpdates = 1
    DeferQualityUpdatesPeriodInDays = 4
    ExcludeWUDriversInQualityUpdate = 1
    ManagePreviewBuilds = 1
    ManagePreviewBuildsPolicyValue = 0

SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
    NoAutoRebootWithLoggedOnUsers = 1
    AUOptions = 2

SOFTWARE\Microsoft\WindowsUpdate\UX\Settings
    ActiveHoursStart = 6
    ActiveHoursEnd = 23
```

**Edge (100+ settings):**
```
SOFTWARE\Policies\Microsoft\Edge
    DiagnosticData = 0
    PersonalizationReportingEnabled = 0
    EdgeCopilotEnabled = 0
    HubsSidebarEnabled = 0
    EdgeShoppingAssistantEnabled = 0
    # ... 95+ more settings
```

**Network:**
```
SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*
    TcpAckFrequency = 1
    TCPNoDelay = 1
```

</details>

### HKEY_CURRENT_USER

<details>
<summary><b>Click to expand registry details</b></summary>

**Explorer:**
```
SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced
    TaskbarAl = 0                    # Left-aligned taskbar
    ShowTaskViewButton = 0           # Hide Task View
    TaskbarDa = 0                    # Hide Widgets
    TaskbarMn = 0                    # Hide Chat
    HideFileExt = 0                  # Show extensions
    Hidden = 1                       # Show hidden files
    LaunchTo = 1                     # Open to This PC
```

**Privacy:**
```
SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo
    Enabled = 0

SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager
    SubscribedContent-310093Enabled = 0
    SubscribedContent-338387Enabled = 0
    SubscribedContent-338388Enabled = 0
    SubscribedContent-338389Enabled = 0
    SubscribedContent-338393Enabled = 0
    SubscribedContent-353694Enabled = 0
    SubscribedContent-353696Enabled = 0
    SilentInstalledAppsEnabled = 0
    SoftLandingEnabled = 0
```

**Search:**
```
SOFTWARE\Microsoft\Windows\CurrentVersion\Search
    BingSearchEnabled = 0
    SearchboxTaskbarMode = 3
```

**Themes:**
```
SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize
    AppsUseLightTheme = 0
    SystemUsesLightTheme = 0
```

</details>

---

## Services Reference

### Services Disabled by This Script

| Service | Display Name | Purpose | Why Disabled |
|---------|--------------|---------|--------------|
| DiagTrack | Connected User Experiences and Telemetry | Sends diagnostic data to Microsoft | Privacy |
| dmwappushservice | Device Management WAP Push | Enterprise push messaging | Unused |
| DPS | Diagnostic Policy Service | Troubleshooting detection | Reduces overhead |
| WdiSystemHost | Diagnostic System Host | Diagnostic execution | Reduces overhead |
| WdiServiceHost | Diagnostic Service Host | Diagnostic execution | Reduces overhead |
| InventorySvc | Inventory and Compatibility Appraisal | Hardware/software inventory | Telemetry |
| WaaSMedicSvc | Windows Update Medic | Repairs Windows Update | Unnecessary on clean install |
| XblAuthManager | Xbox Live Auth Manager | Xbox Live authentication | Gaming bloat |
| XblGameSave | Xbox Live Game Save | Xbox cloud saves | Gaming bloat |
| XboxGipSvc | Xbox Accessory Management | Xbox controller features | Gaming bloat |
| XboxNetApiSvc | Xbox Live Networking | Xbox Live connectivity | Gaming bloat |
| GamingServices | Gaming Services | Windows gaming features | Gaming bloat |
| GamingServicesNet | Gaming Services Network | Gaming network features | Gaming bloat |
| CDPSvc | Connected Devices Platform | Device pairing | Rarely used |
| DoSvc | Delivery Optimization | P2P update sharing | Privacy/bandwidth |
| TrkWks | Distributed Link Tracking Client | NTFS link tracking | Rarely needed |
| OneSyncSvc | Sync Host | Mail/Calendar sync | Unused if not using Mail |
| lmhosts | TCP/IP NetBIOS Helper | NetBIOS name resolution | Legacy protocol |
| lfsvc | Geolocation Service | Location tracking | Privacy |
| Fax | Fax | Fax service | Rarely used |
| WMPNetworkSvc | Windows Media Player Network Sharing | Media streaming | Rarely used |
| WerSvc | Windows Error Reporting | Crash reports to Microsoft | Privacy |
| wisvc | Windows Insider Service | Insider builds | Stability |
| MapsBroker | Downloaded Maps Manager | Offline maps | Rarely used |
| RemoteRegistry | Remote Registry | Remote registry editing | Security risk |

### Services NOT Disabled (Critical)

| Service | Display Name | Why Preserved |
|---------|--------------|---------------|
| iphlpsvc | IP Helper | IPv6 connectivity, some networks require it |
| ShellHWDetection | Shell Hardware Detection | USB drive auto-detect |
| WinHttpAutoProxySvc | WinHTTP Web Proxy Auto-Discovery | Enterprise proxy detection |
| SSDPSRV | SSDP Discovery | UPnP device discovery, medical equipment |
| WbioSrvc | Windows Biometric Service | Fingerprint/face login |
| TabletInputService | Touch Keyboard and Handwriting | Touch/pen input |
| TapiSrv | Telephony | VoIP applications |

---

## Logging System

### Log Location
```
C:\Maven\Logs\Debloat-YYYY-MM-DD-HHmmss.log
```

### Log Format
```
[TIMESTAMP] [LEVEL] Message
```

### Log Levels

| Level | Console Color | Description |
|-------|---------------|-------------|
| INFO | Cyan | Informational messages |
| SUCCESS | Green | Operation completed successfully |
| WARNING | Yellow | Non-critical warning |
| ERROR | Red | Error occurred (sets exit code 1) |
| SECTION | Yellow | Phase/section header |

### Sample Log Output
```
[2025-01-31 10:30:45] [INFO] === WINDOWS DEBLOAT STARTING ===
[2025-01-31 10:30:45] [INFO] Log file: C:\Maven\Logs\Debloat-2025-01-31-103045.log
[2025-01-31 10:30:46] [INFO] [Pre-Check] Windows version: Windows 11 Pro (Build 22631)
[2025-01-31 10:30:46] [INFO] [Pre-Check] Workgroup PC (not domain-joined)
[2025-01-31 10:30:47] [INFO] [Pre-Flight] Running system checks...
[2025-01-31 10:30:47] [INFO]   Disk space: 245.67 GB free of 476.94 GB
[2025-01-31 10:30:47] [INFO]   No pending reboot
[2025-01-31 10:30:47] [INFO]   Total RAM: 32 GB
[2025-01-31 10:30:48] [SUCCESS]   Storage: SSD detected - will apply SSD optimizations
[2025-01-31 10:30:49] [INFO]   Hardware: Desktop
[2025-01-31 10:30:49] [INFO]   System: Dell Inc. OptiPlex 7090
[2025-01-31 10:30:50] [SUCCESS]   Power settings will be optimized for WORKSTATION
[2025-01-31 10:30:51] [INFO] [Pre-Check] Checking OneDrive status...
[2025-01-31 10:30:51] [INFO]   OneDrive not in use - will be removed
[2025-01-31 10:30:52] [INFO] [Pre-Check] Checking Office status...
[2025-01-31 10:30:52] [SUCCESS]   Office 365 subscription detected: O365ProPlusRetail
[2025-01-31 10:30:52] [SUCCESS]   Office will be PRESERVED
[2025-01-31 10:30:53] [SUCCESS]   Restore point created
[2025-01-31 10:30:54] [SECTION] [Phase 1/7] Removing bloatware packages...
...
[2025-01-31 10:45:23] [INFO] === DEBLOAT COMPLETE ===
[2025-01-31 10:45:23] [INFO] Exit code: 0
```

---

## Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | All operations completed without errors |
| 1 | Partial | Script completed but some operations failed |
| 2 | Failed | Critical error, script aborted |

### Using Exit Codes in Deployment

**Batch Script:**
```batch
powershell -ExecutionPolicy Bypass -File "Debloat-Win11.ps1"
IF %ERRORLEVEL% EQU 0 (
    echo SUCCESS: Debloat completed
) ELSE IF %ERRORLEVEL% EQU 1 (
    echo WARNING: Debloat completed with errors - check log
) ELSE (
    echo ERROR: Debloat failed
)
```

**PowerShell:**
```powershell
$result = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"Debloat-Win11.ps1`"" -Wait -PassThru
switch ($result.ExitCode) {
    0 { Write-Host "Success" -ForegroundColor Green }
    1 { Write-Host "Partial success - check logs" -ForegroundColor Yellow }
    2 { Write-Host "Failed" -ForegroundColor Red }
}
```

**PDQ Deploy:** Set success codes to `0` and `1`, failure code to `2`

**SCCM/Intune:** Configure detection based on exit code 0

---

## Deployment Guide

### PDQ Deploy

1. Create new package
2. Add PowerShell step:
   - Script: `Debloat-Win11.ps1`
   - Parameters: `-ExecutionPolicy Bypass`
3. Set success codes: `0, 1`
4. Enable "Run As: Deploy User (Interactive)"

### Microsoft Intune

1. Create Win32 app package (use IntuneWinAppUtil)
2. Install command: `powershell.exe -ExecutionPolicy Bypass -File "Debloat-Win11.ps1"`
3. Detection rule: File exists `C:\Maven\Logs\Debloat-*.log`
4. Requirements: Windows 10 1903+

### SCCM/ConfigMgr

1. Create Package with source files
2. Create Program:
   - Command: `powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "Debloat-Win11.ps1"`
   - Run: Hidden
3. Deploy to collection

### Group Policy (Startup Script)

1. Copy script to NETLOGON or accessible share
2. Computer Configuration → Policies → Windows Settings → Scripts → Startup
3. Add PowerShell script
4. Parameters: `-ExecutionPolicy Bypass -File "\\server\share\Debloat-Win11.ps1"`

---

## Customization Guide

### Preserving Specific Apps

Edit the `$removePatterns` array (around line 1278):

```powershell
$removePatterns = @(
    '*Clipchamp*',
    '*Microsoft.BingNews*',
    # '*Microsoft.WindowsMaps*',  # Commented = PRESERVED
    '*Microsoft.ZuneMusic*',
)
```

### Adding Apps to Remove

```powershell
$removePatterns = @(
    ...existing patterns...
    '*YourApp.Name*',  # Add your pattern
)
```

### Changing Power Settings

Search for "POWER SETTINGS" (around line 885):

```powershell
# Change desktop monitor timeout to 60 minutes (3600 seconds)
powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 3600
```

### Changing Windows Update Deferrals

Search for "WINDOWS UPDATE CONTROL" (around line 603):

```powershell
# Defer feature updates 180 days instead of 365
Set-Reg -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value 180
```

### Adding Defender Exclusions

Edit `$defenderExclusions` array (around line 865):

```powershell
$defenderExclusions = @(
    "C:\images",
    "C:\Maven",
    "C:\YourPath",  # Add your path
)
```

### Adding Edge Bookmarks

Edit `$mavenBookmarks` array (around line 1897):

```powershell
$mavenBookmarks = @(
    @{ name = "Support"; url = "https://www.mavenimaging.com/support" }
    @{ name = "Your Site"; url = "https://your-site.com" }  # Add bookmark
)
```

### Keeping a Service Running

Remove it from `$servicesToDisable` array (around line 2030):

```powershell
$servicesToDisable = @(
    'DiagTrack',
    # 'DoSvc',  # Commented = KEPT RUNNING
    'WerSvc',
)
```

---

## Troubleshooting

### Script Won't Start

**Error:** "Running scripts is disabled"
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

**Error:** "Access denied"
- Right-click PowerShell → Run as Administrator

**Error:** "Script requires Windows 10"
- Script requires Windows 10 version 1903 or later
- Check: `winver`

### OneDrive Not Removed

**Cause:** OneDrive is in use

**Check log for:**
```
OneDrive in use: Personal account (email@example.com)
OneDrive will be PRESERVED
```

**Solution:** Sign out of OneDrive first, or manually remove

### Office Not Removed

**Cause:** Office is licensed or in use

**Check log for:**
```
Office 365 subscription detected: O365ProPlusRetail
Office will be PRESERVED
```

**Solution:** This is intentional - licensed Office should be kept

### Edge Settings Not Applied

**Cause:** Edge profile doesn't exist

**Solution:** Script creates profile automatically, but if it fails:
```powershell
Start-Process msedge -ArgumentList "--no-first-run"
Start-Sleep 5
Stop-Process -Name msedge -Force
# Re-run script
```

### Apps Reinstall After Updates

**Cause:** Normal Windows behavior

**Solution:** Re-run script after major Windows updates

### Network Issues After Script

**Check if needed services were disabled:**
```powershell
# Re-enable if needed
Set-Service -Name "iphlpsvc" -StartupType Automatic
Start-Service -Name "iphlpsvc"
```

---

## Recovery Procedures

### System Restore

1. Press `Win + R`, type `rstrui`
2. Select "Pre-Debloat" restore point
3. Follow wizard

### Re-enable a Service

```powershell
Set-Service -Name "ServiceName" -StartupType Automatic
Start-Service -Name "ServiceName"
```

### Reinstall a Removed App

```powershell
# From Microsoft Store
winget install "App Name"

# Or via PowerShell
Get-AppxPackage -AllUsers *AppName* | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"
}
```

### Reset Windows Update Settings

```powershell
Remove-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Recurse -Force
Restart-Service wuauserv
```

### Reset Edge Settings

```powershell
Remove-Item "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force
# Restart Edge
```

---

## FAQ

**Q: Is this safe for production?**
A: Yes. Extensively tested on medical imaging workstations. Creates restore point, detects in-use apps, preserves critical functionality.

**Q: Will it break Windows Update?**
A: No. Updates are deferred (not disabled) and active hours prevent forced restarts.

**Q: Can I run on domain-joined PCs?**
A: Yes, but Group Policy may override some settings. Script logs a warning.

**Q: How long does it take?**
A: 5-15 minutes depending on installed bloatware.

**Q: Can I run it multiple times?**
A: Yes, script is idempotent.

**Q: Will it delete my files?**
A: No. Only system apps and settings are modified. User files are never touched.

**Q: Why is OneDrive still there?**
A: Script detected active use. Check log for details.

**Q: Does it work on Windows 10?**
A: Yes, Windows 10 1903+ is supported.

**Q: How do I undo everything?**
A: Use System Restore to the "Pre-Debloat" restore point.

---

## Changelog

### Version 2.0 (January 2025)

**New Features:**
- Hardware detection (laptop/desktop, SSD/HDD)
- Pre-flight checks (disk space, pending reboot, RAM)
- Comprehensive logging system
- Exit codes for deployment tools
- OneDrive/Office usage detection
- Windows Update deferrals
- SSD-specific optimizations
- Start Menu cleanup
- Widgets removal (Windows 11)
- Startup apps cleanup
- Context menu cleanup
- Windows optional features disabling
- Default user profile configuration

**OEM Support Added:**
- ASUS (Armoury Crate, MyASUS, ROG)
- Acer (Care Center, Quick Access)
- MSI (Dragon Center, Mystic Light)
- Razer (Synapse, Cortex)

**Safety Improvements:**
- Preserved critical services (iphlpsvc, ShellHWDetection, etc.)
- Preserved useful apps (Quick Assist, Sticky Notes, etc.)
- Preserved business app startup entries
- Removed IPv6 disable (can break networks)
- Hardware-aware hibernation setting

**Total Lines:** 2,469

### Version 1.0 (Initial Release)
- Basic debloat functionality
- AppX removal
- Service disabling
- Registry tweaks

---

## License

This script is provided as-is for use by Maven Imaging and authorized partners. No warranty is provided. Test in non-production environment first.

---

## Support

**Maven Imaging Support:**
- Web: https://www.mavenimaging.com/support
- Portal: https://app.patientimage.ai/login

---

*Documentation last updated: January 31, 2025*
