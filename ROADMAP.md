# Debloat-Win11 Roadmap

## Research-Driven Additions

- [ ] P2 - Expand Pester behavior tests around destructive operations
  Why: Existing tests catch source patterns but do not fully prove mutation order, opt-in destructive actions, WIM cleanup, or drift/remediation parity.
  Evidence: `tests/Debloat-Win11.Tests.ps1`, Pester mocking docs
  Touches: `tests/Debloat-Win11.Tests.ps1`
  Acceptance: Tests mock `Stop-Service`, `Set-Service`, `wevtutil`, `Mount-WindowsImage`, registry setters, and report generation to prove behavior without mutating the host.
  Complexity: M
