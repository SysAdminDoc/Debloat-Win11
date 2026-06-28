#Requires -RunAsAdministrator
#Requires -Version 5.1

# Debloat-Win11 Maintenance Script
# Re-applies privacy/telemetry registry tweaks that Windows Update resets.
# Designed to run as a scheduled task after Windows Update completes.
# Does NOT remove apps or delete files -- registry tweaks only.
# Applies HKLM policies machine-wide and HKCU tweaks to all user profiles.

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
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -EA 0
        Write-MaintainLog "  Reset: $Path\$Name = $Value"
        $script:count++
    }
}

$windowsAiPolicyFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Modules\WindowsAiPolicies.psd1'
$windowsAiPolicies = if (Test-Path $windowsAiPolicyFile) {
    & ([scriptblock]::Create((Get-Content $windowsAiPolicyFile -Raw)))
} else {
    @()
}

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

# Load shared definitions so both scripts stay in sync
$hkcuDataFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Modules\HkcuTweaks.psd1'
if (Test-Path $hkcuDataFile) {
    $hkcuTweaks = & ([scriptblock]::Create((Get-Content $hkcuDataFile -Raw)))
} else {
    Write-MaintainLog "  WARNING: HkcuTweaks.psd1 not found, using inline fallback"
    $hkcuTweaks = @(
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Value = 0 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Value = 0 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Value = 0 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Value = 0 }
        @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0 }
        @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'ContentDeliveryAllowed'; Value = 0 }
    )
}

# Apply to currently-logged-in user via HKCU (covers the interactive session)
foreach ($tweak in $hkcuTweaks) {
    Set-RegMaintain -Path "HKCU:\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value
}

# Apply to all user profile NTUSER.DAT files (covers users not currently logged in)
$userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default User|All Users)$' }
foreach ($userProf in $userProfiles) {
    $ntuser = "$($userProf.FullName)\NTUSER.DAT"
    if (!(Test-Path $ntuser)) { continue }

    $hiveName = "HKU\Maintain_$($userProf.Name -replace '[^a-zA-Z0-9]','_')"
    reg load $hiveName $ntuser 2>$null
    if ($LASTEXITCODE -ne 0) { continue }

    foreach ($tweak in $hkcuTweaks) {
        $regPath = "$hiveName\$($tweak.Path)"
        reg add $regPath /v $tweak.Name /t REG_DWORD /d $tweak.Value /f 2>$null | Out-Null
    }

    [gc]::Collect()
    Start-Sleep -Milliseconds 200
    reg unload $hiveName 2>$null
    $count++
    Write-MaintainLog "  Applied tweaks to profile: $($userProf.Name)"
}

# Also apply to Default profile (new user accounts)
$defaultHive = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultHive) {
    $hiveName = "HKU\Maintain_Default"
    reg load $hiveName $defaultHive 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($tweak in $hkcuTweaks) {
            reg add "$hiveName\$($tweak.Path)" /v $tweak.Name /t REG_DWORD /d $tweak.Value /f 2>$null | Out-Null
        }
        [gc]::Collect()
        Start-Sleep -Milliseconds 200
        reg unload $hiveName 2>$null
        Write-MaintainLog "  Applied tweaks to Default profile"
    }
}

Write-MaintainLog "=== MAINTENANCE COMPLETE: $count settings re-applied ==="

$msg = "Debloat-Win11 maintenance: $count registry settings re-applied after Windows Update"
Write-EventLog -LogName 'Application' -Source $eventSource -EventId 1002 -EntryType Information -Message $msg -EA 0
