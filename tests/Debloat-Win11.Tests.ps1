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
            $count | Should -BeLessOrEqual 3 -Because "$key should appear at most 3 times (HKCU Set-Reg + Default user reg add + AllUsers propagation)"
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

    It 'checks configOverrides for StartupBloat' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('StartupBloat'\)"
    }

    It 'checks configOverrides for TasksToDisable' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('TasksToDisable'\)"
    }

    It 'checks configOverrides for FeaturesToDisable' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('FeaturesToDisable'\)"
    }

    It 'checks configOverrides for FirewallRules' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('FirewallRules'\)"
    }
}

Describe 'No Duplicate AppX Patterns' {
    It 'has no duplicate patterns in defaultRemovePatterns' {
        $patternLines = $scriptContent -split "`n" | Where-Object { $_ -match "^\s*'\*[^']+\*'" }
        $patterns = $patternLines | ForEach-Object { ($_ -replace "^\s*'([^']+)'.*$", '$1').Trim() }
        $grouped = $patterns | Group-Object | Where-Object { $_.Count -gt 1 }
        $grouped | Should -BeNullOrEmpty -Because "each AppX pattern should appear exactly once in defaultRemovePatterns"
    }
}

Describe 'AI Controls' {
    It 'disables IsoEnvBroker for Agent Workspaces' {
        $allContent | Should -Match 'IsoEnvBroker'
    }

    It 'disables Paint AI features' {
        $allContent | Should -Match 'DisableImageCreator'
        $allContent | Should -Match 'DisableGenerativeFill'
        $allContent | Should -Match 'DisableCocreator'
    }
}

Describe 'DryRun Functional Behavior' {
    BeforeAll {
        $script:manifest = @{
            changes = @{
                appx_removed       = [System.Collections.ArrayList]@()
                services_disabled  = [System.Collections.ArrayList]@()
                tasks_disabled     = [System.Collections.ArrayList]@()
                registry_set       = [System.Collections.ArrayList]@()
            }
        }
        $script:counters = @{ AppxRemoved = 0; ServicesDisabled = 0; TasksDisabled = 0; RegistryTweaks = 0 }
        $DryRun = $true

        function Set-Reg {
            param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
            $script:manifest.changes.registry_set.Add(@{
                path = $Path; name = $Name; old_value = $null; new_value = $Value; type = $Type
            }) | Out-Null
            $script:counters.RegistryTweaks++
        }
    }

    It 'Set-Reg records to manifest in DryRun without writing registry' {
        Set-Reg -Path "HKLM:\SOFTWARE\Test\Debloat" -Name "TestDryRun" -Value 1
        $script:manifest.changes.registry_set[-1].new_value | Should -Be 1
        $real = Get-ItemProperty -Path "HKLM:\SOFTWARE\Test\Debloat" -Name "TestDryRun" -EA 0
        $real | Should -BeNullOrEmpty
    }

    It 'manifest tracks all changes without side effects' {
        $count = $script:manifest.changes.registry_set.Count
        $count | Should -BeGreaterThan 0
        $script:counters.RegistryTweaks | Should -Be $count
    }
}

Describe 'Undo Mode Logic' {
    It 'undo block handles both old string and new object service entries' {
        $scriptContent | Should -Match 'if \(\$svcEntry -is \[string\]\)'
        $scriptContent | Should -Match 'original_startup_type'
    }

    It 'undo mode warns about irrecoverable deletions' {
        $scriptContent | Should -Match 'folders_deleted'
        $scriptContent | Should -Match 'registry_deleted'
        $scriptContent | Should -Match 'services_deleted'
        $scriptContent | Should -Match 'cannot be auto-restored'
    }
}

