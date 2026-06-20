# ============================================================================
# MODULE: AppX Package Removal
# Phase 1: Remove bloatware AppX packages (user + provisioned)
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Phase 1/7] Removing bloatware packages..." "SECTION"
Write-Rationale 'AppX'
if ($script:isLTSC) {
    Write-Log "  LTSC edition: most consumer AppX packages are not present -- removals will be no-ops" "INFO"
}

# Allow config file to override; fall back to the canonical list from the orchestrator
$removePatterns = if ($script:configOverrides.ContainsKey('RemovePatterns')) { $script:configOverrides.RemovePatterns } else { $script:defaultRemovePatterns }

foreach ($pattern in $removePatterns) {
    Remove-AppxDryRun -Pattern $pattern
}

# Explicit Xbox/Gaming removal (Xbox Live, Gaming Services)
Remove-AppxDryRun -Pattern '*Xbox*'
Remove-AppxDryRun -Pattern '*Gaming*'
if (-not $DryRun) {
    Get-AppxProvisionedPackage -Online 2>$null | Where-Object { $_.DisplayName -match 'Xbox|Gaming' } | Remove-AppxProvisionedPackage -Online 2>$null
}

# Remove Xbox folders
if (-not $DryRun) {
    @(
        "$env:LOCALAPPDATA\Packages\Microsoft.XboxIdentityProvider*",
        "$env:LOCALAPPDATA\Packages\Microsoft.Xbox*",
        "$env:LOCALAPPDATA\Packages\Microsoft.GamingServices*"
    ) | ForEach-Object {
        Get-Item $_ -EA 0 | Remove-Item -Recurse -Force -EA 0
    }
}

Write-Log "  Bloatware packages removed" "SUCCESS"

# Remove Remote Desktop Connection shortcuts (mstsc is a system component)
if (-not $DryRun) {
    Write-Log "  Removing Remote Desktop shortcuts..." "INFO"
    @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\Remote Desktop Connection.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Windows Accessories\Remote Desktop Connection.lnk",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Accessories\Remote Desktop Connection.lnk"
    ) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force -EA 0 }
    }
}
