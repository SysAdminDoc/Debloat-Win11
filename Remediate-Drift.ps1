# Intune Proactive Remediation - Drift Remediation Script
# Re-applies HKLM privacy/telemetry/AI policies and HKCU tweaks
# to all user profiles when drift is detected.
#
# Usage in Intune:
#   Proactive Remediations > Create script package
#   Detection script: Detect-Drift.ps1
#   Remediation script: Remediate-Drift.ps1
#   Run as: System

$ErrorActionPreference = "SilentlyContinue"
$count = 0

function Set-RegRemediate {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $current = Get-ItemProperty -Path $Path -Name $Name -EA 0
    if ($null -eq $current -or $current.$Name -ne $Value) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -EA 0
        $script:count++
    }
}

# HKLM policies
Set-RegRemediate -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "TurnOffSavingSnapshots" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "AllowRecallEnablement" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableSettingsAgent" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentConnectors" -Value 2
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAgentWorkspaces" -Value 2
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Paint" -Name "DisableImageCreator" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Paint" -Name "DisableGenerativeFill" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Paint" -Name "DisableCocreator" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DiagnosticData" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "EdgeCopilotEnabled" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Value 0
Set-RegRemediate -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -Value 0

# Per-user HKCU tweaks (load shared definitions if available)
$hkcuDataFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Modules\HkcuTweaks.psd1'
if (Test-Path $hkcuDataFile) {
    $hkcuTweaks = & ([scriptblock]::Create((Get-Content $hkcuDataFile -Raw)))
} else {
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

# Apply to current user
foreach ($tweak in $hkcuTweaks) {
    Set-RegRemediate -Path "HKCU:\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value
}

# Apply to all user profiles
$userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default User|All Users)$' }
foreach ($userProf in $userProfiles) {
    $ntuser = "$($userProf.FullName)\NTUSER.DAT"
    if (!(Test-Path $ntuser)) { continue }
    $hiveName = "HKU\Remediate_$($userProf.Name -replace '[^a-zA-Z0-9]','_')"
    reg load $hiveName $ntuser 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    foreach ($tweak in $hkcuTweaks) {
        reg add "$hiveName\$($tweak.Path)" /v $tweak.Name /t REG_DWORD /d $tweak.Value /f 2>$null | Out-Null
    }
    [gc]::Collect()
    Start-Sleep -Milliseconds 200
    reg unload $hiveName 2>$null
    $count++
}

Write-Output "Debloat-Win11: Remediated $count settings"
exit 0
