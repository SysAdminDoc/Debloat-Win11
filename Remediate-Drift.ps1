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

$policyCatalogFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'Modules\PolicyCatalog.psd1'
$policyCatalog = if (Test-Path $policyCatalogFile) { Import-PowerShellDataFile -Path $policyCatalogFile } else { @{} }
$windowsAiPolicies = @($policyCatalog.Policies)

# HKLM policies
Set-RegRemediate -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
foreach ($policy in ($windowsAiPolicies | Where-Object { $_.Scope -eq 'Device' -and $_.ApplyByDefault -ne $false })) {
    Set-RegRemediate -Path ('HKLM:\{0}' -f $policy.Path) -Name $policy.Name -Value $policy.Value -Type $policy.Type
}
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DiagnosticData" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "EdgeCopilotEnabled" -Value 0
Set-RegRemediate -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Value 0
Set-RegRemediate -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -Value 0

$hkcuTweaks = @($policyCatalog.HkcuTweaks)

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

# Apply to all user profiles
$userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default User|All Users)$' }
foreach ($userProf in $userProfiles) {
    $ntuser = "$($userProf.FullName)\NTUSER.DAT"
    if (!(Test-Path $ntuser)) { continue }

    $loadedHivePath = Get-LoadedUserHivePath -ProfilePath $userProf.FullName
    if ($loadedHivePath) {
        foreach ($tweak in $hkcuTweaks) {
            $tweakType = Get-HkcuTweakType -Tweak $tweak
            Set-RegRemediate -Path "$loadedHivePath\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
        }
        continue
    }

    $hiveKey = "Remediate_$($userProf.Name -replace '[^a-zA-Z0-9]','_')"
    $hiveName = "HKU\$hiveKey"
    reg load $hiveName $ntuser 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    foreach ($tweak in $hkcuTweaks) {
        $tweakType = Get-HkcuTweakType -Tweak $tweak
        Set-RegRemediate -Path "Registry::HKEY_USERS\$hiveKey\$($tweak.Path)" -Name $tweak.Name -Value $tweak.Value -Type $tweakType
    }
    [gc]::Collect()
    Start-Sleep -Milliseconds 200
    reg unload $hiveName 2>$null
    $count++
}

Write-Output "Debloat-Win11: Remediated $count settings"
exit 0
