#Requires -Version 5.1

# Disposable-VM integration path. This harness is intentionally skipped unless
# the operator marks the machine as disposable and explicitly permits changes.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ArtifactRoot,
    [switch]$AllowMutation
)

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot = Join-Path $env:TEMP ("Debloat-Win11-Integration-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }

$result = [ordered]@{
    schema_version = 1
    status = 'Skipped'
    reason = $null
    started = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')
    completed = $null
    repository = $RepoRoot
    artifacts = $ArtifactRoot
    steps = @()
    registry_comparison = $null
}

function Write-IntegrationResult {
    param([int]$ExitCode)

    $result.completed = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
    try {
        New-Item -Path $ArtifactRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $resultFile = Join-Path $ArtifactRoot 'integration-result.json'
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultFile -Encoding UTF8
        Write-Output ("Debloat-Win11 integration: status={0} reason={1} result={2}" -f $result.status, $result.reason, $resultFile)
    } catch {
        Write-Output "Debloat-Win11 integration: status=Error reason=$($_.Exception.Message)"
        $ExitCode = 1
    }
    exit $ExitCode
}

function Add-IntegrationStep {
    param([string]$Name, [string]$Status, [int]$ExitCode = 0, [string]$Detail, [string]$Log)
    $result.steps += [ordered]@{
        name = $Name
        status = $Status
        exit_code = $ExitCode
        detail = $Detail
        log = $Log
    }
}

function Invoke-IntegrationCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $safeName = $Name -replace '[^A-Za-z0-9_-]', '_'
    $logPath = Join-Path $ArtifactRoot "$safeName.log"
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $logPath -Encoding UTF8
    $status = if ($exitCode -eq 0) { 'Passed' } else { 'Failed' }
    Add-IntegrationStep -Name $Name -Status $status -ExitCode $exitCode -Detail (($output | Select-Object -Last 1) -join '') -Log $logPath
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output; Log = $logPath }
}

function Test-RegistryStateAgainstManifest {
    param([Parameter(Mandatory)][object]$Manifest)

    $before = [ordered]@{}
    $after = [ordered]@{}
    $mismatches = New-Object System.Collections.ArrayList
    foreach ($entry in @($Manifest.changes.registry_set)) {
        $key = "$($entry.path)\$($entry.name)"
        $before[$key] = $entry.old_value
        $current = $null
        if (Test-Path $entry.path) {
            $currentEntry = Get-ItemProperty -Path $entry.path -Name $entry.name -ErrorAction SilentlyContinue
            if ($currentEntry) { $current = $currentEntry.$($entry.name) }
        }
        $after[$key] = $current
        $expected = $entry.old_value
        $stateMatches = if ($null -eq $expected) { $null -eq $current } else { $current -eq $expected }
        if (-not $stateMatches) {
            $mismatches.Add([ordered]@{ key = $key; expected = $expected; actual = $current }) | Out-Null
        }
    }

    $beforeFile = Join-Path $ArtifactRoot 'before-state.json'
    $afterFile = Join-Path $ArtifactRoot 'after-state.json'
    $before | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $beforeFile -Encoding UTF8
    $after | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $afterFile -Encoding UTF8
    return [pscustomobject]@{
        BeforeFile = $beforeFile
        AfterFile = $afterFile
        Checked = $before.Count
        Mismatches = @($mismatches)
    }
}

try {
    New-Item -Path $ArtifactRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
} catch {
    $result.reason = "Cannot create artifact directory: $($_.Exception.Message)"
    Write-IntegrationResult -ExitCode 1
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    $result.reason = 'Windows integration tests require Windows'
    Write-IntegrationResult -ExitCode 0
}
if ($env:DEBLOAT_WIN11_INTEGRATION_VM -ne '1') {
    $result.reason = 'Set DEBLOAT_WIN11_INTEGRATION_VM=1 only on a disposable Windows VM'
    Write-IntegrationResult -ExitCode 0
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $result.reason = 'An elevated administrator session is required'
    Write-IntegrationResult -ExitCode 0
}
if (-not $AllowMutation) {
    $result.reason = 'Pass -AllowMutation to authorize the apply/revert portion on the disposable VM'
    Write-IntegrationResult -ExitCode 0
}

$mainScript = Join-Path $RepoRoot 'Debloat-Win11.ps1'
$detectScript = Join-Path $RepoRoot 'Detect-Debloat.ps1'
if (-not (Test-Path $mainScript) -or -not (Test-Path $detectScript)) {
    $result.reason = 'Required repository scripts are missing'
    Write-IntegrationResult -ExitCode 1
}
if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
    $result.reason = 'Windows PowerShell 5.1 executable is unavailable'
    Write-IntegrationResult -ExitCode 1
}

