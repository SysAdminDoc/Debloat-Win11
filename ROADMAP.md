# Debloat-Win11 Roadmap

No actionable roadmap items remain.

## Research-Driven Additions

- [ ] P0 - Preserve service startup types in the PowerShell 7 path
  Why: Undo/revert fidelity breaks when the parallel service path records startup type after disabling services.
  Evidence: `Modules/Services.ps1:70-86`, `Debloat-Win11.ps1:760-772`
  Touches: `Modules/Services.ps1`, `tests/Debloat-Win11.Tests.ps1`
  Acceptance: PowerShell 7 service cleanup snapshots startup types before mutation, generated manifest/revert script restores the original type, and Pester mocks prove the order.
  Complexity: S

- [ ] P0 - Make event-log clearing explicit opt-in
  Why: Clearing every Windows event log conflicts with managed-device audit/SIEM expectations.
  Evidence: `Modules/Privacy.ps1:37-39`, README EventLog/SIEM claims, O&O ShutUp10++ restore/audit positioning
  Touches: `Modules/Privacy.ps1`, `Debloat-Win11.ps1`, `debloat.example.psd1`, `tests/Debloat-Win11.Tests.ps1`
  Acceptance: Default `Privacy` no longer clears event logs; a documented config key enables targeted log clearing; DryRun reports the chosen behavior.
  Complexity: M

- [ ] P1 - Align WindowsAI policy scope and names with Microsoft docs
  Why: `DisableRecallDataProviders` is currently treated as HKLM/device policy, while Microsoft documents it as user-scope; newer connector and hardware-key policies are not represented.
  Evidence: `Modules/SystemTweaks_Privacy.ps1:48-56`, `Detect-Drift.ps1:22-26`, Microsoft WindowsAI Policy CSP
  Touches: `Modules/SystemTweaks_Privacy.ps1`, `Modules/HkcuTweaks.psd1`, `Detect-Drift.ps1`, `Remediate-Drift.ps1`, `Debloat-Win11-Maintain.ps1`, `tests/Debloat-Win11.Tests.ps1`
  Acceptance: WindowsAI policy definitions are driven from a shared map with correct HKLM/HKCU scope, drift/remediation parity, and tests for `DisableRecallDataProviders`, connector policies, and hardware key handling.
  Complexity: M

- [ ] P1 - Validate and package RemoveDefaultMicrosoftStorePackages policy output
  Why: Microsoft documents CSP XML/static IDs/dynamic PFN list behavior and GPO/MDM conflict rules that need validation against the direct registry writes.
  Evidence: `Modules/AppX.ps1:34-80`, Microsoft policy-based in-box app removal docs
  Touches: `Modules/AppX.ps1`, `Debloat-Win11.ps1`, `tests/Debloat-Win11.Tests.ps1`, README deployment section
  Acceptance: Script can emit or log a Microsoft-compatible policy payload, validates registry shape on supported Enterprise/Education builds, warns on MDM/GPO conflict risk, and includes tests for PFN formatting.
  Complexity: M

- [ ] P1 - Add WIM-mode failure cleanup and config parity
  Why: Offline image mode can leave mounts behind on failure and ignores `-ConfigPath` remove patterns.
  Evidence: `Debloat-Win11.ps1:458-547`, Winhance ISO tooling, tiny11builder offline servicing pattern
  Touches: `Debloat-Win11.ps1`, `tests/Debloat-Win11.Tests.ps1`
  Acceptance: WIM mode uses try/finally with save/discard behavior, honors config remove patterns, reports offline changes, and has mocked tests for mount failure, removal failure, and cleanup.
  Complexity: M

- [ ] P2 - HTML-encode all report table values
  Why: Manifest values are interpolated directly into HTML and can corrupt or inject report markup.
  Evidence: `Debloat-Win11.ps1:1466-1475`
  Touches: `Debloat-Win11.ps1`, `tests/Debloat-Win11.Tests.ps1`
  Acceptance: Report generation encodes registry paths, names, old/new values, services, app names, and task names; tests cover `<`, `>`, `&`, quotes, and apostrophes.
  Complexity: S

- [ ] P2 - Add local PSScriptAnalyzer gate for PowerShell 5.1 compatibility
  Why: The project targets Windows PowerShell 5.1 and uses direct system mutation; static analysis can catch incompatible commands and quality defects before release.
  Evidence: `#Requires -Version 5.1`, tests are currently Pester-only, Microsoft PSScriptAnalyzer docs
  Touches: `PSScriptAnalyzerSettings.psd1`, `tests/Debloat-Win11.Tests.ps1`, README validation section
  Acceptance: Local validation runs PSScriptAnalyzer across all `.ps1`/`.psd1` files with compatibility rules, excludes only documented false positives, and fails on errors.
  Complexity: S

- [ ] P2 - Expand Pester behavior tests around destructive operations
  Why: Existing tests catch source patterns but do not fully prove mutation order, opt-in destructive actions, WIM cleanup, or drift/remediation parity.
  Evidence: `tests/Debloat-Win11.Tests.ps1`, Pester mocking docs
  Touches: `tests/Debloat-Win11.Tests.ps1`
  Acceptance: Tests mock `Stop-Service`, `Set-Service`, `wevtutil`, `Mount-WindowsImage`, registry setters, and report generation to prove behavior without mutating the host.
  Complexity: M
