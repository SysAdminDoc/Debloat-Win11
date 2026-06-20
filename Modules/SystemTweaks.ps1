# ============================================================================
# MODULE: System Tweaks (shim)
# Dot-sources sub-modules for privacy, UI, performance, and system config.
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope.
# ============================================================================
Write-Log "[System Tweaks] Applying registry tweaks..." "SECTION"
Write-Rationale 'SystemTweaks'

. "$PSScriptRoot\SystemTweaks_Privacy.ps1"
. "$PSScriptRoot\SystemTweaks_UI.ps1"
. "$PSScriptRoot\SystemTweaks_Perf.ps1"
. "$PSScriptRoot\SystemTweaks_System.ps1"
