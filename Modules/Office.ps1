# ============================================================================
# MODULE: Office Nuclear Removal
# Phase 4: Complete Office removal (when not in use)
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
if (-not (Test-IrreversibleOperationAllowed -Name 'Office removal')) {
    Write-Log "[Office] Office and OneNote removal SKIPPED (explicit approval required)" "WARNING"
    return
}

    Write-Log "[Office] Office Nuclear Removal..." "SECTION"
    Write-Rationale 'Office'

    $officeResult = Invoke-TrackedOperation -Name 'Office removal' -Action 'Remove Office, OneNote, services, tasks, files, and registry entries' -Scope 'Machine' -RunDuringDryRun -Operation {
    if (-not $DryRun) {
        # Kill OneNote standalone installs first (all languages) - NUCLEAR
        Write-Log "  Nuking OneNote installations..." "INFO"
        $uninstallPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        foreach ($path in $uninstallPaths) {
            Get-ChildItem $path -EA 0 | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath -EA 0
                if ($props.DisplayName -match 'OneNote') {
                    Write-Log "    Nuking: $($props.DisplayName)" "INFO"
                    $script:counters.OfficeRemoved++
                    # Try MSI uninstall
                    $guid = $_.PSChildName
                    if ($guid -match '^\{') {
                        Start-Process 'msiexec.exe' -ArgumentList "/x$guid /qn /norestart" -Wait -WindowStyle Hidden -EA Stop
                    }
                    # Delete registry entry regardless (nuclear)
                    Remove-Item $_.PSPath -Recurse -Force -EA Stop
                }
            }
        }

        # Nuke OneNote AppX packages (routed through Remove-AppxDryRun for manifest tracking)
        Remove-AppxDryRun -Pattern '*OneNote*' -AllowOutsideAppX

        # Nuke OneNote folders
        @(
            "$env:LOCALAPPDATA\Microsoft\OneNote",
            "$env:APPDATA\Microsoft\OneNote"
        ) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -EA Stop }
        }

        # Check if Office is installed
        $officeInstalled = (Test-Path "C:\Program Files\Microsoft Office") -or
                           (Test-Path "C:\Program Files (x86)\Microsoft Office") -or
                           (Test-Path "C:\Program Files\Common Files\microsoft shared\ClickToRun")

        if ($officeInstalled) {
            Write-Log "  Office detected - nuking..." "INFO"

            # Kill ALL Office processes
            Write-Log "  Killing Office processes..." "INFO"
            $officeProcs = @(
                'WINWORD','EXCEL','POWERPNT','OUTLOOK','ONENOTE','MSACCESS','MSPUB','VISIO','WINPROJ',
                'lync','Teams','OfficeClickToRun','OfficeC2RClient','AppVShNotify',
                'IntegratedOffice','integrator','FirstRun','setup','communicator','msosync',
                'OneNoteM','GROOVE','INFOPATH','MSTORE','CLVIEW','SELFCERT','msoev','OFFDIAG',
                'ose','ose64','osppsvc','sppsvc','msoidsvc','msoidsvcm','officeclicktorun',
                'officeondemand','msoia','msohtmed','msouc'
            )
            # Only kill OneDrive if not in use
            if (-not $script:onedriveInUse) { $officeProcs += 'OneDrive' }
            $officeProcs | ForEach-Object { Get-Process -Name $_ -EA 0 | Stop-Process -Force -EA Stop }

            # Stop and delete Office services
            Write-Log "  Nuking Office services..." "INFO"
            @('ClickToRunSvc','OfficeSvc','ose','ose64','osppsvc') | ForEach-Object {
                $officeService = Get-Service -Name $_ -EA 0
                if ($officeService) {
                    $script:manifest.changes.services_deleted.Add($_) | Out-Null
                    Stop-Service -Name $_ -Force -EA Stop
                    Set-Service -Name $_ -StartupType Disabled -EA Stop
                    sc.exe delete $_ 2>$null
                    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1060) { throw "sc.exe delete $_ exited with code $LASTEXITCODE" }
                    $script:counters.OfficeRemoved++
                }
            }

            # Delete Office scheduled tasks
            Write-Log "  Nuking Office scheduled tasks..." "INFO"
            Get-ScheduledTask -TaskPath "\Microsoft\Office\*" -EA 0 | Unregister-ScheduledTask -Confirm:$false -EA Stop
            @(
                'Office Automatic Updates*','Office ClickToRun*','Office Feature Updates*',
                'Office Serviceability*','OfficeTelemetry*','Office Background*',
                'Office Performance*','Office Subscription*','Office SxS*'
            ) | ForEach-Object {
                Get-ScheduledTask -TaskName $_ -EA 0 | Unregister-ScheduledTask -Confirm:$false -EA Stop
            }

            # Nuclear file deletion
            Write-Log "  Nuking Office folders..." "INFO"
            @(
                "C:\Program Files\Microsoft Office",
                "C:\Program Files\Microsoft Office 15",
                "C:\Program Files\Microsoft Office 16",
                "C:\Program Files (x86)\Microsoft Office",
                "C:\Program Files (x86)\Microsoft Office 15",
                "C:\Program Files (x86)\Microsoft Office 16",
                "C:\Program Files\Common Files\microsoft shared\ClickToRun",
                "C:\Program Files\Common Files\microsoft shared\Office15",
                "C:\Program Files\Common Files\microsoft shared\Office16",
                "C:\Program Files (x86)\Common Files\microsoft shared\ClickToRun",
                "C:\Program Files (x86)\Common Files\microsoft shared\Office15",
                "C:\Program Files (x86)\Common Files\microsoft shared\Office16",
                "$env:ProgramData\Microsoft\Office",
                "$env:ProgramData\Microsoft\ClickToRun",
                "$env:LOCALAPPDATA\Microsoft\Office",
                "$env:APPDATA\Microsoft\Office"
            ) | ForEach-Object {
                if (Test-Path $_) {
                    Remove-Item -LiteralPath $_ -Recurse -Force -EA Stop
                    $script:counters.OfficeRemoved++
                }
            }

            # Delete Office folders from all user profiles
            $userProfiles = Get-ChildItem 'C:\Users' -Directory -EA 0 | Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
            foreach ($userProf in $userProfiles) {
                @(
                    "$($userProf.FullName)\AppData\Local\Microsoft\Office",
                    "$($userProf.FullName)\AppData\Roaming\Microsoft\Office"
                ) | ForEach-Object {
                    if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -EA Stop }
                }
            }

            # Nuclear registry cleanup
            Write-Log "  Nuking Office registry..." "INFO"
            @(
                "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun",
                "HKLM:\SOFTWARE\Microsoft\Office\15.0",
                "HKLM:\SOFTWARE\Microsoft\Office\16.0",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\ClickToRun",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\15.0",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office\16.0",
                "HKCU:\SOFTWARE\Microsoft\Office\15.0",
                "HKCU:\SOFTWARE\Microsoft\Office\16.0"
            ) | ForEach-Object {
                if (Test-Path -LiteralPath $_) { Remove-Item -LiteralPath $_ -Recurse -Force -EA Stop }
            }

            # Delete Office Add/Remove Programs entries
            @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            ) | ForEach-Object {
                Get-ChildItem $_ -EA 0 | ForEach-Object {
                    $props = Get-ItemProperty $_.PSPath -EA 0
                    if ($props.DisplayName -match 'Microsoft 365|Microsoft Office|Office 16 Click-to-Run') {
                        Remove-Item $_.PSPath -Recurse -Force -EA Stop
                    }
                }
            }

            # Clean Office shortcuts
            Write-Log "  Nuking Office shortcuts..." "INFO"
            @(
                "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
                "$env:USERPROFILE\Desktop",
                "$env:PUBLIC\Desktop"
            ) | ForEach-Object {
                Get-ChildItem -Path $_ -Filter "*.lnk" -Recurse -EA 0 | ForEach-Object {
                    $target = (New-Object -COM WScript.Shell).CreateShortcut($_.FullName).TargetPath
                    if ($target -match 'Office|WINWORD|EXCEL|POWERPNT|OUTLOOK|ONENOTE|MSACCESS|ClickToRun') {
                        Remove-Item $_.FullName -Force -EA Stop
                    }
                }
            }

            # Clean Office licenses (Office-only; do NOT touch Windows product key)
            Write-Log "  Cleaning Office licenses..." "INFO"
            Get-CimInstance -Query "SELECT * FROM SoftwareLicensingProduct WHERE ApplicationId='0ff1ce15-a989-479d-af46-f275c6370663' AND PartialProductKey IS NOT NULL" -EA 0 | ForEach-Object {
                Invoke-CimMethod -InputObject $_ -MethodName 'UninstallProductKey' -EA Stop
            }

            Write-Log "  Office nuclear removal complete" "SUCCESS"
        } else {
            Write-Log "  Office not detected - skipping" "INFO"
        }
    } else {
        Write-Log "  [DRY RUN] Would perform full Office nuclear removal" "INFO"
    }

    }
    if ($officeResult) { Write-Log "  Office nuclear removal processed" "SUCCESS" } else { Write-Log "  Office nuclear removal failed" "ERROR" }
