# Intune Win32 App Detection Script for Debloat-Win11
# Returns exit 0 (detected/installed) if a valid undo manifest exists
# matching the expected version. Returns exit 1 otherwise.
#
# Usage in Intune:
#   Detection rule type: Custom script
#   Script file: Detect-Debloat.ps1
#   Run script as 32-bit process: No

$expectedVersion = 'v2.1.0'
$logDir = "$env:ProgramData\Debloat-Win11\Logs"

if (!(Test-Path $logDir)) { exit 1 }

# Find the most recent manifest file
$manifests = Get-ChildItem -Path $logDir -Filter 'Debloat-Manifest-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if ($manifests.Count -eq 0) { exit 1 }

$latestManifest = $manifests[0]

try {
    $data = Get-Content $latestManifest.FullName -Raw | ConvertFrom-Json

    # Check version matches and it was not a dry run
    if ($data.version -eq $expectedVersion -and $data.dryrun -eq $false) {
        Write-Output "Debloat-Win11 $expectedVersion detected (manifest: $($latestManifest.Name))"
        exit 0
    }
} catch {
    # Malformed JSON
}

exit 1
