#Requires -RunAsAdministrator
#Requires -Version 5.1

# Debloat-Win11 Maintenance Script
# Re-applies privacy/telemetry registry tweaks that Windows Update resets.
# Designed to run as a scheduled task after Windows Update completes.
# Does NOT remove apps or delete files -- registry tweaks only.
# Applies HKLM policies machine-wide and HKCU tweaks to all user profiles.

[CmdletBinding()]
param(
    [ValidateSet('Text','Json','Csv')]
    [string]$OutputFormat = 'Text'
)

$ErrorActionPreference = "SilentlyContinue"
$logDir = "$env:ProgramData\Debloat-Win11\Logs"
if (!(Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = "$logDir\Debloat-Maintain-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"

function Write-MaintainLog {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -Path $logFile -Value $entry -EA 0
}

$eventSource = 'Debloat-Win11'
if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    try { New-EventLog -LogName 'Application' -Source $eventSource -EA Stop } catch {}
}

Write-MaintainLog "=== MAINTENANCE RUN STARTING ==="
$count = 0

function Set-RegMaintain {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $current = Get-ItemProperty -Path $Path -Name $Name -EA 0
    if ($null -eq $current -or $current.$Name -ne $Value) {
        Set-DebloatRegistryProperty -Path $Path -Name $Name -Value $Value -Type $Type -EA Stop
        Write-MaintainLog "  Reset: $Path\$Name = $Value"
        $script:count++
    }
}

$policyCatalogFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Modules\PolicyCatalog.psd1'
$policyCatalog = if (Test-Path $policyCatalogFile) { Import-PowerShellDataFile -Path $policyCatalogFile } else { @{} }
$windowsAiPolicies = @($policyCatalog.Policies)
$profileHelperFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'tools\ProfileHive.ps1'
if (Test-Path $profileHelperFile) { . $profileHelperFile }

# ============================================================================
# HKLM POLICIES (machine-wide, work regardless of which user is logged in)
# ============================================================================

# Privacy & Telemetry
Set-RegMaintain -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0

# Copilot / AI
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
foreach ($policy in ($windowsAiPolicies | Where-Object { $_.Scope -eq 'Device' -and $_.ApplyByDefault -ne $false })) {
    Set-RegMaintain -Path ('HKLM:\{0}' -f $policy.Path) -Name $policy.Name -Value $policy.Value -Type $policy.Type
}

# Bing Search (policy)
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1

# Consumer Features
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1

# Widgets
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0

# ============================================================================
# PER-USER HKCU TWEAKS (enumerate all user profiles, not just SYSTEM)
# ============================================================================
Write-MaintainLog "  Applying per-user HKCU tweaks..."

$hkcuTweaks = @($policyCatalog.HkcuTweaks)
if ($hkcuTweaks.Count -eq 0) { Write-MaintainLog "  WARNING: Policy catalog has no HKCU tweaks" }

function Get-HkcuTweakType {
    param([hashtable]$Tweak)
    if ($Tweak.ContainsKey('Type') -and $Tweak.Type) { return [string]$Tweak.Type }
    return 'DWord'
}

# Apply to all user profile NTUSER.DAT files (covers users not currently logged in)
$profileEnumerationError = $null
$userProfiles = @(Get-DebloatUserProfiles -ErrorMessage ([ref]$profileEnumerationError))
if ($profileEnumerationError) { Write-MaintainLog "  WARNING: $profileEnumerationError" }
$skippedProfiles = 0
foreach ($userProf in $userProfiles) {
    $session = Open-DebloatUserHive -UserProfile $userProf -Prefix 'DebloatMaintain'
    if ($session.Status -ne 'Ready') {
        $skippedProfiles++
        Write-MaintainLog "  SKIPPED profile $($userProf.Name): $($session.Reason)"
        continue
    }
    foreach ($tweak in $hkcuTweaks) {
        $tweakType = Get-HkcuTweakType -Tweak $tweak
        Set-RegMaintain -Path "$($session.Path)\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
    }
    $closeResult = Close-DebloatUserHive -Session $session
    if (-not $closeResult.Success) {
        $skippedProfiles++
        Write-MaintainLog "  WARNING: Could not close profile $($userProf.Name): $($closeResult.Reason)"
    } else {
        $profileType = if ($session.Temporary) { 'offline' } else { 'logged-in' }
        Write-MaintainLog "  Applied tweaks to $profileType profile: $($userProf.Name)"
    }
}

# Also apply to Default profile (new user accounts)
$defaultHive = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultHive) {
    $defaultProfile = [pscustomobject]@{
        Name = 'Default'
        SID = $null
        LocalPath = 'C:\Users\Default'
        NtUserPath = $defaultHive
        Loaded = $false
    }
    $session = Open-DebloatUserHive -UserProfile $defaultProfile -Prefix 'DebloatMaintain'
    if ($session.Status -eq 'Ready') {
        foreach ($tweak in $hkcuTweaks) {
            $tweakType = Get-HkcuTweakType -Tweak $tweak
            Set-RegMaintain -Path "$($session.Path)\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
        }
        $closeResult = Close-DebloatUserHive -Session $session
        if (-not $closeResult.Success) {
            $skippedProfiles++
            Write-MaintainLog "  WARNING: Could not close Default profile: $($closeResult.Reason)"
        } else {
            Write-MaintainLog "  Applied tweaks to Default profile"
        }
    } else {
        $skippedProfiles++
        Write-MaintainLog "  SKIPPED Default profile: $($session.Reason)"
    }
}

Write-MaintainLog "=== MAINTENANCE COMPLETE: $count settings re-applied; $skippedProfiles profiles skipped ==="

$msg = "Debloat-Win11 maintenance: $count registry settings re-applied; $skippedProfiles profiles skipped after Windows Update"
Write-EventLog -LogName 'Application' -Source $eventSource -EventId 1002 -EntryType Information -Message $msg -EA 0
$maintenanceStatus = if ($profileEnumerationError -or $skippedProfiles -gt 0) { 'Incomplete' } else { 'Success' }
$maintenanceResult = [ordered]@{
    schema_version = 1
    product = 'Debloat-Win11'
    status = $maintenanceStatus
    output_format = $OutputFormat
    settings_reapplied = $count
    skipped_profiles = $skippedProfiles
    profile_enumeration_error = $profileEnumerationError
    log_file = $logFile
    catalog_version = [string]$policyCatalog.CatalogVersion
}
if ($OutputFormat -eq 'Json') {
    Write-Output ($maintenanceResult | ConvertTo-Json -Depth 6 -Compress)
} elseif ($OutputFormat -eq 'Csv') {
    Write-Output (($maintenanceResult | ConvertTo-Csv -NoTypeInformation) -join "`n")
} else {
    Write-Output ("Debloat-Win11 maintenance: status={0} settings_reapplied={1} skipped_profiles={2}" -f $maintenanceStatus, $count, $skippedProfiles)
}
if ($maintenanceStatus -eq 'Success') { exit 0 }
exit 1
