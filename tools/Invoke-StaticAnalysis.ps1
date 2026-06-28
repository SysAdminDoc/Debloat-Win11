#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Error 'PSScriptAnalyzer is not installed. Install-Module PSScriptAnalyzer -Scope CurrentUser'
}

$results = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Settings $settingsPath |
    Where-Object {
        $_.ScriptPath -notmatch '\\\.git\\' -and
        $_.ScriptPath -notmatch '\\\.claude\\' -and
        $_.ScriptPath -notmatch '\\\.codex\\'
    }

if ($results) {
    $results | Sort-Object Severity, ScriptPath, Line | Format-Table Severity, RuleName, ScriptPath, Line, Message -AutoSize
    $errorCount = @($results | Where-Object { $_.Severity -eq 'Error' }).Count
    if ($errorCount -gt 0) {
        Write-Error "PSScriptAnalyzer found $errorCount error(s)."
    }
    Write-Warning "PSScriptAnalyzer found $(@($results).Count) diagnostic(s); warnings are reported but do not fail this gate."
}

Write-Host 'PSScriptAnalyzer gate passed: no errors.'
