# Shared HKCU tweak definitions consumed by both Debloat-Win11.ps1 (-AllUsers)
# and Debloat-Win11-Maintain.ps1 (post-update re-application).
# Add new HKCU tweaks here -- both scripts pick them up automatically.
# Path is relative to HKU hive root (no HKCU:\ prefix).
@(
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDynamicSearchBoxEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Value = 1 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'LaunchTo'; Value = 1 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowRecent'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowFrequent'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1 }
    @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'TurnOffSavingSnapshots'; Value = 1 }
    @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Value = 1 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\Shell\Copilot'; Name = 'IsCopilotAvailable'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsBackup'; Name = 'NotificationDisabled'; Value = 1 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'; Name = 'EnableAccountNotifications'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Value = 1 }
    @{ Path = 'SOFTWARE\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Value = 1 }
    # ContentDeliveryManager keys
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338387Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353698Enabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'ContentDeliveryAllowed'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Value = 0 }
    @{ Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'FeatureManagementEnabled'; Value = 0 }
)
