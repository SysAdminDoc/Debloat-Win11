# ============================================================================
# MODULE: Firewall Rules
# Phase 6: Import firewall rules for file/printer sharing
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
if (-not (Test-IrreversibleOperationAllowed -Name 'Firewall rule replacement')) {
    Write-Log "[Firewall] Rule replacement SKIPPED (explicit approval required)" "WARNING"
    return
}

Write-Log "[Firewall] Importing firewall rules..." "SECTION"
Write-Rationale 'Firewall'

# Default: File and Printer Sharing rules. Use -ConfigPath with FirewallRules key to override.
$firewallCsv = if ($script:configOverrides.ContainsKey('FirewallRules')) { $script:configOverrides.FirewallRules } else { @"
Name	DisplayName	Direction	Action	Protocol	LocalPort	RemotePort	Program
FPS-NB_Datagram-In-UDP	File and Printer Sharing (NB-Datagram-In)	Inbound	Allow	UDP	138	Any	System
FPS-NB_Name-Out-UDP	File and Printer Sharing (NB-Name-Out)	Outbound	Allow	UDP	Any	137	System
FPS-SMB-In-TCP	File and Printer Sharing (SMB-In)	Inbound	Allow	TCP	445	Any	System
FPS-NB_Session-In-TCP	File and Printer Sharing (NB-Session-In)	Inbound	Allow	TCP	139	Any	System
FPS-NB_Name-In-UDP	File and Printer Sharing (NB-Name-In)	Inbound	Allow	UDP	137	Any	System
FPS-SMB-Out-TCP	File and Printer Sharing (SMB-Out)	Outbound	Allow	TCP	Any	445	System
FPS-NB_Session-Out-TCP	File and Printer Sharing (NB-Session-Out)	Outbound	Allow	TCP	Any	139	System
FPS-NB_Datagram-Out-UDP	File and Printer Sharing (NB-Datagram-Out)	Outbound	Allow	UDP	Any	138	System
FPS-LLMNR-In-UDP	File and Printer Sharing (LLMNR-UDP-In)	Inbound	Allow	UDP	5355	Any	System
FPS-LLMNR-Out-UDP	File and Printer Sharing (LLMNR-UDP-Out)	Outbound	Allow	UDP	Any	5355	System
"@ }

$rules = @($firewallCsv | ConvertFrom-Csv -Delimiter "`t" | Where-Object { $_.Name -notmatch 'LLMNR' })

if (-not $DryRun) {
    Write-Log "  Enabling Windows Firewall..." "INFO"
    Invoke-TrackedOperation -Name 'Domain,Private firewall profiles' -Action 'Enable firewall profiles' -Scope 'Machine' -Operation {
        Set-NetFirewallProfile -Profile Domain,Private -Enabled True -EA Stop
    } -Verification {
        $profiles = @(Get-NetFirewallProfile -Profile Domain,Private -EA Stop)
        @($profiles | Where-Object { -not $_.Enabled }).Count -eq 0
    } | Out-Null

    Write-Log "  Importing firewall rules..." "INFO"
    $successCount = 0

    foreach ($rule in $rules) {
        try {
            $existingRules = @(Get-NetFirewallRule -Name $rule.Name -EA 0)
            foreach ($existing in $existingRules) {
                $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -EA 0
                $script:manifest.changes.firewall_rules.Add([ordered]@{
                    name = $existing.Name
                    display_name = $existing.DisplayName
                    direction = [string]$existing.Direction
                    action = [string]$existing.Action
                    enabled = [string]$existing.Enabled
                    profile = [string]$existing.Profile
                    protocol = if ($portFilter) { [string]$portFilter.Protocol } else { $null }
                    local_port = if ($portFilter) { [string]$portFilter.LocalPort } else { $null }
                    remote_port = if ($portFilter) { [string]$portFilter.RemotePort } else { $null }
                }) | Out-Null
            }

            $params = @{
                Name = $rule.Name
                DisplayName = $rule.DisplayName
                Direction = $rule.Direction
                Action = $rule.Action
                Enabled = 'True'
                Profile = 'Domain,Private'
            }

            if ($rule.Protocol -and $rule.Protocol -ne 'Any') { $params.Protocol = $rule.Protocol }
            if ($rule.LocalPort -and $rule.LocalPort -ne 'Any') { $params.LocalPort = $rule.LocalPort }
            if ($rule.RemotePort -and $rule.RemotePort -ne 'Any') { $params.RemotePort = $rule.RemotePort }
            if ($rule.Program -and $rule.Program -ne 'Any') { $params.Program = $rule.Program }

            $created = Invoke-TrackedOperation -Name $rule.Name -Action 'Replace firewall rule' -Scope 'Machine' -Operation {
                if ($existingRules.Count -gt 0) { Remove-NetFirewallRule -Name $rule.Name -EA Stop }
                New-NetFirewallRule @params -EA Stop | Out-Null
            } -Verification {
                @((Get-NetFirewallRule -Name $rule.Name -EA Stop)).Count -gt 0
            }
            if ($created) { $successCount++ }
        } catch {
            Write-Log "  Failed to import rule '$($rule.Name)': $_" "ERROR"
        }
    }

    Write-Log "  Imported $successCount firewall rules" "SUCCESS"
} else {
    foreach ($rule in $rules) {
        Register-OperationResult -Name $rule.Name -Action 'Replace firewall rule' -Scope 'Machine' -Status 'Planned'
    }
    Register-OperationResult -Name 'Domain,Private firewall profiles' -Action 'Enable firewall profiles' -Scope 'Machine' -Status 'Planned'
    Write-Log "  [DRY RUN] Would import $($rules.Count) firewall rules" "INFO"
}
