@(
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
    @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Paint'; Name = 'DisableImageCreator'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
    @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Paint'; Name = 'DisableGenerativeFill'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
    @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\Microsoft\Paint'; Name = 'DisableCocreator'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
    @{ Scope = 'Device'; Path = 'SOFTWARE\Policies\WindowsNotepad'; Name = 'DisableAIFeatures'; Value = 1; Type = 'DWord'; ApplyByDefault = $true }
)
