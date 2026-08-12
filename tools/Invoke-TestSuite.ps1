#Requires -Version 5.1
# Runs the repository tests with an explicitly selected Pester version.
[CmdletBinding()]
param(
    [string]$PesterVersion = '5.9.0',
    [string]$TestPath
)

if ([string]::IsNullOrWhiteSpace($TestPath)) {
    $TestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests'
}

$requirementsPath = Join-Path $PSScriptRoot 'ValidationRequirements.psd1'
if (-not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) {
    Write-Error "Validation requirements manifest not found: $requirementsPath"
    exit 2
}
$requirements = Import-PowerShellDataFile -LiteralPath $requirementsPath
$declaredPesterVersions = @($requirements.TestMatrix | ForEach-Object { [string]$_.PesterVersion } | Select-Object -Unique)
if ($declaredPesterVersions -notcontains $PesterVersion) {
    Write-Error "Pester $PesterVersion is not declared in the validation matrix: $($declaredPesterVersions -join ', ')"
    exit 2
}

$available = @(Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [version]$PesterVersion })
if ($available.Count -eq 0) {
    Write-Error "Pester $PesterVersion is not installed. Install it explicitly with: Install-Module Pester -RequiredVersion $PesterVersion -Scope CurrentUser"
    exit 2
}

Import-Module Pester -RequiredVersion $PesterVersion -Force
$result = Invoke-Pester -Path $TestPath -Output Normal -PassThru
if ($result.FailedCount -gt 0) {
    Write-Error "Pester reported $($result.FailedCount) failed test(s)."
    exit 1
}

Write-Host "Pester $PesterVersion passed $($result.PassedCount) test(s) under $($PSVersionTable.PSVersion)."
exit 0
