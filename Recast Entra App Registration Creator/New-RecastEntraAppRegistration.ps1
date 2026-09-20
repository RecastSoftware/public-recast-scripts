<#
.SYNOPSIS
    Interactively creates a Microsoft Entra app registration for Recast Software products
    and assigns only the Microsoft Graph permissions required by the features you select.
.DESCRIPTION
    Walks the operator through:
        1. Choosing the product  -> Right Click Tools  or  Application Workspace
        2. Choosing the features -> only the features actually in use
        3. Building the de-duplicated Graph permission set for those features
        4. Creating the app registration, service principal, platform config, and
           (optionally) a client secret
        5. Granting tenant-wide admin consent for every permission it added
    Permission GUIDs are resolved LIVE from the Microsoft Graph service principal in the
    target tenant, so nothing is hardcoded and nothing drifts when Microsoft changes IDs.
    Application Workspace behaviour mirrors the onboarding guide
    "How to Setup Microsoft Entra App Registration to use as an Application Workspace
    Identity Source", including the Web redirect URI, the User.Read delegated sign-in
    scope, and client secret handling.
.PARAMETER DisplayName
    Name for the new app registration. Prompted for if not supplied.
.PARAMETER TenantId
    Target tenant. Optional - omit to use the tenant of the signed-in account.
.PARAMETER CreateClientSecret
    Create a client secret and return it once, in clear text, at the end of the run.
.PARAMETER SecretMonths
    Lifetime of the client secret in months. Default 12, max 24.
.PARAMETER ZoneUrl
    Application Workspace only. Your zone URL, e.g. https://yourzone.recastsoftware.cloud
    The script appends /api/auth/token/end and registers it as the Web redirect URI.
.PARAMETER SkipConsent
    Create the app and stage the permissions but do NOT grant admin consent.
    Use when the person running this does not hold Privileged Role Administrator.
.PARAMETER WhatIfOnly
    Show the resolved permission set and exit without touching the tenant.
.PARAMETER AutoInstallModules
    Install missing modules without prompting.
.PARAMETER ModuleScope
    CurrentUser (default) or AllUsers. AllUsers requires an elevated session.
.PARAMETER ConfigureServiceConnection
    Right Click Tools only. After creating the app registration, create the matching
    AzureActiveDirectory service connection in Recast Management Server. Requires a
    client secret, so use with -CreateClientSecret.
.PARAMETER RmsServer
    RMS server for -ConfigureServiceConnection, e.g. rms.contoso.com
.PARAMETER RmsPort
    RMS port. Defaults to 444; dev installs often use 44339.
.PARAMETER AllowSelfSignedCertificate
    Skip TLS validation when talking to RMS. Needed for the self-signed certificate most
    RMS installs use.
.PARAMETER ConfigureIdentitySource
    Application Workspace only. After creating the app registration, create the Entra ID
    identity source in the connected zone. Requires the Application Workspace (Liquit)
    PowerShell module to already be imported and connected, plus a client secret.
.PARAMETER IdentitySourceName
    Identity source Name. If the tenant is Hybrid Joined this must match the NETBIOS /
    pre-Windows 2000 domain name exactly - it is case sensitive.
.PARAMETER ExistingAppId
    Application (client) ID of an app registration that already exists. Skips creation,
    permissions, and consent entirely, and goes straight to configuring the product -
    either the RMS service connection or the Application Workspace identity source.
    Nothing is written to the app registration in this mode; it is only read, to confirm
    it exists. You will be prompted for the client secret value, because Entra reveals a
    secret exactly once at creation and there is no API to read it back. Either paste the
    vaulted value, or add a new secret in the portal first.
    Cannot be combined with -CreateClientSecret.
.PARAMETER SkipAppValidation
    Skip the read-only Graph lookup that confirms -ExistingAppId exists before
    configuring. Avoids a sign-in, at the cost of not catching a mistyped GUID until the
    product rejects it. Requires -TenantId, or prompts for it.
.PARAMETER EnableAzurePhotos
    -ExistingAppId runs only. Sets AzurePhotos on the Application Workspace identity
    source. Normally derived from the feature catalog, which is skipped in this mode.
    Prompted for unless -Force is used.
.PARAMETER EnableGroupWrite
    -ExistingAppId runs only. Sets AzureWriteMode to GroupMembership on the identity
    source. Prompted for unless -Force is used.
.PARAMETER ConfigureMailServer
    -ExistingAppId runs only. Also creates the Microsoft Graph mail server. Prompted for
    unless -Force is used.
.PARAMETER UseDeviceCode
    Bypass the Windows Web Account Manager (WAM) broker and sign in with a device code.
    Use this when the interactive sign-in window hangs on "Just a moment..." or when the
    broker window opens behind the terminal. Device code auth talks to Entra directly and
    always lets you choose the account.
.PARAMETER ReuseGraphSession
    Accept an existing Microsoft Graph session instead of forcing a fresh sign-in. By
    default the script signs out, clears the cached MSAL tokens, and prompts every run,
    so the account used is always explicit. Use this for unattended runs where a session
    has already been established.
.PARAMETER Force
    Skip the "create the app registration in THIS tenant?" confirmation shown after
    sign-in. For unattended runs.
.PARAMETER MailServerName
    Name for the Application Workspace Microsoft Graph mail server. Only used when the
    "AW - Email notifications sent via Graph" feature is selected. Defaults to
    "Microsoft Graph" if omitted.
.PARAMETER MailServerFrom
    Sender address for the Graph mail server, e.g. noreply@contoso.com. Must be a real
    mailbox in the tenant that the app registration is permitted to send as. Prompted
    for if omitted.
.PARAMETER ZoneCredential
    Credentials for the Application Workspace zone API account (e.g. local\admin).
    Prompted for if omitted when -ConfigureIdentitySource is used.
.PARAMETER AwModulePath
    Full path to Liquit.Server.PowerShell.dll, for a local Application Workspace install
    in a non-standard location. Normally unnecessary - if no local DLL is found, the
    script offers to install the Liquit.Server.PowerShell module from PSGallery instead.
.PARAMETER IdentitySourceDisplayName
    Friendly name shown to end users on the sign-in button, e.g. "Recast Software".
.PARAMETER CleanConflictingModules
    Remove Microsoft.Graph.* versions that do not match the pinned version, without
    prompting.
.EXAMPLE
    .\New-RecastEntraAppRegistration.ps1 -DisplayName "Recast - Right Click Tools" -CreateClientSecret
.EXAMPLE
    .\New-RecastEntraAppRegistration.ps1 -ZoneUrl "https://contoso.recastsoftware.cloud" -CreateClientSecret
