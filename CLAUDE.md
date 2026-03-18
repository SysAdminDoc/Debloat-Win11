# CLAUDE.md - Debloat-Win11

## Overview
Enterprise Windows 11 debloating script targeting Maven Imaging deployments. Removes AppX bloatware, Office/365, OEM software, telemetry services/tasks, and applies privacy/performance registry tweaks.

## Tech Stack
- PowerShell 5.1, CLI/console (no GUI)
- Logging to `C:\Maven\Logs`

## Key Details
- ~2,469 lines, single-file
- Domain-aware (skips GPO-managed settings)
- Pre-flight disk space + Windows version checks
- Unattended deployment compatible
- Maven-specific log path (`C:\Maven\Logs`)

## Build/Run
```powershell
# Run as Administrator
.\Debloat-Win11.ps1
```

## Gotchas
- Log path is hardcoded to `C:\Maven\Logs` (internal production use)
- Targets Windows 10 build 10240+ / Windows 11 build 22000+
