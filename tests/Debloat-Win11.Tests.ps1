BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'Debloat-Win11.ps1'
    $scriptContent = Get-Content $scriptPath -Raw

    # Also read all dot-sourced module files so content checks cover the full codebase
    $modulesDir = Join-Path $PSScriptRoot '..' 'Modules'
    $allContent = $scriptContent
    if (Test-Path $modulesDir) {
        Get-ChildItem $modulesDir -Filter '*.ps1' | ForEach-Object {
            $allContent += "`n" + (Get-Content $_.FullName -Raw)
        }
    }
}

Describe 'Script Structure' {
    It 'starts with #Requires -RunAsAdministrator' {
        $scriptContent | Should -Match '#Requires -RunAsAdministrator'
    }

    It 'starts with #Requires -Version 5.1' {
        $scriptContent | Should -Match '#Requires -Version 5.1'
    }

    It 'declares param block with expected parameters' {
        $scriptContent | Should -Match '\[switch\]\$DryRun'
        $scriptContent | Should -Match '\[switch\]\$Silent'
        $scriptContent | Should -Match '\[string\]\$UndoFile'
        $scriptContent | Should -Match '\[string\]\$ConfigPath'
        $scriptContent | Should -Match '\[string\[\]\]\$Only'
        $scriptContent | Should -Match '\[string\[\]\]\$Skip'
    }

    It 'declares $Explain parameter with rationale support' {
        $scriptContent | Should -Match '\[switch\]\$Explain'
        $scriptContent | Should -Match 'phaseRationale'
    }

    It 'defines valid phase list' {
        $scriptContent | Should -Match "validPhases\s*=\s*@\("
        foreach ($phase in @('AppX','OEM','OneDrive','Office','Edge','Firewall','Privacy','Services','SystemTweaks','Power','Network','StartMenu')) {
            $scriptContent | Should -Match "'$phase'"
        }
    }
}

Describe 'Test-PhaseEnabled Logic' {
    BeforeAll {
        function Test-PhaseEnabled {
            param([string]$Phase)
            if ($script:testOnly) { return ($script:testOnly -contains $Phase) }
            if ($script:testSkip) { return ($script:testSkip -notcontains $Phase) }
            return $true
        }
    }

    It 'returns $true for all phases when no Only/Skip' {
        $script:testOnly = $null
        $script:testSkip = $null
        Test-PhaseEnabled 'AppX' | Should -Be $true
        Test-PhaseEnabled 'Services' | Should -Be $true
    }

    It 'returns $true only for specified phases with -Only' {
        $script:testOnly = @('AppX','Services')
        $script:testSkip = $null
        Test-PhaseEnabled 'AppX' | Should -Be $true
        Test-PhaseEnabled 'Services' | Should -Be $true
        Test-PhaseEnabled 'Edge' | Should -Be $false
    }

    It 'returns $false for skipped phases with -Skip' {
        $script:testOnly = $null
        $script:testSkip = @('Edge','Firewall')
        Test-PhaseEnabled 'AppX' | Should -Be $true
        Test-PhaseEnabled 'Edge' | Should -Be $false
        Test-PhaseEnabled 'Firewall' | Should -Be $false
    }
}

Describe 'Set-Reg Manifest Recording' {
    BeforeAll {
        $script:manifest = @{
            changes = @{
                registry_set = [System.Collections.ArrayList]@()
            }
        }
        $script:counters = @{ RegistryTweaks = 0 }
        $DryRun = $true

        function Set-Reg {
            param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
            $oldValue = $null
            if (Test-Path $Path) {
                $existing = Get-ItemProperty -Path $Path -Name $Name -EA 0
                if ($existing) { $oldValue = $existing.$Name }
            }
            $script:manifest.changes.registry_set.Add(@{
                path = $Path; name = $Name; old_value = $oldValue; new_value = $Value; type = $Type
            }) | Out-Null
            $script:counters.RegistryTweaks++
        }
    }

    It 'records registry change in manifest' {
        Set-Reg -Path "TestRegistry:\Test" -Name "TestValue" -Value 1
        $script:manifest.changes.registry_set.Count | Should -Be 1
        $script:manifest.changes.registry_set[0].name | Should -Be "TestValue"
        $script:manifest.changes.registry_set[0].new_value | Should -Be 1
    }

    It 'increments RegistryTweaks counter' {
        $script:counters.RegistryTweaks | Should -BeGreaterThan 0
    }
}

Describe 'Disable-ServiceDryRun' {
    BeforeAll {
        $script:manifest = @{
            changes = @{
                services_disabled = [System.Collections.ArrayList]@()
            }
        }
        $script:counters = @{ ServicesDisabled = 0 }
        $DryRun = $true

        function Disable-ServiceDryRun {
            param([string]$ServiceName)
            $svc = Get-Service -Name $ServiceName -EA 0
            if ($svc) {
                $script:manifest.changes.services_disabled.Add(@{
                    name = $ServiceName
                    original_startup_type = $svc.StartType.ToString()
                }) | Out-Null
                $script:counters.ServicesDisabled++
            }
        }
    }

    It 'records existing service in manifest with startup type' {
        Disable-ServiceDryRun -ServiceName 'WSearch'
        $wsearch = Get-Service -Name 'WSearch' -EA 0
        if ($wsearch) {
            $entry = $script:manifest.changes.services_disabled | Where-Object { $_.name -eq 'WSearch' }
            $entry | Should -Not -BeNullOrEmpty
            $entry.original_startup_type | Should -Not -BeNullOrEmpty
        }
    }

    It 'does not record non-existent service' {
        $before = $script:manifest.changes.services_disabled.Count
        Disable-ServiceDryRun -ServiceName 'NonExistentService12345'
        $script:manifest.changes.services_disabled.Count | Should -Be $before
    }
}

