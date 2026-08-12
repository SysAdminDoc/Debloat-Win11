#Requires -Version 5.1

# Intune Proactive Remediation - Drift Detection Script
# Returns exit 0 only when machine and every discovered user profile is compliant.
# Returns exit 1 for drift, skipped/locked profiles, or registry errors.
#
# Usage in Intune:
#   Detection script: Detect-Drift.ps1
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

$machineChecks = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeCopilotEnabled'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled'; Expected = 0 }
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Expected = 0 }
)

foreach ($policy in ($windowsAiPolicies | Where-Object { $_.Scope -eq 'Device' -and $_.ApplyByDefault -ne $false })) {
    $machineChecks += @{ Path = ('HKLM:\{0}' -f $policy.Path); Name = $policy.Name; Expected = $policy.Value }
}
$userChecks = @(Get-DebloatUserRegistryChecks -Policies $windowsAiPolicies -Tweaks $hkcuTweaks)

$summary = [ordered]@{
    Checks = 0
    Compliant = 0
    Drifted = 0
    Skipped = 0
    Errors = 0
    Profiles = 0
    LoadedProfiles = 0
    OfflineProfiles = 0
    SkippedProfiles = 0
}
$details = New-Object System.Collections.ArrayList

function Test-DebloatRegistryExpectation {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        $Expected,
        [Parameter(Mandatory)][string]$Scope,
        [string]$ProfileName
    )

    $summary.Checks++
    $status = 'Compliant'
    $reason = $null
    try {
        $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        if ($null -eq $current -or $current.$Name -ne $Expected) {
            $status = 'Drifted'
            $summary.Drifted++
            $reason = 'value differs from catalog expectation'
        } else {
            $summary.Compliant++
        }
    } catch {
        $status = 'Drifted'
        $summary.Drifted++
        $reason = 'value is missing or unreadable'
    }

    if ($status -ne 'Compliant') {
        $details.Add([pscustomobject]@{
            Scope = $Scope
            Profile = $ProfileName
            Path = $Path
            Name = $Name
            Status = $status
            Reason = $reason
        }) | Out-Null
    }
}

foreach ($check in $machineChecks) {
    Test-DebloatRegistryExpectation -Path $check.Path -Name $check.Name -Expected $check.Expected -Scope 'Machine'
}

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
    $session = Open-DebloatUserHive -UserProfile $userProfile -Prefix 'DebloatDetect'
    if ($session.Status -ne 'Ready') {
        $summary.SkippedProfiles++
        $summary.Skipped += $userChecks.Count
        if ($session.Status -eq 'Error') { $summary.Errors++ }
        foreach ($check in $userChecks) {
            $details.Add([pscustomobject]@{
                Scope = 'User'
                Profile = $userProfile.Name
                Path = $check.Path
                Name = $check.Name
                Status = 'Skipped'
                Reason = $session.Reason
            }) | Out-Null
        }
        continue
    }

    if ($session.Temporary) { $summary.OfflineProfiles++ } else { $summary.LoadedProfiles++ }
    foreach ($check in $userChecks) {
        Test-DebloatRegistryExpectation -Path ("{0}\{1}" -f $session.Path, $check.Path) -Name $check.Name -Expected $check.Expected -Scope 'User' -ProfileName $userProfile.Name
    }

    $closeResult = Close-DebloatUserHive -Session $session
    if (-not $closeResult.Success) {
        $summary.Errors++
        $details.Add([pscustomobject]@{
            Scope = 'User'
            Profile = $userProfile.Name
            Path = $null
            Name = $null
            Status = 'Error'
            Reason = $closeResult.Reason
        }) | Out-Null
    }
}

$status = if ($summary.Drifted -eq 0 -and $summary.Errors -eq 0 -and $summary.Skipped -eq 0) { 'Compliant' } else { 'NonCompliant' }
foreach ($detail in $details) {
    Write-Output ("Debloat-Win11: scope={0} profile={1} status={2} path={3} name={4} reason={5}" -f $detail.Scope, $detail.Profile, $detail.Status, $detail.Path, $detail.Name, $detail.Reason)
}
Write-Output ("Debloat-Win11: status={0} checks={1} compliant={2} drifted={3} skipped={4} errors={5} profiles={6} loaded={7} offline={8} skippedProfiles={9}" -f $status, $summary.Checks, $summary.Compliant, $summary.Drifted, $summary.Skipped, $summary.Errors, $summary.Profiles, $summary.LoadedProfiles, $summary.OfflineProfiles, $summary.SkippedProfiles)

if ($status -eq 'Compliant') { exit 0 }
exit 1
