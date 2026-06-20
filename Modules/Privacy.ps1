# ============================================================================
# MODULE: Privacy Cleanup
# Phase 7: Clear browser caches, diagnostics, thumbnails, recent files, event logs
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Privacy] Running privacy cleanup..." "SECTION"
Write-Rationale 'Privacy'

if (-not $DryRun) {
    # Clear browser caches
    Write-Log "  Clearing browser caches..." "INFO"
    @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"
    ) | ForEach-Object {
        if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force -EA 0 }
    }

    # Clear diagnostics logs
    Write-Log "  Clearing diagnostics logs..." "INFO"
    Remove-Item "$env:ProgramData\Microsoft\Diagnosis\*" -Recurse -Force -EA 0
    Remove-Item "$env:LOCALAPPDATA\Diagnostics\*" -Recurse -Force -EA 0

    # Clear thumbnail cache
    Write-Log "  Clearing thumbnail cache..." "INFO"
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\*.db" -Force -EA 0

    # Clear recent files
    Write-Log "  Clearing recent files..." "INFO"
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -EA 0
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*" -Force -EA 0
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*" -Force -EA 0

    # Clear event logs
    Write-Log "  Clearing event logs..." "INFO"
    wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
} else {
    Write-Log "  [DRY RUN] Would clear browser caches, diagnostics, thumbnails, recent files, event logs" "INFO"
}

# Disable app usage tracking
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0

Write-Log "  Privacy cleanup complete" "SUCCESS"