.EXAMPLE
    # Configure RMS against an app registration created earlier
    .\New-RecastEntraAppRegistration.ps1 -ExistingAppId '00000000-1111-2222-3333-444444444444' `
        -ConfigureServiceConnection -RmsServer rms.contoso.com -AllowSelfSignedCertificate
.EXAMPLE
    # Configure an Application Workspace identity source against an existing app
    .\New-RecastEntraAppRegistration.ps1 -ExistingAppId '00000000-1111-2222-3333-444444444444' `
        -ConfigureIdentitySource -ZoneUrl "https://contoso.recastsoftware.cloud" `
        -IdentitySourceName 'EntraID' -IdentitySourceDisplayName 'Recast Software'
.NOTES
    Requires : PowerShell 5.1+ and the Microsoft.Graph.Authentication / Microsoft.Graph.Applications modules
    Rights   : Application Administrator to create the app
               Privileged Role Administrator (or Global Administrator) to grant consent
    Author   : Christopher Antoku
    Run this in a standalone PowerShell window rather than the VS Code Integrated
    Console. That host keeps assemblies loaded between runs, which can make Microsoft
    Graph SDK version conflicts unrecoverable without restarting the console.
#>
[CmdletBinding()]
param(
    [string]$DisplayName,
    [string]$TenantId,
    [switch]$CreateClientSecret,
    [ValidateRange(1, 24)][int]$SecretMonths = 12,
    [string]$ZoneUrl,
    [switch]$SkipConsent,
    [switch]$WhatIfOnly,
    # Install missing modules without prompting. Handy for unattended / bootstrap runs.
    [switch]$AutoInstallModules,
    # Where to install anything that's missing. AllUsers requires an elevated session.
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$ModuleScope = 'CurrentUser',
    # Remove Microsoft.Graph.* versions that do not match the pinned version, without
    # prompting. Mixed Graph SDK versions on disk are the #1 cause of Connect-MgGraph
    # failing with a MissingMethodException.
    [switch]$CleanConflictingModules,
    # ---------------------------------------------------------------- Post-create
    # After the app registration exists, optionally wire it into the product that will
    # consume it. Skipped entirely unless requested.
    # Right Click Tools: create the AzureActiveDirectory service connection in RMS.
    [switch]$ConfigureServiceConnection,
    # RMS server for -ConfigureServiceConnection, e.g. rms.contoso.com
    [string]$RmsServer,
    # RMS port. 444 is the default; dev installs often use 44339.
    [int]$RmsPort = 444,
    # RMS is very commonly installed with a self-signed certificate.
    [switch]$AllowSelfSignedCertificate,
    # Application Workspace: create the Entra ID identity source in the zone.
    # Requires the Application Workspace (Liquit) PowerShell module, already connected
    # to the target zone.
    [switch]$ConfigureIdentitySource,
    # Identity source Name. If hybrid-joined, match the NETBIOS / pre-Windows 2000 name.
    [string]$IdentitySourceName,
    # Friendly name end users see on the sign-in button, e.g. "Recast Software".
    [string]$IdentitySourceDisplayName,
    # Credentials for the Application Workspace zone API account (e.g. local\admin).
    # Prompted for if omitted when -ConfigureIdentitySource is used.
    [pscredential]$ZoneCredential,
    # Full path to Liquit.Server.PowerShell.dll for a local Application Workspace install
    # in a non-standard location. If no local DLL is found, the script offers to install
    # the Liquit.Server.PowerShell module from PSGallery instead.
    [string]$AwModulePath,
    # Application Workspace mail server, created only when the Mail.Send feature is
    # selected. Prompted for if omitted.
    [string]$MailServerName,
    # Sender address for the Graph mail server, e.g. noreply@contoso.com. Must be a real
    # mailbox the app registration is permitted to send as.
    [string]$MailServerFrom,
    # Accept an existing Microsoft Graph session instead of forcing a fresh sign-in.
    # By default the script prompts every run, because a cached MSAL token would
    # otherwise silently reuse whichever account authenticated last.
    [switch]$ReuseGraphSession,
    # Skip the "create in THIS tenant?" confirmation after sign-in. For unattended runs.
    [switch]$Force,
    # Bypass the Windows Web Account Manager (WAM) broker and sign in with a device code.
    # Use when the interactive sign-in hangs on "Just a moment..." or the broker window
    # opens behind the terminal.
    [switch]$UseDeviceCode,
    # --------------------------------------------- Existing app registration
    # Configure a product against an app registration that already exists, skipping
    # creation, permissions, and consent entirely. Nothing is written to the app.
    # Application (client) ID of the existing app registration.
    [string]$ExistingAppId,
    # Skip the read-only Graph lookup that confirms -ExistingAppId exists. Avoids a
    # sign-in, at the cost of not catching a mistyped GUID until the product rejects it.
    [switch]$SkipAppValidation,
    # Application Workspace identity source settings for -ExistingAppId runs, where there
    # is no feature catalog to derive them from. Prompted for unless -Force is used.
    [switch]$EnableAzurePhotos,
    [switch]$EnableGroupWrite,
    [switch]$ConfigureMailServer
)
#region ----------------------------------------------------------- Constants
$GraphAppId = '00000003-0000-0000-c000-000000000000'
$RequiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)
# Holds the original PSGallery InstallationPolicy when we temporarily flip it to Trusted,
# so the finally block can put the machine back exactly how it found it.
$script:RestorePSGalleryPolicy = $null
$ConnectScopes = @(
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All',
    'DelegatedPermissionGrant.ReadWrite.All',
    'Directory.ReadWrite.All'
)
# Product-specific defaults, aligned with the customer-facing onboarding guides.
$ProductDefaults = @{
    'Right Click Tools' = @{
        DisplayName      = 'Recast Software Right Click Tools'
        SecretDisplayName = 'Right Click Tools Client Secret'
    }
    'Application Workspace' = @{
        DisplayName      = 'Recast Software Application Workspace'
        SecretDisplayName = 'Application Workspace Client Secret'
    }
}
#endregion
#region ------------------------------------------------------ Feature catalog
# Application = app-only (app role, requires admin consent)
# Delegated   = on behalf of the signed-in user (oauth2 scope)
#
# Right Click Tools source:
#   https://docs.recastsoftware.com/help/right-click-tools-graph-api-permissions
# Application Workspace source:
#   Recast Software Application Workspace onboarding documentation
$Catalog = [ordered]@{
    'Right Click Tools' = [ordered]@{
        'RCT - Add Device(s) to Entra Security Group' = @{
            Application = @('Device.Read.All', 'Device.ReadWrite.All', 'Group.Read.All', 'Group.ReadWrite.All')
            Delegated   = @()
        }
        'RCT - Delete Device(s) from Intune / Entra' = @{
            Application = @('DeviceManagementManagedDevices.ReadWrite.All', 'Device.ReadWrite.All')
            Delegated   = @()
        }
        'RCT - Entra ID BitLocker Recovery Keys' = @{
            Application = @('Device.Read.All')
            Delegated   = @('User.Read',
                            'BitlockerKey.Read.All',
                            'BitlockerKey.ReadBasic.All',
                            'DeviceManagementConfiguration.Read.All',
                            'DeviceManagementManagedDevices.Read.All')
        }
        'RCT - Register Device(s) in Autopilot' = @{
            Application = @('DeviceManagementServiceConfig.ReadWrite.All')
            Delegated   = @()
        }
        'RCT - Retrieve LAPS Passwords from Entra ID' = @{
            Application = @('DeviceLocalCredential.Read.All')
            Delegated   = @()
        }
        'RCT Insights - Collect Intune warranty information' = @{
            Application = @('DeviceManagementManagedDevices.Read.All')
            Delegated   = @()
        }
        'RCT Privileged Access - All features' = @{
            Application = @('Device.Read.All',
                            'GroupMember.Read.All',
                            'User.Read.All')
            Delegated   = @()
        }
        'RCT Patching - All features' = @{
            # DeviceManagementConfiguration.Read.All is required to test an integration.
            # Device.Read.All is required to test the Entra ID service connection.
            Application = @('DeviceManagementApps.ReadWrite.All',
                            'GroupMember.Read.All',
                            'DeviceManagementConfiguration.Read.All',
                            'Device.Read.All')
            Delegated   = @()
        }
    }
    'Application Workspace' = [ordered]@{
        'AW - Entra ID identity source (REQUIRED)' = @{
            # User.Read delegated is the baseline sign-in scope. The Azure portal adds it
            # automatically to every new app registration, which is why it shows up in the
            # onboarding guide screenshots as "Microsoft Graph (5)". Creating an app via
            # the Graph API does not add it, so it is added explicitly here - without it,
            # SSO sign-in to Application Workspace is missing its baseline scope.
            Application = @('Directory.Read.All')
            Delegated   = @('User.Read')
            Mandatory   = $true
        }
        'AW - User profile photos (not for large tenants)' = @{
            # Syncs photos from Entra to Contacts in Application Workspace. The guide
            # explicitly warns this is slow on large tenants.
            Application = @('User.Read.All')
            Delegated   = @()
        }
        'AW - Group editing from within Workspace' = @{
            # Lets Application Workspace modify Entra groups, e.g. add a user or device to
            # a group when they install an application.
            Application = @('GroupMember.ReadWrite.All')
            Delegated   = @()
        }
        'AW - Email notifications sent via Graph' = @{
            # Recommended for cloud customers. The alternative is an SMTP server, and
            # Exchange Online Basic auth for SMTP client submission is being retired.
            Application = @('Mail.Send')
            Delegated   = @()
        }
        'AW Migration Utility - Intune as a data source' = @{
            Application = @('DeviceManagementApps.Read.All', 'DeviceManagementManagedDevices.Read.All')
            Delegated   = @()
        }
    }
}
#endregion
#region -------------------------------------------------------- Helper funcs
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}
function Write-Ok   { param([string]$m) Write-Host "    [ OK ] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "    [WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "    [FAIL] $m" -ForegroundColor Red }
function Test-IsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}
function Confirm-Action {
    <# Returns $true automatically when -AutoInstallModules or -CleanConflictingModules was passed. #>
    param([string]$Prompt)
    if ($script:AutoInstallModules -or $script:CleanConflictingModules) {
        Write-Host "    $Prompt -> yes (auto)" -ForegroundColor Gray
        return $true
    }
    return ((Read-Host "    $Prompt (Y/n)") -notmatch '^[Nn]')
}
function Initialize-PackageSource {
    <#
        PSGallery installs fail in predictable ways on a fresh box:
          1. PS 5.1 negotiating TLS 1.0 and getting refused
          2. The NuGet package provider missing
          3. PSGallery being untrusted or unregistered
          4. PowerShellGet 1.0.0.1 reporting failures as non-terminating errors
        Clear all four up front rather than letting Install-Module fail mysteriously.
    #>
    # 1. TLS 1.2 - only relevant on Windows PowerShell 5.1
    if ($PSVersionTable.PSEdition -ne 'Core') {
        try {
            if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
                [Net.ServicePointManager]::SecurityProtocol =
                    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                Write-Ok "Enabled TLS 1.2 for this session"
            }
        }
        catch { Write-Warn "Could not set TLS 1.2: $($_.Exception.Message)" }
    }
    # 2. NuGet provider
    $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
             Where-Object { $_.Version -ge [version]'2.8.5.201' }
    if (-not $nuget) {
        Write-Warn "NuGet package provider is missing or out of date."
        if (Confirm-Action "Install the NuGet provider now?") {
            try {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
                    -Scope $script:ModuleScope -Force -ErrorAction Stop | Out-Null
                Write-Ok "NuGet provider installed"
            }
            catch { throw "Failed to install the NuGet provider: $($_.Exception.Message)" }
        }
        else { throw "NuGet provider is required to install modules from PSGallery." }
    }
    # 3. PSGallery must exist and be trusted. Flip it for this run, then restore it.
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (-not $gallery) {
        Write-Warn "PSGallery is not registered. Re-registering with defaults."
        try   { Register-PSRepository -Default -ErrorAction Stop; $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue }
        catch { Write-Warn "Could not register PSGallery: $($_.Exception.Message)" }
    }
    if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        $script:RestorePSGalleryPolicy = $gallery.InstallationPolicy
        Write-Ok "PSGallery temporarily trusted for this run"
    }
    # 4. PowerShellGet 1.0.0.1 is the stock version on Windows PowerShell 5.1 and it is the
    #    single most common reason a Graph module install "succeeds" while installing
    #    nothing: it writes provider failures as NON-terminating errors, so -ErrorAction
    #    Stop never fires. Bootstrap it to 2.x before trying anything else.
    $psGet = Get-Module -ListAvailable -Refresh -Name PowerShellGet -ErrorAction SilentlyContinue |
             Sort-Object Version -Descending | Select-Object -First 1
    if ($psGet -and $psGet.Version -lt [version]'2.0.0') {
        Write-Warn "PowerShellGet $($psGet.Version) detected - too old to install the Graph SDK reliably."
        if (Confirm-Action "Bootstrap PowerShellGet 2.2.5 first? (strongly recommended)") {
            try {
                # Must run isolated: PowerShellGet is already loaded in this session.
                $hostExe = Get-PowerShellHostPath
                $boot = @"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
try { Get-PackageProvider -Name NuGet -ForceBootstrap -ErrorAction SilentlyContinue | Out-Null } catch { }
try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { }
Install-Module -Name PowerShellGet -RequiredVersion 2.2.5 -Scope $script:ModuleScope -Force -AllowClobber -ErrorAction SilentlyContinue
"@
                $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
                Start-Process -FilePath $hostExe `
                              -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc `
                              -Wait -NoNewWindow | Out-Null
                $after = Get-Module -ListAvailable -Refresh -Name PowerShellGet -ErrorAction SilentlyContinue |
                         Sort-Object Version -Descending | Select-Object -First 1
                if ($after -and $after.Version -ge [version]'2.0.0') {
                    Write-Ok "PowerShellGet $($after.Version) installed"
                    Write-Warn "PowerShellGet $($psGet.Version) is still loaded in THIS session."
                    Write-Warn "If the module install below fails, close PowerShell, reopen, and re-run."
                }
                else {
                    Write-Warn "PowerShellGet bootstrap did not take effect. Continuing anyway."
                }
            }
            catch { Write-Warn "PowerShellGet bootstrap failed: $($_.Exception.Message)" }
        }
    }
    elseif ($psGet) {
        Write-Ok "PowerShellGet $($psGet.Version)"
    }
}
function Get-ModuleSearchRoot {
    <#
        Every directory a module could plausibly live in.
        Get-Module -ListAvailable ONLY looks at $env:PSModulePath. If the user module root
        is missing from that variable - which happens with OneDrive-redirected Documents,
        GPO-managed PSModulePath, or a host that rewrites it - then a module can be fully
        installed and still be invisible to Get-Module.
        So: enumerate real directories, do not trust PSModulePath.
    #>
    $roots = New-Object System.Collections.Generic.List[string]
    if ($PSVersionTable.PSEdition -eq 'Core') { $leaf = 'PowerShell\Modules' }
    else                                      { $leaf = 'WindowsPowerShell\Modules' }
    # Documents, as the shell resolves it (honours OneDrive redirection)
    try {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if ($docs) { $roots.Add((Join-Path $docs $leaf)) }
    } catch { }
    # Literal profile paths, in case Documents is redirected and the other one is real.
    # Any OneDrive-style folder is enumerated rather than hardcoded, because the tenant
    # name is part of the folder name on synced profiles.
    if ($env:USERPROFILE) {
        $roots.Add((Join-Path $env:USERPROFILE "Documents\$leaf"))
        Get-ChildItem -Path $env:USERPROFILE -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue |
            ForEach-Object { $roots.Add((Join-Path $_.FullName "Documents\$leaf")) }
    }
    # Machine-wide
    if ($env:ProgramFiles) { $roots.Add((Join-Path $env:ProgramFiles $leaf)) }
    $roots.Add((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'))
    # Anything already on PSModulePath
    foreach ($p in ($env:PSModulePath -split ';')) {
        if ($p -and $p.Trim()) { $roots.Add($p.Trim()) }
    }
    return @($roots | Where-Object { $_ } | Select-Object -Unique |
             Where-Object { Test-Path $_ -ErrorAction SilentlyContinue })
}
function Get-ModuleVersionsOnDisk {
    <#
        Filesystem-based module discovery. Scans candidate roots directly for
        <Root>\<Name>\<Version>\<Name>.psd1 and also the flat <Root>\<Name>\<Name>.psd1
        layout, then falls back to Get-Module for anything in a non-standard location.
        Deliberately does NOT rely on Get-Module -ListAvailable as the primary source,
        because that only sees $env:PSModulePath. See Get-ModuleSearchRoot for why.
    #>
    param([string]$Name)
    $found = New-Object System.Collections.Generic.List[version]
    foreach ($root in (Get-ModuleSearchRoot)) {
        $moduleDir = Join-Path $root $Name
        if (-not (Test-Path $moduleDir)) { continue }
        # Versioned layout: <Name>\<Version>\<Name>.psd1
        Get-ChildItem -Path $moduleDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $v = $null
            if ([version]::TryParse($_.Name, [ref]$v)) {
                if (Test-Path (Join-Path $_.FullName "$Name.psd1")) {
                    if ($found -notcontains $v) { $found.Add($v) }
                }
            }
        }
        # Flat layout: <Name>\<Name>.psd1
        $flat = Join-Path $moduleDir "$Name.psd1"
        if (Test-Path $flat) {
            try {
                $mv = (Import-PowerShellDataFile -Path $flat -ErrorAction Stop).ModuleVersion
                $v = $null
                if ($mv -and [version]::TryParse($mv, [ref]$v) -and $found -notcontains $v) { $found.Add($v) }
            } catch { }
        }
    }
    # Safety net for modules installed somewhere unusual
    try {
        Get-Module -ListAvailable -Refresh -Name $Name -ErrorAction SilentlyContinue |
            ForEach-Object { if ($found -notcontains $_.Version) { $found.Add($_.Version) } }
    } catch { }
    return @($found)
}
function Get-ModuleManifestPath {
    <# Absolute path to a specific version's .psd1, so we can import without PSModulePath. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$Version
    )
    foreach ($root in (Get-ModuleSearchRoot)) {
        $candidate = Join-Path (Join-Path (Join-Path $root $Name) $Version.ToString()) "$Name.psd1"
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}
function Repair-PSModulePath {
    <#
        Adds any real module root that is missing from $env:PSModulePath, for this session.
        Without this, Import-Module -Name <x> fails even when the module is sitting on disk.
    #>
    $current = @($env:PSModulePath -split ';' | ForEach-Object { $_.TrimEnd('\') })
    $added   = @()
    foreach ($root in (Get-ModuleSearchRoot)) {
        if ($current -notcontains $root.TrimEnd('\')) {
            $env:PSModulePath = "$root;$env:PSModulePath"
            $added += $root
        }
    }
    if ($added) {
        Write-Ok "Added $($added.Count) missing path(s) to PSModulePath for this session"
        $added | ForEach-Object { Write-Host "           $_" -ForegroundColor DarkGray }
    }
}
function Get-PowerShellHostPath {
    <# Path to the host executable, used to spawn a clean child process. #>
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $c = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    $c = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}
function Get-ModuleInstallRoot {
    <# The directory Install-Module will write into for the current scope. #>
    param([string]$Scope = $script:ModuleScope)
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $userRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
        $allRoot  = Join-Path $env:ProgramFiles 'PowerShell\Modules'
    }
    else {
        $userRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
        $allRoot  = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
    }
    if ($Scope -eq 'AllUsers') { return $allRoot }
    return $userRoot
}
function Write-InstallDiagnostics {
    <# Dumped only on failure, so the operator does not have to guess. #>
    param([string]$Name)
    Write-Host ""
    Write-Host "    --- install diagnostics -------------------------------------" -ForegroundColor DarkGray
    Write-Host "     Module           : $Name" -ForegroundColor DarkGray
    Write-Host "     Scope            : $script:ModuleScope" -ForegroundColor DarkGray
    Write-Host "     Install root     : $(Get-ModuleInstallRoot)" -ForegroundColor DarkGray
    foreach ($dep in 'PowerShellGet', 'PackageManagement') {
        $v = (Get-Module -ListAvailable -Refresh -Name $dep -ErrorAction SilentlyContinue |
              Sort-Object Version -Descending | Select-Object -First 1).Version
        Write-Host "     $($dep.PadRight(17)): $(if($v){$v}else{'not found'})" -ForegroundColor DarkGray
    }
    $nuget = (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
              Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-Host "     NuGet provider   : $(if($nuget){$nuget}else{'not found'})" -ForegroundColor DarkGray
    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    Write-Host "     PSGallery        : $(if($repo){"$($repo.InstallationPolicy) | $($repo.SourceLocation)"}else{'not registered'})" -ForegroundColor DarkGray
    # Where we looked, and whether the module is physically there.
    Write-Host "     Module roots searched:" -ForegroundColor DarkGray
    foreach ($root in (Get-ModuleSearchRoot)) {
        $dir = Join-Path $root $Name
        $mark = if (Test-Path $dir) { 'FOUND   ' } else { 'absent  ' }
        Write-Host "       $mark $root" -ForegroundColor DarkGray
    }
    Write-Host "     PSModulePath entries:" -ForegroundColor DarkGray
    foreach ($p in ($env:PSModulePath -split ';' | Where-Object { $_ -and $_.Trim() })) {
        Write-Host "       $p" -ForegroundColor DarkGray
    }
    Write-Host "    --------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}
function Test-ModulePresent {
    <# True when the module (optionally an exact version) is on disk right now. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$RequiredVersion
    )
    $onDisk = Get-ModuleVersionsOnDisk -Name $Name
    if ($RequiredVersion) { return ($onDisk -contains $RequiredVersion) }
    return ($onDisk.Count -gt 0)
}
function Install-ModuleInProcess {
    <#
        Plain in-process install. Safe when the module is NOT already imported, and it
        surfaces the real error text instead of hiding it in a child process.
        Returns $true only after confirming the bits landed on disk.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$RequiredVersion
    )
    if (Get-Module -Name $Name) { return $false }   # loaded = locked, caller falls through
    $params = @{
        Name         = $Name
        Scope        = $script:ModuleScope
        Repository   = 'PSGallery'
        Force        = $true
        AllowClobber = $true
        ErrorAction  = 'Stop'
    }
    if ($RequiredVersion) { $params['RequiredVersion'] = $RequiredVersion }
    try   { Install-Module @params }
    catch { Write-Host "      in-process install failed: $($_.Exception.Message)" -ForegroundColor DarkGray }
    return (Test-ModulePresent -Name $Name -RequiredVersion $RequiredVersion)
}
function Install-ModuleChildProcess {
    <#
        Runs the install in a clean child process. Needed when the target module's DLLs are
        already loaded and therefore locked in this session.
        The child verifies on disk before exiting, because PowerShellGet 1.0.0.1 writes
        provider errors as non-terminating and -ErrorAction Stop never fires. The exit
        code alone is not sufficient evidence that an install succeeded.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$RequiredVersion
    )
    $hostExe = Get-PowerShellHostPath
    $stdOut  = Join-Path ([IO.Path]::GetTempPath()) "recast_mod_out_$PID.txt"
    $stdErr  = Join-Path ([IO.Path]::GetTempPath()) "recast_mod_err_$PID.txt"
    # Single-quoted here-string: no interpolation, no escaping traps. Tokens swapped after.
    $template = @'
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
try { Get-PackageProvider -Name NuGet -ForceBootstrap -ErrorAction SilentlyContinue | Out-Null } catch { }
try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { }
$name  = '__NAME__'
$scope = '__SCOPE__'
$ver   = '__VERSION__'
$params = @{ Name = $name; Scope = $scope; Repository = 'PSGallery'; Force = $true; AllowClobber = $true; ErrorAction = 'Stop' }
if ($ver) { $params['RequiredVersion'] = $ver }
try { Install-Module @params }
catch { Write-Output ('CHILD_ERROR: ' + $_.Exception.Message) }
$found = @(Get-Module -ListAvailable -Refresh -Name $name -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty Version -Unique)
if ($ver) {
    if ($found -contains [version]$ver) { Write-Output 'CHILD_OK'; exit 0 }
}
elseif ($found.Count -gt 0) { Write-Output 'CHILD_OK'; exit 0 }
Write-Output ('CHILD_FAIL: on disk = ' + (($found | Sort-Object -Descending) -join ', '))
exit 2
'@
    $childScript = $template.Replace('__NAME__',    $Name).
                             Replace('__SCOPE__',   $script:ModuleScope).
                             Replace('__VERSION__', $(if ($RequiredVersion) { "$RequiredVersion" } else { '' }))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    try {
        $null = Start-Process -FilePath $hostExe `
                              -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded `
                              -Wait -NoNewWindow `
                              -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr -ErrorAction Stop
    }
    catch {
        Write-Host "      could not start child process: $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }
    # Echo whatever the child actually said.
    foreach ($f in @($stdOut, $stdErr)) {
        if (Test-Path $f) {
            Get-Content $f -ErrorAction SilentlyContinue |
                Where-Object { $_ -and $_.Trim() } |
                Select-Object -First 12 |
                ForEach-Object { Write-Host "      child: $_" -ForegroundColor DarkGray }
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    return (Test-ModulePresent -Name $Name -RequiredVersion $RequiredVersion)
}
function Install-ModuleViaSaveModule {
    <#
        Last resort. Save-Module downloads to a folder without the install-path machinery,
        then we copy the payload into the module root ourselves.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$RequiredVersion
    )
    $staging = Join-Path ([IO.Path]::GetTempPath()) "recast_save_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $root    = Get-ModuleInstallRoot
    try {
        New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop | Out-Null
        $saveParams = @{ Name = $Name; Path = $staging; Repository = 'PSGallery'; Force = $true; ErrorAction = 'Stop' }
        if ($RequiredVersion) { $saveParams['RequiredVersion'] = $RequiredVersion }
        Write-Host "      trying Save-Module into staging ..." -ForegroundColor DarkGray
        Save-Module @saveParams
        if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null }
        Get-ChildItem -Path $staging -Directory -ErrorAction Stop | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $root -Recurse -Force -ErrorAction Stop
        }
        Write-Host "      copied into $root" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "      Save-Module fallback failed: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
    finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
    return (Test-ModulePresent -Name $Name -RequiredVersion $RequiredVersion)
}
function Install-RecastModule {
    <#
        Layered installer. Tries the cheapest approach that can work, verifies on disk after
        every attempt, and only reports success when the bits are actually there.
          1. in-process      - skipped if the module is already loaded/locked
          2. child process   - clean session, nothing locked
          3. Save-Module     - manual download and copy
        Returns $true/$false. Never throws on a failed attempt; the caller decides.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$RequiredVersion
    )
    $label = if ($RequiredVersion) { "$Name $RequiredVersion" } else { $Name }
    if (Test-ModulePresent -Name $Name -RequiredVersion $RequiredVersion) {
        Write-Ok "$label already present on disk"
        return $true
    }
    Write-Host "    Installing $label ..." -ForegroundColor Gray
    $attempts = [ordered]@{
        'in-process'    = { Install-ModuleInProcess     -Name $Name -RequiredVersion $RequiredVersion }
        'clean process' = { Install-ModuleChildProcess  -Name $Name -RequiredVersion $RequiredVersion }
        'Save-Module'   = { Install-ModuleViaSaveModule -Name $Name -RequiredVersion $RequiredVersion }
    }
    foreach ($method in $attempts.Keys) {
        Write-Host "      attempt: $method" -ForegroundColor DarkGray
        if (& $attempts[$method]) {
            $actual = (Get-ModuleVersionsOnDisk -Name $Name | Sort-Object -Descending | Select-Object -First 1)
            Write-Ok "$Name $actual installed and verified on disk (via $method)"
            return $true
        }
    }
    Write-Err "Every install method failed for $label."
    Write-InstallDiagnostics -Name $Name
    $versionArg = ''
    if ($RequiredVersion) { $versionArg = "-RequiredVersion $RequiredVersion " }
    Write-Host "           Try manually in a NEW PowerShell window:" -ForegroundColor Gray
    Write-Host "             Install-Module $Name $versionArg-Scope $script:ModuleScope -Force -Verbose" -ForegroundColor Gray
    return $false
}
function Get-LoadedGraphAssembly {
    <#
        Every Microsoft.Graph* assembly .NET has already bound into this AppDomain.
        This is the authoritative check for whether a session is salvageable. Assemblies
        cannot be unloaded, so if the wrong version is already bound, no amount of disk
        cleanup or module re-import will fix THIS session.
    #>
    try {
        return @([AppDomain]::CurrentDomain.GetAssemblies() |
                 Where-Object { $_.FullName -like 'Microsoft.Graph*' -and $_.Location })
    }
    catch { return @() }
}
function Get-AssemblyVersionFromPath {
    <#
        Pulls the version out of a module path like ...\Microsoft.Graph.Authentication\2.27.0\x.dll
        More reliable than the assembly's own FullName version, which the Graph SDK does not
        always keep in step with the module version.
    #>
    param([string]$Path)
    if ($Path -match '\\(\d+\.\d+\.\d+(\.\d+)?)\\') { return $matches[1] }
    return $null
}
function Test-SessionGraphBinding {
    <#
        Runs EARLY, before any cleanup work. Reports which Graph versions are already bound
        in this session so we can fail fast instead of doing a long cleanup pass and only
        then discovering the session was unusable from the start.
        Returns the distinct set of already-bound version strings (empty = clean session).
    #>
    $loaded = Get-LoadedGraphAssembly
    if ($loaded.Count -eq 0) {
        Write-Ok "No Graph assemblies bound in this session (clean start)"
        return @()
    }
    $versions = @($loaded | ForEach-Object { Get-AssemblyVersionFromPath -Path $_.Location } |
                  Where-Object { $_ } | Select-Object -Unique)
    Write-Warn "Graph assemblies are ALREADY bound in this session:"
    $loaded | Select-Object -First 6 | ForEach-Object {
        Write-Host "           $($_.Location)" -ForegroundColor DarkGray
    }
    if ($loaded.Count -gt 6) {
        Write-Host "           ... and $($loaded.Count - 6) more" -ForegroundColor DarkGray
    }
    return $versions
}
function Get-GraphModuleSprawl {
    <#
        Enumerates EVERY Microsoft.Graph.* module version sitting in any module root.
        This matters because the Graph SDK submodules share assemblies
        (Microsoft.Graph.Authentication.Core.dll and friends). When two versions exist on
        disk, .NET can bind the wrong one into the shared Assembly Load Context and you get
        a MissingMethodException like:
            Method 'GetTokenAsync' in type '...UserProvidedTokenCredential' from assembly
            'Microsoft.Graph.Authentication.Core, Version=2.40.0.0' does not have an
            implementation.
        Returns one object per Name+Version+Path found.
    #>
    $found = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($root in (Get-ModuleSearchRoot)) {
        Get-ChildItem -Path $root -Directory -Filter 'Microsoft.Graph*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $modName = $_.Name
            $modDir  = $_.FullName
            Get-ChildItem -Path $modDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $v = $null
                if ([version]::TryParse($_.Name, [ref]$v)) {
                    if (Test-Path (Join-Path $_.FullName "$modName.psd1")) {
                        $found.Add([pscustomobject]@{
                            Name    = $modName
                            Version = $v
                            Path    = $_.FullName
                            Root    = $root
                        })
                    }
                }
            }
        }
    }
    return @($found)
}
function Remove-ConflictingModuleVersion {
    <#
        Removes Microsoft.Graph.* versions that do not match the pinned version.
        Uninstall-Module is tried first; if that fails (common when the module was placed by
        Save-Module rather than Install-Module, so PowerShellGet has no install record) the
        directory is deleted outright. Program Files entries are skipped without elevation.
    #>
    param(
        [Parameter(Mandatory)][version]$KeepVersion,
        [Parameter(Mandatory)][array]$Sprawl
    )
    $elevated = Test-IsElevated
    $removed  = 0
    $skipped  = 0
    $locked   = New-Object System.Collections.Generic.List[string]
    foreach ($item in ($Sprawl | Where-Object { $_.Version -ne $KeepVersion })) {
        $needsAdmin = $item.Path -like "$env:ProgramFiles*" -or $item.Path -like "$env:SystemRoot*"
        if ($needsAdmin -and -not $elevated) {
            Write-Warn "Skipped (needs elevation): $($item.Name) $($item.Version)"
            Write-Host "           $($item.Path)" -ForegroundColor DarkGray
            $skipped++
            continue
        }
        $ok = $false
        try {
            Uninstall-Module -Name $item.Name -RequiredVersion $item.Version -Force -ErrorAction Stop
            $ok = -not (Test-Path $item.Path)
        }
        catch { $ok = $false }
        if (-not $ok) {
            try {
                Remove-Item -Path $item.Path -Recurse -Force -ErrorAction Stop
                $ok = -not (Test-Path $item.Path)
            }
            catch {
                # "Access to the path 'x.dll' is denied" means the DLL is loaded in this
                # process. That is a restart problem, not a permissions problem.
                if ($_.Exception.Message -match 'is denied|being used by another process') {
                    $locked.Add("$($item.Name) $($item.Version)")
                }
                Write-Warn "Could not remove $($item.Name) $($item.Version): $($_.Exception.Message)"
            }
        }
        if ($ok) {
            Write-Ok "Removed $($item.Name) $($item.Version)"
            $removed++
        }
        else {
            $skipped++
        }
    }
    if ($skipped -gt 0 -and -not $elevated) {
        Write-Warn "$skipped item(s) need an elevated PowerShell session to remove."
    }
    if ($locked.Count -gt 0) {
        Write-Warn "$($locked.Count) item(s) are LOADED in this process and cannot be deleted:"
        $locked | ForEach-Object { Write-Host "           $_" -ForegroundColor DarkGray }
        Write-Warn "Close this PowerShell window and re-run to finish removing them."
    }
    return $removed
}
function Resolve-GraphModuleConflict {
    <#
        Detects Graph SDK version sprawl and offers to clean it up, keeping only $KeepVersion.
        Called after the pin is decided but BEFORE anything is imported.
    #>
    param([Parameter(Mandatory)][version]$KeepVersion)
    $sprawl = Get-GraphModuleSprawl
    if ($sprawl.Count -eq 0) { return }
    $conflicts = @($sprawl | Where-Object { $_.Version -ne $KeepVersion })
    if ($conflicts.Count -eq 0) {
        Write-Ok "No conflicting Graph module versions on disk"
        return
    }
    Write-Warn "Found $($conflicts.Count) Graph module version(s) that do not match the pinned $KeepVersion :"
    # Long lists are noise. Summarise by version, then show paths only for short lists.
    $byVersion = $conflicts | Group-Object Version | Sort-Object Name
    foreach ($g in $byVersion) {
        Write-Host ("           {0,-10} {1} module(s)" -f $g.Name, $g.Count) -ForegroundColor Gray
    }
    if ($conflicts.Count -le 12) {
        foreach ($c in ($conflicts | Sort-Object Name, Version)) {
            Write-Host ("             {0,-42} {1,-10} {2}" -f $c.Name, $c.Version, $c.Root) -ForegroundColor DarkGray
        }
    }
    Write-Warn "Mixed Graph SDK versions on disk cause assembly-binding failures at Connect-MgGraph."
    if (-not (Confirm-Action "Remove the non-matching versions and keep only $KeepVersion ?")) {
        Write-Warn "Leaving them in place. Connect-MgGraph may fail with a MissingMethodException."
        return
    }
    $n = Remove-ConflictingModuleVersion -KeepVersion $KeepVersion -Sprawl $sprawl
    Write-Ok "Cleanup complete - $n version(s) removed"
}
function Test-GraphAssemblyHealth {
    <#
        Post-import safety net. Confirms every loaded Microsoft.Graph* assembly actually came
        from the pinned version's folder.
    #>
    param([Parameter(Mandatory)][version]$ExpectedVersion)
    $bad = @()
    try {
        $bad = @(Get-LoadedGraphAssembly |
                 Where-Object { $_.Location -notmatch [regex]::Escape("\$ExpectedVersion\") })
    }
    catch { return $true }
    if ($bad.Count -eq 0) { return $true }
    Write-Warn "These Graph assemblies are loaded from a version other than $ExpectedVersion :"
    $bad | Select-Object -First 8 | ForEach-Object {
        Write-Host "           $($_.Location)" -ForegroundColor Gray
    }
    Write-Warn "This session is already bound to mismatched assemblies."
    Write-Warn "Close PowerShell, open a NEW window, and re-run - the disk cleanup persists."
    return $false
}
function Write-GraphConflictRemediation {
    <# Printed when Connect-MgGraph dies from an assembly binding failure. #>
    param([string]$ErrorMessage)
    Write-Host ""
    Write-Err "Microsoft Graph failed to load its assemblies correctly."
    Write-Host ""
    Write-Host "    This is the classic Graph SDK version-conflict error. It means two different" -ForegroundColor Yellow
    Write-Host "    versions of the Graph modules are visible to .NET in the same session." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    To fix it:" -ForegroundColor White
    Write-Host "      1. Close ALL PowerShell windows, including the VS Code terminal." -ForegroundColor Gray
    Write-Host "      2. Open a new standalone PowerShell window, elevated." -ForegroundColor Gray
    Write-Host "      3. Re-run this script with -CleanConflictingModules." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    To inspect manually:" -ForegroundColor White
    Write-Host "      Get-Module Microsoft.Graph* -ListAvailable | Select Name,Version,ModuleBase" -ForegroundColor DarkGray
    Write-Host ""
    if ($ErrorMessage) {
        Write-Host "    Original error:" -ForegroundColor DarkGray
        Write-Host "      $ErrorMessage" -ForegroundColor DarkGray
        Write-Host ""
    }
}
function Clear-GraphTokenCache {
    <#
        Removes ONLY the Microsoft Graph SDK's own token cache.
        DO NOT add %LOCALAPPDATA%\.IdentityService here. That is the SHARED Web Account
        Manager (WAM) broker store used by Office, Azure CLI, Teams, and Windows itself.
        Removing it while the broker is in use can leave WAM in a bad state - the sign-in dialog
        hangs on "Just a moment..." and never returns, which can take the host process
        down with it.
        Forcing a specific account does not require clearing the shared broker cache.
        Disconnect-MgGraph plus -ContextScope Process handles session reuse, and
        -UseDeviceAuthentication bypasses the broker entirely when an explicit account
        choice is needed.
    #>
    [CmdletBinding()]
    param()
    $path = Join-Path $env:USERPROFILE '.graph'
    if (-not (Test-Path $path -ErrorAction SilentlyContinue)) { return }
    try {
        Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
        Write-Verbose "Cleared Graph SDK token cache: $path"
    }
    catch {
        # Locked by another connected session. Not fatal - disconnect plus
        # -ContextScope Process still prevent reuse within this run.
        Write-Verbose "Could not clear $path : $($_.Exception.Message)"
    }
}
function Connect-GraphForced {
    <#
        Connects to Microsoft Graph, prompting for credentials EVERY time by default.
        Layers, because no single one is reliable on its own:
          1. Disconnect any context already live in this session
          2. Clear the Graph SDK's OWN token cache (never the shared WAM broker store)
          3. Connect with -ContextScope Process so this token is not persisted either
          4. Optionally bypass the WAM broker entirely with device code auth
        Pass -ReuseExisting to skip all of that and accept a cached session, which is what
        you want for unattended runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Scopes,
        [string]$TenantId,
        [switch]$ReuseExisting,
        # Bypass the Windows Web Account Manager broker and authenticate with a device
        # code instead. Use this when the interactive sign-in hangs on "Just a moment..."
        # or when the broker window appears behind the terminal.
        [switch]$UseDeviceCode
    )
    Write-Step "Connecting to Microsoft Graph"
    if ($ReuseExisting) {
        $existing = $null
        try { $existing = Get-MgContext -ErrorAction SilentlyContinue } catch { }
        if ($existing -and $existing.Account) {
            Write-Warn "Reusing the existing Graph session (-ReuseGraphSession)."
            Write-Host "           Account : $($existing.Account)" -ForegroundColor Gray
            Write-Host "           Tenant  : $($existing.TenantId)" -ForegroundColor Gray
            return $existing
        }
        Write-Host "    No existing session to reuse - signing in." -ForegroundColor Gray
    }
    else {
        # 1. Drop anything already connected in this session.
        try {
            if (Get-MgContext -ErrorAction SilentlyContinue) {
                Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            }
        }
        catch { }
        # 2. Remove the cached tokens so the account picker actually appears.
        Clear-GraphTokenCache
        Write-Host "    You will be prompted to sign in." -ForegroundColor Gray
        Write-Host "    Use the account that administers the TARGET tenant - it does not have" -ForegroundColor Gray
        Write-Host "    to match the account you are signed into Windows with." -ForegroundColor Gray
    }
    $connectParams = @{
        Scopes      = $Scopes
        NoWelcome   = $true
        ErrorAction = 'Stop'
    }
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }
    $connectCmd = Get-Command Connect-MgGraph -ErrorAction SilentlyContinue
    # 3. Keep the token in this process only, so the next run prompts again. Checked
    #    rather than assumed, because older SDK builds do not expose the parameter.
    if (-not $ReuseExisting) {
        if ($connectCmd -and $connectCmd.Parameters.ContainsKey('ContextScope')) {
            $connectParams['ContextScope'] = 'Process'
        }
    }
    # 4. Optionally bypass the Web Account Manager broker.
    #
    #    WAM is enabled by default on Windows and is the usual cause of a sign-in that
    #    hangs on "Just a moment...". It is also the reason the dialog can appear behind
    #    the terminal window. Device code auth talks to Entra directly - no broker, no
    #    hidden window, and it always lets you choose the account.
    if ($UseDeviceCode) {
        if ($connectCmd -and $connectCmd.Parameters.ContainsKey('UseDeviceAuthentication')) {
            $connectParams['UseDeviceAuthentication'] = $true
            Write-Host ""
            Write-Host "    Device code sign-in: open the URL shown below and enter the code." -ForegroundColor Cyan
        }
        else {
            Write-Warn "-UseDeviceCode requested, but this SDK build has no -UseDeviceAuthentication."
        }
    }
    else {
        Write-Host "    If the sign-in window hangs on 'Just a moment...', close it and re-run" -ForegroundColor DarkGray
        Write-Host "    with -UseDeviceCode to bypass the Windows broker." -ForegroundColor DarkGray
    }
    try {
        Connect-MgGraph @connectParams
    }
    catch {
        $msg = $_.Exception.Message
        # Assembly binding failures surface as MissingMethodException / TypeLoadException,
        # or as the literal "does not have an implementation" text. Anything else is a
        # genuine auth/tenant problem and should bubble up unchanged.
        if ($msg -match 'does not have an implementation' -or
            $msg -match 'Could not load file or assembly' -or
            $msg -match "manifest definition does not match" -or
            $_.Exception -is [System.MissingMethodException] -or
            $_.Exception -is [System.TypeLoadException]) {
            Write-GraphConflictRemediation -ErrorMessage $msg
            throw "Graph SDK assembly conflict - see remediation steps above."
        }
        throw
    }
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx -or -not $ctx.Account) {
        throw "Connect-MgGraph returned without an authenticated context."
    }
    return $ctx
}
function Test-HostIsolation {
    <#
        The VS Code PowerShell Integrated Console preloads its own modules and keeps a
        long-lived session, which makes assembly conflicts far more likely and impossible to
        clear without restarting the console. Warn, but do not block.
    #>
    if ($Host.Name -match 'Visual Studio Code') {
        Write-Warn "Running inside the VS Code PowerShell Integrated Console."
        Write-Host "           This host preloads modules and keeps assemblies loaded between runs." -ForegroundColor Gray
        Write-Host "           For Graph work, a standalone PowerShell window is strongly preferred." -ForegroundColor Gray
    }
}
function Resolve-TargetModuleVersion {
    <#
        Decides ONE version that every required Graph module will be pinned to.
        The constraint that dominates everything else: a module already imported into this
        session cannot be unloaded. If Authentication 2.27.0 is loaded, the target MUST be
        2.27.0 - installing 2.40.0 of everything else would just guarantee an assembly
        conflict at Connect-MgGraph. So loaded versions win over "newest available".
    #>
    param([string[]]$Modules)
    # --- What is already loaded in this session? ----------------------------
    $loaded = @(Get-Module -Name $Modules | Select-Object Name, Version)
    if ($loaded.Count -gt 0) {
        $loadedVersions = @($loaded | Select-Object -ExpandProperty Version -Unique)
        if ($loadedVersions.Count -gt 1) {
            Write-Err "Conflicting Graph module versions are ALREADY loaded in this session:"
            $loaded | ForEach-Object { Write-Host "           $($_.Name) $($_.Version)" -ForegroundColor Red }
            Write-Warn "PowerShell cannot unload assemblies. This session cannot be repaired."
            throw "Close this PowerShell session, open a new one, and re-run the script."
        }
        $target = $loadedVersions[0]
        Write-Ok "Pinning to $target (already loaded in this session)"
        return $target
    }
    # --- Nothing loaded: pick the newest version common to all modules ------
    $versionSets = @{}
    foreach ($m in $Modules) { $versionSets[$m] = Get-ModuleVersionsOnDisk -Name $m }
    $common = $versionSets[$Modules[0]]
    foreach ($m in $Modules) {
        $common = @($common | Where-Object { $versionSets[$m] -contains $_ })
    }
    if ($common.Count -gt 0) {
        $target = ($common | Sort-Object -Descending | Select-Object -First 1)
        Write-Ok "Pinning to $target (common to all required modules)"
        return $target
    }
    # --- No common version: align by installing the newest across the board -
    Write-Warn "No single version is common to all required Graph modules:"
    foreach ($m in $Modules) {
        $list = if ($versionSets[$m].Count) { ($versionSets[$m] | Sort-Object -Descending) -join ', ' } else { '(none installed)' }
        Write-Host ("           {0,-38} {1}" -f $m, $list) -ForegroundColor Gray
    }
    Write-Warn "Mismatched Graph SDK versions cause assembly-load errors at Connect-MgGraph."
    $target = @($versionSets.Values | ForEach-Object { $_ } | Sort-Object -Descending | Select-Object -First 1)[0]
    if (-not $target) { throw "No versions of the required Graph modules are installed." }
    if (-not (Confirm-Action "Install version $target of every required module to align them?")) {
        throw "Cannot continue with mismatched Graph SDK versions."
    }
    Initialize-PackageSource
    foreach ($m in $Modules) {
        if ($versionSets[$m] -notcontains $target) {
            if (-not (Install-RecastModule -Name $m -RequiredVersion $target)) {
                throw "Could not align $m to $target."
            }
        }
    }
    Write-Ok "All modules aligned to $target"
    return $target
}
function Test-Prerequisites {
    Write-Step "Checking prerequisites"
    # --- PowerShell version -------------------------------------------------
    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        throw "PowerShell 5.1 or later is required. Detected $($PSVersionTable.PSVersion)."
    }
    Write-Ok "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    # --- Scope sanity before anything gets installed ------------------------
    if ($script:ModuleScope -eq 'AllUsers' -and -not (Test-IsElevated)) {
        Write-Warn "AllUsers scope needs an elevated session. Falling back to CurrentUser."
        $script:ModuleScope = 'CurrentUser'
    }
    # --- Host warning -------------------------------------------------------
    Test-HostIsolation
    # --- Are conflicting assemblies already bound? --------------------------
    # Checked before any install or cleanup work. Assemblies cannot be unloaded, so
    # if the wrong version is already bound there is no point doing anything else.
    $preBound = Test-SessionGraphBinding
    # --- Make sure the module roots are actually searchable -----------------
    Repair-PSModulePath
    # --- Install anything missing -------------------------------------------
    foreach ($m in $RequiredModules) {
        if ((Get-ModuleVersionsOnDisk -Name $m).Count -eq 0) {
            Write-Warn "Module '$m' is not installed."
            if (-not (Confirm-Action "Install $m from PSGallery ($script:ModuleScope scope)?")) {
                throw "Missing required module: $m"
            }
            Initialize-PackageSource
            if (-not (Install-RecastModule -Name $m)) {
                throw "Could not install required module: $m"
            }
        }
    }
    # --- Decide the single version everything gets pinned to ----------------
    $pin = Resolve-TargetModuleVersion -Modules $RequiredModules
    # --- Fail fast if the session is bound to something other than the pin --
    if ($pin -and $preBound.Count -gt 0) {
        $mismatch = @($preBound | Where-Object { $_ -ne $pin.ToString() })
        if ($mismatch.Count -gt 0) {
            Write-Host ""
            Write-Err "This session already has Graph $($mismatch -join ', ') bound, but $pin is required."
            Write-Warn "PowerShell cannot unload assemblies, so this session cannot be repaired."
            Write-Host ""
            Write-Host "    Close this window, open a NEW elevated PowerShell window, and run:" -ForegroundColor White
            Write-Host "      .\New-RecastEntraAppRegistration.ps1 -CleanConflictingModules" -ForegroundColor Cyan
            Write-Host ""
            throw "Session bound to Graph $($mismatch -join ', '); restart PowerShell and re-run."
        }
    }
    # --- Clear Graph SDK version sprawl before importing anything -----------
    if ($pin) { Resolve-GraphModuleConflict -KeepVersion $pin }
    # --- Make sure that version is actually present for every module --------
    foreach ($m in $RequiredModules) {
        if ((Get-ModuleVersionsOnDisk -Name $m) -notcontains $pin) {
            Write-Warn "$m $pin is not on disk yet."
            Initialize-PackageSource
            if (-not (Install-RecastModule -Name $m -RequiredVersion $pin)) {
                throw "Required module $m $pin could not be installed."
            }
        }
    }
    # --- Import at the pinned version ---------------------------------------
    foreach ($m in $RequiredModules) {
        $already = Get-Module -Name $m
        if ($already) {
            if ($already.Version -eq $pin) { Write-Ok "$m $($already.Version) already loaded"; continue }
            throw "$m $($already.Version) is loaded but $pin is required. Restart PowerShell and re-run."
        }
        # Import by absolute manifest path when we can find it. Importing by name depends
        # on PSModulePath resolution, which has proven unreliable.
        $manifest = Get-ModuleManifestPath -Name $m -Version $pin
        try {
            if ($manifest) {
                Import-Module -Name $manifest -ErrorAction Stop
                Write-Ok "$m $pin loaded"
                Write-Host "           $manifest" -ForegroundColor DarkGray
            }
            else {
                Import-Module -Name $m -RequiredVersion $pin -ErrorAction Stop
                Write-Ok "$m $pin loaded"
            }
        }
        catch {
            Write-Err "Could not import $m : $($_.Exception.Message)"
            if ($_.Exception.Message -match 'does not have an implementation|Could not load file or assembly') {
                Write-Warn "That is an assembly-binding failure, not a missing module."
                Write-Warn "Close PowerShell, open a NEW window, and re-run."
            }
            throw "Module import failed: $m"
        }
    }
    # --- Confirm .NET actually bound the pinned assemblies ------------------
    if ($pin) {
        if (-not (Test-GraphAssemblyHealth -ExpectedVersion $pin)) {
            throw "Mismatched Graph assemblies are loaded. Restart PowerShell and re-run."
        }
    }
}
function Select-Product {
    Write-Step "Which Recast product is this app registration for?"
    $names = @($Catalog.Keys)
    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $names[$i])
    }
    do {
        $choice = Read-Host "`n    Select 1-$($names.Count)"
    } until ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $names.Count)
    return $names[[int]$choice - 1]
}
function Select-Features {
    param([string]$Product)
    $features   = $Catalog[$Product]
    $names      = @($features.Keys)
    $mandatory  = @($names | Where-Object { $features[$_].Mandatory })
    Write-Step "Select the $Product features this app registration needs to support"
    Write-Host "    Enter numbers separated by commas (e.g. 1,3,4), 'A' for all, or 'Q' to quit." -ForegroundColor Gray
    Write-Host ""
    for ($i = 0; $i -lt $names.Count; $i++) {
        $tag = if ($features[$names[$i]].Mandatory) { ' *always included*' } else { '' }
        Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $names[$i], $tag)
    }
    do {
        $raw = (Read-Host "`n    Selection").Trim()
        if ($raw -match '^[Qq]$') { throw "Cancelled by operator." }
        if ($raw -match '^[Aa]$') {
            $selected = $names
            break
        }
        $picked = $raw -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } |
                  ForEach-Object { [int]$_ } |
                  Where-Object { $_ -ge 1 -and $_ -le $names.Count } |
                  Select-Object -Unique
        if ($picked) { $selected = @($picked | ForEach-Object { $names[$_ - 1] }) }
        else { Write-Warn "No valid selection - try again." }
    } until ($selected)
    # Force in anything flagged mandatory for the product
    $selected = @($selected + $mandatory | Select-Object -Unique)
    Write-Host ""
    Write-Ok "$($selected.Count) feature(s) selected"
    $selected | ForEach-Object { Write-Host "         - $_" -ForegroundColor Gray }
    return $selected
}
function Get-PermissionSet {
    param(
        [string]$Product,
        [string[]]$Features
    )
    $app = New-Object System.Collections.Generic.List[string]
    $del = New-Object System.Collections.Generic.List[string]
    foreach ($f in $Features) {
        foreach ($p in $Catalog[$Product][$f].Application) { if ($app -notcontains $p) { $app.Add($p) } }
        foreach ($p in $Catalog[$Product][$f].Delegated)   { if ($del -notcontains $p) { $del.Add($p) } }
    }
    return [pscustomobject]@{
        Application = @($app | Sort-Object)
        Delegated   = @($del | Sort-Object)
    }
}
function Resolve-GraphPermissions {
    <#
        Turns permission NAMES into the GUIDs this tenant actually uses, by reading them
        off the Microsoft Graph service principal. Fails loudly on anything it can't find
        instead of silently creating an app registration with missing permissions.
    #>
    param(
        [Parameter(Mandatory)] $GraphSp,
        [string[]]$ApplicationPermissions,
        [string[]]$DelegatedPermissions
    )
    $resourceAccess = New-Object System.Collections.Generic.List[hashtable]
    $resolvedApp    = New-Object System.Collections.Generic.List[pscustomobject]
    $resolvedDel    = New-Object System.Collections.Generic.List[pscustomobject]
    $unresolved     = New-Object System.Collections.Generic.List[string]
    foreach ($name in $ApplicationPermissions) {
        $role = $GraphSp.AppRoles | Where-Object { $_.Value -eq $name -and $_.IsEnabled }
        if (-not $role) { $unresolved.Add("$name (Application)"); continue }
        $resourceAccess.Add(@{ Id = $role.Id; Type = 'Role' })
        $resolvedApp.Add([pscustomobject]@{ Name = $name; Id = $role.Id })
    }
    foreach ($name in $DelegatedPermissions) {
        $scope = $GraphSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $name -and $_.IsEnabled }
        if (-not $scope) { $unresolved.Add("$name (Delegated)"); continue }
        $resourceAccess.Add(@{ Id = $scope.Id; Type = 'Scope' })
        $resolvedDel.Add([pscustomobject]@{ Name = $name; Id = $scope.Id })
    }
    if ($unresolved.Count -gt 0) {
        Write-Err "These permissions could not be resolved in this tenant:"
        $unresolved | ForEach-Object { Write-Host "           - $_" -ForegroundColor Red }
        throw "Unresolved Graph permissions. Aborting before any changes are made."
    }
    return [pscustomobject]@{
        ResourceAccess = $resourceAccess
        AppRoles       = $resolvedApp
        Scopes         = $resolvedDel
    }
}
function Grant-AdminConsent {
    param(
        [Parameter(Mandatory)] $AppServicePrincipal,
        [Parameter(Mandatory)] $GraphSp,
        [Parameter(Mandatory)] $Resolved
    )
    # --- Application permissions -> app role assignments --------------------
    # A 403 here means the account can create apps but not consent them (Application
    # Administrator without Privileged Role Administrator). Detect it once rather than
    # producing one wall of Graph error text per permission.
    $consentBlocked = $false
    foreach ($role in $Resolved.AppRoles) {
        if ($consentBlocked) {
            Write-Warn "Skipped (no consent rights): $($role.Name)"
            continue
        }
        try {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $AppServicePrincipal.Id `
                -PrincipalId        $AppServicePrincipal.Id `
                -ResourceId         $GraphSp.Id `
                -AppRoleId          $role.Id `
                -ErrorAction Stop | Out-Null
            Write-Ok "Consented (application): $($role.Name)"
        }
        catch {
            $m = $_.Exception.Message
            if ($m -match 'already exists|Permission being assigned was already assigned') {
                Write-Ok "Already consented: $($role.Name)"
            }
            elseif ($m -match 'Authorization_RequestDenied|Insufficient privileges|Forbidden|\b403\b') {
                $consentBlocked = $true
                Write-Warn "This account cannot grant admin consent."
                Write-Host "           The app registration and its permissions were created successfully." -ForegroundColor Gray
                Write-Host "           A Privileged Role Administrator must grant consent:" -ForegroundColor Gray
                Write-Host "             App registrations > API permissions > Grant admin consent" -ForegroundColor Gray
            }
            else {
                Write-Err "$($role.Name) -> $m"
            }
        }
    }
    # --- Delegated permissions -> single tenant-wide oauth2PermissionGrant ---
    #
    # Uses Invoke-MgGraphRequest rather than New-MgOauth2PermissionGrant. That cmdlet lives
    # in Microsoft.Graph.Identity.SignIns, which we deliberately do NOT load - adding a
    # third Graph submodule means a third module to keep version-aligned, and version
    # sprawl is the single biggest source of failures in this script.
    if ($consentBlocked -and $Resolved.Scopes.Count -gt 0) {
        Write-Warn "Skipped delegated consent - this account cannot grant admin consent."
        $Resolved.Scopes.Name | Sort-Object | ForEach-Object {
            Write-Host "             $_ (delegated)" -ForegroundColor Gray
        }
    }
    elseif ($Resolved.Scopes.Count -gt 0) {
        $scopeString = ($Resolved.Scopes.Name | Sort-Object) -join ' '
        try {
            # Only one grant per resource is allowed, so merge into an existing one.
            $existingGrant = $null
            try {
                $filter = "clientId eq '$($AppServicePrincipal.Id)' and resourceId eq '$($GraphSp.Id)'"
                $existingGrant = (Invoke-MgGraphRequest -Method GET `
                    -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$filter" `
                    -ErrorAction Stop).value
            } catch { }
            if ($existingGrant) {
                $merged = (($existingGrant[0].scope -split ' ') + $Resolved.Scopes.Name |
                           Where-Object { $_ } | Select-Object -Unique | Sort-Object) -join ' '
                Invoke-MgGraphRequest -Method PATCH `
                    -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($existingGrant[0].id)" `
                    -Body @{ scope = $merged } -ErrorAction Stop | Out-Null
                $granted = $merged
            }
            else {
                Invoke-MgGraphRequest -Method POST `
                    -Uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' `
                    -Body @{
                        clientId    = $AppServicePrincipal.Id     # service principal OBJECT id
                        consentType = 'AllPrincipals'
                        resourceId  = $GraphSp.Id
                        scope       = $scopeString
                    } -ErrorAction Stop | Out-Null
                $granted = $scopeString
            }
            # Delegated scopes live in one grant object as a space-separated string, but
            # report them individually so the output matches the application permissions.
            $grantedList = @($granted -split ' ' | Where-Object { $_ })
            foreach ($s in ($Resolved.Scopes.Name | Sort-Object)) {
                if ($grantedList -contains $s) { Write-Ok "Consented (delegated): $s" }
                else { Write-Warn "NOT consented (delegated): $s" }
            }
        }
        catch {
            Write-Err "Delegated consent failed: $($_.Exception.Message)"
            Write-Warn "Grant it manually: Entra admin center > App registrations > API permissions > Grant admin consent"
        }
    }
}
function Resolve-TenantIdFallback {
    <#
        Used when Graph validation could not run. Without a tenant ID the product
        configuration fails later with a misleading authentication error, so ask for it
        at the point the gap actually appears.
    #>
    [CmdletBinding()]
    param([string]$TenantId)
    if ($TenantId) { return $TenantId }
    Write-Host "    The tenant ID could not be read from Microsoft Graph." -ForegroundColor Gray
    Write-Host "    It is shown as Directory (tenant) ID on the app registration Overview page." -ForegroundColor Gray
    $parsed = [guid]::Empty
    do {
        $entered = (Read-Host "    Directory (tenant) ID").Trim()
        if ($entered -and -not [Guid]::TryParse($entered, [ref]$parsed)) {
            Write-Warn "That is not a valid GUID."
            $entered = $null
        }
    } until ($entered)
    return $entered
}
#endregion
#region ------------------------------- Application Workspace identity source
function Import-AwModule {
    <#
        Loads the Application Workspace PowerShell module.
        Resolution order:
          1. Already loaded in this session
          2. Liquit.Server.PowerShell.dll from a local Application Workspace install
             (standard paths, an explicit -ModulePath, or alongside this script)
          3. The Liquit.Server.PowerShell module from PSGallery, installing it if needed
        The DLL is preferred over the gallery module because on a machine with
        Application Workspace installed it is guaranteed to match the installed product
        version. The gallery route covers admin workstations that do not have the
        product installed locally.
        -Global matters on the DLL import - without it the cmdlets are only visible
        inside this function's scope.
    #>
    [CmdletBinding()]
    param([string]$ModulePath)
    # --- Already loaded? -----------------------------------------------------
    if (Get-Command 'Connect-LiquitWorkspace' -ErrorAction SilentlyContinue) {
        Write-Ok "Application Workspace module already loaded"
        return $true
    }
    # --- Local DLL from an Application Workspace install ---------------------
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($ModulePath) { $candidates.Add($ModulePath) }
    $candidates.Add('C:\Program Files (x86)\Liquit Workspace\PowerShell\Liquit.Server.PowerShell.dll')
    $candidates.Add('C:\Program Files\Liquit Workspace\PowerShell\Liquit.Server.PowerShell.dll')
    if ($PSScriptRoot) {
        $candidates.Add((Join-Path $PSScriptRoot 'Liquit.Server.PowerShell.dll'))
    }
    $found = $candidates | Where-Object { $_ -and (Test-Path $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
    if ($found) {
        try {
            Import-Module $found -Global -ErrorAction Stop
            Write-Ok "Application Workspace module loaded"
            Write-Host "           $found" -ForegroundColor DarkGray
            # Loaded by the zone configuration flow for package handling. Harmless here,
            # and keeps behaviour consistent if a later call needs them.
            try {
                [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression") | Out-Null
                [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
            } catch { }
            return $true
        }
        catch {
            Write-Warn "Found the DLL but could not import it: $($_.Exception.Message)"
            Write-Host "           Falling back to the PSGallery module." -ForegroundColor Gray
        }
    }
    # --- PSGallery module ----------------------------------------------------
    $galleryModule = 'Liquit.Server.PowerShell'
    if ((Get-ModuleVersionsOnDisk -Name $galleryModule).Count -eq 0) {
        Write-Warn "The Application Workspace PowerShell module is not installed."
        if ($found) {
            Write-Host "           The local DLL was present but failed to load." -ForegroundColor Gray
        }
        else {
            Write-Host "           No local Application Workspace install was found." -ForegroundColor Gray
        }
        if (-not (Confirm-Action "Install $galleryModule from PSGallery ($script:ModuleScope scope)?")) {
            Write-Host ""
            Write-Host "    Install it manually, then re-run:" -ForegroundColor White
            Write-Host "      Install-Module -Name $galleryModule -Scope $script:ModuleScope" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "    Or point at a local install:" -ForegroundColor White
            Write-Host "      -AwModulePath 'D:\path\to\Liquit.Server.PowerShell.dll'" -ForegroundColor Cyan
            Write-Host ""
            return $false
        }
        Initialize-PackageSource
        if (-not (Install-RecastModule -Name $galleryModule)) {
            return $false
        }
    }
    try {
        Import-Module -Name $galleryModule -Global -ErrorAction Stop
        $loaded = Get-Module -Name $galleryModule
        Write-Ok "Application Workspace module loaded$(if ($loaded.Version) { " ($($loaded.Version))" })"
        if ($loaded.ModuleBase) { Write-Host "           $($loaded.ModuleBase)" -ForegroundColor DarkGray }
    }
    catch {
        Write-Err "Could not import $galleryModule : $($_.Exception.Message)"
        return $false
    }
    # Confirm the cmdlets this script actually depends on are present, rather than
    # assuming a clean import means a usable module.
    if (-not (Get-Command 'Connect-LiquitWorkspace' -ErrorAction SilentlyContinue)) {
        Write-Err "$galleryModule imported, but Connect-LiquitWorkspace is not available."
        Write-Host "           The installed module version may not match this script's expectations." -ForegroundColor Gray
        return $false
    }
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression") | Out-Null
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
    } catch { }
    return $true
}
function Connect-AwZone {
    <#
        Connects to an Application Workspace zone with Connect-LiquitWorkspace.

        Retries on a credential failure (wrong username or password) instead of failing
        outright on the first attempt - a typo in the password is exactly as recoverable
        as a wrong RMS or Entra secret, and this mirrors the retry behavior already used
        for those elsewhere in this script.

        A wrong zone URI, or a missing zone.access.api permission on an otherwise-correct
        account, is NOT retryable by re-typing the same password, so those fail
        immediately rather than looping.
    #>
    [CmdletBinding()]
    param(
        [string]$ZoneUri,
        [pscredential]$Credential,
        [int]$MaxAttempts = 3,
        [switch]$Force
    )
    # Already connected? A cheap read confirms it without side effects.
    try {
        $null = Get-LiquitIdentitySource -ErrorAction Stop 2>$null
        Write-Ok "Already connected to an Application Workspace zone"
        return $true
    }
    catch {
        if ($_.Exception.Message -notmatch 'No connection is available|LiquitContext') {
            Write-Warn "Unexpected error probing the zone connection: $($_.Exception.Message)"
        }
    }
    if (-not $ZoneUri) {
        do {
            $ZoneUri = (Read-Host "    Zone URI (e.g. https://yourzone.recastsoftware.cloud)").Trim()
        } until ($ZoneUri)
    }

    $attempt = 0
    $suppliedCredential = $Credential

    while ($true) {
        $attempt++
        $cred = $suppliedCredential
        if (-not $cred -or $attempt -gt 1) {
            $defaultUser = 'local\admin'
            Write-Host "    API access account for the zone" -ForegroundColor Gray
            $awUser = (Read-Host "    Username [$defaultUser]").Trim()
            if (-not $awUser) { $awUser = $defaultUser }
            $awPass = Read-Host "    Password" -AsSecureString
            if (-not $awPass -or $awPass.Length -eq 0) {
                Write-Err "A password is required to connect to the zone."
                return $false
            }
            $cred = New-Object System.Management.Automation.PSCredential($awUser, $awPass)
        }

        try {
            Write-Host "    Connecting to $ZoneUri ..." -ForegroundColor Gray
            $null = Connect-LiquitWorkspace -URI $ZoneUri -Credential $cred -ErrorAction Stop
            Write-Ok "Connected to zone"
        }
        catch {
            $msg = $_.Exception.Message
            Write-Err "Failed to connect to the zone: $msg"
            $looksLikeBadCredential = $msg -match 'invalid_request|invalid credentials|invalid_grant|Unauthorized|401'

            if (-not $looksLikeBadCredential) {
                Write-Host "           Check the zone URI, and that the account has" -ForegroundColor Gray
                Write-Host "           zone.access.api permission." -ForegroundColor Gray
                return $false
            }
            Write-Host "           Check the username and password." -ForegroundColor Gray

            if ($Force -or $attempt -ge $MaxAttempts) {
                if ($attempt -ge $MaxAttempts) { Write-Warn "Reached $MaxAttempts attempts - stopping." }
                return $false
            }
            if ((Read-Host "    Re-enter the zone credentials and try again? (Y/n)") -match '^[Nn]') {
                return $false
            }
            continue
        }

        try {
            $null = Get-LiquitIdentitySource -ErrorAction Stop 2>$null
            return $true
        }
        catch {
            Write-Err "Connected without error, but zone commands still fail: $($_.Exception.Message)"
            return $false
        }
    }
}
function New-AwEntraIdentitySource {
    <#
    .SYNOPSIS
        Creates the Entra ID identity source in Application Workspace using the app
        registration this script just produced.
    .DESCRIPTION
        Self-contained: loads the Liquit module, connects to the zone, then creates the
        identity source. Mirrors the working zone configuration script - same module path
        logic, same Connect-LiquitWorkspace call, same New-LiquitIdentitySource parameters.
        If a zone connection already exists in the session, it is reused.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [string]$Name,
        [string]$DisplayName,
        [string]$ZoneUri,
        [pscredential]$ZoneCredential,
        [string]$ModulePath,
        # Driven by the features selected earlier. If the app registration was granted
        # User.Read.All / GroupMember.ReadWrite.All, the identity source should actually
        # USE them - otherwise the permission is consented but the feature stays off.
        [bool]$EnablePhotos    = $false,
        [bool]$EnableGroupWrite = $false,
        [switch]$Force
    )
    Write-Step "Creating the Entra ID identity source in Application Workspace"
    # --- Module --------------------------------------------------------------
    if (-not (Import-AwModule -ModulePath $ModulePath)) {
        throw "Application Workspace module not available."
    }
    # --- Connection ----------------------------------------------------------
    # Loading the module is NOT the same as being connected. Every Liquit cmdlet fails
    # with "LiquitContext ... No connection is available to service this operation" when
    # there is no context, and it fails NON-TERMINATING - so without this the script
    # would continue and report success without having configured anything.
    if (-not (Connect-AwZone -ZoneUri $ZoneUri -Credential $ZoneCredential -Force:$Force)) {
        throw "No Application Workspace zone connection."
    }
    # --- Names ---------------------------------------------------------------
    if (-not $Name) {
        Write-Host "    If this tenant is Hybrid Joined, the Name must match the NETBIOS /" -ForegroundColor Gray
        Write-Host "    pre-Windows 2000 domain name exactly - it is case sensitive." -ForegroundColor Gray
        Write-Host "    Letters only, no spaces, is the safe choice." -ForegroundColor Gray
        do {
            $Name = (Read-Host "    Identity Source Name (e.g. EntraID)").Trim()
        } until ($Name)
    }
    if (-not $DisplayName) {
        $DisplayName = (Read-Host "    Friendly Display Name shown to users (e.g. Recast Software)").Trim()
        if (-not $DisplayName) { $DisplayName = $Name }
    }
    # --- Endpoint URIs -------------------------------------------------------
    # The logout URI keeps a literal ${slo.return.url} token - Application Workspace
    # substitutes it at sign-out time. The backtick stops PowerShell expanding it here.
    $tokenUri         = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $authorizationUri = "https://login.microsoftonline.com/$TenantId/oauth2/authorize"
    $logoutUri        = "https://login.microsoftonline.com/$TenantId/oauth2/logout?post_logout_redirect_uri=`${slo.return.url}"
    # --- Create, or skip if it already exists --------------------------------
    $existing = Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue
    $azurePhotos    = if ($EnablePhotos)     { 'Enabled' }        else { 'Disabled' }
    $azureWriteMode = if ($EnableGroupWrite) { 'GroupMembership' } else { 'Disabled' }
    if (-not $existing) {
        # -ErrorAction Stop is required here. The Liquit cmdlets write their failures as
        # non-terminating errors, so without it a failed create does not throw, the catch
        # never runs, and execution falls through to the success message.
        #
        # Driven by the features chosen earlier, so a consented permission actually gets
        # used instead of sitting there switched off.
        #   User.Read.All            -> AzurePhotos    Enabled
        #   GroupMember.ReadWrite.All-> AzureWriteMode  GroupMembership
        Write-Host "    AzurePhotos    : $azurePhotos" -ForegroundColor Gray
        Write-Host "    AzureWriteMode : $azureWriteMode" -ForegroundColor Gray
        try {
            New-LiquitIdentitySource `
                -Type azuread `
                -Methods @('Federated', 'Login') `
                -Name $Name `
                -DisplayName $DisplayName `
                -ClientID $ClientId `
                -ClientSecret $ClientSecret `
                -TokenUri $tokenUri `
                -AuthorizationUri $authorizationUri `
                -LogoutUri $logoutUri `
                -Enabled $true `
                -Hidden $false `
                -AzurePhotos $azurePhotos `
                -Delta $true `
                -IncludeNonSecurityGroups $true `
                -AzureWriteMode $azureWriteMode `
                -UseClientIdAsResource $true `
                -RedirectUriMethod Request `
                -ErrorAction Stop | Out-Null
        }
        catch {
            throw "New-LiquitIdentitySource failed: $($_.Exception.Message)"
        }
        # Confirm the object exists rather than relying on the absence of an exception.
        $created = Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue
        if (-not $created) {
            throw "New-LiquitIdentitySource reported no error, but '$Name' does not exist afterwards. Check the zone connection and the AW audit log."
        }
        Write-Ok "Identity source '$Name' created and verified"
    }
    else {
        Write-Warn "Identity Source '$Name' already exists. Skipping creation."
        Write-Host "           Recreating an identity source is known to break sign-in for users" -ForegroundColor Gray
        Write-Host "           who previously signed in through it, so this is left alone." -ForegroundColor Gray
    }
    # Always reapply the display name - covers both the create and the skip path.
    $displayOk = $false
    try {
        $target = Get-LiquitIdentitySource -Name $Name -ErrorAction Stop
        if ($target) {
            $target | Set-LiquitIdentitySource -DisplayName $DisplayName -ErrorAction Stop | Out-Null
            $displayOk = $true
        }
    }
    catch {
        Write-Warn "Could not set the display name: $($_.Exception.Message)"
    }
    if ($displayOk) { Write-Ok "Display name set to '$DisplayName'" }
    # Read the final state back rather than echoing what we intended to set.
    $final = Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue
    if (-not $final) {
        Write-Err "Identity source '$Name' could not be read back. Nothing was configured."
        throw "Identity source verification failed."
    }
    # A sync is the only point where AW actually presents the client secret to Entra.
    # New-LiquitIdentitySource / Set-LiquitIdentitySource succeed regardless of whether
    # the secret is valid, since they only store configuration - so without this, a bad
    # secret goes undetected until a user cannot sign in.
    $syncResult = Sync-AwIdentitySourceChecked -Name $Name -Force:$Force
    $script:LastIdentitySourceSyncResult = $syncResult
    # A confirmed failure (as opposed to an unverified timeout) means the identity
    # source is either deleted or left in a known-broken state. Either way, printing
    # "Identity source ready" below would be wrong, and any caller further down the
    # chain - e.g. mail server creation - needs to know not to proceed as if this step
    # succeeded.
    if ($syncResult.Success -eq $false) {
        # If the unverified source was intentionally deleted during cleanup, it is gone by
        # design - there is nothing left to configure and nothing failed unexpectedly. Skip
        # the alarming "not left in a usable state" throw and stop quietly; the caller keys
        # off $script:LastIdentitySourceSyncResult.Deleted to suppress the failure banner.
        if ($syncResult.Deleted) {
            Write-Host ""
            Write-Host "   Identity source '$Name' was removed as requested - nothing further to configure." -ForegroundColor Gray
            throw "IdentitySourceDeleted"
        }
        throw "Identity source '$Name' could not be verified and was not left in a usable state: $($syncResult.Message)"
    }
    Write-Host ""
    Write-Host "   Identity source ready." -ForegroundColor Cyan
    Write-Host "     Name         : $Name" -ForegroundColor Gray
    Write-Host "     Display name : $(if ($final.DisplayName) { $final.DisplayName } else { $DisplayName })" -ForegroundColor Gray
    Write-Host "     Methods      : Federated, Login" -ForegroundColor Gray
    Write-Host "     AzurePhotos    : $azurePhotos" -ForegroundColor Gray
    Write-Host "     AzureWriteMode : $azureWriteMode" -ForegroundColor Gray
    if ($null -eq $syncResult.Success) {
        Write-Host "     Sync status    : unverified (assumed to be syncing in the background)" -ForegroundColor Gray
    }
    else {
        Write-Host "     Sync status    : confirmed working" -ForegroundColor Gray
    }
    Write-Host ""
}
function New-AwGraphMailServer {
    <#
    .SYNOPSIS
        Creates a Microsoft Graph mail server in Application Workspace, reusing the app
        registration this script just produced.
    .DESCRIPTION
        Only meaningful when the app registration was granted Mail.Send. The implementation
        guide recommends Graph over SMTP for cloud customers, because Exchange Online basic
        auth for SMTP client submission is being retired.
        Assumes the module is loaded and the zone connection is live - New-AwEntraIdentitySource
        runs first and handles both.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [string]$Name,
        [string]$From,
        [string]$Description
    )
    Write-Step "Creating the Microsoft Graph mail server in Application Workspace"
    if (-not (Get-Command 'New-LiquitMailServer' -ErrorAction SilentlyContinue)) {
        Write-Warn "New-LiquitMailServer is not available in this module version. Skipping."
        Write-Host "           Add it manually: Manage > Mail Servers > Create > Microsoft Graph" -ForegroundColor Gray
        return
    }
    if (-not $Name) {
        $default = 'Microsoft Graph'
        $entered = (Read-Host "    Mail server name [$default]").Trim()
        $Name = if ($entered) { $entered } else { $default }
    }
    # From is required by the API and has no sensible default - it must be a real mailbox
    # the app registration is allowed to send as.
    if (-not $From) {
        Write-Host "    The sender address must be a mailbox in this tenant that the app" -ForegroundColor Gray
        Write-Host "    registration is permitted to send as (e.g. noreply@contoso.com)." -ForegroundColor Gray
        do {
            $From = (Read-Host "    Sender address (From)").Trim()
            if ($From -and $From -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                Write-Warn "That does not look like an email address."
                $From = $null
            }
        } until ($From)
    }
    $existing = Get-LiquitMailServer -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "Mail server '$Name' already exists. Skipping creation."
        return $existing
    }
    if (-not $Description) {
        $Description = "Created by New-RecastEntraAppRegistration on $(Get-Date -Format 'yyyy-MM-dd')"
    }
    try {
        New-LiquitMailServer `
            -Type MicrosoftGraph `
            -Name $Name `
            -From $From `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -ClientSecret $ClientSecret `
            -Description $Description `
            -Enabled $true `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Err "New-LiquitMailServer failed: $($_.Exception.Message)"
        Write-Warn "Add it manually: Manage > Mail Servers > Create > Microsoft Graph"
        return
    }
    # Same discipline as the identity source - confirm rather than assume.
    $created = Get-LiquitMailServer -Name $Name -ErrorAction SilentlyContinue
    if (-not $created) {
        Write-Err "New-LiquitMailServer reported no error, but '$Name' does not exist afterwards."
        return
    }
    Write-Ok "Mail server '$Name' created and verified"
    Write-Host ""
    Write-Host "   Mail server ready." -ForegroundColor Cyan
    Write-Host "     Name   : $Name" -ForegroundColor Gray
    Write-Host "     Type   : Microsoft Graph" -ForegroundColor Gray
    Write-Host "     From   : $From" -ForegroundColor Gray
    Write-Host ""
    Write-Host "     Send a test message from Manage > Mail Servers to confirm the mailbox" -ForegroundColor Gray
    Write-Host "     accepts sends from this app registration." -ForegroundColor Gray
    Write-Host ""
    return $created
}
#endregion
#region ------------------------------------ RMS Entra ID service connection
#
#  Creates an AzureActiveDirectory service connection in Recast Management Server using
#  the app registration produced above.
#
#  A deployed and authorized Recast Proxy is required. RMS does not store service
#  connection credentials in plain text - it encrypts them server-side against the
#  certificate of the proxy that will use the connection, which is why ListProxies runs
#  first and the proxy's certificate thumbprint is submitted with the request.
#
#  Endpoint routes and payload field names are held in one table so they can be adjusted
#  in a single place if a future RMS version changes them.
$script:RmsApiContract = @{
    # --- Endpoints -------------------------------------------------------------
    ApiBase                        = 'api'
    ListProxies                    = 'Administration/ListProxies'
    ListAzureAdServiceConnections  = 'Administration/ListAzureActiveDirectoryServiceConnections'
    CreateAzureAdServiceConnection = 'Administration/CreateAzureActiveDirectoryServiceConnection'
    UpdateAzureAdServiceConnection = 'Administration/UpdateAzureActiveDirectoryServiceConnection'
    DeleteAzureAdServiceConnection = 'Administration/DeleteAzureActiveDirectoryServiceConnection'
    # Validates credentials BEFORE a connection exists - confirmed via Action Tester to
    # take TenantId / ClientId / ClientSecret / ProxyCertificate. Use this as a pre-flight
    # check; it costs nothing and catches a bad secret before RMS writes anything.
    TestNewServiceConnection       = 'AzureActiveDirectory/TestNewServiceConnection'
    # Validates an EXISTING connection. Confirmed via Action Tester to take
    # TenantId / ClientId / ProxyCertificate - no ClientSecret, no ID in the path.
    TestServiceConnection          = 'AzureActiveDirectory/TestServiceConnection'
    # --- Proxy object fields returned by ListProxies ---------------------------
    # Id, ComputerName, UserName, Certificate, Authorized, Connected, Version, Internal
    ProxyIdField          = 'Id'
    ProxyNameField        = 'ComputerName'
    ProxyAccountField     = 'UserName'
    ProxyCertificateField = 'Certificate'
    ProxyAuthorizedField  = 'Authorized'
    ProxyConnectedField   = 'Connected'
    ProxyVersionField     = 'Version'
    ProxyInternalField    = 'Internal'
    # --- CreateAzureActiveDirectoryServiceConnection request fields ------------
    # Note the casing: TenantID and ClientID use a capital D.
    #
    # There is no ProxyId field. The API identifies the proxy by its certificate
    # thumbprint, which is also how the server locates the key used to protect the
    # client secret.
    Body = @{
        Name             = 'Name'
        TenantId         = 'TenantID'
        ClientId         = 'ClientID'
        ClientSecret     = 'ClientSecret'
        Confirmed        = 'Confirmed'
        ProxyCertificate = 'ProxyCertificate'
    }
}
function Resolve-RmsBaseUri {
    <# Accepts rms.contoso.com | rms.contoso.com:444 | https://rms.contoso.com:444 #>
    param(
        [Parameter(Mandatory)][string]$Server,
        [int]$Port = 444
    )
    $s = $Server.Trim().TrimEnd('/')
    if ($s -notmatch '^https?://') { $s = "https://$s" }
    $uri = [Uri]$s
    if ($uri.IsDefaultPort -and $s -notmatch ':\d+$') {
        $builder = [UriBuilder]$uri
        $builder.Port = $Port
        $uri = $builder.Uri
    }
    return $uri.AbsoluteUri.TrimEnd('/')
}
function Enable-RmsSelfSignedCertTrust {
    <# RMS is commonly installed with a self-signed cert. Opt-in only, and noisy about it. #>
    if ($PSVersionTable.PSEdition -eq 'Core') { return }   # PS7 uses -SkipCertificateCheck
    if (-not ([System.Management.Automation.PSTypeName]'RecastCertBypass').Type) {
        Add-Type -TypeDefinition @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class RecastCertBypass : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) {
        return true;
    }
}
'@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object RecastCertBypass
    Write-Warn "TLS certificate validation DISABLED for this session (self-signed RMS cert)."
}
function Invoke-RmsApi {
    <# Single choke point for every RMS call. Windows auth by default. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][string]$Endpoint,
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')][string]$Method = 'GET',
        $Body,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate,
        [int]$TimeoutSec = 60
    )
    if ($AllowSelfSignedCertificate) { Enable-RmsSelfSignedCertTrust }
    $uri = "$BaseUri/$($script:RmsApiContract.ApiBase)/$($Endpoint.TrimStart('/'))"
    $params = @{
        Uri         = $uri
        Method      = $Method
        ContentType = 'application/json'
        TimeoutSec  = $TimeoutSec
        ErrorAction = 'Stop'
    }
    if ($Credential) { $params['Credential'] = $Credential }
    else             { $params['UseDefaultCredentials'] = $true }
    if ($PSVersionTable.PSEdition -eq 'Core' -and $AllowSelfSignedCertificate) {
        $params['SkipCertificateCheck'] = $true
    }
    if ($null -ne $Body -and $Method -ne 'GET') {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }
    Write-Verbose "$Method $uri"
    try {
        $response = Invoke-RestMethod @params
        # Some RMS actions return an array containing both the raw JSON string AND the
        # already-deserialized object for the same payload - confirmed via
        # Get-RmsRawResponse against TestServiceConnection. Collapse that down to the
        # single real object so every caller downstream gets one consistent shape rather
        # than having to guess whether it received an array, a string, or an object.
        if ($response -is [array]) {
            $objectElements = @($response | Where-Object { $_ -isnot [string] })
            if ($objectElements.Count -eq 1) { return $objectElements[0] }
            if ($objectElements.Count -gt 1) { return $objectElements }
            # Only strings came back - fall back to parsing the first one as JSON.
            if ($response.Count -gt 0) {
                try { return ($response[0] | ConvertFrom-Json) } catch { return $response[0] }
            }
        }
        return $response
    }
    catch {
        $status = $null; $detail = $null
        try {
            $status = [int]$_.Exception.Response.StatusCode
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = New-Object IO.StreamReader($stream)
                $detail = $reader.ReadToEnd()
                $reader.Dispose()
            }
        } catch { }
        $msg = "RMS API $Method $Endpoint failed"
        if ($status) { $msg += " (HTTP $status)" }
        $msg += ": $($_.Exception.Message)"
        # A 404 here almost always means the contract table is wrong, not a broken server.
        if ($status -eq 404) {
            $msg += "`n           A 404 usually means the endpoint path in `$RmsApiContract does not match this RMS version."
        }
        if ($detail) { $msg += "`n           Server said: $($detail.Trim())" }
        throw $msg
    }
}
function Test-RmsActionEnvelope {
    <#
        True when an object is an RMS action-result envelope rather than the payload.
        Response shape:
            InputParameters, Result, Index, Total
        RMS actions run over SignalR and return their output wrapped like this. The real
        object lives in .Result; Index/Total describe its position in the result set.
    #>
    param($Object)
    if ($null -eq $Object) { return $false }
    $props = @($Object.PSObject.Properties.Name)
    return (($props -contains 'Result') -and
            (($props -contains 'Index') -or ($props -contains 'Total') -or ($props -contains 'InputParameters')))
}
function Test-RmsActionResult {
    <#
        True for the INNER action-result layer:
            { ErrorMessage, StackTrace, ErrorUrl, IsSuccessful, Result }
        RMS wraps every action twice. The outer envelope carries InputParameters/Index/
        Total; inside that sits this success-or-error object; and the real payload is in
        its .Result. Unwrapping only the outer layer leaves this object rather than the
        payload.
    #>
    param($Object)
    if ($null -eq $Object -or -not $Object.PSObject) { return $false }
    $props = @($Object.PSObject.Properties.Name)
    return (($props -contains 'IsSuccessful') -and ($props -contains 'Result'))
}
function Get-RmsOperationOutcome {
    <#
        Normalizes an RMS action result into { Success, Message }.
        Confirmed shape via Get-RmsRawResponse against TestServiceConnection:
            InputParameters, Result: { ErrorMessage, StackTrace, ErrorUrl, IsSuccessful, Result }
        Reads IsSuccessful as an explicit scalar boolean rather than testing an unwrapped
        array for truthiness. @($null) - a one-element array containing $null - unwraps to
        $null in an if-condition, which is what produced a false "no result" warning on a
        call that had actually returned IsSuccessful = true.
    #>
    param($Raw)
    if ($null -eq $Raw) { return [pscustomobject]@{ Success = $null; Message = $null } }
    $inner = $Raw
    if (Test-RmsActionEnvelope -Object $Raw) { $inner = $Raw.Result }
    if ($null -eq $inner) { return [pscustomobject]@{ Success = $null; Message = $null } }
    $props = @($inner.PSObject.Properties.Name)
    if ($props -contains 'IsSuccessful') {
        return [pscustomobject]@{
            Success = [bool]$inner.IsSuccessful
            Message = $inner.ErrorMessage
        }
    }
    if ($props -contains 'Success') {
        return [pscustomobject]@{
            Success = [bool]$inner.Success
            Message = if ($props -contains 'Message') { $inner.Message } else { $null }
        }
    }
    return [pscustomobject]@{ Success = $null; Message = $null }
}
function Get-RmsAuthFailureGuidance {
    <#
        Maps AADSTS error codes to whether re-entering a value would plausibly fix it.
        Consent/permission errors are NOT retryable by re-typing anything - they need
        action in the Entra portal, and looping on them just burns sign-in attempts.
    #>
    param([string]$Message)
    if ($Message -match 'AADSTS7000215') {
        return [pscustomobject]@{ Retryable = $true;  Hint = "The secret VALUE was rejected - likely the Secret ID was entered instead." }
    }
    if ($Message -match 'AADSTS7000222') {
        return [pscustomobject]@{ Retryable = $true;  Hint = "The client secret has expired. Add a new one under Certificates & secrets." }
    }
    if ($Message -match 'AADSTS90002|AADSTS900023') {
        return [pscustomobject]@{ Retryable = $true;  Hint = "Tenant ID was not recognized. Confirm the Directory (tenant) ID." }
    }
    if ($Message -match 'AADSTS700016') {
        return [pscustomobject]@{ Retryable = $true;  Hint = "App not found in this tenant. Confirm the Application (client) ID." }
    }
    if ($Message -match 'AADSTS65001|consent') {
        return [pscustomobject]@{ Retryable = $false; Hint = "Admin consent has not been granted. Grant it in the portal - re-entering credentials will not fix this." }
    }
    return [pscustomobject]@{ Retryable = $false; Hint = $null }
}
function Invoke-RmsFailedConnectionCleanup {
    <#
        Offers to delete a service connection that failed its credential test and will
        not be corrected in this run - either the operator declined to retry, or the
        maximum retry attempts were reached.
        Leaving a known-broken connection behind is worse than removing it: a stale
        AzureActiveDirectory connection with a bad secret sits in Service Connections
        looking legitimate until someone tries to use it and hits a confusing failure
        with none of the context available right now.
        Delete's own reported outcome is not trusted here - confirmed to report
        Success = true even when nothing was actually deleted (wrong/stale ID). This
        relies on Remove-RmsAzureAdServiceConnection, which re-queries to verify.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][int]$ConnectionId,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate,
        [switch]$Force
    )
    Write-Host ""
    if (-not $Force) {
        $choice = Read-Host "    Delete this unconfirmed service connection (ID $ConnectionId) instead? (y/N)"
        if ($choice -notmatch '^[Yy]') {
            Write-Warn "Left in place. Fix manually: Administration > Service Connections > Edit (ID $ConnectionId)"
            return $false
        }
    }
    $result = Remove-RmsAzureAdServiceConnection -BaseUri $BaseUri -ServiceConnectionId $ConnectionId `
                  -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    if ($result -and $result.Success) {
        Write-Ok "Deleted service connection #$ConnectionId."
        return $true
    }
    Write-Err "Could not delete connection #$ConnectionId."
    Write-Host "           Remove it manually: Administration > Service Connections > Delete" -ForegroundColor Gray
    return $false
}
function Expand-RmsResult {
    <#
        Unwraps an RMS response down to the actual payload objects.
        Response shape - note the double nesting:
            [                                   <- one entry per item
              {
                "InputParameters": {},
                "Result": {                     <- action-result layer
                    "ErrorMessage": null,
                    "IsSuccessful": true,
                    "Result": { "Id": 1, ... }  <- the proxy itself
                },
                "Index": null,
                "Total": null
              }
            ]
        Handles:
          1. An array of outer envelopes      -> unwrap each, recursively
          2. A single outer envelope          -> take .Result, recurse
          3. An action-result layer           -> take .Result, recurse
          4. Conventional collection wrappers -> take that property, recurse
        Surfaces ErrorMessage when IsSuccessful is false, rather than silently
        returning an empty set.
    #>
    param(
        $Response,
        [int]$Depth = 0
    )
    if ($null -eq $Response -or $Depth -gt 6) { return @($Response) }
    # --- Shape 1: array ----------------------------------------------------
    #
    # Deliberately plain arrays here, not System.Collections.Generic.List[object].
    # A generic List resolves .Add() through reflection, and feeding it PSObject-wrapped
    # values from ConvertFrom-Json can throw "Argument types do not match" in Windows
    # PowerShell 5.1. Array concatenation has no such binding step.
    #
    # Also tests [Array] rather than [IEnumerable]: a Hashtable is IEnumerable too, and
    # treating one as a collection of items silently produces nonsense.
    if ($Response -is [Array]) {
        $items = @($Response)
        if ($items.Count -gt 0 -and
            ((Test-RmsActionEnvelope -Object $items[0]) -or (Test-RmsActionResult -Object $items[0]))) {
            $out = @()
            foreach ($i in $items) {
                $unwrapped = Expand-RmsResult -Response $i -Depth ($Depth + 1)
                foreach ($u in @($unwrapped)) {
                    if ($null -ne $u) { $out = $out + $u }
                }
            }
            return $out
        }
        return $items
    }
    # --- Shape 2: outer envelope -------------------------------------------
    if (Test-RmsActionEnvelope -Object $Response) {
        return Expand-RmsResult -Response $Response.Result -Depth ($Depth + 1)
    }
    # --- Shape 3: action-result layer --------------------------------------
    if (Test-RmsActionResult -Object $Response) {
        if ($Response.IsSuccessful -eq $false) {
            $msg = $Response.ErrorMessage
            if (-not $msg) { $msg = 'no ErrorMessage returned' }
            Write-Warn "RMS action reported failure: $msg"
            if ($Response.ErrorUrl) { Write-Host "           $($Response.ErrorUrl)" -ForegroundColor DarkGray }
            return @()
        }
        return Expand-RmsResult -Response $Response.Result -Depth ($Depth + 1)
    }
    # --- Shape 4: conventional collection wrappers -------------------------
    if ($Response.PSObject) {
        foreach ($prop in 'Items', 'Value', 'Data', 'Proxies', 'Results') {
            if ($Response.PSObject.Properties.Name -contains $prop) {
                return Expand-RmsResult -Response $Response.$prop -Depth ($Depth + 1)
            }
        }
    }
    return @($Response)
}
function Get-RmsProxy {
    <#
        ListProxies.
        The response is an action envelope rather than a bare array - see Expand-RmsResult
        for the shape and the unwrapping logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    # Stage-aware error handling: "the call failed" and "the response could not be
    # unwrapped" are completely different problems, and a single catch around both
    # tells you neither.
    try {
        $raw = Invoke-RmsApi -BaseUri $BaseUri `
                             -Endpoint $script:RmsApiContract.ListProxies `
                             -Credential $Credential `
                             -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    }
    catch {
        throw "ListProxies call failed: $($_.Exception.Message)"
    }
    try {
        $expanded = Expand-RmsResult -Response $raw
        $proxies  = @(@($expanded) | Where-Object { $null -ne $_ })
    }
    catch {
        Write-Err "Could not unwrap the ListProxies response: $($_.Exception.Message)"
        Write-Host "           Exception type : $($_.Exception.GetType().FullName)" -ForegroundColor DarkGray
        Write-Host "           Response type  : $(if ($null -ne $raw) { $raw.GetType().FullName } else { '<null>' })" -ForegroundColor DarkGray
        Write-Host "           Dump the raw response with:" -ForegroundColor DarkGray
        Write-Host "             Get-RmsRawResponse -Server <rms> -Endpoint 'Administration/ListProxies' -AllowSelfSignedCertificate" -ForegroundColor DarkGray
        throw "ListProxies response could not be parsed."
    }
    # If unwrapping produced nothing usable, show the raw shape rather than a grid of
    # <unknown>. This is the single most useful diagnostic when the contract is wrong.
    $looksUsable = @($proxies | Where-Object {
        $_.PSObject -and (@($_.PSObject.Properties.Name) -contains $script:RmsApiContract.ProxyNameField)
    })
    if ($proxies.Count -eq 0 -or $looksUsable.Count -eq 0) {
        Write-Warn "ListProxies returned a shape this script did not recognise."
        Write-Host "           Raw response type : $($raw.GetType().Name)" -ForegroundColor DarkGray
        if ($raw.PSObject) {
            Write-Host "           Top-level properties:" -ForegroundColor DarkGray
            @($raw.PSObject.Properties.Name) | ForEach-Object { Write-Host "             $_" -ForegroundColor DarkGray }
        }
        if ($proxies.Count -gt 0 -and $proxies[0].PSObject) {
            Write-Host "           After unwrapping, first object has:" -ForegroundColor DarkGray
            @($proxies[0].PSObject.Properties.Name) | ForEach-Object { Write-Host "             $_" -ForegroundColor DarkGray }
        }
        Write-Host "           Capture the full response with:" -ForegroundColor DarkGray
        Write-Host "             Get-RmsRawResponse -Server <rms> -Endpoint 'Administration/ListProxies' -AllowSelfSignedCertificate" -ForegroundColor DarkGray
    }
    return $proxies
}
function Get-RmsRawResponse {
    <#
    .SYNOPSIS
        Dumps the raw JSON from any RMS endpoint, so response shapes can be inspected
        without guessing.
    .EXAMPLE
        Get-RmsRawResponse -Server rms.contoso.com -Endpoint 'Administration/ListProxies' -AllowSelfSignedCertificate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [int]$Port = 444,
        [Parameter(Mandatory)][string]$Endpoint,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        $Body,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    $baseUri = Resolve-RmsBaseUri -Server $Server -Port $Port
    $raw = Invoke-RmsApi -BaseUri $baseUri -Endpoint $Endpoint -Method $Method -Body $Body `
                         -Credential $Credential `
                         -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    Write-Host ""
    Write-Host "  Raw response from $Endpoint" -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    $raw | ConvertTo-Json -Depth 8
    Write-Host ""
    return $raw
}
function Get-RmsProxyField {
    <#
        Reads a property off a proxy object, tolerating naming drift between RMS versions.
        Tries the configured field name first, then a list of fallbacks, then a
        case-insensitive match against whatever properties actually exist. Returns $null
        rather than throwing, so a display routine never dies over a missing column.
    #>
    param(
        [Parameter(Mandatory)]$Proxy,
        [Parameter(Mandatory)][string]$PreferredName,
        [string[]]$Fallbacks = @()
    )
    if ($null -eq $Proxy) { return $null }
    $props = @($Proxy.PSObject.Properties.Name)
    foreach ($name in (@($PreferredName) + $Fallbacks)) {
        if ($props -contains $name) {
            $v = $Proxy.$name
            if ($null -ne $v -and "$v".Trim()) { return $v }
        }
    }
    # Last resort: case-insensitive match
    foreach ($name in (@($PreferredName) + $Fallbacks)) {
        $hit = $props | Where-Object { $_ -ieq $name } | Select-Object -First 1
        if ($hit) {
            $v = $Proxy.$hit
            if ($null -ne $v -and "$v".Trim()) { return $v }
        }
    }
    return $null
}
function Select-RmsProxy {
    <#
        Interactive proxy picker, laid out like the ListProxies grid in the RMS console so
        the two are easy to reconcile: Id, ComputerName, UserName, Version, then status.
        Proxies missing a certificate or not authorized are flagged - neither can carry a
        service connection, because the client secret is encrypted against the proxy's
        public key.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][array]$Proxies)
    $c = $script:RmsApiContract
    if ($Proxies.Count -eq 0) {
        throw "No Recast Proxies found. A Recast Proxy is required before a service connection can be created."
    }
    Write-Step "Select the Recast Proxy that will use this service connection"
    Write-Host ""
    Write-Host ("        {0,-4} {1,-24} {2,-26} {3,-12} {4}" -f 'Id', 'Computer Name', 'User Name', 'Version', 'Status') -ForegroundColor White
    Write-Host ("        {0}" -f ('-' * 92)) -ForegroundColor DarkGray
    $rows = @()
    for ($i = 0; $i -lt $Proxies.Count; $i++) {
        $p = $Proxies[$i]
        $id       = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyIdField          -Fallbacks @('ProxyId', 'ID')
        $computer = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyNameField        -Fallbacks @('Name', 'Computer', 'ServerName', 'HostName')
        $account  = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyAccountField     -Fallbacks @('ServiceAccount', 'Account', 'User', 'ServiceAccountName')
        $version  = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyVersionField     -Fallbacks @('ProxyVersion', 'AgentVersion')
        $cert     = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyCertificateField -Fallbacks @('ProxyCertificate', 'CertificateThumbprint', 'Thumbprint')
        $auth     = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyAuthorizedField  -Fallbacks @('IsAuthorized')
        $conn     = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyConnectedField   -Fallbacks @('IsConnected', 'Online')
        # Anything we genuinely could not read shows as <unknown> rather than blank, so a
        # contract mismatch is obvious instead of looking like an empty column.
        $computerText = if ($computer) { "$computer" } else { '<unknown>' }
        $accountText  = if ($account)  { "$account"  } else { '<unknown>' }
        $versionText  = if ($version)  { "$version"  } else { '-' }
        $internal = Get-RmsProxyField -Proxy $p -PreferredName $c.ProxyInternalField -Fallbacks @('IsInternal')
        $flags = @()
        if (-not $cert)          { $flags += 'NO CERT' }
        if ($auth -eq $false)    { $flags += 'NOT AUTHORIZED' }
        if ($conn -eq $false)    { $flags += 'OFFLINE' }
        # The built-in "Recast Management Server" entry is not a deployed proxy. It is
        # selectable, but it is almost never what you want for a service connection.
        if ($internal -eq $true) { $flags += 'INTERNAL (RMS itself)' }
        $usable = ($flags -notcontains 'NO CERT') -and ($flags -notcontains 'NOT AUTHORIZED')
        $status = if ($flags) { $flags -join ', ' } else { 'Ready' }
        $color = if (-not $usable) { 'Red' } elseif ($flags) { 'Yellow' } else { 'Green' }
        Write-Host ("    [{0}] {1,-4} {2,-24} {3,-26} {4,-12} {5}" -f `
                    ($i + 1), "$id", $computerText, $accountText, $versionText, $status) -ForegroundColor $color
        $rows += [pscustomobject]@{ Index = $i; Usable = $usable }
    }
    Write-Host ""
    # If nothing came back readable, the contract is wrong - say so plainly rather than
    # letting the operator pick a row of <unknown> values.
    $readable = @($Proxies | Where-Object {
        Get-RmsProxyField -Proxy $_ -PreferredName $c.ProxyNameField -Fallbacks @('Name', 'Computer', 'ServerName', 'HostName')
    })
    if ($readable.Count -eq 0) {
        Write-Warn "No proxy names could be read from the ListProxies response."
        Write-Host "           The Proxy*Field names in `$RmsApiContract likely do not match this" -ForegroundColor Gray
        Write-Host "           RMS version. Properties actually returned on the first object:" -ForegroundColor Gray
        @($Proxies[0].PSObject.Properties.Name) | ForEach-Object {
            Write-Host "             $_" -ForegroundColor DarkGray
        }
        Write-Host "           Update the Proxy*Field values in `$RmsApiContract to match." -ForegroundColor Gray
    }
    $usableRows = @($rows | Where-Object { $_.Usable })
    if ($usableRows.Count -eq 0) {
        Write-Warn "None of these proxies can carry a service connection."
        Write-Host "           A proxy needs both a certificate and Authorized = True." -ForegroundColor Gray
        Write-Host "           Check Administration > Proxies in RMS." -ForegroundColor Gray
    }
    if ($Proxies.Count -eq 1) {
        Write-Ok "Only one proxy available - selecting it"
        return $Proxies[0]
    }
    do {
        $choice = Read-Host "    Select 1-$($Proxies.Count)"
    } until ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Proxies.Count)
    $picked = $Proxies[[int]$choice - 1]
    # Warn, but let them proceed - the operator may know something we do not.
    if (-not ($rows | Where-Object { $_.Index -eq ([int]$choice - 1) }).Usable) {
        Write-Warn "That proxy is flagged as unusable. The service connection will probably fail."
    }
    $pickedName = Get-RmsProxyField -Proxy $picked -PreferredName $c.ProxyNameField -Fallbacks @('Name', 'Computer', 'ServerName', 'HostName')
    Write-Ok "Selected: $(if ($pickedName) { $pickedName } else { "proxy #$choice" })"
    return $picked
}
function Get-RmsProxyCertificateReference {
    <#
        Returns the proxy's certificate REFERENCE - which is what ListProxies actually
        gives us, and what CreateAzureActiveDirectoryServiceConnection wants back.
        The Certificate field is a 40-character
        SHA-1 THUMBPRINT, not a base64-encoded certificate:
            "Certificate": "0FD759ACCDBCFD231C89C389FEAAC40E3496C2F4"
        The built-in RMS entry is the special case:
            "ComputerName": "Recast Management Server",
            "Certificate":  "internal",
            "Internal":     true
        A thumbprint carries no public key, so the client cannot encrypt the secret
        itself. The server performs the encryption, resolving the proxy certificate from
        this thumbprint.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Proxy)
    $c   = $script:RmsApiContract
    $raw = Get-RmsProxyField -Proxy $Proxy -PreferredName $c.ProxyCertificateField `
                             -Fallbacks @('ProxyCertificate', 'CertificateThumbprint', 'Thumbprint')
    $pName = Get-RmsProxyField -Proxy $Proxy -PreferredName $c.ProxyNameField `
                               -Fallbacks @('Name', 'Computer', 'ServerName', 'HostName')
    if (-not $pName) { $pName = '<unknown>' }
    if (-not $raw) {
        throw ("Proxy '{0}' has no value on the '{1}' field. Either the proxy is not fully " -f
               $pName, $c.ProxyCertificateField) +
              "authorized, or ProxyCertificateField is wrong in `$RmsApiContract."
    }
    $value = "$raw".Trim()
    # The RMS server's own built-in entry.
    if ($value -ieq 'internal') {
        Write-Ok "Proxy certificate reference: internal (Recast Management Server)"
        Write-Warn "This is the built-in RMS entry, not a deployed Recast Proxy."
        Write-Host "           Service connections normally target a real proxy. Continue only if" -ForegroundColor Gray
        Write-Host "           you specifically intend to use the internal RMS connection." -ForegroundColor Gray
        return $value
    }
    # A SHA-1 thumbprint: 40 hex characters.
    if ($value -match '^[0-9A-Fa-f]{40}$') {
        Write-Ok "Proxy certificate thumbprint: $($value.ToUpper())"
        return $value
    }
    # Anything longer and base64-ish is probably a real certificate blob - some other RMS
    # version may return one. Parse it for the extra detail, but still hand back the
    # original string, because that is what the API was given.
    if ($value.Length -gt 100) {
        try {
            $b64 = ($value -replace '-----BEGIN CERTIFICATE-----', '' `
                           -replace '-----END CERTIFICATE-----', '' `
                           -replace '\s', '')
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[Convert]::FromBase64String($b64))
            Write-Ok "Proxy certificate: $($cert.Subject)"
            Write-Host "           Thumbprint : $($cert.Thumbprint)" -ForegroundColor DarkGray
            Write-Host "           Expires    : $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
            if ($cert.NotAfter -lt (Get-Date)) {
                Write-Warn "This proxy certificate has EXPIRED. The service connection will not work."
            }
        }
        catch {
            Write-Warn "Certificate value could not be parsed as X509; sending it through as-is."
        }
        return $value
    }
    Write-Warn "Unrecognised certificate value on proxy '$pName': $value"
    Write-Host "           Expected a 40-character thumbprint or 'internal'. Sending as-is." -ForegroundColor Gray
    return $value
}
function Get-RmsAzureAdServiceConnection {
    <#
        Lists existing AzureActiveDirectory service connections.
        RMS silently declines to create a connection whose details match one that already
        exists - no error, no new row. Checking first is the only way to tell "created"
        from "quietly ignored".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    try {
        $raw = Invoke-RmsApi -BaseUri $BaseUri `
                             -Endpoint $script:RmsApiContract.ListAzureAdServiceConnections `
                             -Credential $Credential `
                             -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    }
    catch {
        # Advisory only - a failed read should not block the create attempt.
        Write-Verbose "Could not list existing service connections: $($_.Exception.Message)"
        return $null
    }
    try   { return @(Expand-RmsResult -Response $raw | Where-Object { $null -ne $_ }) }
    catch { return $null }
}
function Update-RmsAzureAdServiceConnection {
    <#
        Corrects an existing service connection in place. Create never upserts - it was
        confirmed to insert a new row even when the operator chose to proceed past a
        duplicate warning - so fixing a bad secret has to go through Update, or every
        retry leaves another row behind.
        Confirmed via manual PUT test with a real secret against a row that was NOT
        already in a failed-test state: Update succeeds. Earlier HTTP 500s traced back to
        rows left over from prior failed attempts, not a fault in Update itself.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][int]$ServiceConnectionId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$ProxyCertificate,
        [bool]$Confirmed = $true,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    if (-not $PSCmdlet.ShouldProcess("Service connection #$ServiceConnectionId ($Name)", "Update")) { return }
    # Field names/casing confirmed via Action Tester's input schema for
    # UpdateAzureActiveDirectoryServiceConnection. Uses PUT - confirmed via Action Tester
    # that POST returns a bare 500 on this action (the server logs "Wrong HTTP verb").
    $body = @{
        ServiceConnectionID = $ServiceConnectionId
        Name                = $Name
        TenantID            = $TenantId
        ClientID            = $ClientId
        ClientSecret        = $ClientSecret
        Confirmed           = $Confirmed
        ProxyCertificate    = $ProxyCertificate
    }
    $raw = Invoke-RmsApi -BaseUri $BaseUri `
                         -Endpoint $script:RmsApiContract.UpdateAzureAdServiceConnection `
                         -Method PUT -Body $body `
                         -Credential $Credential `
                         -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    return Get-RmsOperationOutcome -Raw $raw
}
function Remove-RmsAzureAdServiceConnection {
    <#
        Deletes a service connection by ID, then verifies the row is actually gone.
        The delete action has been observed to report Success = true even when the
        supplied ID does not correspond to any existing connection - it silently no-ops
        rather than erroring. So a successful outcome from the action is not sufficient
        evidence of anything; the row is re-queried afterward to confirm.
        Uses DELETE with the ID as a query string parameter, not a request body - a DELETE
        body was confirmed to arrive empty server-side (standard HTTP client/IIS behaviour
        for this verb), which is why the ID travels in the URL instead.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][int]$ServiceConnectionId,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    if (-not $PSCmdlet.ShouldProcess("Service connection #$ServiceConnectionId", "Delete")) { return }
    $raw = Invoke-RmsApi -BaseUri $BaseUri `
                         -Endpoint "$($script:RmsApiContract.DeleteAzureAdServiceConnection)?ServiceConnectionID=$ServiceConnectionId" `
                         -Method DELETE `
                         -Credential $Credential `
                         -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    $outcome = Get-RmsOperationOutcome -Raw $raw
    # Re-list rather than trusting the action's own Success flag - confirmed to report
    # Success = true even when the ID did not exist and nothing was deleted.
    $stillPresent = Get-RmsAzureAdServiceConnection -BaseUri $BaseUri -Credential $Credential `
                        -AllowSelfSignedCertificate:$AllowSelfSignedCertificate |
                    Where-Object { $_.ID -eq $ServiceConnectionId }
    if ($stillPresent) {
        Write-Err "Delete reported success, but connection #$ServiceConnectionId is still present."
        Write-Host "           Either the ID was wrong, or the delete action did not take effect." -ForegroundColor Gray
        return [pscustomobject]@{ Success = $false; Message = 'Row still present after delete.' }
    }
    Write-Ok "Connection #$ServiceConnectionId confirmed deleted"
    return $outcome
}
function Test-RmsNewServiceConnection {
    <#
        Validates Entra credentials against RMS BEFORE any connection is created.
        Catches a bad secret, missing admin consent, or wrong tenant while nothing has
        been written yet - cheaper to fix at this point than after a failed or duplicate
        create.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$ProxyCertificate,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    Write-Step "Validating credentials before creating the connection"
    $body = @{
        TenantId         = $TenantId
        ClientId         = $ClientId
        ClientSecret     = $ClientSecret
        ProxyCertificate = $ProxyCertificate
    }
    try {
        $null = Invoke-RmsApi -BaseUri $BaseUri `
                             -Endpoint $script:RmsApiContract.TestNewServiceConnection -Method POST -Body $body `
                             -Credential $Credential `
                             -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        # The synchronous response body for this action has not been reliably confirmed
        # to carry an accurate pass/fail signal (the RMS Audit Log is the confirmed
        # source of truth for this action). A call that did not throw is therefore
        # treated as "submitted", not "confirmed passed" - only a thrown exception below
        # is treated as a definite failure.
        Write-Ok "Credentials submitted for validation"
        Write-Host "           Confirm the result in RMS: Administration > Audit Log" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Warn "Could not validate credentials: $($_.Exception.Message)"
        Write-Host "           Proceeding to create anyway - this check is advisory." -ForegroundColor Gray
        return $null
    }
}
function Invoke-RmsServiceConnectionTest {
    <#
        Runs TestServiceConnection and reports the outcome.
        Factored out so the post-create test and the post-retry-update test share one
        implementation. Two separate copies of this logic is exactly how the earlier
        array-collapse shape bug would have gone stale in one spot while getting fixed
        in the other.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ProxyCertificate,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    Write-Step "Testing the service connection"
    try {
        $testBody = @{
            TenantId         = $TenantId
            ClientId         = $ClientId
            ProxyCertificate = $ProxyCertificate
        }
        $testRaw = Invoke-RmsApi -BaseUri $BaseUri `
                                 -Endpoint $script:RmsApiContract.TestServiceConnection -Method POST -Body $testBody `
                                 -Credential $Credential `
                                 -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        $outcome = Get-RmsOperationOutcome -Raw $testRaw
        if ($null -eq $outcome.Success) {
            Write-Ok "Connection test submitted"
            Write-Host "           Result shape not recognized - confirm in RMS: Administration > Audit Log" -ForegroundColor Gray
        }
        elseif ($outcome.Success) {
            Write-Ok "Connection test passed$(if ($outcome.Message) { ": $($outcome.Message)" })"
        }
        else {
            Write-Err "Connection test failed$(if ($outcome.Message) { ": $($outcome.Message)" })"
        }
        return $outcome
    }
    catch {
        Write-Warn "Connection test failed: $($_.Exception.Message)"
        Write-Host "           This can be expected. The test exercises permissions your app" -ForegroundColor Gray
        Write-Host "           registration may not need for the features you enabled." -ForegroundColor Gray
        return $null
    }
}
function Add-RmsAzureAdServiceConnection {
    <#
    .SYNOPSIS
        End to end: connect to RMS, list the proxies, then create the
        AzureActiveDirectory service connection against the selected proxy.
    .DESCRIPTION
        The proxy selection step is not optional. RMS does not store service connection
        credentials in plain text - they are protected against the certificate of the
        proxy that will use the connection, so the proxy must be identified before the
        secret can be submitted.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Server,
        [int]$Port = 444,
        [string]$Name = 'Entra ID',
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate,
        # Confirmed defaults to true. A service connection created unconfirmed still has
        # to be confirmed by hand in RMS before it will be used, which defeats the point
        # of automating it. Pass -MarkConfirmed:$false to create it unconfirmed.
        [bool]$MarkConfirmed = $true,
        [switch]$TestAfterCreate,
        # When a duplicate is found, skip the interactive Update/Create/Quit prompt and go
        # straight to Update. Used by the retry loop, so correcting a bad secret does not
        # re-prompt for a decision that was already made on the first attempt.
        [switch]$ForceUpdateExisting,
        # Skip the pre-flight TestNewServiceConnection call. Set when the tenant/app
        # pairing was never verified against Microsoft Graph - e.g. sign-in failed or
        # -SkipAppValidation was used - because in that state a validation failure carries
        # no information; it was never going to succeed either way.
        [switch]$SkipCredentialValidation
    )
    $baseUri = Resolve-RmsBaseUri -Server $Server -Port $Port
    # --- Reachability / auth -------------------------------------------------
    Write-Step "Connecting to Recast Management Server"
    Write-Host "    $baseUri" -ForegroundColor Gray
    try {
        $null = Invoke-RmsApi -BaseUri $baseUri -Endpoint $script:RmsApiContract.ListProxies `
                              -Credential $Credential `
                              -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        Write-Ok "Connected and authenticated"
    }
    catch {
        Write-Err $_.Exception.Message
        Write-Host ""
        Write-Host "    Common causes:" -ForegroundColor White
        Write-Host "      - Wrong port. RMS defaults to 444; dev installs often use 44339." -ForegroundColor Gray
        Write-Host "      - Self-signed RMS certificate. Re-run with -AllowSelfSignedCertificate." -ForegroundColor Gray
        Write-Host "      - Your account has no RMS permissions." -ForegroundColor Gray
        Write-Host "      - Endpoint path in `$RmsApiContract does not match this RMS version." -ForegroundColor Gray
        throw "Could not reach or authenticate to RMS at $baseUri"
    }
    # --- Proxies -------------------------------------------------------------
    Write-Step "Retrieving Recast Proxies (ListProxies)"
    $proxies = Get-RmsProxy -BaseUri $baseUri -Credential $Credential `
                            -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    Write-Ok "$($proxies.Count) proxy/proxies returned"
    $proxy = Select-RmsProxy -Proxies $proxies
    $c = $script:RmsApiContract
    $proxyId   = Get-RmsProxyField -Proxy $proxy -PreferredName $c.ProxyIdField      -Fallbacks @('ProxyId', 'ID')
    $proxyName = Get-RmsProxyField -Proxy $proxy -PreferredName $c.ProxyNameField    -Fallbacks @('Name', 'Computer', 'ServerName', 'HostName')
    $proxyUser = Get-RmsProxyField -Proxy $proxy -PreferredName $c.ProxyAccountField -Fallbacks @('ServiceAccount', 'Account', 'User')
    # --- Certificate reference ----------------------------------------------
    # Validates the value and reports what it is (thumbprint / internal / blob).
    $rawProxyCertificate = Get-RmsProxyCertificateReference -Proxy $proxy
    # --- Secret handling -----------------------------------------------------
    #
    # ListProxies returns Certificate as a 40-character SHA-1 thumbprint rather than a
    # certificate blob, so the client has no public key to encrypt with. The server
    # performs the encryption, resolving the certificate from the thumbprint submitted
    # with the request - which is consistent with the plain "ClientSecret" field name.
    $secretForBody = $ClientSecret
    Write-Ok "Client secret submitted (encrypted server-side against the proxy certificate)"
    # --- Pre-flight credential check ------------------------------------------
    if ($SkipCredentialValidation) {
        Write-Step "Validating credentials before creating the connection"
        Write-Warn "Skipped - the tenant/app pairing was not verified against Microsoft Graph."
        Write-Host "           Proceeding directly to creation with the supplied values." -ForegroundColor Gray
    }
    else {
        $validated = Test-RmsNewServiceConnection -BaseUri $baseUri `
                        -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
                        -ProxyCertificate $rawProxyCertificate `
                        -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        if ($validated -eq $false) {
            Write-Err "Credential validation failed."
            Write-Host "           Common causes: wrong client secret value, admin consent not" -ForegroundColor Gray
            Write-Host "           granted, or wrong tenant ID." -ForegroundColor Gray
            if (-not $Force) {
                if ((Read-Host "    Attempt the create anyway? (y/N)") -notmatch '^[Yy]') {
                    throw "Cancelled - credential validation failed."
                }
            }
        }
    }
    # --- Duplicate check -------------------------------------------------------
    # A true duplicate is the SAME tenant AND the SAME client. This RMS instance has
    # confirmed cases of one tenant legitimately holding multiple connections against
    # different app registrations, so matching on tenant alone produces false positives.
    $existingConns = Get-RmsAzureAdServiceConnection -BaseUri $baseUri -Credential $Credential `
                        -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    $updatedInstead = $false
    $connectionId   = $null
    if ($null -eq $existingConns) {
        Write-Warn "Could not read existing service connections - skipping the duplicate check."
    }
    else {
        $exactMatch = $existingConns | Where-Object {
            "$($_.TenantID)".Trim() -ieq $TenantId.Trim() -and
            "$($_.ClientID)".Trim() -ieq $ClientId.Trim()
        } | Select-Object -First 1
        $sameTenantOther = @($existingConns | Where-Object {
            "$($_.TenantID)".Trim() -ieq $TenantId.Trim() -and
            "$($_.ClientID)".Trim() -ine $ClientId.Trim()
        })
        if ($exactMatch) {
            Write-Warn "A service connection already exists for this exact tenant and app registration."
            Write-Host "           ID     : $($exactMatch.ID)" -ForegroundColor Gray
            Write-Host "           Name   : $($exactMatch.Name)" -ForegroundColor Gray
            Write-Host "           Tenant : $TenantId" -ForegroundColor Gray
            Write-Host "           Client : $ClientId" -ForegroundColor Gray
            Write-Host ""
            Write-Host "           RMS does not upsert on Create - choosing Create would add a" -ForegroundColor Gray
            Write-Host "           second row rather than fix the existing one." -ForegroundColor Gray
            Write-Host ""
            if ($ForceUpdateExisting) {
                $choice = 'U'
            }
            else {
                $choice = (Read-Host "    (U)pdate the existing connection, (C)reate a new one anyway, or (Q)uit? [U/c/q]").Trim()
            }
            if ($choice -match '^[Qq]') {
                throw "Cancelled - a matching service connection already exists (ID $($exactMatch.ID))."
            }
            elseif ($choice -notmatch '^[Cc]') {
                Write-Step "Updating the existing service connection"
                # Update is confirmed reliable (PUT, with real credentials, against a row
                # not already in a failed-test state). Still wrapped in try/catch: a
                # transient HTTP failure here should degrade to a controlled message and a
                # delete-then-recreate offer, rather than propagate uncaught and abort the
                # whole run.
                $updateOutcome = $null
                try {
                    $updateOutcome = Update-RmsAzureAdServiceConnection -BaseUri $baseUri `
                        -ServiceConnectionId $exactMatch.ID -Name $Name `
                        -TenantId $TenantId -ClientId $ClientId -ClientSecret $secretForBody `
                        -ProxyCertificate $rawProxyCertificate -Confirmed:$MarkConfirmed `
                        -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
                }
                catch {
                    Write-Err "Update request failed: $($_.Exception.Message)"
                }
                if ($updateOutcome -and $updateOutcome.Success) {
                    Write-Ok "Existing connection updated$(if ($updateOutcome.Message) { ": $($updateOutcome.Message)" })"
                    $updatedInstead = $true
                    $connectionId   = $exactMatch.ID
                }
                else {
                    if ($updateOutcome) { Write-Err "Update failed$(if ($updateOutcome.Message) { ": $($updateOutcome.Message)" })" }
                    Write-Host ""
                    Write-Warn "Update did not succeed for this row. Delete row #$($exactMatch.ID) and create a new one instead?"
                    Write-Host "           Delete is confirmed to work reliably and is a safe fallback here." -ForegroundColor Gray
                    if ((Read-Host "    Delete and recreate? (Y/n)") -notmatch '^[Nn]') {
                        try {
                            $delOutcome = Remove-RmsAzureAdServiceConnection -BaseUri $baseUri `
                                -ServiceConnectionId $exactMatch.ID `
                                -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
                            if ($delOutcome -and $delOutcome.Success -eq $false) {
                                throw "RMS reported the delete did not succeed."
                            }
                            Write-Ok "Deleted row #$($exactMatch.ID) - proceeding to create a fresh connection."
                            # $updatedInstead stays $false, so the Create block below runs.
                        }
                        catch {
                            Write-Err "Delete failed: $($_.Exception.Message)"
                            throw "Could not update or delete the existing connection (ID $($exactMatch.ID)). Resolve manually in RMS."
                        }
                    }
                    else {
                        throw "Cancelled - existing connection (ID $($exactMatch.ID)) was not updated."
                    }
                }
            }
            # else: operator chose Create - fall through below
        }
        elseif ($sameTenantOther.Count -gt 0) {
            Write-Ok "Note: $($sameTenantOther.Count) other connection(s) exist for this tenant under a different app registration - expected if multiple products target the same tenant."
        }
    }
    # --- Create (skipped when Update ran instead) -----------------------------
    if (-not $updatedInstead) {
        Write-Step "Creating the AzureActiveDirectory service connection"
        Write-Host "    Name     : $Name"      -ForegroundColor Gray
        Write-Host "    Tenant   : $TenantId"  -ForegroundColor Gray
        Write-Host "    Client   : $ClientId"  -ForegroundColor Gray
        Write-Host "    Proxy    : $(if ($proxyName) { $proxyName } else { '<unknown>' })$(if ($proxyId) { " (Id $proxyId)" })" -ForegroundColor Gray
        if ($proxyUser) { Write-Host "    Runs as  : $proxyUser" -ForegroundColor Gray }
        Write-Host "    Confirmed: $([bool]$MarkConfirmed)" -ForegroundColor Gray
        if (-not $PSCmdlet.ShouldProcess($baseUri, "Create AzureActiveDirectory service connection '$Name'")) {
            Write-Warn "-WhatIf specified - nothing was created."
            return
        }
        $f = $c.Body
        $body = @{
            $f.Name             = $Name
            $f.TenantId         = $TenantId
            $f.ClientId         = $ClientId
            $f.ClientSecret     = $secretForBody
            $f.Confirmed        = [bool]$MarkConfirmed
            $f.ProxyCertificate = $rawProxyCertificate
        }
        $rawCreate = Invoke-RmsApi -BaseUri $baseUri `
                                   -Endpoint $c.CreateAzureAdServiceConnection `
                                   -Method POST -Body $body `
                                   -Credential $Credential `
                                   -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
        $created = Expand-RmsResult -Response $rawCreate
        if (-not $created -or @($created).Count -eq 0) {
            Write-Err "RMS did not create the service connection."
            Write-Host ""
            Write-Host "    Most likely causes:" -ForegroundColor White
            Write-Host "      - An AzureActiveDirectory connection already exists for this tenant/client." -ForegroundColor Gray
            Write-Host "      - The account lacks permission to create service connections." -ForegroundColor Gray
            Write-Host "      - A payload field name in `$RmsApiContract.Body does not match this RMS version." -ForegroundColor Gray
            Write-Host ""
            Write-Host "    Raw response:" -ForegroundColor DarkGray
            try   { ($rawCreate | ConvertTo-Json -Depth 8) -split "`n" | Select-Object -First 25 |
                    ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray } }
            catch { Write-Host "      (could not serialise)" -ForegroundColor DarkGray }
            Write-Host ""
            throw "Service connection was not created - see the response above."
        }
        Write-Ok "Service connection created"
        # Create's response does not reliably expose the new row's ID, so look it up by
        # tenant + client. A retry needs this ID to call Update instead of Create again.
        try {
            $justCreated = Get-RmsAzureAdServiceConnection -BaseUri $baseUri -Credential $Credential `
                                -AllowSelfSignedCertificate:$AllowSelfSignedCertificate |
                           Where-Object { "$($_.TenantID)".Trim() -ieq $TenantId.Trim() -and "$($_.ClientID)".Trim() -ieq $ClientId.Trim() } |
                           Select-Object -First 1
            if ($justCreated) { $connectionId = $justCreated.ID }
        }
        catch { }
    }
    # --- Optional test ---------------------------------------------------------
    # Shared with the retry path (Repair-RmsServiceConnectionSecret) via
    # Invoke-RmsServiceConnectionTest, rather than a second inline copy of the same logic.
    $outcome = $null
    if ($TestAfterCreate) {
        $outcome = Invoke-RmsServiceConnectionTest -BaseUri $baseUri `
            -TenantId $TenantId -ClientId $ClientId -ProxyCertificate $rawProxyCertificate `
            -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    }
    Write-Host ""
    Write-Host "   Next in RMS:" -ForegroundColor Cyan
    Write-Host "     Administration > Service Connections - confirm it shows as Confirmed" -ForegroundColor Gray
    Write-Host "     Administration > Routes - make sure a Recast Proxy route exists" -ForegroundColor Gray
    Write-Host ""
    return [pscustomobject]@{
        ConnectionId     = $connectionId
        TestOutcome      = $outcome
        BaseUri          = $baseUri
        ProxyCertificate = $rawProxyCertificate
    }
}
function Repair-RmsServiceConnectionSecret {
    <#
        Corrects the secret on an already-identified connection and re-tests it.
        Deliberately lighter than calling Add-RmsAzureAdServiceConnection again: that
        function re-runs interactive proxy selection and the duplicate-name prompt,
        neither of which should repeat once the right connection was already identified
        on the first attempt.
        Uses Update directly - confirmed reliable for correcting a secret in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][int]$ConnectionId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$ProxyCertificate,
        [bool]$Confirmed = $true,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )
    Write-Step "Updating connection #$ConnectionId with the new secret"
    # Still wrapped in try/catch even though Update is confirmed reliable: a transient
    # HTTP failure here should degrade to a controlled message rather than propagate
    # uncaught through the retry loop and kill the script.
    $updateOutcome = $null
    try {
        $updateOutcome = Update-RmsAzureAdServiceConnection -BaseUri $BaseUri `
            -ServiceConnectionId $ConnectionId -Name $Name `
            -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
            -ProxyCertificate $ProxyCertificate -Confirmed:$Confirmed `
            -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    }
    catch {
        Write-Err "Update request failed: $($_.Exception.Message)"
        return [pscustomobject]@{ ConnectionId = $ConnectionId; TestOutcome = $null; BaseUri = $BaseUri; ProxyCertificate = $ProxyCertificate }
    }
    if (-not $updateOutcome -or $updateOutcome.Success -ne $true) {
        Write-Err "Update failed$(if ($updateOutcome -and $updateOutcome.Message) { ": $($updateOutcome.Message)" })"
        return [pscustomobject]@{ ConnectionId = $ConnectionId; TestOutcome = $null; BaseUri = $BaseUri; ProxyCertificate = $ProxyCertificate }
    }
    Write-Ok "Connection updated"
    $outcome = Invoke-RmsServiceConnectionTest -BaseUri $BaseUri `
        -TenantId $TenantId -ClientId $ClientId -ProxyCertificate $ProxyCertificate `
        -Credential $Credential -AllowSelfSignedCertificate:$AllowSelfSignedCertificate
    return [pscustomobject]@{ ConnectionId = $ConnectionId; TestOutcome = $outcome; BaseUri = $BaseUri; ProxyCertificate = $ProxyCertificate }
}
#endregion
#region ------------------------------ Existing app registration mode
function ConvertFrom-SecureStringPlain {
    <#
        Converts a SecureString to plain text, because the RMS and Application Workspace
        APIs both take the secret as a string. The unmanaged BSTR is always freed, even
        if the conversion throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Security.SecureString]$Secure)
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
function Read-ClientSecretValue {
    <#
        Prompts for the client secret VALUE.
        Entra reveals a secret value exactly once, at creation. There is no API to read
        it back afterwards, which is why this mode has to ask: either paste the vaulted
        value, or add a new secret in the portal first.
    #>
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "    The client secret VALUE is required - not the Secret ID." -ForegroundColor Gray
    Write-Host "    Entra only shows it once, at creation. If you do not have it, add a new" -ForegroundColor Gray
    Write-Host "    secret under App registrations > Certificates & secrets and use that." -ForegroundColor Gray
    do {
        $secure = Read-Host "    Client secret value" -AsSecureString
        if (-not $secure -or $secure.Length -eq 0) {
            Write-Warn "A client secret is required to configure the product."
            $secure = $null
        }
    } until ($secure)
    return (ConvertFrom-SecureStringPlain -Secure $secure)
}
function Get-GraphPermissionNameMap {
    <#
        Builds a GUID -> permission name lookup from the Microsoft Graph service principal.
        Resolve-GraphPermissions does this in the create direction (name -> GUID). This is
        the reverse, needed to make sense of an app registration that already exists:
        RequiredResourceAccess stores only GUIDs, so without this the report would be a
        list of meaningless IDs.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$GraphSp)
    $map = @{}
    foreach ($role in $GraphSp.AppRoles) {
        if ($role.Id) { $map["$($role.Id)"] = @{ Name = $role.Value; Type = 'Application' } }
    }
    foreach ($scope in $GraphSp.Oauth2PermissionScopes) {
        if ($scope.Id) { $map["$($scope.Id)"] = @{ Name = $scope.Value; Type = 'Delegated' } }
    }
    return $map
}
function Get-AppRegistrationPermissionState {
    <#
        Returns what an app registration ASKS FOR and what has actually been CONSENTED.
        These are different things and the difference matters. RequiredResourceAccess on
        the app registration is a request - it is what the portal shows under API
        permissions. The actual grant lives on the SERVICE PRINCIPAL:
          Application permissions -> appRoleAssignments
          Delegated permissions   -> oauth2PermissionGrants
        A permission listed but never consented looks correct in the portal at a glance
        and still fails at runtime with an authorization error. Surfacing both is the
        whole point of this report.
        Consent reads are best-effort: they need more scope than reading the app does, so
        a failure degrades to "requested only" rather than aborting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)]$GraphSp
    )
    $nameMap = Get-GraphPermissionNameMap -GraphSp $GraphSp
    $app = Get-MgApplication -Filter "appId eq '$AppId'" -ErrorAction Stop | Select-Object -First 1
    if (-not $app) { throw "App registration '$AppId' not found." }
    # --- Requested, from the app registration --------------------------------
    $requestedApp = New-Object System.Collections.Generic.List[string]
    $requestedDel = New-Object System.Collections.Generic.List[string]
    $unknownIds   = New-Object System.Collections.Generic.List[string]
    $graphAccess = @($app.RequiredResourceAccess | Where-Object { $_.ResourceAppId -eq $GraphAppId })
    foreach ($entry in $graphAccess) {
        foreach ($ra in $entry.ResourceAccess) {
            $hit = $nameMap["$($ra.Id)"]
            if (-not $hit) { $unknownIds.Add("$($ra.Id)"); continue }
            if ($ra.Type -eq 'Role') { if ($requestedApp -notcontains $hit.Name) { $requestedApp.Add($hit.Name) } }
            else                     { if ($requestedDel -notcontains $hit.Name) { $requestedDel.Add($hit.Name) } }
        }
    }
    # --- Consented, from the service principal -------------------------------
    $consentedApp   = New-Object System.Collections.Generic.List[string]
    $consentedDel   = New-Object System.Collections.Generic.List[string]
    $consentReadable = $true
    $spMissing       = $false
    $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if (-not $sp) {
        # An app registration with no enterprise application cannot hold any grant.
        $spMissing = $true
    }
    else {
        try {
            $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All -ErrorAction Stop
            foreach ($a in $assignments) {
                if ($a.ResourceId -ne $GraphSp.Id) { continue }
                $hit = $nameMap["$($a.AppRoleId)"]
                if ($hit -and $consentedApp -notcontains $hit.Name) { $consentedApp.Add($hit.Name) }
            }
        }
        catch { $consentReadable = $false }
        try {
            $filter = "clientId eq '$($sp.Id)' and resourceId eq '$($GraphSp.Id)'"
            $grants = (Invoke-MgGraphRequest -Method GET `
                        -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$filter" `
                        -ErrorAction Stop).value
            foreach ($g in $grants) {
                foreach ($s in ($g.scope -split ' ')) {
                    if ($s -and $consentedDel -notcontains $s) { $consentedDel.Add($s) }
                }
            }
        }
        catch { $consentReadable = $false }
    }
    return [pscustomobject]@{
        DisplayName      = $app.DisplayName
        AppId            = $app.AppId
        ObjectId         = $app.Id
        RequestedApp     = @($requestedApp)
        RequestedDel     = @($requestedDel)
        ConsentedApp     = @($consentedApp)
        ConsentedDel     = @($consentedDel)
        UnknownIds       = @($unknownIds)
        ConsentReadable  = $consentReadable
        ServicePrincipal = $sp
        SpMissing        = $spMissing
    }
}
function Show-FeatureCoverageReport {
    <#
        Maps the permissions actually on an app registration back onto the feature
        catalog, so an admin can see which product features will work, which are missing
        a permission, and exactly which permission to add.
        Reports against CONSENTED permissions where consent could be read, because that is
        what determines whether a feature works at runtime. Where consent could not be
        read, it falls back to requested and says so rather than implying more certainty
        than it has.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PermissionState,
        [Parameter(Mandatory)][string]$Product
    )
    $features = $Catalog[$Product]
    if (-not $features) { throw "Unknown product '$Product'." }
    $ps = $PermissionState
    # Consent is the real gate. Without it, fall back to what was requested.
    $useConsent = $ps.ConsentReadable -and -not $ps.SpMissing
    $effectiveApp = if ($useConsent) { $ps.ConsentedApp } else { $ps.RequestedApp }
    $effectiveDel = if ($useConsent) { $ps.ConsentedDel } else { $ps.RequestedDel }
    Write-Step "Feature coverage for $Product"
    if ($ps.SpMissing) {
        Write-Warn "This app registration has no enterprise application (service principal)."
        Write-Host "           No permission can be consented until one exists, so nothing below" -ForegroundColor Gray
        Write-Host "           will work yet." -ForegroundColor Gray
        Write-Host ""
    }
    elseif (-not $ps.ConsentReadable) {
        Write-Warn "Consent status could not be read - showing REQUESTED permissions instead."
        Write-Host "           A permission can be requested and never consented, so treat" -ForegroundColor Gray
        Write-Host "           'Available' below as 'requested' rather than confirmed." -ForegroundColor Gray
        Write-Host ""
    }
    else {
        Write-Host "    Based on permissions actually consented in this tenant." -ForegroundColor Gray
        Write-Host ""
    }
    Write-Host ("    {0,-52} {1,-14} {2}" -f 'Feature', 'Status', 'Missing') -ForegroundColor White
    Write-Host ("    {0}" -f ('-' * 110)) -ForegroundColor DarkGray
    $available = 0
    $partial   = 0
    $none      = 0
    $gaps      = New-Object System.Collections.Generic.List[string]
    foreach ($name in $features.Keys) {
        $needApp = @($features[$name].Application)
        $needDel = @($features[$name].Delegated)
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($p in $needApp) { if ($effectiveApp -notcontains $p) { $missing.Add($p) } }
        foreach ($p in $needDel) { if ($effectiveDel -notcontains $p) { $missing.Add("$p (delegated)") } }
        $needCount = $needApp.Count + $needDel.Count
        $haveCount = $needCount - $missing.Count
        if ($missing.Count -eq 0)      { $status = 'Available';     $color = 'Green';    $available++ }
        elseif ($haveCount -gt 0)      { $status = 'Partial';       $color = 'Yellow';   $partial++ }
        else                           { $status = 'Not available'; $color = 'DarkGray'; $none++ }
        # Keep the table readable; the full list goes in the gap summary below.
        $missingText = ''
        if ($missing.Count -gt 0) {
            $missingText = ($missing | Select-Object -First 2) -join ', '
            if ($missing.Count -gt 2) { $missingText += " (+$($missing.Count - 2) more)" }
            foreach ($m in $missing) { if ($gaps -notcontains $m) { $gaps.Add($m) } }
        }
        Write-Host ("    {0,-52} {1,-14} {2}" -f $name, $status, $missingText) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host ("    {0} available, {1} partial, {2} not available" -f $available, $partial, $none) -ForegroundColor White
    # --- Requested but not consented ----------------------------------------
    # The quiet failure mode: the portal shows the permission, the product still fails.
    if ($useConsent) {
        $pendingApp = @($ps.RequestedApp | Where-Object { $ps.ConsentedApp -notcontains $_ })
        $pendingDel = @($ps.RequestedDel | Where-Object { $ps.ConsentedDel -notcontains $_ })
        if ($pendingApp.Count -gt 0 -or $pendingDel.Count -gt 0) {
            Write-Host ""
            Write-Warn "These permissions are requested on the app but NOT consented:"
            $pendingApp | ForEach-Object { Write-Host "             $_" -ForegroundColor Yellow }
            $pendingDel | ForEach-Object { Write-Host "             $_ (delegated)" -ForegroundColor Yellow }
            Write-Host "           Grant admin consent in the portal:" -ForegroundColor Gray
            Write-Host "             App registrations > API permissions > Grant admin consent" -ForegroundColor Gray
        }
    }
    # --- What to add to close the gaps --------------------------------------
    if ($gaps.Count -gt 0) {
        Write-Host ""
        Write-Host "    To enable the features above, add these Graph permissions:" -ForegroundColor White
        $gaps | Sort-Object | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "    App registrations > $($ps.DisplayName) > API permissions >" -ForegroundColor Gray
        Write-Host "    Add a permission > Microsoft Graph, then Grant admin consent." -ForegroundColor Gray
    }
    # --- Permissions present but unused by this product ---------------------
    $catalogPerms = New-Object System.Collections.Generic.List[string]
    foreach ($f in $features.Keys) {
        foreach ($p in $features[$f].Application) { if ($catalogPerms -notcontains $p) { $catalogPerms.Add($p) } }
        foreach ($p in $features[$f].Delegated)   { if ($catalogPerms -notcontains $p) { $catalogPerms.Add($p) } }
    }
    $extra = @($effectiveApp + $effectiveDel | Where-Object { $catalogPerms -notcontains $_ } | Select-Object -Unique)
    if ($extra.Count -gt 0) {
        Write-Host ""
        Write-Host "    Also present, not used by any $Product feature:" -ForegroundColor DarkGray
        $extra | Sort-Object | ForEach-Object { Write-Host "      - $_" -ForegroundColor DarkGray }
        Write-Host "    These may belong to another product or a custom integration." -ForegroundColor DarkGray
    }
    if ($ps.UnknownIds.Count -gt 0) {
        Write-Host ""
        Write-Warn "$($ps.UnknownIds.Count) permission ID(s) could not be resolved to a name."
        Write-Host "           They may be from a non-Graph API or a preview permission." -ForegroundColor Gray
    }
    Write-Host ""
    return [pscustomobject]@{
        Available = $available
        Partial   = $partial
        None      = $none
        Gaps      = @($gaps)
    }
}
function Get-ExistingAppRegistration {
    <#
        Attempts to validate an existing app registration and read its permissions.
        Validation is advisory. The account running this may have no rights in the tenant
        that owns the app - a normal situation when another team created it and supplied
        the credentials. Sign-in failures, authorization failures, and a missing app all
        produce an unverified result rather than terminating the workflow.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [string]$TenantId,
        [switch]$ReuseExisting,
        [switch]$UseDeviceCode
    )
    Write-Step "Validating the existing app registration"
    # --- Sign-in -------------------------------------------------------------
    try {
        $ctx = Connect-GraphForced `
            -Scopes @('Application.Read.All', 'DelegatedPermissionGrant.Read.All') `
            -TenantId $TenantId `
            -ReuseExisting:$ReuseExisting `
            -UseDeviceCode:$UseDeviceCode
    }
    catch {
        # Captured before the prompt below, which would otherwise clobber $_.
        $authError = $_.Exception.Message
        Write-Warn "Microsoft Graph sign-in did not complete."
        Write-Host "           $authError" -ForegroundColor Gray
        Write-Host ""
        Write-Host "           This is expected when the account has no rights in the tenant that" -ForegroundColor Gray
        Write-Host "           owns the app registration - for example when another team created" -ForegroundColor Gray
        Write-Host "           the app and supplied the credentials." -ForegroundColor Gray
        Write-Host "           Configuration can continue with the supplied values." -ForegroundColor Gray
        Write-Host ""
        Write-Host "           To skip the sign-in attempt on future runs, use:" -ForegroundColor Gray
        Write-Host "             -SkipAppValidation" -ForegroundColor Cyan
        return [pscustomobject]@{
            AppId                 = $AppId
            ObjectId              = $null
            DisplayName           = '(not verified)'
            TenantId              = (Resolve-TenantIdFallback -TenantId $TenantId)
            ValidationSucceeded   = $false
            PermissionReadAllowed = $false
            ValidationReason      = $authError
        }
    }
    Write-Ok "Signed in as $($ctx.Account)"
    Write-Host "           Tenant : $($ctx.TenantId)" -ForegroundColor Gray
    # --- Read the app --------------------------------------------------------
    try {
        $app = Get-MgApplication -Filter "appId eq '$AppId'" -ErrorAction Stop |
               Select-Object -First 1
    }
    catch {
        $readError = $_.Exception.Message
        if ($readError -match 'Authorization_RequestDenied|Insufficient privileges|Access is denied|Forbidden|\b403\b') {
            Write-Warn "The signed-in account cannot read this app registration."
            Write-Host "           API permissions and feature coverage cannot be verified." -ForegroundColor Gray
            Write-Host "           This is expected when app ownership and product administration" -ForegroundColor Gray
            Write-Host "           are handled by different teams." -ForegroundColor Gray
            Write-Host "           Configuration will continue using the supplied App ID." -ForegroundColor Gray
        }
        else {
            Write-Warn "The app registration lookup failed."
            Write-Host "           $readError" -ForegroundColor Gray
            Write-Host "           API permissions cannot be verified." -ForegroundColor Gray
        }
        return [pscustomobject]@{
            AppId                 = $AppId
            ObjectId              = $null
            DisplayName           = '(access restricted)'
            TenantId              = $ctx.TenantId
            ValidationSucceeded   = $false
            PermissionReadAllowed = $false
            ValidationReason      = $readError
        }
    }
    # --- Not found -----------------------------------------------------------
    if (-not $app) {
        Write-Warn "The app registration was not visible to the signed-in account."
        Write-Host "           Possible causes:" -ForegroundColor Gray
        Write-Host "             - The Application ID is incorrect" -ForegroundColor Gray
        Write-Host "             - The account is signed into a different tenant" -ForegroundColor Gray
        Write-Host "             - The account cannot read this app registration" -ForegroundColor Gray
        return [pscustomobject]@{
            AppId                 = $AppId
            ObjectId              = $null
            DisplayName           = '(not visible)'
            TenantId              = $ctx.TenantId
            ValidationSucceeded   = $false
            PermissionReadAllowed = $false
            ValidationReason      = 'The app registration was not returned by Microsoft Graph.'
        }
    }
    Write-Ok "Found: $($app.DisplayName)"
    Write-Host "           Object ID : $($app.Id)" -ForegroundColor DarkGray
    return [pscustomobject]@{
        AppId                 = $app.AppId
        ObjectId              = $app.Id
        DisplayName           = $app.DisplayName
        TenantId              = $ctx.TenantId
        ValidationSucceeded   = $true
        PermissionReadAllowed = $true
        ValidationReason      = $null
    }
}
function Invoke-ExistingAppConfiguration {
    <#
    .SYNOPSIS
        Configures a product against an app registration that already exists, skipping
        creation and consent entirely.
    .DESCRIPTION
        Re-running configuration against an app registration created earlier is a normal
        onboarding situation - the app exists, but the RMS service connection or the
        Application Workspace identity source still needs to be created.
        Reads the script-level parameters directly, the same way the main Execute block
        does, rather than taking a fifteen-parameter signature.
        Nothing in this path writes to the app registration. It only reads it (to confirm
        it exists) and then configures the consuming product.
    #>
    [CmdletBinding()]
    param()
    Write-Host ""
    Write-Host "  Existing app registration mode" -ForegroundColor White
    Write-Host "  ------------------------------" -ForegroundColor DarkGray
    Write-Host "  No app registration will be created, modified, or consented." -ForegroundColor Gray
    # --- Guard: contradictory switches --------------------------------------
    if ($CreateClientSecret) {
        throw "-CreateClientSecret cannot be used with -ExistingAppId. This mode never modifies the app registration; supply the existing secret value when prompted."
    }
    # --- Guard: the app id has to look like a GUID --------------------------
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($ExistingAppId, [ref]$parsed)) {
        throw "-ExistingAppId '$ExistingAppId' is not a valid GUID. Use the Application (client) ID from the app registration Overview page."
    }
    $appId = $parsed.ToString()
    # --- Which product? ------------------------------------------------------
    # Inferred from the -Configure* switch when only one was given, because asking again
    # would be redundant.
    if ($ConfigureServiceConnection -and -not $ConfigureIdentitySource) {
        $product = 'Right Click Tools'
    }
    elseif ($ConfigureIdentitySource -and -not $ConfigureServiceConnection) {
        $product = 'Application Workspace'
    }
    else {
        if ($ConfigureServiceConnection -and $ConfigureIdentitySource) {
            Write-Warn "Both -ConfigureServiceConnection and -ConfigureIdentitySource were given."
            Write-Host "           This mode configures one product per run." -ForegroundColor Gray
        }
        $product = Select-Product
    }
    Write-Ok "Target product : $product"
    # --- Confirm the app exists ---------------------------------------------
    $tenantId = $TenantId
    # Tracks whether permissions/feature coverage were actually verified against Graph.
    # Explicitly initialized here (rather than left as an implicit $null in the
    # -SkipAppValidation branch) so both branches set it the same way and neither relies
    # on PowerShell's "-not $null is $true" behaviour for correctness.
    $canValidate = $false
    if ($SkipAppValidation) {
        # -WhatIfOnly in this mode IS the permission report, and the report needs the
        # Graph lookup that -SkipAppValidation suppresses. Combining them would otherwise
        # fall through and configure the product, which is the opposite of -WhatIfOnly.
        if ($WhatIfOnly) {
            throw "-WhatIfOnly cannot be combined with -SkipAppValidation. The coverage report requires reading the app registration from Microsoft Graph."
        }
        Write-Step "Skipping app registration validation (-SkipAppValidation)"
        Write-Warn "The app registration will not be checked before configuring the product."
        Write-Host "           The feature coverage report is also skipped." -ForegroundColor Gray
        if (-not $tenantId) {
            do {
                $tenantId = (Read-Host "    Directory (tenant) ID").Trim()
                $tGuid = [guid]::Empty
                if ($tenantId -and -not [guid]::TryParse($tenantId, [ref]$tGuid)) {
                    Write-Warn "That is not a valid GUID."
                    $tenantId = $null
                }
            } until ($tenantId)
        }
        $appDisplay = '(not validated)'
    }
    else {
        $existing = Get-ExistingAppRegistration -AppId $appId -TenantId $tenantId `
                        -ReuseExisting:$ReuseGraphSession -UseDeviceCode:$UseDeviceCode
        $appId       = $existing.AppId
        $tenantId    = $existing.TenantId
        $appDisplay  = $existing.DisplayName
        $canValidate = $existing.PermissionReadAllowed
        if ($canValidate) {
            try {
                $graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'" -ErrorAction Stop
                if ($graphSp) {
                    $permState = Get-AppRegistrationPermissionState -AppId $appId -GraphSp $graphSp
                    $coverage  = Show-FeatureCoverageReport -PermissionState $permState -Product $product
                    if ($coverage.None -gt 0 -and $coverage.Available -eq 0) {
                        Write-Warn "No $product feature is fully supported by this app registration."
                    }
                }
            }
            catch {
                Write-Warn "Could not build the feature coverage report: $($_.Exception.Message)"
                Write-Host "           Configuration can still proceed." -ForegroundColor Gray
            }
        }
        else {
            Write-Step "Feature coverage"
            Write-Warn "Feature coverage cannot be verified with the signed-in account."
            Write-Host "           Configuration will continue using the supplied values." -ForegroundColor Gray
            Write-Host "           Have the Entra application owner confirm the app holds the" -ForegroundColor Gray
            Write-Host "           permissions required for the selected product features." -ForegroundColor Gray
        }
        # -WhatIfOnly turns this mode into a read-only audit: report and stop.
        if ($WhatIfOnly) {
            if ($canValidate) { Write-Warn "-WhatIfOnly specified. Nothing was configured." }
            else {
                Write-Warn "-WhatIfOnly specified, but permissions could not be read."
                Write-Host "           No feature coverage determination could be made." -ForegroundColor Gray
            }
            return
        }
        if (-not $Force) {
            if (-not $canValidate) {
                if ((Read-Host "`n    Continue without verifying the app registration or permissions? (y/N)") -notmatch '^[Yy]') {
                    throw "Cancelled because the app registration could not be verified."
                }
            }
            elseif ((Read-Host "`n    Configure $product using this app registration? (Y/n)") -match '^[Nn]') {
                throw "Cancelled - wrong app registration."
            }
        }
    }
    # --- Secret --------------------------------------------------------------
    $secretValue = Read-ClientSecretValue
    # --- Configure -----------------------------------------------------------
    if ($product -eq 'Right Click Tools') {
        $rmsServer = $RmsServer
        $rmsPort   = $RmsPort
        $selfSigned = $AllowSelfSignedCertificate
        if (-not $rmsServer) {
            do {
                $rmsServer = (Read-Host "    RMS server (e.g. rms.contoso.com)").Trim()
            } until ($rmsServer)
            $portIn = (Read-Host "    RMS port [$rmsPort]").Trim()
            if ($portIn -match '^\d+$') { $rmsPort = [int]$portIn }
        }
        if (-not $selfSigned -and -not $Force) {
            $selfSigned = (Read-Host "    Allow a self-signed RMS certificate? (y/N)") -match '^[Yy]'
        }
        $connName = (Read-Host "    Service connection name [Entra ID]").Trim()
        if (-not $connName) { $connName = 'Entra ID' }
        $maxAttempts = 3
        $attempt     = 1
        $secretToUse = $secretValue
        # Attempt 1: the full flow - connect, list proxies, pick proxy, duplicate check,
        # create-or-update, test.
        $rmsResult = Add-RmsAzureAdServiceConnection -Server $rmsServer -Port $rmsPort `
            -Name $connName -TenantId $tenantId -ClientId $appId -ClientSecret $secretToUse `
            -AllowSelfSignedCertificate:$selfSigned `
            -SkipCredentialValidation:(-not $canValidate) `
            -TestAfterCreate
        while ($true) {
            if (-not $rmsResult -or $null -eq $rmsResult.TestOutcome -or $null -eq $rmsResult.TestOutcome.Success) {
                break   # nothing testable to retry against
            }
            if ($rmsResult.TestOutcome.Success) {
                Write-Ok "Service connection verified working."
                break
            }
            if (-not $rmsResult.ConnectionId) {
                Write-Warn "Cannot retry automatically - the connection ID was not captured."
                Write-Host "    Fix manually: Administration > Service Connections > Edit" -ForegroundColor Gray
                break
            }
            $guidance = Get-RmsAuthFailureGuidance -Message $rmsResult.TestOutcome.Message
            Write-Host ""
            if ($guidance.Hint) { Write-Warn $guidance.Hint }
            if (-not $guidance.Retryable -or $attempt -ge $maxAttempts) {
                if ($attempt -ge $maxAttempts) { Write-Warn "Reached $maxAttempts attempts - stopping to avoid tripping Entra's lockout." }
                Invoke-RmsFailedConnectionCleanup -BaseUri $rmsResult.BaseUri -ConnectionId $rmsResult.ConnectionId `
                    -AllowSelfSignedCertificate:$selfSigned -Force:$Force | Out-Null
                break
            }
            if ((Read-Host "    Re-enter the client secret and try again? (Y/n)") -match '^[Nn]') {
                Invoke-RmsFailedConnectionCleanup -BaseUri $rmsResult.BaseUri -ConnectionId $rmsResult.ConnectionId `
                    -AllowSelfSignedCertificate:$selfSigned -Force:$Force | Out-Null
                break
            }
            $secretToUse = Read-ClientSecretValue
            $attempt++
            # Retries go straight to Update on the connection ID from attempt 1 - the
            # confirmed working path - instead of re-running proxy selection and the
            # duplicate check again through Add-RmsAzureAdServiceConnection.
            $rmsResult = Repair-RmsServiceConnectionSecret -BaseUri $rmsResult.BaseUri `
                -ConnectionId $rmsResult.ConnectionId -Name $connName `
                -TenantId $tenantId -ClientId $appId -ClientSecret $secretToUse `
                -ProxyCertificate $rmsResult.ProxyCertificate `
                -AllowSelfSignedCertificate:$selfSigned
        }
    }
    else {
        # The identity source settings normally come from the feature catalog. There is no
        # catalog selection in this mode, so ask directly - or take the switches as given
        # when -Force signals an unattended run.
        $wantPhotos     = [bool]$EnableAzurePhotos
        $wantGroupWrite = [bool]$EnableGroupWrite
        $wantMail       = [bool]$ConfigureMailServer
        if (-not $Force) {
            Write-Host ""
            Write-Host "    These map to permissions the app registration may already hold." -ForegroundColor Gray
            Write-Host "    Enable only what it was actually granted." -ForegroundColor Gray
            $defPhotos = if ($wantPhotos)     { 'Y/n' } else { 'y/N' }
            $defGroup  = if ($wantGroupWrite) { 'Y/n' } else { 'y/N' }
            $defMail   = if ($wantMail)       { 'Y/n' } else { 'y/N' }
            $ansPhotos = (Read-Host "    Sync user profile photos?            ($defPhotos)").Trim()
            if ($ansPhotos) { $wantPhotos = $ansPhotos -match '^[Yy]' }
            $ansGroup = (Read-Host "    Allow group editing from Workspace?  ($defGroup)").Trim()
            if ($ansGroup) { $wantGroupWrite = $ansGroup -match '^[Yy]' }
            $ansMail = (Read-Host "    Create a Microsoft Graph mail server? ($defMail)").Trim()
            if ($ansMail) { $wantMail = $ansMail -match '^[Yy]' }
        }
        $identitySourceOk = $false
        try {
            New-AwEntraIdentitySource -TenantId $tenantId `
                -ClientId $appId -ClientSecret $secretValue `
                -Name $IdentitySourceName -DisplayName $IdentitySourceDisplayName `
                -ZoneUri $ZoneUrl -ZoneCredential $ZoneCredential `
                -ModulePath $AwModulePath `
                -EnablePhotos $wantPhotos -EnableGroupWrite $wantGroupWrite `
                -Force:$Force
            $identitySourceOk = $true
        }
        catch {
            # A deliberate cleanup delete is expected, not a failure - keep $identitySourceOk
            # $false (so the mail server step is skipped) but don't print the failure banner.
            if ($script:LastIdentitySourceSyncResult -and $script:LastIdentitySourceSyncResult.Deleted) {
                Write-Host "    Identity source removed - skipping the remaining Application Workspace steps." -ForegroundColor Gray
            }
            else {
                Write-Err "Identity source creation failed: $($_.Exception.Message)"
                Write-Warn "The app registration is fine. Add the identity source manually:"
                Write-Host "           Manage > Identity Sources > Create > Microsoft Entra ID" -ForegroundColor Gray
            }
        }
        # $identitySourceOk is sufficient on its own. New-AwEntraIdentitySource only
        # throws (leaving this $false) on a CONFIRMED sync failure - a confirmed success
        # and an unverified/timed-out sync both fall through to $true. A timeout is
        # treated as "probably still syncing in the background," which is grounds to
        # proceed with the mail server, not to withhold it.
        if ($wantMail -and $identitySourceOk) {
            try {
                New-AwGraphMailServer -TenantId $tenantId `
                    -ClientId $appId -ClientSecret $secretValue `
                    -Name $MailServerName -From $MailServerFrom | Out-Null
            }
            catch {
                Write-Err "Mail server creation failed: $($_.Exception.Message)"
                Write-Warn "Add it manually: Manage > Mail Servers > Create > Microsoft Graph"
            }
        }
        elseif ($wantMail -and -not $identitySourceOk) {
            if (-not ($script:LastIdentitySourceSyncResult -and $script:LastIdentitySourceSyncResult.Deleted)) {
                Write-Warn "Skipping mail server creation - identity source creation failed."
            }
        }
    }
    # --- Summary -------------------------------------------------------------
    Write-Host ""
    Write-Host "  ===========================================================" -ForegroundColor Green
    Write-Host "   Configuration complete" -ForegroundColor Green
    Write-Host "  ===========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Product                  : $product"
    Write-Host "   App registration         : $appDisplay"
    Write-Host "   Application (client) ID  : $appId"
    Write-Host "   Directory (tenant) ID    : $tenantId"
    Write-Host ""
    Write-Host "   The app registration itself was not modified." -ForegroundColor Gray
    Write-Host ""
}
function Wait-LiquitTaskChecked {
    <#
        Classifies a task outcome as Success / Failed / Unverified.

        Takes the STATE STRING and the RESULT DICTIONARY as separate, already-captured
        values rather than the live $Task object. Task.State was confirmed to sometimes
        disagree with itself between two reads a few lines apart on the same object -
        almost certainly because it is a live/remote-backed property, not a static
        snapshot. Reading it exactly once, at the earliest possible point, and threading
        that frozen value through is the only reliable fix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$State,
        $Result
    )
    $state = "$State".Trim()

    # --- Confirmed success, checked BEFORE .Result is ever inspected ------------
    if ($state -eq 'Success') {
        return [pscustomobject]@{ Success = $true; ErrorMessage = $null }
    }

    # --- Confirmed failure --------------------------------------------------------
    if ($state -eq 'Failed' -or $state -match 'Fail') {
        $errMsg = $null
        if ($Result -and $Result.ContainsKey('error') -and $Result['error']) {
            $errObj = $Result['error']
            if ($errObj -is [System.Collections.IDictionary]) {
                $parts = @()
                if ($errObj.ContainsKey('code'))    { $parts += "$($errObj['code'])" }
                if ($errObj.ContainsKey('message')) { $parts += "$($errObj['message'])" }
                $errMsg = $parts -join ': '
            }
            else { $errMsg = "$errObj" }
        }
        if (-not $errMsg) { $errMsg = 'Task reported a failed state with no error detail.' }
        return [pscustomobject]@{ Success = $false; ErrorMessage = $errMsg }
    }

    # --- Anything else: genuinely unresolved, not a guess in either direction ----
    return [pscustomobject]@{ Success = $null; ErrorMessage = "Task state '$state' is not a recognized outcome." }
}
function Get-AwSyncFailureGuidance {
    <# Mirrors Get-RmsAuthFailureGuidance. Consent problems are not fixed by retyping a secret. #>
    param([string]$Message)
    if ($Message -match 'AADSTS7000215') {
        return [pscustomobject]@{ Retryable = $true; Hint = "The secret VALUE was rejected - likely the Secret ID was entered instead." }
    }
    if ($Message -match 'AADSTS7000222') {
        return [pscustomobject]@{ Retryable = $true; Hint = "The client secret has expired. Add a new one under Certificates & secrets." }
    }
    if ($Message -match 'AADSTS700016|AADSTS90002|AADSTS900023') {
        return [pscustomobject]@{ Retryable = $true; Hint = "Tenant or Application ID was not recognized. Confirm both values." }
    }
    if ($Message -match 'AADSTS65001|consent') {
        return [pscustomobject]@{ Retryable = $false; Hint = "Admin consent has not been granted. Re-entering the secret will not fix this." }
    }
    return [pscustomobject]@{ Retryable = $false; Hint = $null }
}
function Sync-AwIdentitySourceChecked {
    <#
        Triggers an identity source sync and verifies it actually succeeded, bounded by
        Wait-LiquitTask's own -Timeout so a slow-but-legitimate sync does not block the
        whole script waiting for something that was never going to fail.
        A result that is still unresolved when the timeout is hit is assumed to be a
        normal sync running longer than the window, not a stuck or failing one - real
        failures (bad secret, wrong tenant) have been observed to surface well inside the
        timeout. So an unverified result returns immediately without retrying or
        prompting; only a CONFIRMED failure (bad secret, wrong tenant/client) offers a
        retry, and only exhausting retries or a non-retryable failure (consent) offers to
        delete the identity source this run created - mirroring the RMS side, where
        leaving a known-broken connection behind is worse than removing it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$MaxAttempts = 3,
        [int]$TimeoutSeconds = 20,
        [switch]$Force
    )
    $attempt = 0
    while ($true) {
        $attempt++
        $source = Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue
        if (-not $source) {
            Write-Err "Identity source '$Name' could not be read back before syncing."
            return [pscustomobject]@{ Success = $false; Message = 'Identity source not found.' }
        }
        Write-Step "Synchronizing identity source '$Name' (attempt $attempt of $MaxAttempts, up to $TimeoutSeconds sec)"

        # Timed independently of Wait-LiquitTask's own -Timeout, so the messaging below
        # can tell "genuinely hit the full timeout" apart from "resolved almost
        # immediately with a state we don't yet trust" - those two cases previously
        # printed near-identical text, which read as if the timeout was being ignored
        # when it was not.
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $task    = $source | Update-LiquitIdentitySource -ErrorAction Stop
            $waited  = $task | Wait-LiquitTask -Timeout $TimeoutSeconds -ErrorAction Stop

            # Read State and Result EXACTLY ONCE, immediately after the single
            # Wait-LiquitTask call, and never call Wait-LiquitTask a second time on the
            # same $task - confirmed that doing so re-waits rather than re-reading, and
            # can silently overwrite a genuinely successful $waited with a different
            # result from waiting on an already-completed task a second time.
            $capturedState  = "$($waited.State)"
            $capturedResult = $waited.Result

            $outcome = Wait-LiquitTaskChecked -State $capturedState -Result $capturedResult
        }
        catch {
            if ($_.Exception.Message -match 'timeout|timed out') {
                Write-Warn "No result within $TimeoutSeconds seconds - continuing without blocking further."
                Write-Host "           Likely still running normally. Check later: Manage > Identity Sources > $Name" -ForegroundColor Gray
                return [pscustomobject]@{ Success = $null; Message = 'Timed out waiting.' }
            }
            Write-Err "Sync request failed: $($_.Exception.Message)"
            return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
        }
        finally {
            $stopwatch.Stop()
        }

        if ($null -eq $outcome.Success) {
            $elapsed = $stopwatch.Elapsed.TotalSeconds
            # Wait-LiquitTask's -Timeout is a ceiling, not a fixed wait - it returns as
            # soon as the task reaches a terminal state. Resolving in under a second is
            # correct behavior, not a sign the timeout was ignored.
            if ($elapsed -ge ($TimeoutSeconds * 0.9)) {
                Write-Warn "No confirmed result after waiting the full $TimeoutSeconds sec."
                Write-Host "           Failures are expected to surface faster than this, so this is" -ForegroundColor Gray
                Write-Host "           assumed to be a normal sync still running, not a stuck one." -ForegroundColor Gray
            }
            else {
                Write-Warn "Sync returned in $([math]::Round($elapsed, 1))s with an unrecognized state: $($outcome.ErrorMessage)"
                Write-Host "           This is not a timeout - the task finished quickly, but its state" -ForegroundColor Gray
                Write-Host "           is not yet on the confirmed-success list. Treating it as unverified." -ForegroundColor Gray
            }
            Write-Host "           Continuing without waiting further. Check later: Manage > Identity Sources > $Name" -ForegroundColor Gray
            return [pscustomobject]@{ Success = $null; Message = $outcome.ErrorMessage }
        }

        # --- Confirmed success --------------------------------------------------
        # Wait-LiquitTaskChecked returns Success = $true only for a terminal 'Success'
        # state. Without this branch a genuine success falls through to the failure
        # handling below (true is not $null, so the unverified check above does not catch
        # it), which is what produced the false "Synchronization failed" report.
        if ($outcome.Success) {
            Write-Ok "Identity source '$Name' synchronized successfully."
            return [pscustomobject]@{ Success = $true; Message = $null }
        }

        $detail = if ($outcome.ErrorMessage) { $outcome.ErrorMessage } else { 'Sync task reported failure with no error detail.' }
        Write-Err "Synchronization failed: $detail"
        $guidance = Get-AwSyncFailureGuidance -Message $detail
        if ($guidance.Hint) { Write-Warn $guidance.Hint }
        $giveUp = (-not $guidance.Retryable) -or ($attempt -ge $MaxAttempts)
        if (-not $giveUp -and -not $Force) {
            if ((Read-Host "    Re-enter the client secret and try again? (Y/n)") -match '^[Nn]') { $giveUp = $true }
        }
        elseif (-not $giveUp -and $Force) {
            $giveUp = $false   # unattended: keep retrying up to MaxAttempts without asking
        }
        if ($giveUp) {
            if ($attempt -ge $MaxAttempts) { Write-Warn "Reached $MaxAttempts attempts - stopping to avoid tripping Entra's lockout." }
            # Capture the cleanup outcome instead of piping it to Out-Null. When the user
            # chooses to delete the unverified source, it is gone BY DESIGN - the caller
            # uses this flag to stay quiet rather than reporting a sync "failure" against a
            # source that no longer exists, which is expected, not a real problem.
            # Capturing into a variable (rather than letting the bare boolean fall into the
            # output stream) also keeps $syncResult a single object at the call site,
            # preserving the "-eq $false" check in New-AwEntraIdentitySource.
            $deleted = [bool](Invoke-AwFailedIdentitySourceCleanup -Name $Name -Force:$Force)
            return [pscustomobject]@{ Success = $false; Message = $detail; Deleted = $deleted }
        }
        $newSecret = Read-ClientSecretValue
        try {
            $source | Set-LiquitIdentitySource -ClientSecret $newSecret -ErrorAction Stop | Out-Null
            Write-Ok "Client secret updated on '$Name'."
        }
        catch {
            Write-Err "Could not update the client secret: $($_.Exception.Message)"
            return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
        }
        # loop back around and re-sync
    }
}
function Invoke-AwFailedIdentitySourceCleanup {
    <#
        Offers to delete an identity source that failed to sync and will not be
        corrected in this run. Mirrors Invoke-RmsFailedConnectionCleanup: a known-broken
        identity source left in place looks legitimate in the UI until an end user tries
        to sign in through it and hits a confusing failure with none of today's context.
        Verifies the delete by reading the source back afterward rather than trusting
        Remove-LiquitIdentitySource's own reported outcome, consistent with every other
        destructive action in this script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force
    )
    Write-Host ""
    if (-not $Force) {
        $choice = Read-Host "    Delete this unverified identity source ('$Name') instead? (y/N)"
        if ($choice -notmatch '^[Yy]') {
            Write-Warn "Left in place. Fix manually: Manage > Identity Sources > $Name > Edit"
            return $false
        }
    }
    $source = Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue
    if (-not $source) {
        Write-Warn "Identity source '$Name' was not found - nothing to delete."
        return $true
    }
    try {
        $source | Remove-LiquitIdentitySource -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Err "Could not delete identity source '$Name': $($_.Exception.Message)"
        Write-Host "           Remove it manually: Manage > Identity Sources > $Name > Delete" -ForegroundColor Gray
        return $false
    }
    if (Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue) {
        Write-Err "Delete reported success, but '$Name' is still present."
        Write-Host "           Remove it manually: Manage > Identity Sources > $Name > Delete" -ForegroundColor Gray
        return $false
    }
    Write-Ok "Identity source '$Name' deleted."
    return $true
}
#endregion
#region ------------------------------------------------------------- Execute
try {
    Write-Host ""
    Write-Host "  Recast Entra App Registration Builder" -ForegroundColor White
    Write-Host "  -------------------------------------" -ForegroundColor DarkGray
    Test-Prerequisites
    # --- Existing app registration mode -------------------------------------
    # Skips creation, permissions, and consent entirely and goes straight to configuring
    # the consuming product. Returns before any of the creation flow below runs.
    if ($ExistingAppId) {
        Invoke-ExistingAppConfiguration
        return
    }
    $product  = Select-Product
    $features = Select-Features -Product $product
    $permSet  = Get-PermissionSet -Product $product -Features $features
    Write-Step "Resolved Graph permission set"
    if ($permSet.Application) {
        Write-Host "    Application permissions:" -ForegroundColor White
        $permSet.Application | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
    }
    if ($permSet.Delegated) {
        Write-Host "    Delegated permissions:" -ForegroundColor White
        $permSet.Delegated | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
    }
    if ($WhatIfOnly) {
        Write-Host ""
        Write-Warn "-WhatIfOnly specified. No changes made to the tenant."
        return
    }
    # --- Name + product-specific input -------------------------------------
    if (-not $DisplayName) {
        $default = $ProductDefaults[$product].DisplayName
        $entered = Read-Host "`n    App registration display name [$default]"
        $DisplayName = if ([string]::IsNullOrWhiteSpace($entered)) { $default } else { $entered.Trim() }
    }
    if ($product -eq 'Application Workspace' -and -not $ZoneUrl) {
        Write-Host ""
        Write-Host "    Your Application Workspace zone URL was sent in the follow-up email after" -ForegroundColor Gray
        Write-Host "    your Prerequisite call. Ask your onboarding manager if you do not have it." -ForegroundColor Gray
        do {
            $ZoneUrl = (Read-Host "    Zone URL (e.g. https://contoso.recastsoftware.cloud)").Trim()
            if ($ZoneUrl -notmatch '^https://') { Write-Warn "The zone URL must start with https://" ; $ZoneUrl = $null }
        } until ($ZoneUrl)
    }
    # --- Connect ------------------------------------------------------------
    # Prompts every run by default. See Connect-GraphForced for why a cached token would
    # otherwise let this target whichever tenant was used last, with no prompt at all.
    $ctx = Connect-GraphForced -Scopes $ConnectScopes -TenantId $TenantId `
                               -ReuseExisting:$ReuseGraphSession `
                               -UseDeviceCode:$UseDeviceCode
    Write-Ok "Signed in as $($ctx.Account)"
    Write-Host "           Tenant : $($ctx.TenantId)" -ForegroundColor Gray
    # An app registration created in the wrong tenant is a costly mistake to unpick, so
    # confirm the target before anything is written. -Force skips the check.
    if (-not $Force) {
        if ((Read-Host "`n    Create the app registration in THIS tenant? (Y/n)") -match '^[Nn]') {
            throw "Cancelled - wrong tenant. Re-run and sign in with the correct account."
        }
    }
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'" -ErrorAction Stop
    if (-not $graphSp) { throw "Could not locate the Microsoft Graph service principal in this tenant." }
    $resolved = Resolve-GraphPermissions -GraphSp $graphSp `
                    -ApplicationPermissions $permSet.Application `
                    -DelegatedPermissions   $permSet.Delegated
    # --- Duplicate name check ----------------------------------------------
    $existingApp = Get-MgApplication -Filter "displayName eq '$($DisplayName -replace "'","''")'" -ErrorAction SilentlyContinue
    if ($existingApp) {
        Write-Warn "An app registration named '$DisplayName' already exists (AppId $($existingApp[0].AppId))."
        if ((Read-Host "    Create another with the same name? (y/N)") -notmatch '^[Yy]') {
            throw "Cancelled - duplicate display name."
        }
    }
    # --- Build the application object ---------------------------------------
    Write-Step "Creating app registration '$DisplayName'"
    $appBody = @{
        DisplayName            = $DisplayName
        SignInAudience         = 'AzureADMyOrg'   # single tenant
        RequiredResourceAccess = @(
            @{
                ResourceAppId  = $GraphAppId
                ResourceAccess = @($resolved.ResourceAccess)
            }
        )
    }
    $redirect = $null
    if ($product -eq 'Application Workspace' -and $ZoneUrl) {
        $redirect = "$($ZoneUrl.TrimEnd('/'))/api/auth/token/end"
        $appBody['Web'] = @{ RedirectUris = @($redirect) }
    }
    $app = New-MgApplication -BodyParameter $appBody -ErrorAction Stop
    Write-Ok "Application (client) ID : $($app.AppId)"
    Write-Ok "Object ID               : $($app.Id)"
    # --- Public client platform (Right Click Tools) --------------------------
    #
    # The WAM broker redirect URI and "Allow public client flows" only matter for
    # delegated sign-in, where the tool acts as the signed-in admin and needs an
    # interactive token from the Windows token broker.
    #
    # Application-permission tools (client ID + secret, no user) never use a redirect
    # URI at all, so adding it there is dead configuration.
    #
    # Right now the only RCT feature with delegated scopes is Entra ID BitLocker
    # Recovery Keys - Microsoft deliberately provides no application-permission
    # equivalent, because retrieving a recovery key has to be attributable to a person.
    # Rather than hardcode that one feature, key off the resolved permission set, so any
    # future delegated feature picks this up automatically.
    if ($product -eq 'Right Click Tools') {
        if ($permSet.Delegated.Count -gt 0) {
            $brokerUri = "ms-appx-web://microsoft.aad.brokerplugin/$($app.AppId)"
            Write-Step "Configuring public client platform for Right Click Tools"
            Write-Host "    Required because these delegated permissions need interactive sign-in:" -ForegroundColor Gray
            $permSet.Delegated | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
            # The broker URI embeds the AppId, so this can only run after the app exists.
            Update-MgApplication -ApplicationId $app.Id -BodyParameter @{
                PublicClient           = @{ RedirectUris = @($brokerUri) }
                IsFallbackPublicClient = $true
            } -ErrorAction Stop
            Write-Ok "Redirect URI : $brokerUri"
            Write-Ok "Allow public client flows : enabled"
        }
        else {
            Write-Step "Public client platform"
            Write-Ok "Not required - every selected feature uses application permissions only"
            Write-Host "           The WAM broker redirect URI and public client flows are only" -ForegroundColor Gray
            Write-Host "           needed for delegated sign-in, e.g. Entra ID BitLocker Recovery" -ForegroundColor Gray
            Write-Host "           Keys. Re-run with that feature selected if you add it later." -ForegroundColor Gray
        }
    }
    elseif ($redirect) {
        Write-Ok "Web redirect URI : $redirect"
    }
    # --- Service principal ---------------------------------------------------
    Write-Step "Creating the enterprise application (service principal)"
    # Non-fatal. Without this the app registration exists but the operator sees only an
    # error - an orphaned app they may not know about.
    $sp = $null
    try {
        $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
        Write-Ok "Service principal object ID : $($sp.Id)"
        Start-Sleep -Seconds 10   # let replication settle before consenting
    }
    catch {
        Write-Warn "Enterprise application could not be created: $($_.Exception.Message)"
        Write-Host "           The app registration exists, but no permission can be consented" -ForegroundColor Gray
        Write-Host "           until an enterprise application exists for it." -ForegroundColor Gray
    }
    # --- Consent -------------------------------------------------------------
    if ($SkipConsent) {
        Write-Step "Admin consent"
        Write-Warn "-SkipConsent specified. Permissions are staged but NOT consented."
        Write-Host "           Have a Privileged Role Administrator click 'Grant admin consent' in the portal." -ForegroundColor Gray
    }
    elseif (-not $sp) {
        Write-Step "Admin consent"
        Write-Warn "Skipped - no enterprise application exists to assign permissions to."
    }
    else {
        Write-Step "Granting tenant-wide admin consent"
        Grant-AdminConsent -AppServicePrincipal $sp -GraphSp $graphSp -Resolved $resolved
    }
    # --- Client secret -------------------------------------------------------
    $secretValue  = $null
    $secretExpiry = $null
    if (-not $CreateClientSecret) {
        if ((Read-Host "`n    Create a client secret now? (y/N)") -match '^[Yy]') { $CreateClientSecret = $true }
    }
    if ($CreateClientSecret) {
        Write-Step "Creating client secret ($SecretMonths month lifetime)"
        $secretExpiry = (Get-Date).AddMonths($SecretMonths)
        # Non-fatal. The app registration and consent already succeeded; a secret failure
        # should not report the whole run as failed. Downstream configuration is already
        # gated on $secretValue and falls back to printing manual steps.
        try {
            $pw = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{
                DisplayName = $ProductDefaults[$product].SecretDisplayName
                EndDateTime = $secretExpiry
            } -ErrorAction Stop
            $secretValue = $pw.SecretText
            Write-Ok "Secret created, expires $($secretExpiry.ToString('yyyy-MM-dd'))"
        }
        catch {
            $secretExpiry = $null
            Write-Warn "Client secret could not be created: $($_.Exception.Message)"
            Write-Host "           The app registration itself is fine. Add a secret under" -ForegroundColor Gray
            Write-Host "           Certificates & secrets, then re-run with -ExistingAppId." -ForegroundColor Gray
        }
    }
    # --- Summary -------------------------------------------------------------
    Write-Host ""
    Write-Host "  ===========================================================" -ForegroundColor Green
    Write-Host "   App registration created" -ForegroundColor Green
    Write-Host "  ===========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Product                  : $product"
    Write-Host "   Display name             : $DisplayName"
    Write-Host "   Application (client) ID  : $($app.AppId)"
    Write-Host "   Directory (tenant) ID    : $($ctx.TenantId)"
    if ($redirect) {
        Write-Host "   Web redirect URI         : $redirect"
    }
    if ($secretValue) {
        Write-Host ""
        Write-Host "   Client secret value      : $secretValue" -ForegroundColor Yellow
        Write-Host "   ^ This is the secret value, not the Secret ID. It is shown once." -ForegroundColor Yellow
        Write-Host "     Copy it into your password vault now." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Secret expires           : $($secretExpiry.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow
        Write-Host "   ^ Set a reminder ahead of this date. If it expires, end users cannot" -ForegroundColor Yellow
        Write-Host "     authenticate through Single Sign On until the secret is replaced." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "   Features enabled:"
    $features | ForEach-Object { Write-Host "     - $_" }
    Write-Host ""
    Write-Host "   Graph permissions applied:"
    $permSet.Application | ForEach-Object { Write-Host "     - $_  (Application)" }
    $permSet.Delegated   | ForEach-Object { Write-Host "     - $_  (Delegated)" }
    Write-Host ""
    # --- Optional: wire the app registration into its product ----------------
    #
    # Both paths need the client secret VALUE, which only exists in memory right now.
    # If no secret was created there is nothing to configure with, so don't offer it.
    if (-not $secretValue) {
        if ($product -eq 'Application Workspace') {
            Write-Host "   Next step: add the Identity Source in Application Workspace" -ForegroundColor Cyan
            Write-Host "     Manage > Identity Sources > Create > Microsoft Entra ID" -ForegroundColor Gray
            Write-Host "     You will need the Application (client) ID, Directory (tenant) ID," -ForegroundColor Gray
            Write-Host "     and a client secret value." -ForegroundColor Gray
            Write-Host ""
        }
        else {
            Write-Host "   Next step: add the Entra ID service connection in RMS" -ForegroundColor Cyan
            Write-Host "     Administration > Service Connections > Add service connection" -ForegroundColor Gray
            Write-Host ""
        }
        Write-Warn "No client secret was created, so automatic configuration was skipped."
    }
    elseif ($product -eq 'Right Click Tools') {
        $doRms = $ConfigureServiceConnection
        if (-not $doRms) {
            Write-Host "   Next step: add the Entra ID service connection in RMS" -ForegroundColor Cyan
            $doRms = (Read-Host "`n    Create the RMS service connection now? (y/N)") -match '^[Yy]'
        }
        if ($doRms) {
            try {
                if (-not $RmsServer) {
                    do {
                        $RmsServer = (Read-Host "    RMS server (e.g. rms.contoso.com)").Trim()
                    } until ($RmsServer)
                    $portIn = (Read-Host "    RMS port [$RmsPort]").Trim()
                    if ($portIn -match '^\d+$') { $RmsPort = [int]$portIn }
                }
                if (-not $AllowSelfSignedCertificate) {
                    $AllowSelfSignedCertificate = (Read-Host "    Allow a self-signed RMS certificate? (y/N)") -match '^[Yy]'
                }
                $connName = (Read-Host "    Service connection name [Entra ID]").Trim()
                if (-not $connName) { $connName = 'Entra ID' }
                # Uses the same confirmed-working RMS pipeline (create, pre-flight test,
                # post-create test) as the -ExistingAppId path via Add-RmsAzureAdServiceConnection.
                # Unlike that path, a fresh app + fresh secret was just created here, so a
                # multi-attempt retry loop is not offered - this is the first and only
                # secret the operator has, and a failure here is far more likely to mean a
                # transient replication delay than a mistyped secret. On failure, the
                # catch below prints the manual next steps.
                Add-RmsAzureAdServiceConnection -Server $RmsServer -Port $RmsPort `
                    -Name $connName `
                    -TenantId $ctx.TenantId -ClientId $app.AppId -ClientSecret $secretValue `
                    -AllowSelfSignedCertificate:$AllowSelfSignedCertificate `
                    -TestAfterCreate | Out-Null
            }
            catch {
                Write-Err "RMS service connection failed: $($_.Exception.Message)"
                # .Exception.Message alone names no line and no type, which is not enough
                # to diagnose a .NET binding error. Dump the type, failing line, and stack.
                Write-Host ""
                Write-Host "    --- error detail ---------------------------------------" -ForegroundColor DarkGray
                Write-Host "     Type       : $($_.Exception.GetType().FullName)" -ForegroundColor DarkGray
                if ($_.InvocationInfo) {
                    Write-Host "     At line    : $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
                    if ($_.InvocationInfo.Line) {
                        Write-Host "     Statement  : $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
                    }
                }
                if ($_.Exception.InnerException) {
                    Write-Host "     Inner      : $($_.Exception.InnerException.Message)" -ForegroundColor DarkGray
                }
                if ($_.ScriptStackTrace) {
                    Write-Host "     Stack:" -ForegroundColor DarkGray
                    foreach ($frame in @($_.ScriptStackTrace -split "`n" | Select-Object -First 6)) {
                        Write-Host "       $($frame.Trim())" -ForegroundColor DarkGray
                    }
                }
                Write-Host "    --------------------------------------------------------" -ForegroundColor DarkGray
                Write-Host ""
                Write-Warn "The app registration is fine. Add the service connection manually:"
                Write-Host "           Administration > Service Connections > Add service connection" -ForegroundColor Gray
                Write-Host "           Or re-run with -ExistingAppId '$($app.AppId)' -ConfigureServiceConnection" -ForegroundColor Gray
                Write-Host "           to get the retry-on-failure flow." -ForegroundColor Gray
            }
        }
    }
    elseif ($product -eq 'Application Workspace') {
        $doIs = $ConfigureIdentitySource
        if (-not $doIs) {
            Write-Host "   Next step: add the Identity Source in Application Workspace" -ForegroundColor Cyan
            $doIs = (Read-Host "`n    Create the Entra ID identity source now? (y/N)") -match '^[Yy]'
        }
        if ($doIs) {
            # Derive the identity source settings from the features actually selected, so a
            # consented permission is switched on rather than left dormant.
            $wantPhotos     = $features -contains 'AW - User profile photos (not for large tenants)'
            $wantGroupWrite = $features -contains 'AW - Group editing from within Workspace'
            $wantMail       = $features -contains 'AW - Email notifications sent via Graph'
            $identitySourceOk = $false
            try {
                # ZoneUrl was already collected for the app registration's redirect URI,
                # so reuse it rather than asking for the same value twice.
                New-AwEntraIdentitySource -TenantId $ctx.TenantId `
                    -ClientId $app.AppId -ClientSecret $secretValue `
                    -Name $IdentitySourceName -DisplayName $IdentitySourceDisplayName `
                    -ZoneUri $ZoneUrl -ZoneCredential $ZoneCredential `
                    -ModulePath $AwModulePath `
                    -EnablePhotos $wantPhotos -EnableGroupWrite $wantGroupWrite `
                    -Force:$Force
                $identitySourceOk = $true
            }
            catch {
                # A deliberate cleanup delete is expected, not a failure - keep
                # $identitySourceOk $false (so mail server is skipped) but stay quiet.
                if ($script:LastIdentitySourceSyncResult -and $script:LastIdentitySourceSyncResult.Deleted) {
                    Write-Host "    Identity source removed - skipping the remaining Application Workspace steps." -ForegroundColor Gray
                }
                else {
                    Write-Err "Identity source creation failed: $($_.Exception.Message)"
                    Write-Warn "The app registration is fine. Add the identity source manually:"
                    Write-Host "           Manage > Identity Sources > Create > Microsoft Entra ID" -ForegroundColor Gray
                }
            }
            # $identitySourceOk alone is sufficient, since New-AwEntraIdentitySource only
            # throws on a confirmed sync failure (see the identical comment on the
            # -ExistingAppId path in Invoke-ExistingAppConfiguration).
            if ($wantMail -and $identitySourceOk) {
                try {
                    New-AwGraphMailServer -TenantId $ctx.TenantId `
                        -ClientId $app.AppId -ClientSecret $secretValue `
                        -Name $MailServerName -From $MailServerFrom | Out-Null
                }
                catch {
                    Write-Err "Mail server creation failed: $($_.Exception.Message)"
                    Write-Warn "Add it manually: Manage > Mail Servers > Create > Microsoft Graph"
                }
            }
            elseif ($wantMail -and -not $identitySourceOk) {
                if (-not ($script:LastIdentitySourceSyncResult -and $script:LastIdentitySourceSyncResult.Deleted)) {
                    Write-Warn "Skipping mail server creation - identity source creation failed."
                }
            }
        }
    }
    # --- Optional artifact ----------------------------------------------------
    if ((Read-Host "    Write a summary file to the current directory? (y/N)") -match '^[Yy]') {
        $outFile = Join-Path (Get-Location) ("RecastAppReg_{0}_{1}.txt" -f ($product -replace '\s',''), (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $lines = @(
            "Recast Entra App Registration"
            "Created            : $(Get-Date -Format 'u')"
            "Created by         : $($ctx.Account)"
            "Product            : $product"
            "Display name       : $DisplayName"
            "Application ID     : $($app.AppId)"
            "Tenant ID          : $($ctx.TenantId)"
            "Object ID          : $($app.Id)"
            "Consent granted    : $(-not $SkipConsent)"
        )
        if ($redirect)     { $lines += "Web redirect URI   : $redirect" }
        if ($secretExpiry) { $lines += "Secret expires     : $($secretExpiry.ToString('yyyy-MM-dd'))" }
        $lines += @(
            ""
            "Features:"
            ($features | ForEach-Object { "  - $_" })
            ""
            "Application permissions:"
            ($permSet.Application | ForEach-Object { "  - $_" })
            ""
            "Delegated permissions:"
            ($permSet.Delegated | ForEach-Object { "  - $_" })
            ""
            "Note: the client secret value is intentionally not written to this file."
            "      Store it in your password vault."
        )
        # A read-only working directory should not turn a successful run into a failure
        # at the very last step.
        try {
            $lines | Out-File -FilePath $outFile -Encoding UTF8 -ErrorAction Stop
            Write-Ok "Summary written to $outFile"
        }
        catch {
            Write-Warn "Summary file could not be written: $($_.Exception.Message)"
            Write-Host "           Everything above still applies - copy it from the console." -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host ""
    Write-Err $_.Exception.Message
    # Enough detail to diagnose without a second run - the window may be about to close.
    if ($_.InvocationInfo) {
        Write-Host "           At line   : $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
        if ($_.InvocationInfo.Line) {
            Write-Host "           Statement : $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
        }
    }
    Write-Host "           Type      : $($_.Exception.GetType().FullName)" -ForegroundColor DarkGray
    # Avoid `exit` here. Under some hosts - including right-click > Run with PowerShell -
    # it closes the window before the error can be read. Set the exit code and return.
    $global:LASTEXITCODE = 1
    return
}
finally {
    # Guarded: when the Graph modules fail to import, Get-MgContext does not exist and an
    # unguarded call throws CommandNotFoundException, burying the real error.
    if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
        try {
            if (Get-MgContext -ErrorAction SilentlyContinue) {
                # -WarningAction suppresses the harmless MSAL token-cache warning
                # ("The authority ... must be in a well-formed URI format") the SDK emits
                # on disconnect. It has no bearing on work already completed.
                Disconnect-MgGraph -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
            }
        }
        catch { }
    }
    # Put PSGallery back the way we found it if we flipped it to Trusted.
    if ($script:RestorePSGalleryPolicy) {
        Set-PSRepository -Name PSGallery -InstallationPolicy $script:RestorePSGalleryPolicy -ErrorAction SilentlyContinue
        Write-Host "    [ OK ] PSGallery InstallationPolicy restored to $script:RestorePSGalleryPolicy" -ForegroundColor Gray
    }
}
#endregion
