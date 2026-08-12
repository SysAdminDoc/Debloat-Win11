# Changelog

All notable changes to Debloat-Win11 will be documented in this file.

## [Unreleased]

### Fixed
- Maintenance and drift remediation now apply HKCU tweaks directly to already-loaded user hives, including profiles active while the task runs as SYSTEM.
- Shared HKCU propagation honors optional registry `Type` metadata instead of forcing every value to `REG_DWORD`.
- AppX removal counters now include provisioned-only packages while avoiding duplicate manifest entries.

### Tests
- Added coverage for loaded-profile propagation, typed HKCU writes, and provisioned-only AppX counting.

## [v2.3.9] - 2026-07-01

### Fixed
- Stale lockfile from crashed runs now detected via PID check instead of permanently blocking future executions.
- Lockfile event handler cleanup now captures the path via closure instead of broken `$script:` scope reference.
- Revert script generation properly quotes string registry values to prevent broken PowerShell output.
- Eliminated double-disable of DiagTrack, dmwappushservice, lfsvc, and Fax between SystemTweaks_Privacy and Services phases.
- Temp file cleanup now gated behind Privacy phase check instead of running unconditionally.
- Firewall rules correctly pass `Program=System` for kernel-level file/printer sharing rules instead of dropping it.
- OneDrive removal checks per-profile file count before deleting across multi-user profiles.
- Maintenance script counter tracks individual settings re-applied, not profiles visited.

### Added
- Paint AI policies (Cocreator, ImageCreator, GenerativeFill) and Notepad DisableAIFeatures unified into `WindowsAiPolicies.psd1` shared map.
- Drift detection summary reports total checks performed.
- Pester tests for lockfile stale PID, revert script quoting, service dedup, temp cleanup gating, shared AI map coverage, OneDrive safety, and firewall Program parameter.

### Changed
- Removed duplicate Win32_ComputerSystem CIM query in hardware detection.

## [v2.3.8] - 2026-06-28

### Tests
- Expanded Pester behavior coverage for destructive operations using mocks instead of host mutation.

## [v2.3.7] - 2026-06-28

### Added
- Added local PSScriptAnalyzer settings and a static-analysis gate for PowerShell 5.1 compatibility checks.

## [v2.3.6] - 2026-06-28

### Fixed
- HTML reports now encode all manifest-derived table values before rendering.

## [v2.3.5] - 2026-06-28

### Fixed
- WIM mode now honors `-ConfigPath` remove patterns and discards mounted image changes on failure after unloading offline hives.

## [v2.3.4] - 2026-06-28

### Added
- Added PFN validation, DynamicRemovalList CSP payload logging, registry-shape validation, and GPO/Intune conflict warnings for RemoveDefaultMicrosoftStorePackages.

## [v2.3.3] - 2026-06-28

### Fixed
- Aligned WindowsAI policy scope handling with Microsoft Policy CSP documentation, including user-scope `DisableRecallDataProviders`.

### Added
- Added shared WindowsAI policy definitions for apply, drift detection, remediation, maintenance, and tests.
- Represented Copilot hardware-key policy metadata without applying a deployment-specific AUMID by default.

## [v2.3.2] - 2026-06-28

### Fixed
- Made Privacy event-log clearing explicit opt-in through `ClearEventLogs` instead of clearing all Windows event logs by default.

### Added
- Added Pester coverage for default event-log preservation, targeted log clearing, and config-key validation.

## [v2.3.1] - 2026-06-28

### Fixed
- Preserved original service startup types before the PowerShell 7 parallel service-disable path mutates services, restoring undo/revert fidelity.

### Added
- Added Pester coverage that verifies PowerShell 7 service manifest entries come from pre-mutation snapshots.

## [v2.3.0] - 2026-06-27

### Added
- Expanded 25H2/26H1 AppX removal coverage for Copilot provider, Windows Backup, File Explorer extension, CrossDevice/WebExperience, PC Manager, AIHub, M365 Companions, and Start Experiences packages.
- Added newer package family names to the Enterprise/Education RemoveDefaultMicrosoftStorePackages policy list.
- Added drift detection and remediation parity for Remote Agent Connectors, Recall data providers, and Recall export blocking.
- Added shared HKCU maintenance tweaks for per-user Copilot, Recall, Windows Backup, and account-notification suppression.

