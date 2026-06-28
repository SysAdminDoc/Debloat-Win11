# Debloat-Win11 Roadmap

## Research-Driven Additions

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
