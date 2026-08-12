# ============================================================================
# SystemTweaks sub-module: Start Menu only
# Dot-sourced by SystemTweaks.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Start Menu] Cleaning pinned items..." "SECTION"
$allowStartMenuCleanup = Test-IrreversibleOperationAllowed -Name 'Start Menu tile cleanup'
if (-not $DryRun -and $allowStartMenuCleanup) {
    $startLayoutPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
    if (Test-Path $startLayoutPath) {
        Get-ChildItem "$startLayoutPath\*windows.data.unifiedtile*" -EA 0 | Remove-Item -Recurse -Force -EA 0
        Get-ChildItem "$startLayoutPath\*windows.data.taskmgr*" -EA 0 | Remove-Item -Recurse -Force -EA 0
    }
} elseif ($DryRun) {
    Write-Log "  [DRY RUN] Would remove stale Start Menu tile state" "INFO"
} else {
    Write-Log "  Start Menu tile cleanup skipped (explicit approval required)" "WARNING"
}
Set-Reg -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "FeatureManagementEnabled" -Value 0
Write-Log "  Start Menu cleaned" "SUCCESS"
