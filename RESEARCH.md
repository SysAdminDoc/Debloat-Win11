# Research - Debloat-Win11

## Executive Summary
Debloat-Win11 is a modular PowerShell 5.1 Windows 10/11 debloat, privacy, optimization, and enterprise deployment script. Verified current strengths are strong: admin-only execution, DryRun/Explain modes, undo manifests plus generated revert scripts, config presets, drift detection/remediation, AllUsers HKCU propagation, Intune detection, EventLog reporting, WIM mode, and current 25H2/26H1 app and WindowsAI coverage. The highest-value direction is not adding a GUI; it is making the existing headless enterprise story more trustworthy. Top opportunities: fix PowerShell 7 service undo fidelity, stop clearing all Windows event logs by default, align WindowsAI policies with Microsoft scope/value names, validate the RemoveDefaultMicrosoftStorePackages registry payload against Microsoft's CSP/GPO model, add WIM-mode try/finally cleanup and ConfigPath parity, encode HTML reports, add PSScriptAnalyzer plus behavior tests, and add operator-visible policy/drift validation outputs.

## Product Map
- Core workflows: preflight safety checks, system/privacy/UI/performance tweaks, AppX/OEM/OneDrive/Office cleanup, service/task cleanup, Edge/firewall/privacy phases, report/manifest/revert generation, post-update remediation.
- User personas: IT admin deploying through Intune/SCCM/GPO/PDQ, MSP standardizing client PCs, Windows image builder using WIM/sysprep, power user running controlled local cleanup.
- Platforms and distribution: Windows 10 1903+ and Windows 11 24H2/25H2/26H1, PowerShell 5.1+, administrator context, direct folder/network-share execution, Intune proactive remediation companion scripts.
- Key integrations and data flows: registry policies, AppX/provisioned AppX, DISM WIM servicing, scheduled tasks, Windows EventLog, System Restore, Edge policy/bookmarks, Defender exclusions, HTML/JSON/PowerShell rollback artifacts.

## Competitive Landscape
- ChrisTitusTech/winutil: large preset-driven Windows utility with install/tweak/fix/update flows. Learn from named presets and exact preset visibility; avoid remote one-liner execution as the primary enterprise posture.
- Raphire/Win11Debloat: lightweight PowerShell debloater with export/import, Audit mode, other-user support, and clear reversible-change messaging. Learn from profile portability and sysprep/Audit workflows; avoid requiring interactive wizard flow.
- Sophia Script: mature function-by-function tweaker with explicit selectable functions and package-manager distribution. Learn from function-granular execution and inverse-action discipline; avoid too many Windows-version variants.
- Winhance: C# app with searchable sections, config export/import, WinGet install surface, ISO and autounattend support. Learn from settings-profile export and offline provisioning UX; avoid expanding this repo into a full GUI/ISO suite.
- RemoveWindowsAI: focused Windows AI removal project with CBS-level blocking and post-update cleanup. Learn from hidden-package coverage and update recheck thinking; avoid CBS mutation as a default because it risks servicing supportability.
- privacy.sexy: large privacy catalog with transparent, reversible generated scripts across platforms. Learn from per-tweak transparency and reversibility metadata; avoid web-generation workflow for managed Windows fleets.
- Bloatynosy/Optimizer: GUI-focused optimizer lineage with localization and broad tweak surfaces. Learn from concise risk explanations and localization demand; avoid broad optimizer sprawl that weakens Debloat-Win11's fleet-script identity.
- O&O ShutUp10++: commercial/privacy benchmark centered on risk categories and easy restore. Learn from risk labels and restore visibility; avoid opaque closed-source policy application.

