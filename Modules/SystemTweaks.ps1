# ============================================================================
# MODULE: System Tweaks (shim)
# Dot-sources sub-modules for privacy, UI, performance, and system config.
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope.
# ============================================================================
if (Test-PhaseEnabled 'SystemTweaks') {
    Write-Log "[System Tweaks] Applying selected registry tweaks..." "SECTION"
    Write-Rationale 'SystemTweaks'

    $script:systemTweaksCoreSelected = Test-SystemTweaksCoreSelected
    if ($script:systemTweaksCoreSelected) {
        . "$PSScriptRoot\SystemTweaks_Privacy.ps1"
        . "$PSScriptRoot\SystemTweaks_UI.ps1"
        if (Test-SystemTweakEnabled 'StartMenu') {
            . "$PSScriptRoot\SystemTweaks_StartMenu.ps1"
        }
        . "$PSScriptRoot\SystemTweaks_System.ps1"
    } elseif (Test-SystemTweakEnabled 'StartMenu') {
        . "$PSScriptRoot\SystemTweaks_StartMenu.ps1"
    }

    if ($script:systemTweaksCoreSelected -or
        (Test-SystemTweakEnabled 'Power') -or
        (Test-SystemTweakEnabled 'Network')) {
        . "$PSScriptRoot\SystemTweaks_Perf.ps1"
    }
} else {
    Write-Log "[System Tweaks] SKIPPED (phase excluded)" "INFO"
}
