# Offline validation requirements. This file declares acceptable versions; it
# never installs or downloads modules.
@{
    SchemaVersion = 1
    PowerShell = @{
        WindowsPowerShellMinimum = '5.1.0'
        PowerShellMinimum = '7.4.0'
        SupportedMajors = @('5','7')
    }
    TestMatrix = @(
        @{ Shell = 'Windows PowerShell 5.1'; PesterVersion = '5.9.0' }
        @{ Shell = 'PowerShell 7'; PesterVersion = '5.9.0' }
        @{ Shell = 'PowerShell 7'; PesterVersion = '6.0.1' }
    )
    Modules = @(
        @{ Name = 'Pester'; Required = $true; AllowedVersions = @('5.9.0','6.0.1') }
        @{ Name = 'PSScriptAnalyzer'; Required = $true; AllowedVersions = @('1.25.0') }
    )
}