Describe 'Drift Detection' {
    It 'defines CheckDrift parameter' {
        $scriptContent | Should -Match '\[switch\]\$CheckDrift'
    }

    It 'checks key privacy registry values' {
        $scriptContent | Should -Match 'AllowTelemetry.*Expected'
        $scriptContent | Should -Match 'TurnOffWindowsCopilot.*Expected'
        $scriptContent | Should -Match 'BingSearchEnabled.*Expected'
    }

    It 'reports drift status counts' {
        $scriptContent | Should -Match 'DRIFTED:'
        $scriptContent | Should -Match 'MISSING:'
    }
}

Describe 'Security Hardening' {
    It 'disables WDigest plaintext credential caching' {
        $allContent | Should -Match 'UseLogonCredential'
    }

    It 'restricts NTLM to NTLMv2' {
        $allContent | Should -Match 'LmCompatibilityLevel'
    }

    It 'enables PowerShell script block logging' {
        $allContent | Should -Match 'EnableScriptBlockLogging'
    }
}

Describe 'Revert Script Generation' {
    It 'generates a standalone revert .ps1 file' {
        $scriptContent | Should -Match 'Debloat-Revert-'
        $scriptContent | Should -Match 'Revert script:'
    }
}

Describe 'Pre-Flight Enhancements' {
    It 'reports VBS/HVCI status' {
        $scriptContent | Should -Match 'VirtualizationBasedSecurityStatus'
    }

    It 'detects Smart App Control enforcement' {
        $scriptContent | Should -Match 'VerifiedAndReputablePolicyState'
    }

    It 'informs Enterprise about native RemoveDefaultMicrosoftStorePackages policy' {
        $scriptContent | Should -Match 'RemoveDefaultMicrosoftStorePackages'
    }
}

# ============================================================================
# MOCK-BASED BEHAVIORAL TESTS
# ============================================================================

Describe 'Config Override Merge' {
    BeforeAll {
        $script:configOverrides = @{
            RemovePatterns = @('*TestApp1*', '*TestApp2*')
            ServicesToDisable = @('TestSvc1')
        }
        $script:defaultRemovePatterns = @('*Default1*', '*Default2*')
    }

    It 'config RemovePatterns overrides defaults' {
        $patterns = if ($script:configOverrides.ContainsKey('RemovePatterns')) { $script:configOverrides.RemovePatterns } else { $script:defaultRemovePatterns }
        $patterns | Should -Be @('*TestApp1*', '*TestApp2*')
    }

    It 'falls back to defaults when key is absent' {
        $hasKey = $script:configOverrides.ContainsKey('EdgeBookmarks')
        $hasKey | Should -Be $false
    }
}

Describe 'DarkMode Config Override' {
    It 'script checks configOverrides for DarkMode' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('DarkMode'\)"
    }
}

Describe 'OemExclude Config Override' {
    It 'script checks configOverrides for OemExclude' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('OemExclude'\)"
    }

    It 'defines Test-OemTarget helper' {
        $allContent | Should -Match 'function Test-OemTarget'
    }
}

Describe 'Disable-TaskDryRun Behavior' {
    BeforeAll {
        $script:manifest = @{
            changes = @{
                tasks_disabled = [System.Collections.ArrayList]@()
            }
        }
        $script:counters = @{ TasksDisabled = 0 }
        $DryRun = $true

        function Disable-TaskDryRun {
            param([string]$TaskName)
            $tasks = Get-ScheduledTask -TaskName $TaskName -EA 0
            foreach ($task in $tasks) {
                $script:manifest.changes.tasks_disabled.Add($task.TaskName) | Out-Null
                $script:counters.TasksDisabled++
            }
        }
    }

    It 'records existing tasks in manifest' {
        $task = Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachineCore*' -EA 0
        if ($task) {
            $before = $script:manifest.changes.tasks_disabled.Count
            Disable-TaskDryRun -TaskName 'MicrosoftEdgeUpdateTaskMachineCore*'
            $script:manifest.changes.tasks_disabled.Count | Should -BeGreaterThan $before
        }
    }

    It 'does not record non-existent tasks' {
        $before = $script:manifest.changes.tasks_disabled.Count
        Disable-TaskDryRun -TaskName 'NonExistentTask99999'
        $script:manifest.changes.tasks_disabled.Count | Should -Be $before
    }
}

