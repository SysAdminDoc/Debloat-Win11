# Intune Proactive Remediation - Drift Detection Script
# Returns exit 0 (compliant) if all debloat settings are intact.
# Returns exit 1 (non-compliant) if any settings have drifted.
#
# Usage in Intune:
#   Proactive Remediations > Create script package
#   Detection script: Detect-Drift.ps1
#   Remediation script: Remediate-Drift.ps1
#   Run as: System

$ErrorActionPreference = "SilentlyContinue"

$driftChecks = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableSettingsAgent'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAgentWorkspaces'; Expected = 2 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Paint'; Name = 'DisableCocreator'; Expected = 1 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Expected = 0 }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeCopilotEnabled'; Expected = 0 }
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Name = 'UseLogonCredential'; Expected = 0 }
)

$drifted = 0
foreach ($check in $driftChecks) {
    $current = Get-ItemProperty -Path $check.Path -Name $check.Name -EA 0
    if ($null -eq $current -or $current.$($check.Name) -ne $check.Expected) {
        $drifted++
    }
}

if ($drifted -gt 0) {
    Write-Output "Debloat-Win11: $drifted settings have drifted"
    exit 1
}

Write-Output "Debloat-Win11: All settings compliant"
exit 0
