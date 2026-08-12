# ============================================================================
# MODULE: OneDrive Removal
# Phase 3: OneDrive removal (when not in use)
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
if (-not (Test-IrreversibleOperationAllowed -Name 'OneDrive removal')) {
    Write-Log "[OneDrive] OneDrive removal SKIPPED (explicit approval required)" "WARNING"
    return
}

    Write-Log "[OneDrive] Removing OneDrive..." "SECTION"
    Write-Rationale 'OneDrive'

    $oneDriveResult = Invoke-TrackedOperation -Name 'OneDrive removal' -Action 'Uninstall OneDrive and remove residual files' -Scope 'AllUsers' -RunDuringDryRun -Operation {
    if (-not $DryRun) {
        # Kill OneDrive processes
        Get-Process -Name 'OneDrive', 'OneDriveSetup' -EA 0 | Stop-Process -Force -EA Stop

        # Run official uninstaller (fast, ~5 seconds)
        $oneDrivePaths = @(
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
        )
        foreach ($path in $oneDrivePaths) {
            if (Test-Path $path) {
                Write-Log "  Running OneDrive uninstaller..." "INFO"
                Start-Process $path -ArgumentList '/uninstall' -Wait -WindowStyle Hidden -EA Stop
                break
            }
        }

        # Clean OneDrive folders
        @(
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive",
            "$env:USERPROFILE\OneDrive"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -EA Stop }
        }

        # Clean OneDrive from all user profiles (skip profiles with active OneDrive files)
        $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
        foreach ($userProf in $userProfiles) {
            $profileOneDrive = "$($userProf.FullName)\OneDrive"
            if ((Test-Path $profileOneDrive) -and (Get-ChildItem $profileOneDrive -Recurse -File -EA 0 | Select-Object -First 1)) {
                Write-Log "  Skipping $($userProf.Name) OneDrive folder (contains files)" "WARNING"
                continue
            }
            @(
                "$($userProf.FullName)\AppData\Local\Microsoft\OneDrive",
                "$($userProf.FullName)\OneDrive"
            ) | ForEach-Object {
                if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -EA Stop }
            }
        }

        # Remove OneDrive from Explorer sidebar
        foreach ($sidebarKey in @(
            'Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
            'Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        )) {
            if (Test-Path -LiteralPath $sidebarKey) {
                $regKey = $sidebarKey -replace '^Registry::HKEY_CLASSES_ROOT', 'HKCR'
                reg delete $regKey /f 2>$null
                if ($LASTEXITCODE -ne 0) { throw "reg.exe exited with code $LASTEXITCODE" }
            }
        }
    } else {
        Write-Log "  [DRY RUN] Would uninstall OneDrive, clean folders and registry" "INFO"
    }
    }

    if ($oneDriveResult) { Write-Log "  OneDrive removed" "SUCCESS" } else { Write-Log "  OneDrive removal failed" "ERROR" }
