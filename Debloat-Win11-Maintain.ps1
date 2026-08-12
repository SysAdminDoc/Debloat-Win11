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

$policyCatalogFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Modules\PolicyCatalog.psd1'
$policyCatalog = if (Test-Path $policyCatalogFile) { Import-PowerShellDataFile -Path $policyCatalogFile } else { @{} }
$windowsAiPolicies = @($policyCatalog.Policies)

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

function Get-LoadedUserHivePath {
    param([Parameter(Mandatory)][string]$ProfilePath)

    $normalizedProfilePath = $ProfilePath.TrimEnd('\')
    $profileRecord = Get-CimInstance -ClassName Win32_UserProfile -EA 0 |
        Where-Object {
            $_.Loaded -and $_.SID -and $_.LocalPath -and
            ($_.LocalPath.TrimEnd('\') -ieq $normalizedProfilePath)
        } | Select-Object -First 1

    if ($profileRecord) {
        $hivePath = "Registry::HKEY_USERS\$($profileRecord.SID)"
        if (Test-Path $hivePath) { return $hivePath }
    }

    # Fall back to the loaded HKU hives when WMI does not report the profile.
    foreach ($hive in @(Get-ChildItem 'Registry::HKEY_USERS' -EA 0 | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' })) {
        $profileList = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($hive.PSChildName)" -Name ProfileImagePath -EA 0
        if ($profileList) {
            $imagePath = [Environment]::ExpandEnvironmentVariables([string]$profileList.ProfileImagePath).TrimEnd('\')
            if ($imagePath -ieq $normalizedProfilePath) {
                return "Registry::HKEY_USERS\$($hive.PSChildName)"
            }
        }
    }

    return $null
}

# Apply to all user profile NTUSER.DAT files (covers users not currently logged in)
$userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default User|All Users)$' }
foreach ($userProf in $userProfiles) {
    $ntuser = "$($userProf.FullName)\NTUSER.DAT"
    if (!(Test-Path $ntuser)) { continue }

    $loadedHivePath = Get-LoadedUserHivePath -ProfilePath $userProf.FullName
    if ($loadedHivePath) {
        foreach ($tweak in $hkcuTweaks) {
            $tweakType = Get-HkcuTweakType -Tweak $tweak
            Set-RegMaintain -Path "$loadedHivePath\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
        }
        Write-MaintainLog "  Applied tweaks to logged-in profile: $($userProf.Name)"
        continue
    }

    $hiveKey = "Maintain_$($userProf.Name -replace '[^a-zA-Z0-9]','_')"
    $hiveName = "HKU\$hiveKey"
    reg load $hiveName $ntuser 2>$null
    if ($LASTEXITCODE -ne 0) { continue }

    foreach ($tweak in $hkcuTweaks) {
        $tweakType = Get-HkcuTweakType -Tweak $tweak
        Set-RegMaintain -Path "Registry::HKEY_USERS\$hiveKey\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
    }

    [gc]::Collect()
    Start-Sleep -Milliseconds 200
    reg unload $hiveName 2>$null
    Write-MaintainLog "  Applied tweaks to profile: $($userProf.Name)"
}

# Also apply to Default profile (new user accounts)
$defaultHive = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultHive) {
    $hiveKey = 'Maintain_Default'
    $hiveName = "HKU\$hiveKey"
    reg load $hiveName $defaultHive 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($tweak in $hkcuTweaks) {
            $tweakType = Get-HkcuTweakType -Tweak $tweak
            Set-RegMaintain -Path "Registry::HKEY_USERS\$hiveKey\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
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
