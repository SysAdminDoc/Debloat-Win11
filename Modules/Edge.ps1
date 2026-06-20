# ============================================================================
# MODULE: Edge Debloat
# Phase 5: Edge Group Policy configuration, telemetry, Copilot, bookmarks
# Dot-sourced by Debloat-Win11.ps1 -- runs in caller's scope
# ============================================================================
Write-Log "[Phase 5/7] Configuring Microsoft Edge..." "SECTION"
Write-Rationale 'Edge'

# Close Edge first
if (-not $DryRun) {
    Stop-Process -Name 'msedge' -Force -EA 0
    Start-Sleep -Seconds 2
}

$edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (!(Test-Path $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }

# Edge Telemetry & Data Collection
Write-Log "  Disabling Edge telemetry..." "INFO"
@{
    "DiagnosticData" = 0; "MetricsReportingEnabled" = 0; "PersonalizationReportingEnabled" = 0
    "SendSiteInfoToImproveServices" = 0; "Edge3PSerpTelemetryEnabled" = 0
    "UserFeedbackAllowed" = 0; "CrashReportingMode" = 0
    "ExperimentationAndConfigurationServiceControl" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Copilot & AI
Write-Log "  Disabling Edge Copilot & AI..." "INFO"
@{
    "HubsSidebarEnabled" = 0; "EdgeCopilotEnabled" = 0; "CopilotPageContext" = 0
    "CopilotCDPPageContext" = 0; "Microsoft365CopilotChatIconEnabled" = 0
    "NewTabPageBingChatEnabled" = 0; "NewTabPageBingAIPromptEnabled" = 0
    "GenAILocalFoundationalModelSettings" = 0; "ComposeInlineEnabled" = 0
    "VisualSearchEnabled" = 0; "QuickSearchShowMiniMenu" = 0
    "EdgeHistoryAISearchEnabled" = 0; "AIGenThemesEnabled" = 0
    "BuiltInAIAPIsEnabled" = 0; "CopilotAddressBarSuggestionsEnabled" = 0
    "EdgeEntraCopilotPageContext" = 0; "CopilotNewTabPageEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Shopping & Promotions
Write-Log "  Disabling Edge shopping & promotions..." "INFO"
@{
    "EdgeShoppingAssistantEnabled" = 0; "EdgeWalletEnabled" = 0; "EdgeWalletCheckoutEnabled" = 0
    "ShowMicrosoftRewards" = 0; "ShowRecommendationsEnabled" = 0
    "SpotlightExperiencesAndRecommendationsEnabled" = 0; "PromotionalTabsEnabled" = 0
    "DefaultBrowserSettingsCampaignEnabled" = 0; "TravelAssistanceEnabled" = 0
    "GamerModeEnabled" = 0; "WebWidgetAllowed" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge New Tab & UI
Write-Log "  Configuring Edge new tab & UI..." "INFO"
@{
    "NewTabPageContentEnabled" = 0; "NewTabPageHideDefaultTopSites" = 1
    "NewTabPageNewsEnabled" = 0; "NewTabPageQuickLinksEnabled" = 0
    "FavoritesBarEnabled" = 1; "TabGroupsEnabled" = 0; "TabGroupsAutoCreate" = 0
    "EdgeCollectionsEnabled" = 0; "EdgeFollowEnabled" = 0; "WorkspacesEnabled" = 0
    "ShowOfficeShortcutInFavoritesBar" = 0; "SplitScreenEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Performance
Write-Log "  Configuring Edge performance..." "INFO"
@{
    "StartupBoostEnabled" = 0; "BackgroundModeEnabled" = 0
    "SleepingTabsEnabled" = 1; "HardwareAccelerationModeEnabled" = 1
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Sync & Sign-In
Write-Log "  Disabling Edge sync & sign-in..." "INFO"
@{
    "SyncDisabled" = 1; "BrowserSignin" = 0; "ImplicitSignInEnabled" = 0
    "SignInCtaOnNtpEnabled" = 0; "LinkedAccountEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge Privacy
Write-Log "  Configuring Edge privacy..." "INFO"
@{
    "TrackingPrevention" = 3; "ConfigureDoNotTrack" = 1; "BlockThirdPartyCookies" = 1
    "DefaultGeolocationSetting" = 2; "DefaultNotificationsSetting" = 2
    "AutofillAddressEnabled" = 0; "AutofillCreditCardEnabled" = 0
    "PasswordManagerEnabled" = 0; "SmartScreenEnabled" = 1
    "AutomaticHttpsDefault" = 2; "EnableMediaRouter" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Edge First Run & Homepage
Write-Log "  Configuring Edge first run & homepage..." "INFO"
@{
    "HideFirstRunExperience" = 1; "PreventFirstRunPage" = 1
    "ShowBrowserMigrationPrompt" = 0; "AutoImportAtFirstRun" = 0
    "HomepageIsNewTabPage" = 0; "ShowHomeButton" = 1; "RestoreOnStartup" = 4
    "DefaultSearchProviderEnabled" = 1; "AddressBarMicrosoftSearchInBingProviderEnabled" = 0
}.GetEnumerator() | ForEach-Object { Set-Reg -Path $edgePolicyPath -Name $_.Key -Value $_.Value }

# Set homepage and search to Google
Set-Reg -Path $edgePolicyPath -Name "HomepageLocation" -Value "https://www.google.com" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "NewTabPageLocation" -Value "https://www.google.com" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "DefaultSearchProviderName" -Value "Google" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "DefaultSearchProviderSearchURL" -Value "https://www.google.com/search?q={searchTerms}" -Type "String"
Set-Reg -Path $edgePolicyPath -Name "DefaultSearchProviderSuggestURL" -Value "https://www.google.com/complete/search?client=chrome&q={searchTerms}" -Type "String"

# Startup URLs
$startupUrlsPath = "$edgePolicyPath\RestoreOnStartupURLs"
if (!(Test-Path $startupUrlsPath)) { New-Item -Path $startupUrlsPath -Force | Out-Null }
Set-Reg -Path $startupUrlsPath -Name "1" -Value "https://www.google.com" -Type "String"

# Force install uBlock Origin
Write-Log "  Installing uBlock Origin..." "INFO"
$forcelistPath = "$edgePolicyPath\ExtensionInstallForcelist"
if (!(Test-Path $forcelistPath)) { New-Item -Path $forcelistPath -Force | Out-Null }
Set-Reg -Path $forcelistPath -Name "1" -Value "odfafepnkmbhccpbejgmiehpchacaeak;https://edge.microsoft.com/extensionwebstorebase/v1/crx" -Type "String"

# Configure Edge bookmarks (default: Google only; use -ConfigPath to add vendor links)
if (-not $DryRun) {
    Write-Log "  Configuring Edge bookmarks..." "INFO"
    $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"

    # Check if Edge profile exists, if not create it by launching Edge
    $edgeProfileExists = (Test-Path "$edgeUserData\Default\Bookmarks") -or (Test-Path "$edgeUserData\Profile 1\Bookmarks")
    if (-not $edgeProfileExists) {
        Write-Log "  Creating Edge profile..." "INFO"
        $edgePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        if (-not (Test-Path $edgePath)) { $edgePath = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }

        if (Test-Path $edgePath) {
            # Launch Edge to create profile
            Start-Process $edgePath -ArgumentList "--no-first-run" -EA 0
            Start-Sleep -Seconds 5

            # Close Edge
            Stop-Process -Name 'msedge' -Force -EA 0
            Start-Sleep -Seconds 2
        }
    }

    if (Test-Path $edgeUserData) {
        $edgeProfiles = Get-ChildItem $edgeUserData -Directory -EA 0 | Where-Object { $_.Name -match '^(Default|Profile)' }
        foreach ($userProf in $edgeProfiles) {
            $bookmarksFile = Join-Path $userProf.FullName "Bookmarks"
            if (Test-Path $bookmarksFile) {
                try {
                    $content = Get-Content $bookmarksFile -Raw -Encoding UTF8 | ConvertFrom-Json

                    # Remove OEM folders (Dell, Import favorites, etc.)
                    if ($content.roots.bookmark_bar.children) {
                        $content.roots.bookmark_bar.children = @($content.roots.bookmark_bar.children | Where-Object {
                            $_.name -notin @('Dell', 'Import favorites', 'Favorites bar', 'Managed favorites', 'HP', 'Lenovo', 'ASUS', 'Acer', 'MSI')
                        })
                    }

                    # Get max ID
                    $script:maxId = 1
                    function Get-MaxBookmarkId($node) {
                        if ($node.id) { $id = [int]$node.id; if ($id -gt $script:maxId) { $script:maxId = $id } }
                        if ($node.children) { foreach ($child in $node.children) { Get-MaxBookmarkId $child } }
                    }
                    Get-MaxBookmarkId $content.roots.bookmark_bar

                    # Bookmarks to add (use -ConfigPath for vendor-specific bookmarks)
                    $edgeBookmarks = if ($script:configOverrides.ContainsKey('EdgeBookmarks')) { $script:configOverrides.EdgeBookmarks } else { @(
                        @{ name = "Google"; url = "https://www.google.com" }
                    ) }

                    # Get existing URLs
                    $existingUrls = @{}
                    foreach ($bm in $content.roots.bookmark_bar.children) {
                        if ($bm.url) { $existingUrls[$bm.url.TrimEnd('/').ToLower()] = $true }
                    }

                    # Add new bookmarks
                    $timestamp = [math]::Floor((Get-Date -UFormat %s)) * 1000000
                    $newBookmarks = @()
                    foreach ($bm in $edgeBookmarks) {
                        $normalizedUrl = $bm.url.TrimEnd('/').ToLower()
                        if (-not $existingUrls.ContainsKey($normalizedUrl)) {
                            $script:maxId++
                            $newBookmarks += @{
                                date_added = $timestamp.ToString()
                                date_last_used = "0"
                                guid = [guid]::NewGuid().ToString()
                                id = $script:maxId.ToString()
                                name = $bm.name
                                type = "url"
                                url = $bm.url
                            }
                            $timestamp++
                        }
                    }

                    if ($newBookmarks.Count -gt 0) {
                        $content.roots.bookmark_bar.children = @($newBookmarks) + @($content.roots.bookmark_bar.children)
                        $content.checksum = ""
                        $json = $content | ConvertTo-Json -Depth 100
                        [System.IO.File]::WriteAllText($bookmarksFile, $json, [System.Text.Encoding]::UTF8)
                    }
                } catch {
                    Write-Log "  Failed to configure bookmarks for $($userProf.Name): $_" "ERROR"
                }
            }
        }
    }
}

Write-Log "  Edge configured" "SUCCESS"
