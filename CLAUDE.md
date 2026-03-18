# CLAUDE.md - Debloat-Win11

## Overview
Enterprise Windows 11 debloating script targeting Maven Imaging deployments. Removes AppX bloatware, Office/365, OEM software, telemetry services/tasks, and applies privacy/performance registry tweaks.

## Version
v1.1.0

## Tech Stack
- PowerShell 5.1, CLI/console (no GUI)
- Configurable log path (default: `$env:ProgramData\Debloat-Win11\Logs`)

## Key Details
- ~2,800 lines, single-file
- Domain-aware (skips GPO-managed settings)
- Pre-flight disk space + Windows version checks
- Unattended deployment compatible
- DryRun mode (`-DryRun`) for scan-only operation
- Undo manifest (JSON) records every change with old/new values
- End-of-run summary report (counts, disk space, runtime)
- Windows 11 24H2/25H2 coverage (Recall, Copilot, Spotlight, Suggested Actions, Teams new, Phone Link)

## Parameters
```powershell
param(
    [string]$LogDir = "$env:ProgramData\Debloat-Win11\Logs",
    [switch]$DryRun,
    [switch]$SkipOfficeRemoval,
    [switch]$SkipOneDriveRemoval,
    [switch]$KeepDefender
)
```

## Build/Run
```powershell
# Run as Administrator (default)
.\Debloat-Win11.ps1

# Custom log path
.\Debloat-Win11.ps1 -LogDir "C:\Logs"

# Dry run (no changes, report only)
.\Debloat-Win11.ps1 -DryRun

# Skip Office and OneDrive removal
.\Debloat-Win11.ps1 -SkipOfficeRemoval -SkipOneDriveRemoval
```

## Output Files
- Log: `<LogDir>\Debloat-YYYY-MM-DD-HHmmss.log`
- Undo manifest: `<LogDir>\Debloat-Undo-YYYY-MM-DD-HHmmss.json`

## Gotchas
- No emoji/unicode in PowerShell output (encoding errors)
- Targets Windows 10 build 10240+ / Windows 11 build 22000+
- `Set-Reg` wrapper captures old values for undo manifest
- DryRun wraps all destructive ops with `if (-not $DryRun)` guards

## Changelog
- v1.1.0: Configurable log path, DryRun mode, summary report, undo manifest, 24H2/25H2 updates
- v1.0.0: Initial version (hardcoded log path, ~2,469 lines)
