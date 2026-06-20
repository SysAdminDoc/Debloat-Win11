#Requires -RunAsAdministrator
#Requires -Version 5.1

# Debloat-Win11 Maintenance Script
# Re-applies privacy/telemetry registry tweaks that Windows Update resets.
# Designed to run as a scheduled task after Windows Update completes.
# Does NOT remove apps or delete files -- registry tweaks only.

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

# Privacy & Telemetry
Set-RegMaintain -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0

# Copilot / AI
Set-RegMaintain -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "TurnOffSavingSnapshots" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "AllowRecallEnablement" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSettingsAgent" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentConnectors" -Value 1
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentWorkspaces" -Value 1
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0

# Bing Search
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDynamicSearchBoxEnabled" -Value 0

# Content Delivery Manager (Start Menu ads, suggestions, silent installs)
$CDMPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
@("SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338387Enabled",
  "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled",
  "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SilentInstalledAppsEnabled",
  "SoftLandingEnabled", "ContentDeliveryAllowed", "OemPreInstalledAppsEnabled",
  "PreInstalledAppsEnabled", "FeatureManagementEnabled") | ForEach-Object {
    Set-RegMaintain -Path $CDMPath -Name $_ -Value 0
}

# Consumer Features
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1

# Widgets
Set-RegMaintain -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0

# Taskbar
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 0

# Nag screens
Set-RegMaintain -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0

Write-MaintainLog "=== MAINTENANCE COMPLETE: $count settings re-applied ==="

$evtType = if ($count -gt 0) { 'Information' } else { 'Information' }
$msg = "Debloat-Win11 maintenance: $count registry settings re-applied after Windows Update"
Write-EventLog -LogName 'Application' -Source $eventSource -EventId 1002 -EntryType $evtType -Message $msg -EA 0
