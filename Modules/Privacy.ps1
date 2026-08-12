# ============================================================================
# MODULE: Privacy Cleanup
# Phase 7: Clear browser caches, diagnostics, thumbnails, recent files, optional event logs
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Privacy] Running privacy cleanup..." "SECTION"
Write-Rationale 'Privacy'

$clearEventLogs = if ($script:configOverrides.ContainsKey('ClearEventLogs')) { @($script:configOverrides.ClearEventLogs) } else { @() }
$allowPrivacyCleanup = Test-IrreversibleOperationAllowed -Name 'Privacy file and event-log cleanup'

if (-not $DryRun -and $allowPrivacyCleanup) {
    Write-Log "  Clearing browser caches, diagnostics, thumbnails, and recent files..." "INFO"
    Invoke-TrackedOperation -Name 'Privacy file cleanup' -Action 'Delete privacy caches and recent files' -Scope 'CurrentUser' -Operation {
        @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache\*",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache\*",
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*",
            "$env:ProgramData\Microsoft\Diagnosis\*",
            "$env:LOCALAPPDATA\Diagnostics\*",
            "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\*.db",
            "$env:APPDATA\Microsoft\Windows\Recent\*",
            "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*",
            "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*"
        ) | ForEach-Object {
            Get-ChildItem -Path $_ -Force -EA 0 | Remove-Item -Recurse -Force -EA Stop
        }
    } | Out-Null

    if ($clearEventLogs.Count -gt 0) {
        Write-Log "  Clearing configured event logs: $($clearEventLogs -join ', ')" "INFO"
        foreach ($eventLogName in $clearEventLogs) {
            Invoke-TrackedOperation -Name $eventLogName -Action 'Clear event log' -Scope 'Machine' -Operation {
                & wevtutil cl "$eventLogName" 2>$null
                if ($LASTEXITCODE -ne 0) { throw "wevtutil exited with code $LASTEXITCODE" }
            } | Out-Null
        }
    } else {
        Register-OperationResult -Name 'Event log clearing' -Action 'Clear configured event logs' -Scope 'Machine' -Status 'Skipped' -ErrorMessage 'No event logs configured'
        Write-Log "  Event log clearing skipped (set ClearEventLogs in config to opt in)" "INFO"
    }
} elseif ($DryRun) {
    Invoke-TrackedOperation -Name 'Privacy file cleanup' -Action 'Delete privacy caches and recent files' -Scope 'CurrentUser' -Operation { } | Out-Null
    if ($clearEventLogs.Count -gt 0) {
        foreach ($eventLogName in $clearEventLogs) {
            Invoke-TrackedOperation -Name $eventLogName -Action 'Clear event log' -Scope 'Machine' -Operation { } | Out-Null
        }
        Write-Log "  [DRY RUN] Would clear browser caches, diagnostics, thumbnails, recent files, and configured event logs: $($clearEventLogs -join ', ')" "INFO"
    } else {
        Register-OperationResult -Name 'Event log clearing' -Action 'Clear configured event logs' -Scope 'Machine' -Status 'Skipped' -ErrorMessage 'No event logs configured'
        Write-Log "  [DRY RUN] Would clear browser caches, diagnostics, thumbnails, and recent files; event log clearing would be skipped" "INFO"
    }
} else {
    Write-Log "  Privacy file and event-log cleanup skipped (explicit approval required)" "WARNING"
}

# Disable app usage tracking
Set-Reg -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0

Write-Log "  Privacy cleanup complete" "SUCCESS"
