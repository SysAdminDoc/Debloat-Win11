# Debloat-Win11 Roadmap

Actionable work only. Historical and completed roadmap material is archived in CHANGELOG.md; blocked work is kept in Roadmap_Blocked.md.

## Actionable Items

- [ ] P2 — Maintenance/remediation HKCU propagation skips logged-in users
  Why: `reg load` fails for profiles of currently logged-in users; their HKCU tweaks are not re-applied by the scheduled task running as SYSTEM
  Where: Debloat-Win11-Maintain.ps1, Remediate-Drift.ps1

- [ ] P3 — AllUsers HKCU propagation hardcodes REG_DWORD for all values
  Why: If a String-type tweak is added to HkcuTweaks.psd1, the AllUsers/maintenance/remediation paths will write it as REG_DWORD
  Where: Modules/SystemTweaks_System.ps1:213, Debloat-Win11-Maintain.ps1:113, Remediate-Drift.ps1:83

- [ ] P3 — AppxRemoved counter undercounts provisioned-only packages
  Why: Remove-AppxDryRun only increments the counter for user-installed packages, not provisioned-only ones
  Where: Debloat-Win11.ps1 Remove-AppxDryRun function