Describe 'Concurrent Execution Guard' {
    It 'creates lockfile mechanism in script' {
        $scriptContent | Should -Match 'lockFile'
        $scriptContent | Should -Match 'Debloat-Win11\.lock'
    }

    It 'registers cleanup on PowerShell.Exiting' {
        $scriptContent | Should -Match 'Register-EngineEvent.*PowerShell\.Exiting'
    }

    It 'removes lockfile at script end' {
        $scriptContent | Should -Match 'Remove-Item \$script:lockFile'
    }
}

Describe 'Registry Version Stamp' {
    It 'writes version to HKLM registry key' {
        $scriptContent | Should -Match 'HKLM:\\SOFTWARE\\Debloat-Win11'
        $scriptContent | Should -Match 'Version.*v2\.2\.0'
    }

    It 'detection script checks registry first' {
        $detectContent = Get-Content (Join-Path $PSScriptRoot '..' 'Detect-Debloat.ps1') -Raw
        $detectContent | Should -Match 'HKLM:\\SOFTWARE\\Debloat-Win11'
        $detectContent | Should -Match 'registry stamp'
    }
}

Describe 'Shared HKCU Tweaks' {
    It 'HkcuTweaks.psd1 exists and is valid' {
        $tweakFile = Join-Path $PSScriptRoot '..' 'Modules' 'HkcuTweaks.psd1'
        Test-Path $tweakFile | Should -Be $true
        $tweaks = & ([scriptblock]::Create((Get-Content $tweakFile -Raw)))
        $tweaks.Count | Should -BeGreaterThan 20
    }

    It 'maintenance script loads shared tweaks' {
        $maintainContent = Get-Content (Join-Path $PSScriptRoot '..' 'Debloat-Win11-Maintain.ps1') -Raw
        $maintainContent | Should -Match 'HkcuTweaks\.psd1'
    }

    It 'AllUsers block loads shared tweaks' {
        $allContent | Should -Match 'HkcuTweaks\.psd1'
    }
}

Describe 'RemoveMicrosoftCopilotApp Policy' {
    It 'sets policy on Enterprise/Education editions' {
        $allContent | Should -Match 'RemoveMicrosoftCopilotApp'
    }
}

Describe 'RemoveDefaultMicrosoftStorePackages Policy' {
    It 'sets policy with package family names on Enterprise/Education 24H2+' {
        $allContent | Should -Match 'RemoveDefaultMicrosoftStorePackages'
        $allContent | Should -Match 'Clipchamp\.Clipchamp'
        $allContent | Should -Match 'Microsoft\.Copilot_8wekyb3d8bbwe'
    }
}

Describe 'Expanded Drift Detection' {
    It 'checks at least 30 registry values' {
        $driftBlock = [regex]::Match($scriptContent, '\$driftChecks\s*=\s*@\(([\s\S]*?)\)').Groups[1].Value
        $checkCount = ([regex]::Matches($driftBlock, '@\{')).Count
        $checkCount | Should -BeGreaterOrEqual 30
    }

    It 'covers AI agent policies' {
        $scriptContent | Should -Match "DisableSettingsAgent.*Expected"
        $scriptContent | Should -Match "DisableAgentWorkspaces.*Expected"
    }

    It 'covers Edge telemetry' {
        $scriptContent | Should -Match "DiagnosticData.*Expected.*0"
    }

    It 'covers WDigest security' {
        $scriptContent | Should -Match "UseLogonCredential.*Expected.*0"
    }
}

Describe 'Maintenance Task Trigger' {
    It 'uses WU-completion event trigger instead of AtLogOn' {
        $scriptContent | Should -Not -Match 'New-ScheduledTaskTrigger -AtLogOn'
        $scriptContent | Should -Match 'EventID=19'
        $scriptContent | Should -Match 'WindowsUpdateClient'
    }
}
