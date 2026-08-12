#Requires -Version 5.1

 [CmdletBinding()]
 param(
    [string]$BaselinePath = (Join-Path $PSScriptRoot 'StaticAnalysisBaseline.json'),
    [int]$MaxWarnings = -1,
    [int]$MaxErrors = 0,
    [switch]$Json
 )

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
    Write-Error "Static-analysis baseline not found: $BaselinePath"
    exit 2
}

try {
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Static-analysis baseline is invalid: $($_.Exception.Message)"
    exit 2
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Error 'PSScriptAnalyzer is not installed. Install-Module PSScriptAnalyzer -Scope CurrentUser'
}

$results = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Settings $settingsPath |
    Where-Object {
        $_.ScriptPath -notmatch '\\\.git\\' -and
        $_.ScriptPath -notmatch '\\\.claude\\' -and
        $_.ScriptPath -notmatch '\\\.codex\\'
    }

 $errorCount = @($results | Where-Object { $_.Severity -eq 'Error' }).Count
 $warningCount = @($results | Where-Object { $_.Severity -eq 'Warning' }).Count
 $informationCount = @($results | Where-Object { $_.Severity -eq 'Information' }).Count
 $warningBudget = if ($MaxWarnings -ge 0) { $MaxWarnings } else { [int]$baseline.max_warning_count }
 $errorBudget = if ($MaxErrors -ge 0) { $MaxErrors } else { [int]$baseline.max_error_count }
 $summary = [ordered]@{
     schema_version = 1
     warning_count = $warningCount
     information_count = $informationCount
     error_count = $errorCount
     warning_budget = $warningBudget
     error_budget = $errorBudget
     baseline_warning_count = [int]$baseline.warning_count
     baseline_updated = [string]$baseline.updated
 }

if ($results -and -not $Json) {
    $results | Sort-Object Severity, ScriptPath, Line | Format-Table Severity, RuleName, ScriptPath, Line, Message -AutoSize
}

if ($errorCount -gt $errorBudget) {
    Write-Error "PSScriptAnalyzer found $errorCount error(s), exceeding the budget of $errorBudget."
    exit 1
}
if ($warningCount -gt $warningBudget) {
    Write-Error "PSScriptAnalyzer found $warningCount warning(s), exceeding the budget of $warningBudget. Update the reviewed baseline only after investigating new diagnostics."
    exit 1
}
if ($Json) {
    Write-Output ($summary | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}
if (-not $Json) { Write-Warning "PSScriptAnalyzer diagnostics: warnings=$warningCount information=$informationCount errors=$errorCount; budgets: warnings=$warningBudget errors=$errorBudget." }
Write-Host "PSScriptAnalyzer gate passed: warnings=$warningCount/$warningBudget errors=$errorCount/$errorBudget."
exit 0
