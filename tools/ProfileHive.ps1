# Shared profile and registry-hive helpers for drift detection and remediation.
# This file defines functions only; callers decide whether to read or write.
#Requires -Version 5.1

function Get-DebloatUserProfiles {
    [CmdletBinding()]
    param([ref]$ErrorMessage)

    $records = @{}
    $cimFailed = $false
    try {
        $cimProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object {
                $_.SID -match '^S-1-5-21-' -and
                $_.LocalPath -and
                -not $_.Special -and
                $_.LocalPath -notmatch '\\(Public|Default|Default User|All Users)$'
            })
    } catch {
        $cimProfiles = @()
        $cimFailed = $true
    }

    foreach ($profileEntry in $cimProfiles) {
        $localPath = ([Environment]::ExpandEnvironmentVariables([string]$profileEntry.LocalPath)).TrimEnd('\')
        if ([string]::IsNullOrWhiteSpace($localPath)) { continue }
        $key = $localPath.ToLowerInvariant()
        if ($records.ContainsKey($key)) { continue }
        $records[$key] = [pscustomobject]@{
            Name = (Split-Path $localPath -Leaf)
            SID = [string]$profileEntry.SID
            LocalPath = $localPath
            NtUserPath = Join-Path $localPath 'NTUSER.DAT'
            Loaded = [bool]$profileEntry.Loaded
            Source = 'Win32_UserProfile'
        }
    }

    # ProfileList is the fallback when CIM is unavailable or incomplete.
    $profileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($profileKey in @(Get-ChildItem $profileListRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' })) {
        $profileEntry = Get-ItemProperty -Path $profileKey.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue
        if (-not $profileEntry -or [string]::IsNullOrWhiteSpace([string]$profileEntry.ProfileImagePath)) { continue }
        $localPath = ([Environment]::ExpandEnvironmentVariables([string]$profileEntry.ProfileImagePath)).TrimEnd('\')
        if ($localPath -match '\\(Public|Default|Default User|All Users)$') { continue }
        $key = $localPath.ToLowerInvariant()
        if ($records.ContainsKey($key)) { continue }
        $loaded = Test-Path ("Registry::HKEY_USERS\$($profileKey.PSChildName)")
        $records[$key] = [pscustomobject]@{
            Name = (Split-Path $localPath -Leaf)
            SID = [string]$profileKey.PSChildName
            LocalPath = $localPath
            NtUserPath = Join-Path $localPath 'NTUSER.DAT'
            Loaded = [bool]$loaded
            Source = 'ProfileList'
        }
    }

    if ($records.Count -eq 0 -and $cimFailed) {
        $ErrorMessage.Value = 'Win32_UserProfile and ProfileList enumeration returned no user profiles'
    } elseif ($records.Count -eq 0) {
        $ErrorMessage.Value = 'ProfileList enumeration returned no user profiles'
    }

    return @($records.Values | Sort-Object LocalPath)
}

function Get-DebloatLoadedUserHivePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$UserProfile)

    if ($UserProfile.SID) {
        $sidPath = "Registry::HKEY_USERS\$($UserProfile.SID)"
        if (Test-Path $sidPath) { return $sidPath }
    }

    $normalizedProfilePath = ([Environment]::ExpandEnvironmentVariables([string]$UserProfile.LocalPath)).TrimEnd('\')
    foreach ($hive in @(Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' })) {
        $profileList = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($hive.PSChildName)" -Name ProfileImagePath -ErrorAction SilentlyContinue
        if ($profileList) {
            $imagePath = ([Environment]::ExpandEnvironmentVariables([string]$profileList.ProfileImagePath)).TrimEnd('\')
            if ($imagePath -ieq $normalizedProfilePath) {
                return "Registry::HKEY_USERS\$($hive.PSChildName)"
            }
        }
    }

    return $null
}

function Open-DebloatUserHive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$UserProfile,
        [Parameter(Mandatory)][string]$Prefix
    )

    $loadedPath = Get-DebloatLoadedUserHivePath -UserProfile $UserProfile
    if ($loadedPath) {
        return [pscustomobject]@{
            Status = 'Ready'
            Path = $loadedPath
            HiveName = $null
            Temporary = $false
            Reason = $null
        }
    }

    if (-not (Test-Path $UserProfile.NtUserPath)) {
        return [pscustomobject]@{
            Status = 'Skipped'
            Path = $null
            HiveName = $null
            Temporary = $false
            Reason = 'NTUSER.DAT is missing'
        }
    }

    $safeSid = if ($UserProfile.SID) { $UserProfile.SID -replace '[^A-Za-z0-9]', '_' } else { $UserProfile.Name -replace '[^A-Za-z0-9]', '_' }
    $hiveKey = "${Prefix}_$safeSid"
    $hiveName = "HKU\$hiveKey"
    & reg load $hiveName $UserProfile.NtUserPath 2>$null | Out-Null
    $loadExitCode = $LASTEXITCODE
    if ($loadExitCode -ne 0) {
        return [pscustomobject]@{
            Status = 'Skipped'
            Path = $null
            HiveName = $hiveName
            Temporary = $false
            Reason = "reg load failed with exit code $loadExitCode"
        }
    }

    $registryPath = "Registry::HKEY_USERS\$hiveKey"
    if (-not (Test-Path $registryPath)) {
        & reg unload $hiveName 2>$null | Out-Null
        return [pscustomobject]@{
            Status = 'Error'
            Path = $null
            HiveName = $hiveName
            Temporary = $false
            Reason = 'reg load reported success but the hive was not available'
        }
    }

    return [pscustomobject]@{
        Status = 'Ready'
        Path = $registryPath
        HiveName = $hiveName
        Temporary = $true
        Reason = $null
    }
}

function Close-DebloatUserHive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Session)

    if (-not $Session.Temporary) {
        return [pscustomobject]@{ Success = $true; Reason = $null }
    }

    [gc]::Collect()
    Start-Sleep -Milliseconds 200
    & reg unload $Session.HiveName 2>$null | Out-Null
    $unloadExitCode = $LASTEXITCODE
    if ($unloadExitCode -ne 0) {
        return [pscustomobject]@{ Success = $false; Reason = "reg unload failed with exit code $unloadExitCode" }
    }
    return [pscustomobject]@{ Success = $true; Reason = $null }
}

