#Requires -Version 5.1

# Intune Proactive Remediation - Drift Remediation Script
# Re-applies catalog-backed machine policies and user settings to every
# discovered profile. Skipped profiles and failed settings are non-success.
#
# Usage in Intune:
#   Remediation script: Remediate-Drift.ps1
#   Run as: System

$ErrorActionPreference = 'SilentlyContinue'
$scriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$policyCatalogFile = Join-Path $scriptRoot 'Modules\PolicyCatalog.psd1'
$profileHelperFile = Join-Path $scriptRoot 'tools\ProfileHive.ps1'

try {
    if (-not (Test-Path $policyCatalogFile)) { throw "Policy catalog not found: $policyCatalogFile" }
    $policyCatalog = Import-PowerShellDataFile -Path $policyCatalogFile
    if ($policyCatalog.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$policyCatalog.CatalogVersion)) {
        throw "Unsupported policy catalog schema/version: $($policyCatalog.SchemaVersion)/$($policyCatalog.CatalogVersion)"
    }
    if (-not (Test-Path $profileHelperFile)) { throw "Profile helper not found: $profileHelperFile" }
    . $profileHelperFile
} catch {
    Write-Output "Debloat-Win11: status=Error reason=$($_.Exception.Message)"
    exit 1
}

$windowsAiPolicies = @($policyCatalog.Policies)
$hkcuTweaks = @($policyCatalog.HkcuTweaks)
$summary = [ordered]@{
    Attempted = 0
    Remediated = 0
    AlreadyCompliant = 0
    Failed = 0
    Skipped = 0
    Errors = 0
    Profiles = 0
    LoadedProfiles = 0
    OfflineProfiles = 0
    SkippedProfiles = 0
}
$details = New-Object System.Collections.ArrayList

function Set-RegRemediate {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name, $Value, [string]$Type = 'DWord', [string]$Scope = 'Machine', [string]$ProfileName)

    $summary.Attempted++
    try {
        $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($current -and $current.$Name -eq $Value) {
            $summary.AlreadyCompliant++
            return $true
        }
        Set-DebloatRegistryProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
        $verified = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        if ($null -eq $verified -or $verified.$Name -ne $Value) { throw 'registry value did not match after write' }
        $summary.Remediated++
        return $true
    } catch {
        $summary.Failed++
        $details.Add([pscustomobject]@{
            Scope = $Scope
            Profile = $ProfileName
            Path = $Path
            Name = $Name
            Status = 'Failed'
            Reason = $_.Exception.Message
        }) | Out-Null
        return $false
    }
}

# Machine policies are intentionally explicit because these settings are not
# user-profile state and must remain available when no user is logged in.
$machineChecks = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Value = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeCopilotEnabled'; Value = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled'; Value = 0 }
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Value = 0 }
)
foreach ($check in $machineChecks) {
    Set-RegRemediate -Path $check.Path -Name $check.Name -Value $check.Value -Scope 'Machine' | Out-Null
}
foreach ($policy in ($windowsAiPolicies | Where-Object { $_.Scope -eq 'Device' -and $_.ApplyByDefault -ne $false })) {
    Set-RegRemediate -Path ('HKLM:\{0}' -f $policy.Path) -Name $policy.Name -Value $policy.Value -Type $policy.Type -Scope 'Machine' | Out-Null
}

$userChecks = @(Get-DebloatUserRegistryChecks -Policies $windowsAiPolicies -Tweaks $hkcuTweaks)
$profileEnumerationError = $null
$userProfiles = @(Get-DebloatUserProfiles -ErrorMessage ([ref]$profileEnumerationError))
if ($profileEnumerationError -and $userProfiles.Count -eq 0) {
    $summary.Errors++
    $details.Add([pscustomobject]@{
        Scope = 'AllUsers'
        Profile = $null
        Path = $null
        Name = $null
        Status = 'Error'
        Reason = $profileEnumerationError
    }) | Out-Null
}

foreach ($userProfile in $userProfiles) {
    $summary.Profiles++
    $session = Open-DebloatUserHive -UserProfile $userProfile -Prefix 'DebloatRemediate'
    if ($session.Status -ne 'Ready') {
        $summary.SkippedProfiles++
        $summary.Skipped += $userChecks.Count
        if ($session.Status -eq 'Error') { $summary.Errors++ }
        $details.Add([pscustomobject]@{
            Scope = 'User'
            Profile = $userProfile.Name
            Path = $userProfile.NtUserPath
            Name = $null
            Status = 'Skipped'
            Reason = $session.Reason
        }) | Out-Null
        continue
    }

    if ($session.Temporary) { $summary.OfflineProfiles++ } else { $summary.LoadedProfiles++ }
    foreach ($check in $userChecks) {
        Set-RegRemediate -Path ("{0}\{1}" -f $session.Path, $check.Path) -Name $check.Name -Value $check.Expected -Type $check.Type -Scope 'User' -ProfileName $userProfile.Name | Out-Null
    }

    $closeResult = Close-DebloatUserHive -Session $session
    if (-not $closeResult.Success) {
        $summary.Errors++
        $details.Add([pscustomobject]@{
            Scope = 'User'
            Profile = $userProfile.Name
            Path = $null
            Name = $null
            Status = 'Failed'
            Reason = $closeResult.Reason
        }) | Out-Null
    }
}

$status = if ($summary.Failed -eq 0 -and $summary.Errors -eq 0 -and $summary.Skipped -eq 0) { 'Success' } else { 'Incomplete' }
foreach ($detail in $details) {
    Write-Output ("Debloat-Win11: scope={0} profile={1} status={2} path={3} name={4} reason={5}" -f $detail.Scope, $detail.Profile, $detail.Status, $detail.Path, $detail.Name, $detail.Reason)
}
Write-Output ("Debloat-Win11: status={0} attempted={1} remediated={2} alreadyCompliant={3} failed={4} skipped={5} errors={6} profiles={7} loaded={8} offline={9} skippedProfiles={10}" -f $status, $summary.Attempted, $summary.Remediated, $summary.AlreadyCompliant, $summary.Failed, $summary.Skipped, $summary.Errors, $summary.Profiles, $summary.LoadedProfiles, $summary.OfflineProfiles, $summary.SkippedProfiles)

if ($status -eq 'Success') { exit 0 }
exit 1