### Changed
- Bumped all version strings, registry stamp, detection script, README badge, and generated-report text to v2.3.0.
- Updated documentation to reflect local-only validation.

## [v2.0.0] - 2026-06-19

### Added
- Real `-UndoFile` mode replays a manifest to reverse a prior run
- Per-phase `-Only` / `-Skip` flags for surgical runs
- Config file support (`-ConfigPath`) with presets (corporate, developer, medical, kiosk)
- Progress bar in interactive mode; `-Silent` suppresses console output
- Smart Office detection (ClickToRun, standalone, Visio/Project, running processes)
- Parallel service disable via `ForEach-Object -Parallel` on PS7+
- 26H1+ AI controls (Click to Do, Settings Agent, Agent Workspaces, M365 Copilot blocking)
- New AppX targets: PCManager, AIHub, M365Companions, OutlookForWindows, StartExperiencesApp
- `-Explain` mode prints rationale for each phase without making changes
- `-RestoreApp` reinstalls a removed package via winget
- `-DiffManifests` compares two undo manifests side-by-side
- `-WimPath` offline WIM image debloat for sysprep/MDT/WDS workflows
- Enterprise LTSC edition detection (skips consumer-only phases)
- S Mode detection (aborts with clear message)
- Tamper Protection pre-flight detection with warnings
- Windows EventLog integration (Application log, source: Debloat-Win11) for SIEM
- Post-update maintenance task (`Debloat-Win11-Maintain.ps1`) re-applies privacy tweaks
- Self-contained HTML report with Catppuccin dark theme
- Crash dump collection (`%TEMP%\Debloat-Win11-crash-*.zip`) on errors
- winget upgrade phase for keeping surviving apps current
- Fresh-OOBE mode (suppresses setup/privacy prompts for new user profiles)
- Intel chipset driver safeguard in OEM cleanup
- Pester test suite (27 tests) + local validation

### Fixed
- Removed `slmgr.vbs /upk` call that stripped Windows activation key during Office removal
- Fixed WSAIFabricSvc comment (was mislabeled as "Windows Subsystem for Android")
- Deduplicated ContentDeliveryManager registry writes (were applied 4x each)
- Synced all version strings to v2.0.0 (README, CHANGELOG, script header, detection script)

## [v1.1.0] - 2026-03-18

### Added
- Configurable log path via `-LogDir` parameter
- DryRun mode (`-DryRun`)
- End-of-run summary report
- JSON undo manifest for change tracking/reversal
- Windows 11 24H2/25H2 coverage (Recall, Copilot, Spotlight, Suggested Actions, Teams, Phone Link)
- `-SkipOfficeRemoval`, `-SkipOneDriveRemoval`, `-KeepDefender` switches

## [v1.0.0] - 2025-01-01

### Added
- Initial release with hardware detection, pre-flight checks, comprehensive logging
- AppX removal (80+ packages), OEM cleanup (6 manufacturers)
- Privacy/telemetry registry tweaks, service disabling, Edge configuration
- OneDrive/Office usage detection with conditional preservation

## Roadmap archive — 2026-08-10 — ROADMAP.md

<details>
<summary>Original roadmap snapshot</summary>

```markdown
# Debloat-Win11 Roadmap

## Research-Driven Additions

- [ ] P2 — Maintenance/remediation HKCU propagation skips logged-in users
  Why: `reg load` fails for profiles of currently logged-in users; their HKCU tweaks are not re-applied by the scheduled task running as SYSTEM
  Where: Debloat-Win11-Maintain.ps1, Remediate-Drift.ps1
- [ ] P3 — AllUsers HKCU propagation hardcodes REG_DWORD for all values
  Why: If a String-type tweak is added to HkcuTweaks.psd1, the AllUsers/maintenance/remediation paths will write it as REG_DWORD
  Where: Modules/SystemTweaks_System.ps1:213, Debloat-Win11-Maintain.ps1:113, Remediate-Drift.ps1:83
- [ ] P3 — AppxRemoved counter undercounts provisioned-only packages
  Why: Remove-AppxDryRun only increments the counter for user-installed packages, not provisioned-only ones
  Where: Debloat-Win11.ps1 Remove-AppxDryRun function
```

</details>
