# Debloat-Win11 Roadmap

PowerShell debloater with hardware detection, DryRun, and JSON undo manifest. Tracks work after v1.1.0.

## Planned Features

### Core
- Real `-Undo` mode that replays the JSON undo manifest to reverse a prior run (currently only System Restore)
- Module split: break the 2,800-line script into `Modules\` (`AppX.psm1`, `Services.psm1`, `Edge.psm1`, `Power.psm1`, `Logging.psm1`) with a thin `Debloat-Win11.ps1` orchestrator
- `#Requires -RunAsAdministrator` + `#Requires -Version 5.1` sentinel (fail fast instead of mid-script)
- Config file support (`-ConfigPath .\debloat.psd1`) so arrays (`$removePatterns`, `$servicesToDisable`, `$defenderExclusions`) live outside the script
- Per-phase `-Only` / `-Skip` flags (`-Only AppX,Services`) so MDM can run surgical subsets
- Progress bar in interactive mode via `Write-Progress`; suppress under `-Silent`

### Windows Coverage
- Track new 25H2 / 26H1 bloat as it ships (Copilot variants, new Store apps, Recall+, advertising SKUs)
- Detect and refuse to touch Enterprise LTSC editions of specific components that aren't present
- Add `winget upgrade --all --silent --include-unknown` optional phase for keeping surviving apps current
- Add an optional "fresh-OOBE" mode that also disables OOBE telemetry keys before user-profile config

### Deployment / Automation
- Publish as a signed `.ps1` + `.msi` wrapper for Intune Win32 app packaging
- Intune detection script: check undo manifest exists and version line matches
- SCCM CI/CB compliance baseline template bundled in `docs/sccm/`
- Ansible / Puppet / Chef wrappers in `contrib/` for cross-platform automation users
- PSGallery release: `Install-Module Debloat-Win11` invoking the same script

### Safety
- Pre-flight check: fail if the machine is in a known-problematic state (pending Feature Update, Windows Setup active, MSIX staging in progress)
- "Explain mode" that prints the rationale for each planned change next to its action
- Opt-in telemetry-free crash dump: on error, collect `%TEMP%\Debloat-Win11-crash-<ts>.zip` with logs, manifest, system info — never uploaded, just convenient for bug reports
- Smart Office detection: also check for OneNote 2016, Visio, Project, Access before bulk-removal
- Defender exclusions: optional prompt instead of hard-coded medical imaging paths

### UI (Optional)
- Lightweight WPF companion (`Debloat-Win11.GUI.ps1`) matching DisableDefender's pattern: Catppuccin Mocha, async runspace, live log stream
- Checkbox tree of planned changes before execution
- Tamper Protection status indicator at the top (informational, not actionable)

### Performance
- Replace serial `Get-AppxPackage` calls with a single pipeline to cut AppX phase from ~60s to < 15s
- Batch registry writes inside a single `reg.exe import` for phases with > 50 keys
- Parallel service-disable via `ForEach-Object -Parallel` (PS7 path) with a PS5 fallback

## Competitive Research

- **ChrisTitusTech/winutil** — Popular WPF tool with scriptable tweaks and App install manager. Better UX, weaker hardware awareness. Debloat-Win11 should steal its checkbox tree UI but keep the stricter safety model.
- **Raphire/Win11Debloat** — Flag-driven PowerShell with good Intune examples. Narrower scope than Debloat-Win11 but cleaner module structure — model the refactor on it.
- **builtbybel/ThisIsWin11** — Rich GUI but C# and Win11-only. Validates GUI direction; the companion WPF plan stays PowerShell-native to preserve deploy-as-script simplicity.
- **O&O ShutUp10++** — Closed-source but comprehensive privacy toggles; useful reference for keys Debloat-Win11 hasn't hit yet (WebGL fingerprint, Clipboard cloud history toggles).

## Nice-to-Haves