$fixtureConfig = Join-Path $ArtifactRoot 'integration-config.psd1'
@'
@{
    RemovePatterns = @()
    ServicesToDisable = @()
    DefenderExclusions = @()
    EdgeBookmarks = @()
    StartupBloat = @()
    TasksToDisable = @()
    FeaturesToDisable = @()
    FirewallRules = ''
    DarkMode = $false
    OemExclude = @()
    ClearEventLogs = @()
    NetworkProfile = 'Preserve'
    DisableNagle = $false
    EnableNetworkDiscovery = $false
    EnableFilePrinterSharing = $false
}
'@ | Set-Content -LiteralPath $fixtureConfig -Encoding UTF8

$dryRunRoot = Join-Path $ArtifactRoot 'dry-run'
$dryRun = Invoke-IntegrationCommand -Name 'DryRun' -ScriptPath $mainScript -Arguments @('-DryRun','-Only','AppX','-ConfigPath',$fixtureConfig,'-LogDir',$dryRunRoot)
if ($dryRun.ExitCode -ne 0) {
    $result.status = 'Failed'
    $result.reason = 'DryRun command failed'
    Write-IntegrationResult -ExitCode 1
}

$applyRoot = Join-Path $ArtifactRoot 'apply'
$apply = Invoke-IntegrationCommand -Name 'Apply' -ScriptPath $mainScript -Arguments @('-Only','SystemTweaks','-AllowIrreversibleChanges','-ConfigPath',$fixtureConfig,'-LogDir',$applyRoot)
if ($apply.ExitCode -ne 0) {
    $result.status = 'Failed'
    $result.reason = 'Apply command failed; inspect preserved artifacts'
    Write-IntegrationResult -ExitCode 1
}

$manifestFile = Get-ChildItem -LiteralPath $applyRoot -Filter 'Debloat-Manifest-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $manifestFile) {
    $result.status = 'Failed'
    $result.reason = 'Apply did not produce an undo manifest'
    Write-IntegrationResult -ExitCode 1
}
$manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
$beforeState = Test-RegistryStateAgainstManifest -Manifest $manifest
$result.registry_comparison = [ordered]@{ before_entries = $beforeState.Checked; before_state = $beforeState.BeforeFile; after_state = $beforeState.AfterFile }

$detect = Invoke-IntegrationCommand -Name 'DetectAfterApply' -ScriptPath $detectScript
if ($detect.ExitCode -ne 0) {
    $result.status = 'Failed'
    $result.reason = 'Detection did not report the applied state as compliant'
    Write-IntegrationResult -ExitCode 1
}

$revert = Get-ChildItem -LiteralPath $applyRoot -Filter 'Debloat-Revert-*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $revert) {
    $result.status = 'Failed'
    $result.reason = 'Apply did not produce a generated revert script'
    Write-IntegrationResult -ExitCode 1
}
$revertResult = Invoke-IntegrationCommand -Name 'Revert' -ScriptPath $revert.FullName
if ($revertResult.ExitCode -ne 0) {
    $result.status = 'Failed'
    $result.reason = 'Revert command failed; inspect preserved artifacts'
    Write-IntegrationResult -ExitCode 1
}

$comparison = Test-RegistryStateAgainstManifest -Manifest $manifest
$afterRevertFile = Join-Path $ArtifactRoot 'after-revert-state.json'
Copy-Item -LiteralPath $comparison.AfterFile -Destination $afterRevertFile -Force
$result.registry_comparison.after_revert_entries = $comparison.Checked
$result.registry_comparison.after_revert_state = $afterRevertFile
$result.registry_comparison.mismatches = @($comparison.Mismatches)
if (@($comparison.Mismatches).Count -gt 0) {
    $result.status = 'Failed'
    $result.reason = "Revert left $(@($comparison.Mismatches).Count) registry values different from the manifest snapshot"
    Write-IntegrationResult -ExitCode 1
}

$detectAfterRevert = Invoke-IntegrationCommand -Name 'DetectAfterRevert' -ScriptPath $detectScript
if ($detectAfterRevert.ExitCode -eq 0) {
    $result.status = 'Failed'
    $result.reason = 'Detection still reported compliance after revert'
    Write-IntegrationResult -ExitCode 1
}

$result.status = 'Passed'
$result.reason = 'DryRun, apply, detect, revert, state comparison, and post-revert detection passed'
Write-IntegrationResult -ExitCode 0