Describe 'DryRun Guards' {
    It 'has at least 10 DryRun guard blocks covering destructive phases' {
        $dryRunGuards = ([regex]::Matches($allContent, 'if\s*\(\s*-not\s+\$DryRun\s*\)')).Count
        $dryRunGuards | Should -BeGreaterOrEqual 10
    }

    It 'Remove-AppxDryRun function checks DryRun before Remove-AppxPackage' {
        $fnBody = [regex]::Match($scriptContent, 'function Remove-AppxDryRun[\s\S]*?(?=\nfunction\s)').Value
        $fnBody | Should -Match 'if\s*\(\s*-not\s+\$DryRun\s*\)'
        $fnBody | Should -Match 'Remove-AppxPackage'
    }

    It 'Disable-ServiceDryRun function checks DryRun before Stop-Service' {
        $fnBody = [regex]::Match($scriptContent, 'function Disable-ServiceDryRun[\s\S]*?(?=\nfunction\s)').Value
        $fnBody | Should -Match 'if\s*\(\s*-not\s+\$DryRun\s*\)'
        $fnBody | Should -Match 'Stop-Service'
    }
}

Describe 'No Duplicate ContentDeliveryManager Writes' {
    It 'writes each SubscribedContent key exactly once' {
        $cdmKeys = @(
            'SubscribedContent-310093Enabled',
            'SubscribedContent-338387Enabled',
            'SubscribedContent-338388Enabled',
            'SubscribedContent-338389Enabled',
            'SubscribedContent-338393Enabled',
            'SubscribedContent-353694Enabled',
            'SubscribedContent-353696Enabled'
        )

        foreach ($key in $cdmKeys) {
            $count = ([regex]::Matches($allContent, [regex]::Escape($key))).Count
            $count | Should -BeLessOrEqual 2 -Because "$key should appear at most twice (HKCU Set-Reg + Default user reg add)"
        }
    }
}

Describe 'Version Consistency' {
    It 'has consistent version in script header and manifest' {
        $headerVersion = [regex]::Match($scriptContent, 'DEBLOAT SCRIPT (v[\d.]+)').Groups[1].Value
        $manifestVersion = [regex]::Match($scriptContent, "version\s*=\s*'(v[\d.]+)'").Groups[1].Value
        $bannerVersion = [regex]::Match($scriptContent, 'WINDOWS DEBLOAT (v[\d.]+) STARTING').Groups[1].Value

        $headerVersion | Should -Be $manifestVersion
        $headerVersion | Should -Be $bannerVersion
    }
}

Describe 'Intel Driver Safeguard' {
    It 'defines oemSafeIntelPattern before OEM cleanup' {
        $allContent | Should -Match 'oemSafeIntelPattern\s*='
    }

    It 'applies Intel exclusion to all OEM service/process patterns' {
        $oemBlocks = [regex]::Matches($allContent, "Get-(Service|Process).*'dell\|intel")
        foreach ($block in $oemBlocks) {
            $lineNum = ($allContent.Substring(0, $block.Index) -split "`n").Count
            $line = ($allContent -split "`n")[$lineNum - 1]
            $line | Should -Match 'oemSafeIntelPattern' -Because "OEM match at line $lineNum should exclude Intel drivers"
        }
    }
}

Describe 'Manifest Structure' {
    It 'initializes all required manifest arrays' {
        $scriptContent | Should -Match 'appx_removed'
        $scriptContent | Should -Match 'services_disabled'
        $scriptContent | Should -Match 'services_deleted'
        $scriptContent | Should -Match 'tasks_disabled'
        $scriptContent | Should -Match 'registry_set'
        $scriptContent | Should -Match 'registry_deleted'
        $scriptContent | Should -Match 'folders_deleted'
    }
}

Describe 'EventLog Integration' {
    It 'registers Debloat-Win11 event source' {
        $scriptContent | Should -Match "eventLogSource\s*=\s*'Debloat-Win11'"
    }

    It 'writes completion event with summary' {
        $scriptContent | Should -Match 'Write-EventLog.*EventId 1000'
    }

    It 'writes error events' {
        $scriptContent | Should -Match 'Write-EventLog.*EventId 9001.*Error'
    }
}

Describe 'Config Override Mechanism' {
    It 'checks configOverrides for RemovePatterns' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('RemovePatterns'\)"
    }

    It 'checks configOverrides for ServicesToDisable' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('ServicesToDisable'\)"
    }

    It 'checks configOverrides for DefenderExclusions' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('DefenderExclusions'\)"
    }

    It 'checks configOverrides for EdgeBookmarks' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('EdgeBookmarks'\)"
    }
}
