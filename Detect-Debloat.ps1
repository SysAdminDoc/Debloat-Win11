#Requires -Version 5.1
# Intune Win32 App detection for Debloat-Win11.
# A run is compliant only when its complete manifest, policy/config fingerprints,
# target scope, supported runtime, and operation accounting all agree.
#
# Optional deployment parameters:
#   -ExpectedScope AllUsers|CurrentUser
#   -ExpectedConfigPath path-to-the-deployment-psd1
#   -OutputFormat Text|Json

[CmdletBinding()]
param(
    [ValidateSet('Text','Json','Csv')]
    [string]$OutputFormat = 'Text',
    [ValidateSet('CurrentUser','AllUsers')]
    [string]$ExpectedScope,
    [string]$ExpectedConfigPath,
    [string]$LogDir = "$env:ProgramData\Debloat-Win11\Logs"
)

$expectedVersion = 'v2.3.11'
$manifestSchemaVersion = 2
$catalogPath = Join-Path $PSScriptRoot 'Modules\PolicyCatalog.psd1'
$reasons = [System.Collections.ArrayList]@()

function Add-ComplianceReason {
    param([Parameter(Mandatory)][string]$Message)
    if (@($reasons) -notcontains $Message) { $reasons.Add($Message) | Out-Null }
}

function Get-ContentHash {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    } catch {
        return $null
    }
}

$catalogHash = Get-ContentHash -Path $catalogPath
if ([string]::IsNullOrWhiteSpace($catalogHash)) { Add-ComplianceReason "Policy catalog is missing or cannot be hashed: $catalogPath" }

$expectedConfigHash = 'none'
if ($ExpectedConfigPath) {
    $resolvedExpectedConfig = $null
    try { $resolvedExpectedConfig = (Resolve-Path -LiteralPath $ExpectedConfigPath -ErrorAction Stop).Path } catch {}
    if (-not $resolvedExpectedConfig) {
        Add-ComplianceReason "Expected configuration was not found: $ExpectedConfigPath"
    } else {
        $expectedConfigHash = Get-ContentHash -Path $resolvedExpectedConfig
        if ([string]::IsNullOrWhiteSpace($expectedConfigHash)) { Add-ComplianceReason "Expected configuration cannot be hashed: $ExpectedConfigPath" }
    }
}

$currentBuild = $null
$currentEdition = $null
$currentArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { [string]$env:PROCESSOR_ARCHITEW6432 } else { [string]$env:PROCESSOR_ARCHITECTURE }
$currentArchitecture = switch -Regex ($currentArchitecture) {
    'amd64|x64' { 'x64'; break }
    'arm64' { 'arm64'; break }
    default { 'x86' }
}
try {
    $currentVersion = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $currentBuild = [int]$currentVersion.CurrentBuild
    $currentEdition = [string]$currentVersion.EditionID
} catch {}

function Test-ComplianceManifest {
    param([Parameter(Mandatory)]$Manifest)

    $localReasons = [System.Collections.ArrayList]@()
    if ($null -eq $Manifest) { $localReasons.Add('Manifest is empty') | Out-Null; return [pscustomobject]@{ Valid = $false; Reasons = @($localReasons) } }
    if ($Manifest.schema_version -ne $manifestSchemaVersion) { $localReasons.Add("Manifest schema is $($Manifest.schema_version), expected $manifestSchemaVersion") | Out-Null }
    if ($Manifest.version -ne $expectedVersion) { $localReasons.Add("Manifest version is $($Manifest.version), expected $expectedVersion") | Out-Null }
    if ($Manifest.dryrun -ne $false) { $localReasons.Add('Manifest is a dry-run or does not declare dryrun=false') | Out-Null }
    if ($Manifest.status -ne 'Complete') { $localReasons.Add("Manifest status is $($Manifest.status), expected Complete") | Out-Null }
    if ($Manifest.runtime.supported -ne $true) { $localReasons.Add('Manifest runtime is outside the supported matrix') | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.runtime.os_build) -or [int]$Manifest.runtime.os_build -lt 1) { $localReasons.Add('Manifest is missing a supported OS build') | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.runtime.edition)) { $localReasons.Add('Manifest is missing an OS edition') | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.runtime.architecture)) { $localReasons.Add('Manifest is missing an OS architecture') | Out-Null }
    if ([string]$Manifest.catalog.policy_catalog_hash -ne [string]$catalogHash) { $localReasons.Add('Policy catalog hash does not match the deployed catalog') | Out-Null }
    if ([string]$Manifest.configuration.config_hash -ne [string]$expectedConfigHash) { $localReasons.Add('Configuration hash does not match the expected deployment configuration') | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.scope.user_policy)) { $localReasons.Add('Manifest is missing the target user scope') | Out-Null }
    if ($ExpectedScope -and [string]$Manifest.scope.user_policy -ne $ExpectedScope) { $localReasons.Add("Target scope is $($Manifest.scope.user_policy), expected $ExpectedScope") | Out-Null }
    if ($Manifest.operation_summary -eq $null) {
        $localReasons.Add('Manifest is missing operation accounting') | Out-Null
    } else {
        if ([int]$Manifest.operation_summary.failed -ne 0) { $localReasons.Add("Manifest records $($Manifest.operation_summary.failed) failed operations") | Out-Null }
        $accounted = [int]$Manifest.operation_summary.succeeded + [int]$Manifest.operation_summary.failed + [int]$Manifest.operation_summary.skipped
        if ([int]$Manifest.operation_summary.attempted -ne $accounted) { $localReasons.Add('Operation accounting is inconsistent') | Out-Null }
    }
    $unsupportedSelected = @($Manifest.action_plan | Where-Object { $_.selected -eq $true -and $_.supported -ne $true })
    if ($unsupportedSelected.Count -gt 0) { $localReasons.Add('Manifest selects an action outside the supported build/edition/architecture matrix') | Out-Null }

    if ($currentBuild -and [int]$Manifest.runtime.os_build -gt $currentBuild) { $localReasons.Add("Manifest was produced for build $($Manifest.runtime.os_build), newer than current build $currentBuild") | Out-Null }
    if ($currentEdition -and [string]$Manifest.runtime.edition -ne $currentEdition) { $localReasons.Add("Manifest edition $($Manifest.runtime.edition) does not match current edition $currentEdition") | Out-Null }
    if ($currentArchitecture -and [string]$Manifest.runtime.architecture -ne $currentArchitecture) { $localReasons.Add("Manifest architecture $($Manifest.runtime.architecture) does not match current architecture $currentArchitecture") | Out-Null }

    return [pscustomobject]@{ Valid = ($localReasons.Count -eq 0); Reasons = @($localReasons) }
}

