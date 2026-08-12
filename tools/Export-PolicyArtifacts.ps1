#Requires -Version 5.1
# Export catalog-backed, Microsoft-mapped policy delivery artifacts.
# This tool never invents an OMA-URI: catalog entries without a verified mapping
# are emitted as Unsupported with a reason and are not placed in the ready set.

[CmdletBinding()]
param(
    [string]$OutputPath,
    [ValidateRange(10240,99999)]
    [int]$Build = 26100,
    [ValidateSet('Any','Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS')]
    [string]$Edition = 'Any',
    [ValidateSet('x86','x64','arm64')]
    [string]$Architecture = 'x64'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$catalogPath = Join-Path $repoRoot 'Modules\PolicyCatalog.psd1'
$catalog = Import-PowerShellDataFile -Path $catalogPath
$catalogHash = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash

$windowsAiRegistryPath = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
$paintRegistryPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
$copilotKeyRegistryPath = 'SOFTWARE\Policies\Microsoft\Windows\CopilotKey'
$policyMap = @(
    @{ Name = 'DisableAIDataAnalysis'; Scopes = @('Device','User'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer and User Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $false }
    @{ Name = 'AllowRecallEnablement'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $false }
    @{ Name = 'AllowRecallExport'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableClickToDo'; Scopes = @('Device','User'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer and User Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableSettingsAgent'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableAgentConnectors'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = $null; SupportedEditions = @('Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableAgentWorkspaces'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = $null; SupportedEditions = @('Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableRemoteAgentConnectors'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = $null; SupportedEditions = @('Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableRecallDataProviders'; Scopes = @('User'); CspArea = 'WindowsAI'; RegistryPath = $windowsAiRegistryPath; GpoLocation = 'User Configuration'; GpoPath = 'Windows Components > Windows AI'; Admx = $null; SupportedEditions = @('Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 26100; PreviewOnly = $true }
    @{ Name = 'DisableImageCreator'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $paintRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Paint'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 22621; PreviewOnly = $false }
    @{ Name = 'DisableGenerativeFill'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $paintRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Paint'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 22621; PreviewOnly = $false }
    @{ Name = 'DisableCocreator'; Scopes = @('Device'); CspArea = 'WindowsAI'; RegistryPath = $paintRegistryPath; GpoLocation = 'Computer Configuration'; GpoPath = 'Windows Components > Paint'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 22621; PreviewOnly = $false }
    @{ Name = 'SetCopilotHardwareKey'; Scopes = @('User'); CspArea = 'WindowsAI'; RegistryPath = $copilotKeyRegistryPath; GpoLocation = 'User Configuration'; GpoPath = 'Windows Components > Windows Copilot'; Admx = 'WindowsCopilot.admx'; SupportedEditions = @('Pro','Enterprise','Education','IoTEnterprise','IoTEnterpriseS'); MinBuild = 22621; PreviewOnly = $false }
)

function Test-EditionApplicable {
    param([Parameter(Mandatory)][string[]]$SupportedEditions)
    return $Edition -eq 'Any' -or $SupportedEditions -contains $Edition
}

$records = [System.Collections.ArrayList]@()
foreach ($policy in @($catalog.Policies | Where-Object { $_.ApplyByDefault -ne $false })) {
    $mapping = @($policyMap | Where-Object { $_.Name -eq $policy.Name -and $_.Scopes -contains $policy.Scope }) | Select-Object -First 1
    $reason = $null
    $status = 'Ready'
    $buildApplicable = $false
    $editionApplicable = $false
    $architectureApplicable = $Architecture -in @('x86','x64','arm64')
    $scopeApplicable = $false
    if (-not $mapping) {
        $status = 'Unsupported'
        $reason = 'No verified Microsoft CSP/GPO mapping exists for this catalog policy and scope.'
    } else {
        $buildApplicable = $Build -ge [int]$mapping.MinBuild
        $editionApplicable = Test-EditionApplicable -SupportedEditions $mapping.SupportedEditions
        $scopeApplicable = $mapping.Scopes -contains $policy.Scope
        if ($policy.Path -ine $mapping.RegistryPath) {
            $status = 'Unsupported'
            $reason = "Catalog registry path '$($policy.Path)' does not match the documented path '$($mapping.RegistryPath)'."
        } elseif (-not $buildApplicable) {
            $status = 'NotApplicable'
            $reason = "Target build $Build is below documented minimum build $($mapping.MinBuild)."
        } elseif (-not $editionApplicable) {
            $status = 'NotApplicable'
            $reason = "Target edition '$Edition' is not in the documented edition set: $($mapping.SupportedEditions -join ', ')."
        } elseif (-not $architectureApplicable) {
            $status = 'NotApplicable'
            $reason = "Target architecture '$Architecture' is unsupported."
        } elseif (-not $scopeApplicable) {
            $status = 'Unsupported'
            $reason = "Catalog scope '$($policy.Scope)' is not documented for this policy."
        }
    }
    $omaUri = $null
    $gpo = $null
    if ($mapping) {
        $omaUri = './{0}/Vendor/MSFT/Policy/Config/{1}/{2}' -f $policy.Scope, $mapping.CspArea, $policy.Name
        if ($mapping.Admx) {
            $gpo = [ordered]@{
                location = $mapping.GpoLocation
                path = $mapping.GpoPath
                registry_key = $mapping.RegistryPath
                registry_value = $policy.Name
                admx = $mapping.Admx
            }
        }
    }
    $records.Add([ordered]@{
        name = $policy.Name
        scope = $policy.Scope
        type = $policy.Type
        value = $policy.Value
        catalog_path = $policy.Path
        min_build = if ($mapping) { $mapping.MinBuild } else { $null }
        supported_editions = if ($mapping) { @($mapping.SupportedEditions) } else { @() }
        preview_only = if ($mapping) { [bool]$mapping.PreviewOnly } else { $false }
        status = $status
        applicable = $status -eq 'Ready'
        reason = $reason
        oma_uri = $omaUri
        gpo = $gpo
    }) | Out-Null
}

$inboxApplicable = $Build -ge 26100 -and ($Edition -eq 'Any' -or $Edition -in @('Enterprise','Education'))
$inboxPolicy = [ordered]@{
    name = 'RemoveDefaultMicrosoftStorePackages'
    scope = 'Device'
    min_build = 26100
    supported_editions = @('Enterprise','Education')
    applicable = $inboxApplicable
    status = if ($inboxApplicable) { 'Ready' } else { 'NotApplicable' }
    oma_uri = './Device/Vendor/MSFT/Policy/Config/ApplicationManagement/RemoveDefaultMicrosoftStorePackages'
    gpo = [ordered]@{
        location = 'Computer Configuration'
        path = 'Administrative Templates > Windows Components > App Package Deployment'
        registry_key = 'SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages'
        registry_value = 'RemoveDefaultMicrosoftStorePackages'
        admx = 'Appx.admx'
    }
    catalog_selection = 'Not emitted: the catalog RemovePatterns values are wildcard names, not verified package family names.'
    dynamic_removal_list = @()
    reason = if ($inboxApplicable) { 'Populate static app selections in the management console; custom OMA-URI DynamicRemovalList PFNs are documented by Microsoft as practical for testing only.' } else { "Target $Edition/build $Build is outside the Enterprise/Education Windows 11 24H2+ scope." }
}

$result = [ordered]@{
    schema_version = 1
    artifact_type = 'Debloat-Win11.PolicyDelivery'
    generated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    catalog = [ordered]@{
        catalog_version = [string]$catalog.CatalogVersion
        schema_version = [int]$catalog.SchemaVersion
        sha256 = $catalogHash
    }
    target = [ordered]@{
        build = $Build
        edition = $Edition
        architecture = $Architecture
    }
    delivery_guidance = @(
        'Choose one delivery channel per setting: MDM/OMA-URI or GPO. Do not configure both for the same device.'
        'Policy applicability is evaluated against the requested build, edition, architecture, and catalog registry path.'
        'Preview-only WindowsAI mappings are emitted with preview_only=true and require live validation before production use.'
    )
    sources = @(
        'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai'
        'https://learn.microsoft.com/en-us/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal'
    )
    policies = @($records)
    inbox_app_removal = $inboxPolicy
    summary = [ordered]@{
        total_catalog_policies = @($records).Count
        ready = @($records | Where-Object status -eq 'Ready').Count
        not_applicable = @($records | Where-Object status -eq 'NotApplicable').Count
        unsupported = @($records | Where-Object status -eq 'Unsupported').Count
    }
}

$json = $result | ConvertTo-Json -Depth 12
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    [System.IO.File]::WriteAllText($resolvedOutputPath, $json, [System.Text.Encoding]::UTF8)
    Write-Output $resolvedOutputPath
} else {
    Write-Output $json
}