- HTML report (self-contained single file) summarizing every change with before/after values
- Optional "restore app" helper: given an AppX name, reinstall from Store via `winget install --id <id>`
- Image-customization mode that runs against a mounted WIM (`DISM /Mount-Image`) for sysprep-time debloat
- Per-user phase (currently most HKCU keys target the current user only) that also configures the Default user hive for future accounts
- Kiosk preset (remove Start Menu pins, hide taskbar search, force single-app mode) as a layered add-on
- Diff view: given two undo manifests, show which tweaks changed across two runs

## Open-Source Research (Round 2)

### Related OSS Projects
- **Raphire/Win11Debloat** — https://github.com/Raphire/Win11Debloat — Most-active single-file script; Copilot/Recall/Click-to-Do removal, Audit-mode support, multi-user provisioning flag.
- **ChrisTitusTech/winutil** — https://github.com/ChrisTitusTech/winutil — Full WPF hub: WinGet installer + tweaks + ISO creator + OOSU10 launcher; exportable JSON configs for re-apply.
- **undergroundwires/privacy.sexy** — https://github.com/undergroundwires/privacy.sexy — Open-source script generator; users select tweaks, tool emits a reviewed `.ps1`/`.bat`/`.sh` for air-gapped execution.
- **simeononsecurity/Windows-Optimize-Harden-Debloat** — https://github.com/simeononsecurity/Windows-Optimize-Harden-Debloat — DoD STIG/SRG-aligned hardening on top of debloat.
- **SamuelJayasingh/Universal-Windows-Debloater** — https://github.com/SamuelJayasingh/Universal-Windows-Debloater — Ships `Regfiles/` folder with explicit `.reg` undo pairs for each tweak.
- **Sycnex/Windows10Debloater** — https://github.com/Sycnex/Windows10Debloater — Three-mode distribution (interactive / GUI / pure-silent); one of the earliest reference scripts.
- **itsNileshHere/Windows-ISO-Debloater** — https://github.com/itsNileshHere/Windows-ISO-Debloater — Debloats offline install.wim/ISO before deployment.
- **farag2/Sophia-Script-for-Windows** — https://github.com/farag2/Sophia-Script-for-Windows — Highly structured PS module; every tweak is a parameterized function with `-Enable`/`-Disable`.

### Features to Borrow
- Audit-mode / multi-user provisioning: apply tweaks to the default profile so every new user inherits them — borrow from `Raphire/Win11Debloat`.
- Offline WIM/ISO debloating path (before first boot) — borrow from `Windows-ISO-Debloater`.
- "Script generator" flow where the user picks toggles and the tool emits a static `.ps1` with only the selected ops — borrow from `privacy.sexy`.
- Exportable JSON configuration with import to re-apply across fleet — borrow from `winutil` (`Get-ControlPanel`→ JSON → apply).
- Per-tweak paired `.reg`-undo file generated alongside the operation — borrow from `SamuelJayasingh/Universal-Windows-Debloater`.
- Parameterized module functions (`Disable-Telemetry -Enable` / `-Disable`) instead of monolithic if/else — borrow from `Sophia-Script-for-Windows`.
- Built-in launcher for OOSU10 / privacy.sexy script for users who want finer telemetry control — borrow from `winutil` shelling out to OOSU10.
- STIG/SRG category tagging on every tweak (`-Category Compliance` vs `-Category Convenience`) — borrow from `simeononsecurity`.

### Patterns & Architectures Worth Studying
- `Sophia-Script-for-Windows` module layout: one function per tweak, pure parameters, tested individually — gold standard for maintainable debloat scripts.
- `winutil` WPF hub that shells out to specialist tools rather than reimplementing them — reduces scope creep and keeps this script focused.
- `privacy.sexy`'s declarative YAML of tweaks → compiled to multiple script languages — would let Debloat-Win11 emit both PowerShell and an Intune/SCCM-friendly format from one source.
- `Raphire/Win11Debloat`'s GPO-vs-registry fallback logic for Home-edition compatibility — essential given ~40% of policy keys are ignored on Home.
