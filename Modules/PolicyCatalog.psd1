# Data-only policy and profile catalog. Do not add executable expressions here.
# Type is optional for registry entries and defaults to DWord in profile propagation.
@{
    SchemaVersion = 1
    CatalogVersion = '1.0'

    Policies = @(
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'TurnOffSavingSnapshots'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'TurnOffSavingSnapshots'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Value = 0; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableSettingsAgent'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAgentConnectors'; Value = 2; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAgentWorkspaces'; Value = 2; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableRemoteAgentConnectors'; Value = 2; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableRecallDataProviders'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallExport'; Value = 0; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\CopilotKey'; Name = 'SetCopilotHardwareKey'; Value = ''; Type = 'String'; ApplyByDefault = $false }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableImageCreator'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableGenerativeFill'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableCocreator'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
        @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\WindowsNotepad'; Name = 'DisableAIFeatures'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
    )

    HkcuTweaks = @(
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDynamicSearchBoxEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LaunchTo'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowRecent'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowFrequent'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'TurnOffSavingSnapshots'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableRecallDataProviders'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\Shell\Copilot'; Name = 'IsCopilotAvailable'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup'; Name = 'NotificationDisabled'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'; Name = 'EnableAccountNotifications'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Value = 1; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338387Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353698Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'ContentDeliveryAllowed'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'FeatureManagementEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-88000326Enabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenEnabled'; Value = 0; Type = 'DWord' }
        @{ Scope = 'User'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Value = 0; Type = 'DWord' }
    )

    Actions = @(
        @{ Name = 'AppX package removal'; Phase = 'AppX'; Risk = 'High'; Scope = 'Mixed'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'AppX and DISM cmdlets'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'OEM cleanup'; Phase = 'OEM'; Risk = 'Critical'; Scope = 'Mixed'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'Vendor detection'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'OneDrive removal'; Phase = 'OneDrive'; Risk = 'High'; Scope = 'Mixed'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'No active account or files'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'Office removal'; Phase = 'Office'; Risk = 'Critical'; Scope = 'Mixed'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'No license or running Office process'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'Edge configuration'; Phase = 'Edge'; Risk = 'Medium'; Scope = 'Machine,User'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'Microsoft Edge policy support'); Dependencies = @(); Rollback = 'RegistryManifest'; DefaultEnabled = $true; RequiresApproval = $false }
        @{ Name = 'Firewall rules'; Phase = 'Firewall'; Risk = 'High'; Scope = 'Machine'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'NetSecurity cmdlets'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'Privacy cleanup'; Phase = 'Privacy'; Risk = 'High'; Scope = 'Mixed'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'Review event-log policy'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'Service cleanup'; Phase = 'Services'; Risk = 'High'; Scope = 'Machine'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'Review service dependencies'); Dependencies = @(); Rollback = 'ServiceManifest'; DefaultEnabled = $true; RequiresApproval = $false }
        @{ Name = 'System tweaks'; Phase = 'SystemTweaks'; Risk = 'Medium'; Scope = 'Machine,User'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'Registry provider'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $true; RequiresApproval = $false }
        @{ Name = 'Power configuration'; Phase = 'Power'; Risk = 'Medium'; Scope = 'Machine'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'PowerCfg'); Dependencies = @(); Rollback = 'RegistryManifest'; DefaultEnabled = $true; RequiresApproval = $false }
        @{ Name = 'Network configuration'; Phase = 'Network'; Risk = 'High'; Scope = 'Machine'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'NetSecurity cmdlets'); Dependencies = @(); Rollback = 'Partial'; DefaultEnabled = $false; RequiresApproval = $true }
        @{ Name = 'Start menu cleanup'; Phase = 'StartMenu'; Risk = 'Medium'; Scope = 'CurrentUser'; SupportedBuildMin = 10240; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'Explorer profile'); Dependencies = @(); Rollback = 'RegistryManifest'; DefaultEnabled = $true; RequiresApproval = $false }
        @{ Name = 'WinGet updates'; Phase = 'Updates'; Risk = 'High'; Scope = 'Machine,User'; SupportedBuildMin = 19041; SupportedEditions = @('AnyClient'); SupportedArchitectures = @('x86','x64','arm64'); Prerequisites = @('Administrator', 'WinGet source and network'); Dependencies = @(); Rollback = 'NotAvailable'; DefaultEnabled = $false; RequiresApproval = $true }
    )

    ConfigSchema = @{
        RemovePatterns = @{ Type = 'StringArray'; ElementPattern = '^\*.*\*$' }
        ServicesToDisable = @{ Type = 'StringArray'; ElementPattern = '^[A-Za-z0-9_\-]+$' }
        DefenderExclusions = @{ Type = 'StringArray'; ElementPattern = '.+' }
        EdgeBookmarks = @{ Type = 'BookmarkArray' }
        StartupBloat = @{ Type = 'StringArray'; ElementPattern = '.+' }
        TasksToDisable = @{ Type = 'StringArray'; ElementPattern = '.+' }
        FeaturesToDisable = @{ Type = 'StringArray'; ElementPattern = '.+' }
        FirewallRules = @{ Type = 'String' }
        DarkMode = @{ Type = 'Boolean' }
        OemExclude = @{ Type = 'StringArray'; ElementPattern = '.+' }
        ClearEventLogs = @{ Type = 'StringArray'; ElementPattern = '^[A-Za-z0-9 _\-/]+$' }
        NetworkProfile = @{ Type = 'Enum'; Values = @('Preserve') }
        DisableNagle = @{ Type = 'Boolean' }
        EnableNetworkDiscovery = @{ Type = 'Boolean' }
        EnableFilePrinterSharing = @{ Type = 'Boolean' }
        PackageUpdates = @{ Type = 'PackageArray' }
    }
}
