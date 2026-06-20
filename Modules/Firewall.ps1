# ============================================================================
# MODULE: Firewall Rules
# Phase 6: Import firewall rules for file/printer sharing
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Phase 6/7] Importing firewall rules..." "SECTION"
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

$rules = $firewallCsv | ConvertFrom-Csv -Delimiter "`t"

if (-not $DryRun) {
    Write-Log "  Enabling Windows Firewall..." "INFO"
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -EA 0

    Write-Log "  Importing firewall rules..." "INFO"
    $successCount = 0

    foreach ($rule in $rules) {
        try {
            Remove-NetFirewallRule -Name $rule.Name -EA 0

            $params = @{
                Name = $rule.Name
                DisplayName = $rule.DisplayName
                Direction = $rule.Direction
                Action = $rule.Action
                Enabled = 'True'
                Profile = 'Private,Public'
            }

            if ($rule.Protocol -and $rule.Protocol -ne 'Any') { $params.Protocol = $rule.Protocol }
            if ($rule.LocalPort -and $rule.LocalPort -ne 'Any') { $params.LocalPort = $rule.LocalPort }
            if ($rule.RemotePort -and $rule.RemotePort -ne 'Any') { $params.RemotePort = $rule.RemotePort }
            if ($rule.Program -and $rule.Program -ne 'System') { $params.Program = $rule.Program }

            New-NetFirewallRule @params -EA Stop | Out-Null
            $successCount++
        } catch {
            Write-Log "  Failed to import rule '$($rule.Name)': $_" "ERROR"
        }
    }

    Write-Log "  Imported $successCount firewall rules" "SUCCESS"
} else {
    Write-Log "  [DRY RUN] Would import $($rules.Count) firewall rules" "INFO"
}
