# ============================================================================
# MODULE: OneDrive Removal
# Phase 3: OneDrive removal (when not in use)
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
    Write-Log "[Phase 3/7] Removing OneDrive..." "SECTION"
    Write-Rationale 'OneDrive'

    if (-not $DryRun) {
        # Kill OneDrive processes
        Stop-Process -Name 'OneDrive', 'OneDriveSetup' -Force -EA 0

        # Run official uninstaller (fast, ~5 seconds)
        $oneDrivePaths = @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )
        foreach ($path in $oneDrivePaths) {
            if (Test-Path $path) {
                Write-Log "  Running OneDrive uninstaller..." "INFO"
                Start-Process $path -ArgumentList '/uninstall' -Wait -WindowStyle Hidden -EA 0
                break
            }
        }

        # Clean OneDrive folders
        @(
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive",
            "$env:USERPROFILE\OneDrive"
        ) | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
        }

        # Clean OneDrive from all user profiles
        $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
        foreach ($userProf in $userProfiles) {
            @(
                "$($userProf.FullName)\AppData\Local\Microsoft\OneDrive",
                "$($userProf.FullName)\OneDrive"
            ) | ForEach-Object {
                if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 }
            }
        }

        # Remove OneDrive from Explorer sidebar
        reg delete "HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f 2>$null
        reg delete "HKCR\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f 2>$null
    } else {
        Write-Log "  [DRY RUN] Would uninstall OneDrive, clean folders and registry" "INFO"
    }

    Write-Log "  OneDrive removed" "SUCCESS"