function Finish-Compliance {
    param([Parameter(Mandatory)][bool]$Compliant, [Parameter(Mandatory)][string]$Source)

    $result = [ordered]@{
        schema_version = 1
        product = 'Debloat-Win11'
        expected_version = $expectedVersion
        compliant = $Compliant
        source = $Source
        reasons = @($reasons)
    }
    if ($OutputFormat -eq 'Json') {
        Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
    } elseif ($OutputFormat -eq 'Csv') {
        $csv = [ordered]@{
            product = $result.product
            expected_version = $result.expected_version
            compliant = $result.compliant
            source = $result.source
            reasons = (@($result.reasons) -join ' | ')
        }
        Write-Output (($csv | ConvertTo-Csv -NoTypeInformation) -join "`n")
    } elseif ($Compliant) {
        Write-Output "Debloat-Win11 $expectedVersion detected ($Source)"
    } else {
        Write-Output ('Debloat-Win11 not compliant: ' + (@($reasons) -join '; '))
    }
    if ($Compliant) { exit 0 }
    exit 1
}

# Check the registry stamp first (survives log cleanup and is compatible with Intune rules).
$regStamp = Get-ItemProperty 'HKLM:\SOFTWARE\Debloat-Win11' -ErrorAction SilentlyContinue
if ($regStamp -and $regStamp.ManifestPath -and (Test-Path -LiteralPath $regStamp.ManifestPath -PathType Leaf)) {
    $stampValid = $true
    if ($regStamp.Version -ne $expectedVersion) { Add-ComplianceReason "Registry stamp version is $($regStamp.Version), expected $expectedVersion"; $stampValid = $false }
    if ($regStamp.Status -ne 'Complete') { Add-ComplianceReason "Registry stamp status is $($regStamp.Status), expected Complete"; $stampValid = $false }
    if ($regStamp.CatalogHash -ne $catalogHash) { Add-ComplianceReason 'Registry catalog hash does not match the deployed catalog'; $stampValid = $false }
    if ($regStamp.ConfigHash -ne $expectedConfigHash) { Add-ComplianceReason 'Registry configuration hash does not match the expected configuration'; $stampValid = $false }
    if ($ExpectedScope -and $regStamp.Scope -ne $ExpectedScope) { Add-ComplianceReason "Registry scope is $($regStamp.Scope), expected $ExpectedScope"; $stampValid = $false }
    try {
        $stampManifest = Get-Content -LiteralPath $regStamp.ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $stampCheck = Test-ComplianceManifest -Manifest $stampManifest
        if (-not $stampCheck.Valid) { $stampCheck.Reasons | ForEach-Object { Add-ComplianceReason $_ }; $stampValid = $false }
        if ($stampValid) { Finish-Compliance -Compliant $true -Source 'registry stamp' }
    } catch {
        Add-ComplianceReason "Registry-stamped manifest could not be read: $($_.Exception.Message)"
    }
}

# Fallback: inspect newest manifests until a valid complete run is found. A newer
# incomplete run must not hide an older complete run, and an incomplete run never passes.
$manifests = @()
if (Test-Path -LiteralPath $logDir -PathType Container) {
    $manifests = @(Get-ChildItem -LiteralPath $logDir -Filter 'Debloat-Manifest-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}
foreach ($manifestFile in $manifests) {
    try {
        $data = Get-Content -LiteralPath $manifestFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
        $check = Test-ComplianceManifest -Manifest $data
        if ($check.Valid) { Finish-Compliance -Compliant $true -Source "manifest $($manifestFile.Name)" }
        if ($manifestFile -eq $manifests[0]) { $check.Reasons | ForEach-Object { Add-ComplianceReason $_ } }
    } catch {
        if ($manifestFile -eq $manifests[0]) { Add-ComplianceReason "Newest manifest could not be read: $($_.Exception.Message)" }
    }
}

if ($manifests.Count -eq 0) { Add-ComplianceReason 'No Debloat-Win11 manifest was found' }
Finish-Compliance -Compliant $false -Source 'none'
