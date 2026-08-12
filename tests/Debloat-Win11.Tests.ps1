BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $scriptPath = Join-Path $repoRoot 'Debloat-Win11.ps1'
    $scriptContent = Get-Content $scriptPath -Raw

    # Also read all dot-sourced module files so content checks cover the full codebase
    $modulesDir = Join-Path $repoRoot 'Modules'
    $allContent = $scriptContent
    if (Test-Path $modulesDir) {
        Get-ChildItem $modulesDir -Filter '*.ps1' | ForEach-Object {
            $allContent += "`n" + (Get-Content $_.FullName -Raw)
        }
        Get-ChildItem $modulesDir -Filter '*.psd1' | ForEach-Object {
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
        $scriptContent | Should -Match '\[switch\]\$AllowIrreversibleChanges'
    }

    It 'declares $Explain parameter with rationale support' {
        $scriptContent | Should -Match '\[switch\]\$Explain'
        $scriptContent | Should -Match 'phaseRationale'
    }

    It 'defines valid phase list' {
        $scriptContent | Should -Match "validPhases\s*=\s*@\("
        foreach ($phase in @('AppX','OEM','OneDrive','Office','Edge','Firewall','Privacy','Services','SystemTweaks','Power','Network','StartMenu','Updates')) {
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

Describe 'Service Operation Result Fidelity' {
    BeforeAll {
        $servicesContent = Get-Content (Join-Path $repoRoot 'Modules\Services.ps1') -Raw
    }

    It 'routes every configured service through the verified helper' {
        $servicesContent | Should -Match 'Disable-ServiceDryRun -ServiceName \$svc'
        $servicesContent | Should -Not -Match 'ForEach-Object -Parallel'
    }

    It 'records an operation result for service success and failure paths' {
        $scriptContent | Should -Match 'Register-OperationResult -Name \$ServiceName -Action ''Disable service'''
        $scriptContent | Should -Match 'Register-OperationFailure -Name \$ServiceName -Action ''Disable service'''
    }
}

Describe 'Verified Operation Contract' {
    It 'defines one tracked helper with verification and failure registration' {
        $scriptContent | Should -Match 'function Invoke-TrackedOperation'
        $scriptContent | Should -Match '\[scriptblock\]\$Verification'
        $scriptContent | Should -Match 'Post-operation verification failed'
        $scriptContent | Should -Match 'Register-OperationFailure'
    }

    It 'initializes operation results and incomplete-run metadata' {
        $scriptContent | Should -Match 'operations\s*=\s*\[System\.Collections\.ArrayList\]'
        $scriptContent | Should -Match 'operation_summary\s*=\s*\[ordered\]@'
        $scriptContent | Should -Match 'OperationsFailed'
        $scriptContent | Should -Match 'manifest\.status\s*='
        $scriptContent | Should -Match '\$DryRun\)\s*\{\s*''Planned''\s*\}'
    }

    It 'renders operation names, scopes, statuses, and errors in HTML' {
        $scriptContent | Should -Match 'Operation Results'
        $scriptContent | Should -Match 'ConvertTo-HtmlCell \$_.error'
        $scriptContent | Should -Match '<th>Scope</th><th>Status</th><th>Error</th>'
    }

    It 'writes correlation-linked structured summaries and bounded redacted crash artifacts' {
        $scriptContent | Should -Match 'correlation_id'
        $scriptContent | Should -Match 'summaryPayload'
        $scriptContent | Should -Match 'OutputFormat'
        $scriptContent | Should -Match 'Invoke-DebloatLogRetention'
        $scriptContent | Should -Match 'Write-DebloatRedactedFile'
        $scriptContent | Should -Match 'redaction_policy'
        $scriptContent | Should -Match 'rollback_unsupported'
        $scriptContent | Should -Match 'package_operations'
    }

    It 'enforces a reviewed static-analysis warning/error budget' {
        $analysisContent = Get-Content (Join-Path $repoRoot 'tools\Invoke-StaticAnalysis.ps1') -Raw
        $baseline = Get-Content (Join-Path $repoRoot 'tools\StaticAnalysisBaseline.json') -Raw | ConvertFrom-Json
        $analysisContent | Should -Match 'MaxWarnings'
        $analysisContent | Should -Match 'MaxErrors'
        $analysisContent | Should -Match 'warning_budget'
        $analysisContent | Should -Match 'error_budget'
        $baseline.max_warning_count | Should -BeGreaterOrEqual $baseline.warning_count
        $baseline.max_error_count | Should -Be 0
    }

    It 'uses Pester Should-Invoke syntax for cross-version mock assertions' {
        $testsContent = Get-Content $PSScriptRoot\Debloat-Win11.Tests.ps1 -Raw
        $testsContent | Should -Not -Match 'Assert-MockCalled\s+\w+\s+-Times'
        $testsContent | Should -Match 'Should -Invoke'
    }

    It 'provides a version-checked test runner and documents the matrix' {
        $runnerContent = Get-Content (Join-Path $repoRoot 'tools\Invoke-TestSuite.ps1') -Raw
        $runnerContent | Should -Match 'PesterVersion'
        $runnerContent | Should -Match 'Get-Module -ListAvailable -Name Pester'
        $runnerContent | Should -Match 'Install-Module Pester -RequiredVersion'
        $runnerContent | Should -Match 'FailedCount'
        $readmeContent = Get-Content (Join-Path $repoRoot 'README.md') -Raw
        $readmeContent | Should -Match 'Windows PowerShell 5\.1'
        $readmeContent | Should -Match 'Pester 5\.9\.0'
        $readmeContent | Should -Match 'Pester 6\.0\.1'
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

    It 'records schema, catalog/config fingerprints, and target scope' {
        $scriptContent | Should -Match 'schema_version = 2'
        $scriptContent | Should -Match 'correlation_id'
        $scriptContent | Should -Match 'policy_catalog_hash'
        $scriptContent | Should -Match 'config_hash'
        $scriptContent | Should -Match 'user_policy'
        $scriptContent | Should -Match 'ManifestSchemaVersion'
        $scriptContent | Should -Match 'CatalogHash'
        $scriptContent | Should -Match 'ConfigHash'
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

    It 'checks configOverrides for ClearEventLogs' {
        $allContent | Should -Match "configOverrides\.ContainsKey\('ClearEventLogs'\)"
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

    It 'does not target Intel packages, folders, registry roots, or startup entries' {
        $oemContent = Get-Content (Join-Path $repoRoot 'Modules\OEM.ps1') -Raw
        $oemContent | Should -Not -Match "Get-Package \*Intel\*"
        $oemContent | Should -Not -Match '\$env:ProgramFiles\\Intel'
        $oemContent | Should -Not -Match 'SOFTWARE\\Intel'
        $oemContent | Should -Not -Match 'oemAppxPatterns\s*=\s*@\([^)]*Intel'
    }

    It 'never removes language packs or Windows Security startup' {
        $oemContent = Get-Content (Join-Path $repoRoot 'Modules\OEM.ps1') -Raw
        $oemContent | Should -Not -Match 'C:\\langpacks'
        $oemContent | Should -Not -Match 'SecurityHealth'
    }
}

Describe 'Irreversible Change Gate' {
    It 'defines the approval gate and records skipped operations' {
        $scriptContent | Should -Match 'function Test-IrreversibleOperationAllowed'
        $scriptContent | Should -Match "Status 'Skipped'"
        $scriptContent | Should -Match '-AllowIrreversibleChanges'
    }

    It 'gates destructive dot-sourced modules' {
        foreach ($module in @('AppX.ps1','OEM.ps1','OneDrive.ps1','Office.ps1','Firewall.ps1')) {
            $moduleContent = Get-Content (Join-Path $repoRoot (Join-Path 'Modules' $module)) -Raw
            $moduleContent | Should -Match 'Test-IrreversibleOperationAllowed'
        }
    }

    It 'keeps default network behavior profile-preserving and private-only' {
        $perfContent = Get-Content (Join-Path $repoRoot 'Modules\SystemTweaks_Perf.ps1') -Raw
        $perfContent | Should -Not -Match 'Set-NetConnectionProfile'
        $perfContent | Should -Match "NetworkProfile.*Preserve"
        $perfContent | Should -Match 'Profile Domain,Private'
        $perfContent | Should -Not -Match 'Profile Domain,Private,Public'
    }

    It 'makes compliance require a complete manifest and registry stamp' {
        $detectionContent = Get-Content (Join-Path $repoRoot 'Detect-Debloat.ps1') -Raw
        $detectionContent | Should -Match "Status -ne 'Complete'"
        $detectionContent | Should -Match 'operation_summary\.failed -ne 0'
        $detectionContent | Should -Match 'ManifestPath'
        $detectionContent | Should -Match 'schema_version'
        $detectionContent | Should -Match 'policy_catalog_hash'
        $detectionContent | Should -Match 'config_hash'
        $detectionContent | Should -Match 'ExpectedScope'
        $detectionContent | Should -Match 'ExpectedConfigPath'
        $detectionContent | Should -Match 'OutputFormat'
        $detectionContent | Should -Match 'unsupportedSelected'
    }

    It 'records rollback limitations instead of silently claiming full recovery' {
        $scriptContent | Should -Match 'unsupportedRollback'
        $scriptContent | Should -Match '\$script:manifest\.rollback'
        $scriptContent | Should -Match 'schema_version = 1'
        $scriptContent | Should -Match 'unsupported changes'
    }
}

Describe 'AppX Removal Counters' {
    BeforeAll {
        $appxHelper = [regex]::Match($scriptContent, 'function Add-AppxManifestEntry[\s\S]*?(?=\nfunction Remove-AppxDryRun)').Value
        Invoke-Expression $appxHelper
    }

    BeforeEach {
        $script:manifest = @{
            changes = @{
                appx_removed = [System.Collections.ArrayList]@()
            }
        }
        $script:counters = @{ AppxRemoved = 0 }
    }

    It 'counts a provisioned-only package in the shared manifest counter' {
        Add-AppxManifestEntry -PackageName 'Provisioned.Only' | Should -Be $true
        $script:counters.AppxRemoved | Should -Be 1
        $script:manifest.changes.appx_removed | Should -Contain 'Provisioned.Only'
    }

    It 'does not double-count a package already recorded from a user install' {
        Add-AppxManifestEntry -PackageName 'Shared.Package' | Out-Null
        Add-AppxManifestEntry -PackageName 'Shared.Package' | Should -Be $false
        $script:counters.AppxRemoved | Should -Be 1
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

Describe 'HTML Report Encoding' {
    It 'defines a helper that uses System.Net.WebUtility HtmlEncode' {
        $scriptContent | Should -Match 'function ConvertTo-HtmlCell'
        $scriptContent | Should -Match '\[System\.Net\.WebUtility\]::HtmlEncode'
    }

    It 'routes report table values through ConvertTo-HtmlCell' {
        foreach ($variable in @('path','name','oldValue','newValue','serviceName','serviceAction','appName','taskName')) {
            $scriptContent | Should -Match ('\${0}\s*=\s*ConvertTo-HtmlCell' -f $variable)
        }
    }

    It 'encodes HTML-sensitive characters used in manifest values' {
        $encoded = [System.Net.WebUtility]::HtmlEncode("<tag attr=`"value`">&'")
        $encoded | Should -Match '&lt;'
        $encoded | Should -Match '&gt;'
        $encoded | Should -Match '&amp;'
        $encoded | Should -Match '&quot;'
        $encoded | Should -Match '&#39;'
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

Describe 'WIM Mode Resilience' {
    It 'loads config before WIM mode so offline removals honor ConfigPath' {
        $configIndex = $scriptContent.IndexOf('# CONFIG FILE SUPPORT')
        $wimIndex = $scriptContent.IndexOf('# WIM IMAGE MODE')
        $configIndex | Should -BeGreaterOrEqual 0
        $wimIndex | Should -BeGreaterThan $configIndex
        $scriptContent | Should -Match "configOverrides\.ContainsKey\('RemovePatterns'\)"
    }

    It 'wraps WIM mutation in try/finally cleanup' {
        $scriptContent | Should -Match 'try \{'
        $scriptContent | Should -Match '\} finally \{'
        $scriptContent | Should -Match '\$wimMounted'
    }

    It 'saves only successful WIM mutations' {
        $scriptContent | Should -Match '\$wimSave = \$true'
        $scriptContent | Should -Match 'Dismount-WindowsImage -Path \$resolvedMountDir -Save'
        $scriptContent | Should -Match 'Dismount-WindowsImage -Path \$resolvedMountDir -Save -ErrorAction Stop'
    }

    It 'discards mounted image changes on failure' {
        $scriptContent | Should -Match 'WIM mode failed'
        $scriptContent | Should -Match 'Dismount-WindowsImage -Path \$resolvedMountDir -Discard'
    }

    It 'unloads offline hives in cleanup paths' {
        $scriptContent | Should -Match '\$defaultHiveLoaded'
        $scriptContent | Should -Match '\$softwareHiveLoaded'
        $scriptContent | Should -Match 'Open-WimRegistryHive'
        $scriptContent | Should -Match 'Close-WimRegistryHive'
    }

    It 'validates DISM state and records transactional output' {
        $scriptContent | Should -Match 'Get-WindowsImage -Mounted'
        $scriptContent | Should -Match 'Mount directory must be empty'
        $scriptContent | Should -Match 'AllowIrreversibleChanges'
        $scriptContent | Should -Match 'commit_status'
        $scriptContent | Should -Match 'catalog_version'
        $scriptContent | Should -Match 'Debloat-WIM-.*\.json'
    }

    It 'uses the policy catalog for offline user and device registry writes' {
        $scriptContent | Should -Match 'Get-DebloatUserRegistryChecks -Policies \$script:windowsAiPolicies -Tweaks \$script:hkcuTweaks'
        $scriptContent | Should -Match 'Where-Object \{ \$_.Scope -eq ''Device'''
        $scriptContent | Should -Not -Match 'reg add'
    }
}

Describe 'Windows Integration Harness' {
    BeforeAll {
        $integrationContent = Get-Content (Join-Path $repoRoot 'tools\Invoke-WindowsIntegrationTests.ps1') -Raw
    }

    It 'skips explicitly when the disposable VM marker or mutation opt-in is absent' {
        $integrationContent | Should -Match 'DEBLOAT_WIN11_INTEGRATION_VM'
        $integrationContent | Should -Match '\-AllowMutation'
        $integrationContent | Should -Match "status = 'Skipped'"
        $integrationContent | Should -Match 'Write-IntegrationResult -ExitCode 0'
    }

    It 'preserves artifacts and runs the full apply/detect/revert sequence when enabled' {
        foreach ($step in @('DryRun','Apply','DetectAfterApply','Revert','DetectAfterRevert')) {
            $integrationContent | Should -Match "-Name '$step'"
        }
        $integrationContent | Should -Match 'before-state\.json'
        $integrationContent | Should -Match 'after-revert-state\.json'
        $integrationContent | Should -Match 'integration-result\.json'
        $integrationContent | Should -Match 'registry_comparison'
    }

    It 'fails instead of claiming success when apply, revert, or state comparison fails' {
        $integrationContent | Should -Match "Apply command failed"
        $integrationContent | Should -Match "Revert command failed"
        $integrationContent | Should -Match 'Mismatches'
        $integrationContent | Should -Match "status = 'Failed'"
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

Describe 'Privacy Event Log Clearing' {
    BeforeAll {
        $privacyContent = Get-Content (Join-Path $repoRoot 'Modules\Privacy.ps1') -Raw
        $exampleConfigContent = Get-Content (Join-Path $repoRoot 'debloat.example.psd1') -Raw
    }

    It 'does not enumerate and clear every event log by default' {
        $privacyContent | Should -Not -Match 'wevtutil\s+el'
        $privacyContent | Should -Match 'Event log clearing skipped'
    }

    It 'clears only configured event log names' {
        $privacyContent | Should -Match "configOverrides\.ContainsKey\('ClearEventLogs'\)"
        $privacyContent | Should -Match 'foreach \(\$eventLogName in \$clearEventLogs\)'
        $privacyContent | Should -Match 'wevtutil cl "\$eventLogName"'
    }

    It 'documents ClearEventLogs as an empty-by-default caution setting' {
        $exampleConfigContent | Should -Match 'ClearEventLogs'
        $exampleConfigContent | Should -Match 'Default is empty'
        $exampleConfigContent | Should -Match 'audit/SIEM evidence'
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
        $scriptContent | Should -Match 'Version.*v2\.3\.10'
    }

    It 'detection script checks registry first' {
        $detectContent = Get-Content (Join-Path $repoRoot 'Detect-Debloat.ps1') -Raw
        $detectContent | Should -Match 'HKLM:\\SOFTWARE\\Debloat-Win11'
        $detectContent | Should -Match 'registry stamp'
    }
}

Describe 'Shared HKCU Tweaks' {
    It 'PolicyCatalog.psd1 contains valid shared HKCU tweaks' {
        $tweakFile = Join-Path $repoRoot 'Modules\PolicyCatalog.psd1'
        Test-Path $tweakFile | Should -Be $true
        $catalog = Import-PowerShellDataFile -Path $tweakFile
        $tweaks = @($catalog.HkcuTweaks)
        $tweaks.Count | Should -BeGreaterThan 20
    }

    It 'maintenance script loads shared tweaks' {
        $maintainContent = Get-Content (Join-Path $repoRoot 'Debloat-Win11-Maintain.ps1') -Raw
        $maintainContent | Should -Match 'PolicyCatalog\.psd1'
    }

    It 'AllUsers block loads shared tweaks' {
        $allContent | Should -Match 'PolicyCatalog'
    }
}

Describe 'Logged-in HKCU Propagation' {
    BeforeAll {
        $maintainContent = Get-Content (Join-Path $repoRoot 'Debloat-Win11-Maintain.ps1') -Raw
        $remediateContent = Get-Content (Join-Path $repoRoot 'Remediate-Drift.ps1') -Raw
        $profileHelperContent = Get-Content (Join-Path $repoRoot 'tools\ProfileHive.ps1') -Raw
    }

    It 'resolves loaded profile hives through Win32_UserProfile and HKEY_USERS' {
        $profileHelperContent | Should -Match 'Get-CimInstance -ClassName Win32_UserProfile'
        $profileHelperContent | Should -Match 'Registry::HKEY_USERS'
        $profileHelperContent | Should -Match 'Get-DebloatLoadedUserHivePath'
    }

    It 'handles loaded profiles before attempting temporary hive loads' {
        $loadedIndex = $profileHelperContent.IndexOf('Get-DebloatLoadedUserHivePath')
        $loadIndex = $profileHelperContent.IndexOf('reg load')
        $loadedIndex | Should -BeGreaterOrEqual 0
        $loadIndex | Should -BeGreaterThan $loadedIndex
        $maintainContent | Should -Match 'ProfileHive\.ps1'
        $remediateContent | Should -Match 'ProfileHive\.ps1'
    }
}

Describe 'Multi-user Drift Contract' {
    BeforeAll {
        $profileHelperContent = Get-Content (Join-Path $repoRoot 'tools\ProfileHive.ps1') -Raw
        $detectContent = Get-Content (Join-Path $repoRoot 'Detect-Drift.ps1') -Raw
        $remediateContent = Get-Content (Join-Path $repoRoot 'Remediate-Drift.ps1') -Raw
    }

    It 'enumerates both loaded and offline profiles through one helper' {
        $profileHelperContent | Should -Match 'Win32_UserProfile'
        $profileHelperContent | Should -Match 'ProfileList'
        $profileHelperContent | Should -Match 'Open-DebloatUserHive'
        $profileHelperContent | Should -Match 'Temporary = \$true'
        $detectContent | Should -Match 'foreach \(\$userProfile in \$userProfiles\)'
        $remediateContent | Should -Match 'foreach \(\$userProfile in \$userProfiles\)'
    }

    It 'deduplicates user policy and HKCU checks before counting settings' {
        $catalog = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Modules\PolicyCatalog.psd1')
        . (Join-Path $repoRoot 'tools\ProfileHive.ps1')
        $checks = @(Get-DebloatUserRegistryChecks -Policies @($catalog.Policies) -Tweaks @($catalog.HkcuTweaks))
        $keys = @($checks | ForEach-Object { "$($_.Path)|$($_.Name)" })
        @($keys | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        $checks.Count | Should -Be 47
    }

    It 'reports per-setting detection and remediation outcomes' {
        $detectContent | Should -Match 'checks=.*compliant=.*drifted=.*skipped=.*errors='
        $remediateContent | Should -Match 'attempted=.*remediated=.*alreadyCompliant=.*failed=.*skipped='
        $remediateContent | Should -Match '\$summary\.Skipped \+= \$userChecks\.Count'
        $remediateContent | Should -Not -Match '\$count\+\+'
    }

    It 'treats profile load and unload failures as visible non-success' {
        $profileHelperContent | Should -Match 'reg load failed with exit code'
        $profileHelperContent | Should -Match 'reg unload failed with exit code'
        $profileHelperContent | Should -Match 'New-ItemProperty[\s\S]*PropertyType'
        $profileHelperContent | Should -Not -Match 'Set-ItemProperty[\s\S]*-Type'
        $detectContent | Should -Match 'status = if \(\$summary\.Drifted -eq 0 -and \$summary\.Errors -eq 0 -and \$summary\.Skipped -eq 0\)'
        $remediateContent | Should -Match 'status = if \(\$summary\.Failed -eq 0 -and \$summary\.Errors -eq 0 -and \$summary\.Skipped -eq 0\)'
    }
}

Describe 'Typed HKCU Propagation' {
    BeforeAll {
        $hkcuContent = Get-Content (Join-Path $repoRoot 'Modules\PolicyCatalog.psd1') -Raw
        $maintainContent = Get-Content (Join-Path $repoRoot 'Debloat-Win11-Maintain.ps1') -Raw
        $remediateContent = Get-Content (Join-Path $repoRoot 'Remediate-Drift.ps1') -Raw
        $systemTweaksContent = Get-Content (Join-Path $repoRoot 'Modules\SystemTweaks_System.ps1') -Raw
        $profileHelperContent = Get-Content (Join-Path $repoRoot 'tools\ProfileHive.ps1') -Raw
        $allUsersBlock = [regex]::Match($systemTweaksContent, '# ALL-USERS HKCU PROPAGATION[\s\S]*').Value
    }

    It 'supports optional shared tweak Type metadata with a DWord fallback' {
        $hkcuContent | Should -Match 'Type is optional'
        $maintainContent | Should -Match 'ContainsKey\(''Type''\)'
        $profileHelperContent | Should -Match '\$tweak\.Type.*DWord'
        $allUsersBlock | Should -Match 'ContainsKey\(''Type''\)'
    }

    It 'applies the resolved type through the registry provider' {
        $maintainContent | Should -Match '-Type \$tweakType'
        $remediateContent | Should -Match '-Type \$check\.Type'
        $allUsersBlock | Should -Match '-Type \$tweakType'
        foreach ($content in @($maintainContent, $remediateContent, $allUsersBlock)) {
            $content | Should -Not -Match 'reg add[\s\S]*REG_DWORD'
        }
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
        $allContent | Should -Match 'Microsoft\.Windows\.Ai\.Copilot\.Provider_8wekyb3d8bbwe'
        $allContent | Should -Match 'MicrosoftWindows\.CrossDevice_cw5n1h2txyewy'
    }

    It 'validates PFN formatting before writing policy values' {
        $allContent | Should -Match 'invalidPfns'
        $allContent | Should -Match '\^\[A-Za-z0-9\]\[A-Za-z0-9\.\]\+_\[A-Za-z0-9\]\+\$'
    }

    It 'emits Microsoft-compatible DynamicRemovalList payload' {
        $allContent | Should -Match 'DynamicRemovalList'
        $allContent | Should -Match '&#x0D;&#x0A;'
        $allContent | Should -Match '<enabled/><data id=""DynamicRemovalList""'
    }

    It 'warns about GPO and Intune OMA-URI conflict risk' {
        $allContent | Should -Match 'Intune OMA-URI'
        $allContent | Should -Match 'GPO registry'
    }

    It 'keeps RemoveDefaultMicrosoftStorePackages registry creation behind DryRun' {
        $allContent | Should -Match 'if \(-not \$DryRun -and !\(Test-Path \$pfnPath\)\)'
        $allContent | Should -Match '\[DRY RUN\].*registry shape'
    }
}

Describe 'Expanded Drift Detection' {
    It 'checks at least 30 registry values' {
        $driftBlock = [regex]::Match($scriptContent, '\$driftChecks\s*=\s*@\(([\s\S]*?)\)').Groups[1].Value
        $policyFile = Join-Path $repoRoot 'Modules\PolicyCatalog.psd1'
        $catalog = Import-PowerShellDataFile -Path $policyFile
        $policyChecks = @($catalog.Policies) | Where-Object { $_.ApplyByDefault -ne $false }
        $checkCount = ([regex]::Matches($driftBlock, '@\{')).Count + @($policyChecks).Count
        $checkCount | Should -BeGreaterOrEqual 30
    }

    It 'covers AI agent policies' {
        $allContent | Should -Match "DisableSettingsAgent"
        $allContent | Should -Match "DisableAgentWorkspaces"
        $allContent | Should -Match "DisableRemoteAgentConnectors"
        $allContent | Should -Match "DisableRecallDataProviders"
        $allContent | Should -Match "AllowRecallExport"
    }

    It 'covers Edge telemetry' {
        $scriptContent | Should -Match "DiagnosticData.*Expected.*0"
    }

    It 'covers WDigest security' {
        $scriptContent | Should -Match "UseLogonCredential.*Expected.*0"
    }
}

Describe 'WindowsAI Policy Map' {
    BeforeAll {
        $windowsAiPolicyFile = Join-Path $repoRoot 'Modules\PolicyCatalog.psd1'
        $catalog = Import-PowerShellDataFile -Path $windowsAiPolicyFile
        $windowsAiPolicies = @($catalog.Policies)
        $hkcuContent = Get-Content $windowsAiPolicyFile -Raw
        $remediateContent = Get-Content (Join-Path $repoRoot 'Remediate-Drift.ps1') -Raw
        $maintainContent = Get-Content (Join-Path $repoRoot 'Debloat-Win11-Maintain.ps1') -Raw
    }

    It 'keeps DisableRecallDataProviders as a user-scope policy' {
        $policy = $windowsAiPolicies | Where-Object { $_.Name -eq 'DisableRecallDataProviders' }
        $policy.Scope | Should -Be 'User'
        $policy.Path | Should -Be 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
        $hkcuContent | Should -Match 'DisableRecallDataProviders'
    }

    It 'keeps connector policies as device-scope disable values' {
        foreach ($name in @('DisableAgentConnectors','DisableAgentWorkspaces','DisableRemoteAgentConnectors')) {
            $policy = $windowsAiPolicies | Where-Object { $_.Name -eq $name }
            $policy.Scope | Should -Be 'Device'
            $policy.Value | Should -Be 2
        }
    }

    It 'represents Copilot hardware key policy without applying a fake AUMID by default' {
        $policy = $windowsAiPolicies | Where-Object { $_.Name -eq 'SetCopilotHardwareKey' }
        $policy.Scope | Should -Be 'User'
        $policy.Type | Should -Be 'String'
        $policy.ApplyByDefault | Should -Be $false
    }

    It 'drives remediation and maintenance from the shared policy file' {
        $remediateContent | Should -Match 'PolicyCatalog\.psd1'
        $maintainContent | Should -Match 'PolicyCatalog\.psd1'
    }
}

Describe 'Policy Catalog Contract' {
    BeforeAll {
        $catalogFile = Join-Path $repoRoot 'Modules\PolicyCatalog.psd1'
        $catalog = Import-PowerShellDataFile -Path $catalogFile
        $catalogContent = Get-Content $catalogFile -Raw
    }

    It 'is data-only and versioned' {
        $catalog.SchemaVersion | Should -Be 1
        [string]::IsNullOrWhiteSpace([string]$catalog.CatalogVersion) | Should -Be $false
        $catalogContent | Should -Not -Match '(?m)^\s*(function|param)\s'
        $catalogContent | Should -Not -Match 'scriptblock::Create|Invoke-Expression'
    }

    It 'keeps policy and configuration metadata typed' {
        @($catalog.Policies).Count | Should -BeGreaterThan 10
        @($catalog.HkcuTweaks).Count | Should -BeGreaterThan 20
        @($catalog.ConfigSchema.Keys) | Should -Contain 'RemovePatterns'
        $catalog.ConfigSchema.DarkMode.Type | Should -Be 'Boolean'
        $catalog.ConfigSchema.NetworkProfile.Values | Should -Contain 'Preserve'
        $catalog.ConfigSchema.PackageUpdates.Type | Should -Be 'PackageArray'
    }

    It 'defines complete action risk and support metadata for every phase' {
        $actions = @($catalog.Actions)
        $actions.Count | Should -Be 13
        foreach ($action in $actions) {
            $action.Name | Should -Not -BeNullOrEmpty
            $action.Phase | Should -Not -BeNullOrEmpty
            $action.Risk | Should -BeIn @('Low','Medium','High','Critical')
            @($action.Prerequisites).Count | Should -BeGreaterThan 0
            @($action.SupportedEditions).Count | Should -BeGreaterThan 0
            @($action.SupportedArchitectures).Count | Should -BeGreaterThan 0
            $action.SupportedBuildMin | Should -BeGreaterThan 0
            $action.Rollback | Should -Not -BeNullOrEmpty
            $action.DefaultEnabled | Should -BeOfType [bool]
            $action.RequiresApproval | Should -BeOfType [bool]
        }
    }
}

Describe 'Action Plan and Support Matrix' {
    It 'records selected action metadata and rejects unsupported selections before mutation' {
        $scriptContent | Should -Match 'manifest\.action_plan\.Add'
        $scriptContent | Should -Match 'runtime\.supported'
        $scriptContent | Should -Match 'supportErrors'
        $scriptContent | Should -Match 'build.*edition.*architecture'
        $scriptContent | Should -Match 'Write-ActionPlan'
    }
}

Describe 'Deterministic WinGet Operations' {
    It 'does not use unbounded upgrade-all or ambiguous restore search' {
        $scriptContent | Should -Not -Match 'winget upgrade --all'
        $scriptContent | Should -Not -Match '--include-unknown'
        $scriptContent | Should -Match "'upgrade', '--id',"
        $scriptContent | Should -Match "'install', '--id',"
        $scriptContent | Should -Match 'Get-WingetPackageSnapshot'
    }

    It 'records package source, requested version, old/new versions, return code, and skip/failure states' {
        $scriptContent | Should -Match 'package_operations'
        $scriptContent | Should -Match 'before_version'
        $scriptContent | Should -Match 'after_version'
        $scriptContent | Should -Match 'return_code'
        $scriptContent | Should -Match 'UnknownPackage'
        $scriptContent | Should -Match 'Exact package ID is not installed'
        $scriptContent | Should -Match 'RestoreSource'
        $scriptContent | Should -Match 'RestoreVersion'
    }
}

Describe 'Policy Delivery Artifact Export' {
    BeforeAll {
        $exportPolicyScript = Join-Path $repoRoot 'tools\Export-PolicyArtifacts.ps1'
    }

    It 'emits documented OMA-URI/GPO mappings with applicability metadata' {
        $content = Get-Content $exportPolicyScript -Raw
        $content | Should -Match 'Vendor/MSFT/Policy/Config'
        $content | Should -Match 'RemoveDefaultMicrosoftStorePackages'
        $content | Should -Match 'SupportedEditions'
        $content | Should -Match 'PreviewOnly'
        $content | Should -Match 'Do not configure both'
        $content | Should -Match 'catalog_selection'
    }

    It 'produces different Pro and Enterprise 24H2 applicability results' {
        $pro = (& $exportPolicyScript -Edition Pro -Build 26100 | ConvertFrom-Json)
        $enterprise = (& $exportPolicyScript -Edition Enterprise -Build 26100 | ConvertFrom-Json)

        $pro.inbox_app_removal.status | Should -Be 'NotApplicable'
        $enterprise.inbox_app_removal.status | Should -Be 'Ready'
        $enterprise.inbox_app_removal.oma_uri | Should -Be './Device/Vendor/MSFT/Policy/Config/ApplicationManagement/RemoveDefaultMicrosoftStorePackages'
        ($pro.policies | Where-Object { $_.name -eq 'DisableAIDataAnalysis' -and $_.scope -eq 'Device' }).status | Should -Be 'Ready'
        ($enterprise.policies | Where-Object { $_.name -eq 'DisableSettingsAgent' -and $_.scope -eq 'Device' }).preview_only | Should -Be $true
    }

    It 'refuses to turn wildcard removal patterns into package family names' {
        $enterprise = (& $exportPolicyScript -Edition Enterprise -Build 26100 | ConvertFrom-Json)
        $enterprise.inbox_app_removal.catalog_selection | Should -Match 'wildcard'
        @($enterprise.inbox_app_removal.dynamic_removal_list).Count | Should -Be 0
    }
}

Describe 'Destructive Operation Behavior Mocks' {
    BeforeAll {
        function Mount-WindowsImage {
            [CmdletBinding()]
            param(
                [string]$ImagePath,
                [int]$Index,
                [string]$Path
            )
        }

        function Dismount-WindowsImage {
            [CmdletBinding()]
            param(
                [string]$Path,
                [switch]$Save,
                [switch]$Discard
            )
        }

        function Invoke-TestServiceDisable {
            param([string]$ServiceName, [switch]$DryRun)

            $svc = Get-Service -Name $ServiceName -EA 0
            if (-not $svc) { return }

            $script:testManifest.changes.services_disabled.Add(@{
                name = $ServiceName
                original_startup_type = $svc.StartType.ToString()
            }) | Out-Null

            if (-not $DryRun) {
                Stop-Service -Name $ServiceName -Force -EA 0
                Set-Service -Name $ServiceName -StartupType Disabled -EA 0
            }
        }

        function Invoke-TestEventLogClear {
            param([string[]]$ClearEventLogs)

            foreach ($eventLogName in $ClearEventLogs) {
                if ([string]::IsNullOrWhiteSpace($eventLogName)) { continue }
                wevtutil cl "$eventLogName"
            }
        }

        function Invoke-TestWimMutation {
            param([switch]$ShouldFail)

            $wimMounted = $false
            $wimSave = $false
            try {
                Mount-WindowsImage -ImagePath 'C:\install.wim' -Index 1 -Path 'C:\Mount' -EA Stop | Out-Null
                $wimMounted = $true
                if ($ShouldFail) { throw 'simulated WIM failure' }
                $wimSave = $true
            } finally {
                if ($wimMounted) {
                    if ($wimSave) {
                        Dismount-WindowsImage -Path 'C:\Mount' -Save -EA 0 | Out-Null
                    } else {
                        Dismount-WindowsImage -Path 'C:\Mount' -Discard -EA 0 | Out-Null
                    }
                }
            }
        }

        function Invoke-TestRegistrySet {
            param([string]$Path, [string]$Name, $Value, [switch]$DryRun)

            $oldValue = $null
            if (Test-Path $Path) {
                $existing = Get-ItemProperty -Path $Path -Name $Name -EA 0
                if ($existing) { $oldValue = $existing.$Name }
            }

            $script:testManifest.changes.registry_set.Add(@{
                path = $Path
                name = $Name
                old_value = $oldValue
                new_value = $Value
                type = 'DWord'
            }) | Out-Null

            if (-not $DryRun) {
                if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
                Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -EA 0
            }
        }

        function Invoke-TestHtmlReport {
            param([string]$Path, [object[]]$Rows)

            $htmlRows = ($Rows | ForEach-Object {
                $name = [System.Net.WebUtility]::HtmlEncode([string]$_.Name)
                $value = [System.Net.WebUtility]::HtmlEncode([string]$_.Value)
                "<tr><td>$name</td><td>$value</td></tr>"
            }) -join "`n"

            Set-Content -Path $Path -Value "<table>$htmlRows</table>" -Encoding UTF8
        }
    }

    BeforeEach {
        $script:testManifest = @{
            changes = @{
                registry_set = [System.Collections.ArrayList]@()
                services_disabled = [System.Collections.ArrayList]@()
            }
        }
    }

    It 'mocks Stop-Service and Set-Service while preserving original startup type' {
        Mock Get-Service { [pscustomobject]@{ Name = 'TestSvc'; StartType = 'Manual' } }
        Mock Stop-Service {}
        Mock Set-Service {}

        Invoke-TestServiceDisable -ServiceName 'TestSvc'

        $script:testManifest.changes.services_disabled[0].original_startup_type | Should -Be 'Manual'
        Should -Invoke Stop-Service -Times 1 -Exactly -Scope It -ParameterFilter { $Name -eq 'TestSvc' -and $Force }
        Should -Invoke Set-Service -Times 1 -Exactly -Scope It -ParameterFilter { $Name -eq 'TestSvc' -and $StartupType -eq 'Disabled' }
    }

    It 'mocks wevtutil and clears only configured event logs' {
        Mock wevtutil {}

        Invoke-TestEventLogClear -ClearEventLogs @('Application', '', 'System')

        Should -Invoke wevtutil -Times 2 -Exactly -Scope It
        Should -Invoke wevtutil -Times 1 -Exactly -Scope It -ParameterFilter { $args[0] -eq 'cl' -and $args[1] -eq 'Application' }
        Should -Invoke wevtutil -Times 1 -Exactly -Scope It -ParameterFilter { $args[0] -eq 'cl' -and $args[1] -eq 'System' }
    }

    It 'mocks WIM mount and discards image changes after failure' {
        Mock Mount-WindowsImage { [pscustomobject]@{ Mounted = $true } }
        Mock Dismount-WindowsImage {}

        { Invoke-TestWimMutation -ShouldFail } | Should -Throw 'simulated WIM failure'

        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -Scope It
        Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq 'C:\Mount' -and $Discard }
        Should -Invoke Dismount-WindowsImage -Times 0 -Exactly -Scope It -ParameterFilter { $Save }
    }

    It 'mocks registry setters and avoids host writes in DryRun' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { [pscustomobject]@{ ExistingValue = 3 } }
        Mock New-Item {}
        Mock Set-ItemProperty {}

        Invoke-TestRegistrySet -Path 'HKLM:\SOFTWARE\Test' -Name 'ExistingValue' -Value 1 -DryRun

        $script:testManifest.changes.registry_set[0].old_value | Should -Be 3
        $script:testManifest.changes.registry_set[0].new_value | Should -Be 1
        Should -Invoke Set-ItemProperty -Times 0 -Exactly -Scope It
        Should -Invoke New-Item -Times 0 -Exactly -Scope It
    }

    It 'mocks report generation and encodes manifest-derived values' {
        Mock Set-Content {}

        Invoke-TestHtmlReport -Path 'C:\Temp\report.html' -Rows @(
            [pscustomobject]@{ Name = '<Path>'; Value = '"quoted" & raw' }
        )

        Should -Invoke Set-Content -Times 1 -Exactly -Scope It -ParameterFilter {
            $Path -eq 'C:\Temp\report.html' -and
            $Value -match '&lt;Path&gt;' -and
            $Value -match '&quot;quoted&quot; &amp; raw'
        }
    }
}

Describe 'Maintenance Task Trigger' {
    It 'uses WU-completion event trigger instead of AtLogOn' {
        $scriptContent | Should -Not -Match 'New-ScheduledTaskTrigger -AtLogOn'
        $scriptContent | Should -Match 'EventID=19'
        $scriptContent | Should -Match 'WindowsUpdateClient'
    }
}

Describe 'PSScriptAnalyzer Gate' {
    BeforeAll {
        $settingsContent = Get-Content (Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1') -Raw
        $gateContent = Get-Content (Join-Path $repoRoot 'tools\Invoke-StaticAnalysis.ps1') -Raw
    }

    It 'enables PowerShell 5.1 compatibility rules' {
        $settingsContent | Should -Match 'PSUseCompatibleSyntax'
        $settingsContent | Should -Match 'PSUseCompatibleCommands'
        $settingsContent | Should -Match 'PSUseCompatibleTypes'
        $settingsContent | Should -Match "TargetVersions\s*=\s*@\('5\.1'\)"
        $settingsContent | Should -Match 'win-48_x64_10\.0\.17763\.0_5\.1\.17763\.316_x64_4\.0\.30319\.42000_framework'
    }

    It 'runs Invoke-ScriptAnalyzer with the repo settings file' {
        $gateContent | Should -Match 'Invoke-ScriptAnalyzer'
        $gateContent | Should -Match 'PSScriptAnalyzerSettings\.psd1'
        $gateContent | Should -Match '-Recurse'
    }

    It 'fails the local gate on analyzer errors' {
        $gateContent | Should -Match "Severity -eq 'Error'"
        $gateContent | Should -Match 'Write-Error "PSScriptAnalyzer found'
    }
}

Describe 'Lockfile Stale PID Detection' {
    It 'checks PID from lockfile content before aborting' {
        $scriptContent | Should -Match 'PID=\(\\d\+\)'
        $scriptContent | Should -Match 'Get-Process -Id \$lockPid'
        $scriptContent | Should -Match '\$staleLock'
    }

    It 'removes stale lockfile instead of aborting' {
        $scriptContent | Should -Match 'Removing stale lock file'
    }

    It 'captures lockfile path for event handler closure' {
        $scriptContent | Should -Match '\$lockFilePath = \$script:lockFile'
        $scriptContent | Should -Match 'Remove-Item \$lockFilePath'
    }
}

Describe 'Revert Script String Value Quoting' {
    It 'quotes string old_value in generated revert script' {
        $scriptContent | Should -Match "escapedValue.*if.*'String'"
    }
}

Describe 'Service Deduplication' {
    It 'does not double-disable telemetry services in SystemTweaks_Privacy' {
        $privacyContent = Get-Content (Join-Path $repoRoot 'Modules\SystemTweaks_Privacy.ps1') -Raw
        $privacyContent | Should -Not -Match 'Disable-ServiceDryRun.*DiagTrack'
        $privacyContent | Should -Not -Match 'Disable-ServiceDryRun.*dmwappushservice'
    }
}

Describe 'Temp Cleanup Phase Gating' {
    It 'gates temp file cleanup behind Privacy phase check' {
        $servicesContent = Get-Content (Join-Path $repoRoot 'Modules\Services.ps1') -Raw
        $servicesContent | Should -Match "Test-PhaseEnabled 'Privacy'"
    }
}

Describe 'Shared AI Policy Map Coverage' {
    BeforeAll {
        $policyFile = Join-Path $repoRoot 'Modules\PolicyCatalog.psd1'
        $catalog = Import-PowerShellDataFile -Path $policyFile
        $policies = @($catalog.Policies)
    }

    It 'includes Paint AI policies in the shared map' {
        $paintPolicies = $policies | Where-Object { $_.Path -match 'Paint' }
        $paintPolicies.Count | Should -BeGreaterOrEqual 3
    }

    It 'includes Notepad AI policy in the shared map' {
        $notepadPolicies = $policies | Where-Object { $_.Path -match 'Notepad' }
        $notepadPolicies.Count | Should -BeGreaterOrEqual 1
    }

    It 'no longer hardcodes Paint or Notepad policies in drift detection' {
        $detectContent = Get-Content (Join-Path $repoRoot 'Detect-Drift.ps1') -Raw
        $detectContent | Should -Not -Match 'DisableCocreator'
        $detectContent | Should -Not -Match 'DisableImageCreator'
    }
}

Describe 'OneDrive Multi-Profile Safety' {
    It 'checks for files before deleting per-profile OneDrive folders' {
        $oneDriveContent = Get-Content (Join-Path $repoRoot 'Modules\OneDrive.ps1') -Raw
        $oneDriveContent | Should -Match 'Get-ChildItem.*Recurse.*File'
        $oneDriveContent | Should -Match 'contains files'
    }
}

Describe 'Firewall Program Parameter' {
    It 'does not filter out Program=System from firewall rules' {
        $firewallContent = Get-Content (Join-Path $repoRoot 'Modules\Firewall.ps1') -Raw
        $firewallContent | Should -Not -Match "Program -ne 'System'"
        $firewallContent | Should -Match "Program -ne 'Any'"
    }
}