function Get-DebloatUserRegistryChecks {
    [CmdletBinding()]
    param(
        [object[]]$Policies,
        [object[]]$Tweaks
    )

    $checks = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($policy in @($Policies | Where-Object { $_.Scope -eq 'User' -and $_.ApplyByDefault -ne $false })) {
        $key = "$($policy.Path)|$($policy.Name)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $checks.Add([pscustomobject]@{
            Path = [string]$policy.Path
            Name = [string]$policy.Name
            Expected = $policy.Value
            Type = [string]$policy.Type
            Source = 'Policy'
        }) | Out-Null
    }

    foreach ($tweak in @($Tweaks | Where-Object { $_.Scope -eq 'User' })) {
        $key = "$($tweak.Path)|$($tweak.Name)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $tweakType = if ($tweak.Type) { [string]$tweak.Type } else { 'DWord' }
        $checks.Add([pscustomobject]@{
            Path = [string]$tweak.Path
            Name = [string]$tweak.Name
            Expected = $tweak.Value
            Type = $tweakType
            Source = 'HKCU'
        }) | Out-Null
    }

    return @($checks)
}

function Set-DebloatRegistryProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [ValidateSet('DWord','QWord','String','ExpandString','MultiString','Binary')]
        [string]$Type = 'DWord'
    )

    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    # New-ItemProperty -Force works for both missing and existing values and
    # supports PropertyType on Windows PowerShell 5.1.
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}
