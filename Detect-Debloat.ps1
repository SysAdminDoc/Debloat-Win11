# Intune Win32 App Detection Script for Debloat-Win11
# Returns exit 0 (detected/installed) if a valid undo manifest exists
# matching the expected version. Returns exit 1 otherwise.
#
# Usage in Intune:
#   Detection rule type: Custom script
#   Script file: Detect-Debloat.ps1
#   Run script as 32-bit process: No

$expectedVersion = 'v2.3.3'
$logDir = "$env:ProgramData\Debloat-Win11\Logs"

# Check registry stamp first (survives file cleanup, compatible with Intune native rules)
$regStamp = Get-ItemProperty "HKLM:\SOFTWARE\Debloat-Win11" -EA SilentlyContinue
if ($regStamp -and $regStamp.Version -eq $expectedVersion) {
    Write-Output "Debloat-Win11 $expectedVersion detected (registry stamp)"
    exit 0
}

# Fallback: check manifest file
if (Test-Path $logDir) {
    $manifests = Get-ChildItem -Path $logDir -Filter 'Debloat-Manifest-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($manifests.Count -gt 0) {
        try {
            $data = Get-Content $manifests[0].FullName -Raw | ConvertFrom-Json
            if ($data.version -eq $expectedVersion -and $data.dryrun -eq $false) {
                Write-Output "Debloat-Win11 $expectedVersion detected (manifest: $($manifests[0].Name))"
                exit 0
            }
        } catch {}
    }
}

exit 1
