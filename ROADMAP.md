# Debloat-Win11 Roadmap

## Research-Driven Additions

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
