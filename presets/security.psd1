# Security Hardening Preset - Enterprise/healthcare environments
# Applies standard debloat + additional security hardening controls
# Usage: .\Debloat-Win11.ps1 -ConfigPath .\presets\security.psd1
#
# Hardening controls applied via registry (in addition to standard debloat):
#   - WDigest plaintext credential caching disabled
#   - Remote Desktop disabled
#   - NTLM restricted to NTLMv2 only
#   - PowerShell script block logging enabled
#   - ASR rules in audit mode
#   - Anonymous SAM enumeration disabled
#   - Autoplay disabled on all drives
#   - Windows Script Host restricted

@{
    ServicesToDisable = @(
        # Standard telemetry/bloat
        'DiagTrack',
        'dmwappushservice',
        'DPS',
        'WdiSystemHost',
        'WdiServiceHost',
        'InventorySvc',
        'WaaSMedicSvc',
        'XblAuthManager',
        'XblGameSave',
        'XboxGipSvc',
        'XboxNetApiSvc',
        'GamingServices',
        'GamingServicesNet',
        'CDPSvc',
        'CDPUserSvc',
        'DoSvc',
        'TrkWks',
        'NPSMSvc',
        'RmSvc',
        'OneSyncSvc',
        'lmhosts',
        'WSAIFabricSvc',
        'IsoEnvBroker',
        'lfsvc',
        'Fax',
        'WMPNetworkSvc',
        'icssvc',
        'WerSvc',
        'wisvc',
        'RetailDemo',
        'MapsBroker',
        'PhoneSvc',
        'AJRouter',
        'WalletService',
        'RemoteRegistry',
        'WpcMonSvc',
        'SharedAccess',
        'MessagingService',
        'PcaSvc',
        'SEMgrSvc',
        'SmsRouter',
        # Security hardening additions
        'TermService',
        'UmRdpService',
        'SessionEnv'
    )

    DefenderExclusions = @()

    EdgeBookmarks = @(
        @{ name = "Google"; url = "https://www.google.com" }
    )
}
