#Requires -Version 5.1
# Reports local validation prerequisites without changing the machine or
# installing modules. Use -Strict for a non-zero result when requirements fail.

[CmdletBinding()]
param(
    [string]$RequirementsPath,
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RequirementsPath)) {
    $RequirementsPath = Join-Path $PSScriptRoot 'ValidationRequirements.psd1'
}
$requirements = Import-PowerShellDataFile -LiteralPath $RequirementsPath
$repoRoot = Split-Path $PSScriptRoot -Parent
$issues = [System.Collections.ArrayList]@()

function Add-Issue {
    param([Parameter(Mandatory)][string]$Message)
    $issues.Add($Message) | Out-Null
}

function Get-ManifestHash {
    param([Parameter(Mandatory)][string]$Path)
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { return $null }
}

$psVersion = [version]$PSVersionTable.PSVersion
$psMajor = [string]$psVersion.Major
$shellLabel = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'Windows PowerShell' } else { 'PowerShell' }
$minimum = if ($PSVersionTable.PSEdition -eq 'Desktop') { [version]$requirements.PowerShell.WindowsPowerShellMinimum } else { [version]$requirements.PowerShell.PowerShellMinimum }
$shellSupported = $requirements.PowerShell.SupportedMajors -contains $psMajor -and $psVersion -ge $minimum
if (-not $shellSupported) { Add-Issue "Unsupported PowerShell runtime: $shellLabel $psVersion (minimum $minimum)" }

$moduleResults = [System.Collections.ArrayList]@()
foreach ($moduleRequirement in @($requirements.Modules)) {
    $installed = @(Get-Module -ListAvailable -Name $moduleRequirement.Name | Sort-Object Version -Descending)
    $allowed = @($moduleRequirement.AllowedVersions | ForEach-Object { [version]$_ })
    $compatible = @($installed | Where-Object { $allowed -contains $_.Version })
    $versions = @($installed | Select-Object -ExpandProperty Version -Unique | ForEach-Object { [string]$_ })
    $hashes = [System.Collections.ArrayList]@()
    foreach ($module in $compatible) {
        $manifestHash = Get-ManifestHash -Path $module.Path
        $hashes.Add([ordered]@{
            version = [string]$module.Version
            manifest = [string]$module.Path
            manifest_sha256 = $manifestHash
            module_base = [string]$module.ModuleBase
        }) | Out-Null
    }
    $moduleValid = $compatible.Count -gt 0
    if (-not $moduleValid -and $moduleRequirement.Required) {
        Add-Issue "$($moduleRequirement.Name) requires one of $($moduleRequirement.AllowedVersions -join ', '); installed versions: $(if ($versions.Count) { $versions -join ', ' } else { 'none' })"
    }
    $moduleResults.Add([ordered]@{
        name = $moduleRequirement.Name
        required = [bool]$moduleRequirement.Required
        allowed_versions = @($moduleRequirement.AllowedVersions)
        installed_versions = @($versions)
        compatible_versions = @($compatible | Select-Object -ExpandProperty Version -Unique | ForEach-Object { [string]$_ })
        manifest_hashes = @($hashes)
        valid = $moduleValid
    }) | Out-Null
}

$commandResults = [System.Collections.ArrayList]@()
foreach ($commandName in @('powershell.exe','pwsh')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    $commandResults.Add([ordered]@{
        name = $commandName
        available = $null -ne $command
        path = if ($command) { [string]$command.Source } else { $null }
    }) | Out-Null
}

$result = [ordered]@{
    schema_version = 1
    requirements_schema_version = [int]$requirements.SchemaVersion
    generated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    repository = $repoRoot
    runtime = [ordered]@{
        edition = [string]$PSVersionTable.PSEdition
        name = $shellLabel
        version = [string]$psVersion
        minimum = [string]$minimum
        supported = $shellSupported
    }
    test_matrix = @($requirements.TestMatrix)
    modules = @($moduleResults)
    commands = @($commandResults)
    offline = $true
    installs_performed = $false
    requirements_valid = ($issues.Count -eq 0)
    issues = @($issues)
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
} else {
    Write-Output "Validation environment: $($result.runtime.name) $($result.runtime.version) | valid=$($result.requirements_valid)"
    foreach ($module in $result.modules) {
        Write-Output ("  {0}: {1} (allowed: {2})" -f $module.name, ($module.installed_versions -join ', '), ($module.allowed_versions -join ', '))
    }
    if ($result.issues.Count -gt 0) { $result.issues | ForEach-Object { Write-Output "  ISSUE: $_" } }
}

if ($Strict -and -not $result.requirements_valid) { exit 1 }
exit 0