## Security, Privacy, and Reliability
- Verified bug: `Modules/Services.ps1:70-86` disables services in the PowerShell 7 parallel path before recording `original_startup_type`, unlike `Debloat-Win11.ps1:760-772`; undo/revert can preserve `Disabled` instead of restoring the true prior startup mode.
- Verified risk: `Modules/Privacy.ps1:37-39` clears every Windows event log, conflicting with the project claim of audit/SIEM friendliness and potentially removing operational/security evidence from managed devices.
- Verified policy mismatch: `Modules/SystemTweaks_Privacy.ps1:55`, `Detect-Drift.ps1:25`, and `Remediate-Drift.ps1:38` set/check `DisableRecallDataProviders` under HKLM, while Microsoft documents it as a user-scope WindowsAI policy.
- Likely policy gap: the project sets `DisableAgentConnectors`, `DisableAgentWorkspaces`, and `DisableRemoteAgentConnectors`; Microsoft also documents `ConfigureAgentConnectors`, `AgentConnectorMinimumPolicy`, `AgentConsentDuration`, Windows assistant hardware-key behavior, and Recall deny-list policies that are not represented.
- Needs live validation: `Modules/AppX.ps1:34-80` writes numbered PFN values under `RemoveDefaultMicrosoftStorePackages`; Microsoft documents CSP XML with `DynamicRemovalList`, static app IDs, timing constraints, and GPO/MDM conflict warnings. Verify the registry shape on 24H2/25H2 Enterprise before relying on the current direct-write implementation.
- Verified resilience gap: `Debloat-Win11.ps1:458-547` WIM mode lacks try/finally dismount/discard handling and uses default remove patterns instead of honoring `-ConfigPath`.
- Verified report-safety gap: `Debloat-Win11.ps1:1466-1475` interpolates manifest values directly into HTML table cells without HTML encoding.
- Verified tooling gap: tests are useful but still mostly text/pattern assertions; Pester supports mocking command calls, and PSScriptAnalyzer can catch PowerShell compatibility and quality issues locally.

## Architecture Assessment
- Keep the CLI/headless architecture. It is the strongest differentiator versus GUI-first tools and fits Intune/SCCM/GPO/PDQ deployment.
- Add a small policy-validation layer rather than scattering new WindowsAI keys across scripts. A shared data map should drive apply, drift detect, remediation, AllUsers/HKCU propagation, and tests.
- Add a WIM cleanup boundary: mount state, failure path, dismount save/discard, config-aware remove patterns, and an offline summary report.
- Add a destructive-action classification layer for privacy cleanup. Event-log clearing, browser cache clearing, recent-file clearing, and diagnostics deletion should be separately controllable.
- Add local quality gates: PSScriptAnalyzer settings for Windows PowerShell 5.1 compatibility, behavior-focused Pester mocks around service disabling, WIM failure cleanup, WindowsAI scope, report encoding, and event-log opt-in.

## Rejected Ideas
- Full GUI: WinUtil/Winhance/Bloatynosy prove demand, but this repo's advantage is unattended fleet execution.
- CBS-level package removal/blocking: RemoveWindowsAI uses it, but default CBS mutation is too risky for supportable enterprise Windows servicing.
- Remote one-liner install as primary path: common in WinUtil/Win11Debloat, but direct network-share/package deployment is safer for managed environments.
- Cross-platform privacy tool: privacy.sexy does this well; Debloat-Win11 is Windows-specific by design.
- WinGet app installer catalog: useful in WinUtil/Winhance, but this repo should keep app installation separate from debloat policy.
- autounattend.xml generator: valuable in Winhance, but WIM/sysprep support is the better fit here.
- Multilingual GUI/i18n work: relevant for GUI tools, low value for this script's current CLI/report surface.
- Hosts/DNS blocking: seen in optimizer/privacy tools, but creates ongoing list maintenance and can break enterprise DNS/DoH/network policy.

## Sources
### Project
- https://github.com/SysAdminDoc/Debloat-Win11

### Competitors
- https://github.com/ChrisTitusTech/winutil
- https://github.com/Raphire/Win11Debloat
- https://github.com/farag2/Sophia-Script-for-Windows
- https://github.com/memstechtips/Winhance
- https://github.com/zoicware/RemoveWindowsAI
- https://github.com/undergroundwires/privacy.sexy
- https://github.com/builtbybel/Bloatynosy
- https://github.com/hellzerg/optimizer
- https://www.oo-software.com/en/shutup10

### Microsoft / Platform
- https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai
- https://learn.microsoft.com/en-us/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal
- https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations
- https://learn.microsoft.com/en-us/powershell/module/psscriptanalyzer/invoke-scriptanalyzer
- https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-service

### Testing / Adjacent
- https://pester.dev/docs/usage/mocking
- https://pester.dev/docs/usage/testregistry
- https://github.com/ntdevlabs/tiny11builder
- https://atlasos.net/
- https://ameliorated.io/
- https://github.com/simeononsecurity/Windows-Optimize-Harden-Debloat

## Open Questions
- Which deployment channel should be authoritative for `RemoveDefaultMicrosoftStorePackages` in this repo: local GPO-compatible registry writes, generated Intune OMA-URI XML, or both?
- Should `Privacy` continue to include any event-log clearing by default, or should event-log clearing move behind an explicit config key only?
