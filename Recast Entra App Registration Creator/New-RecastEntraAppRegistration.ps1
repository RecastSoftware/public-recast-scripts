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
    Full path to Liquit.Server.PowerShell.dll, if it is not in a standard install
    location. Normally unnecessary.

.PARAMETER IdentitySourceDisplayName
    Friendly name shown to end users on the sign-in button, e.g. "Recast Software".

.PARAMETER CleanConflictingModules
    Remove Microsoft.Graph.* versions that do not match the pinned version, without
    prompting.

.EXAMPLE
    .\New-RecastEntraAppRegistration.ps1 -DisplayName "Recast - Right Click Tools" -CreateClientSecret

.EXAMPLE
    .\New-RecastEntraAppRegistration.ps1 -ZoneUrl "https://contoso.recastsoftware.cloud" -CreateClientSecret

.NOTES
    Requires : PowerShell 5.1+ and the Microsoft.Graph.Authentication / Microsoft.Graph.Applications modules
    Rights   : Application Administrator to create the app
               Privileged Role Administrator (or Global Administrator) to grant consent
    Author   : Christopher Antoku - Onboarding & Enablement

    IMPORTANT: Run this in a standalone PowerShell window, not the VS Code Integrated
    Console. That host keeps assemblies loaded between runs, which makes Graph SDK
    version conflicts unrecoverable without restarting the whole console.
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

    # Full path to Liquit.Server.PowerShell.dll, if it is not in a standard location.
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
    [switch]$UseDeviceCode
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
#   "How to Setup Microsoft Entra App Registration to use as an Application Workspace
#    Identity Source" https://scribehow.com/o/xf43_qHmRXqaTl4dNDHGFA/viewer/How_to_Setup_Microsoft_Entra_App_Registration_to_use_as_an_Application_Workspace_Identity_Source__UmRbqg_rSqORT_QX2UTqZQ

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
            # User.Read delegated is the baseline sign-in scope. The Azure PORTAL adds it
            # automatically to every new app registration, which is why it shows up in the
            # onboarding guide screenshots as "Microsoft Graph (5)". Creating an app via
            # the Graph API does NOT add it, so we add it explicitly here - without it,
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

    # Literal profile paths, in case Documents is redirected and the other one is real
    foreach ($base in @($env:USERPROFILE, (Join-Path $env:USERPROFILE 'OneDrive'),
                        (Join-Path $env:USERPROFILE 'OneDrive - Recast Software'))) {
        if ($base) { $roots.Add((Join-Path $base "Documents\$leaf")) }
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

        The child VERIFIES on disk and exits with a meaningful code. An earlier version of
        this script ran 'exit 0' immediately after Install-Module, which masked a failed
        install completely - PowerShellGet 1.0.0.1 writes provider errors non-terminating,
        so -ErrorAction Stop never fired. Never trust the exit code alone.
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
        $proc = Start-Process -FilePath $hostExe `
                              -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded `
                              -Wait -PassThru -NoNewWindow `
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
        Deleting it out from under the broker mid-session wedges WAM - the sign-in dialog
        hangs on "Just a moment..." and never returns, which can take the host process
        down with it. An earlier version of this script did exactly that.

        Forcing a specific account does not require nuking the shared broker cache.
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

    # --- Is this session already poisoned? ----------------------------------
    # Checked FIRST, before any install or cleanup work. Assemblies cannot be unloaded, so
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

    # --- Clear Graph SDK version sprawl BEFORE importing anything -----------
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
    foreach ($role in $Resolved.AppRoles) {
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
            if ($_.Exception.Message -match 'already exists|Permission being assigned was already assigned') {
                Write-Ok "Already consented: $($role.Name)"
            }
            else {
                Write-Err "$($role.Name) -> $($_.Exception.Message)"
            }
        }
    }

    # --- Delegated permissions -> single tenant-wide oauth2PermissionGrant ---
    #
    # Uses Invoke-MgGraphRequest rather than New-MgOauth2PermissionGrant. That cmdlet lives
    # in Microsoft.Graph.Identity.SignIns, which we deliberately do NOT load - adding a
    # third Graph submodule means a third module to keep version-aligned, and version
    # sprawl is the single biggest source of failures in this script.
    if ($Resolved.Scopes.Count -gt 0) {
        $scopeString = ($Resolved.Scopes.Name | Sort-Object) -join ' '
        try {
            # A service principal can hold only ONE grant per resource, so check first.
            $existing = $null
            try {
                $filter = "clientId eq '$($AppServicePrincipal.Id)' and resourceId eq '$($GraphSp.Id)'"
                $existing = (Invoke-MgGraphRequest -Method GET `
                    -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$filter" `
                    -ErrorAction Stop).value
            } catch { }

            if ($existing) {
                $merged = (($existing[0].scope -split ' ') + $Resolved.Scopes.Name |
                           Where-Object { $_ } | Select-Object -Unique | Sort-Object) -join ' '
                Invoke-MgGraphRequest -Method PATCH `
                    -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($existing[0].id)" `
                    -Body @{ scope = $merged } -ErrorAction Stop | Out-Null
                $granted = $merged
            }
            else {
                Invoke-MgGraphRequest -Method POST `
                    -Uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' `
                    -Body @{
                        clientId    = $AppServicePrincipal.Id
                        consentType = 'AllPrincipals'
                        resourceId  = $GraphSp.Id
                        scope       = $scopeString
                    } -ErrorAction Stop | Out-Null
                $granted = $scopeString
            }

            # Delegated scopes live in ONE grant object as a space-separated string, but
            # report them individually so the output matches the application permissions.
            $grantedList = @($granted -split ' ' | Where-Object { $_ })
            foreach ($s in ($Resolved.Scopes.Name | Sort-Object)) {
                if ($grantedList -contains $s) { Write-Ok "Consented (delegated): $s" }
                else { Write-Warn "NOT consented (delegated): $s" }
            }
        }
        catch {
            Write-Err "Delegated consent failed -> $($_.Exception.Message)"
            Write-Warn "Grant it manually: Entra admin center > App registrations > API permissions > Grant admin consent"
        }
    }
}
#endregion

#region ------------------------------- Application Workspace identity source

function Import-AwModule {
    <#
        Loads Liquit.Server.PowerShell.dll.

        Path logic mirrors the working zone configuration script: the standard install
        location first, then alongside this script, then anything already on the module
        path. -Global matters - without it the cmdlets are only visible inside this
        function's module scope.
    #>
    [CmdletBinding()]
    param([string]$ModulePath)

    # Already loaded? Nothing to do.
    if (Get-Command 'Connect-LiquitWorkspace' -ErrorAction SilentlyContinue) {
        Write-Ok "Application Workspace module already loaded"
        return $true
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($ModulePath) { $candidates.Add($ModulePath) }
    $candidates.Add('C:\Program Files (x86)\Liquit Workspace\PowerShell\Liquit.Server.PowerShell.dll')
    $candidates.Add('C:\Program Files\Liquit Workspace\PowerShell\Liquit.Server.PowerShell.dll')

    # Next to this script, the way the zone config script falls back.
    if ($PSScriptRoot) {
        $candidates.Add((Join-Path $PSScriptRoot 'Liquit.Server.PowerShell.dll'))
    }

    $found = $candidates | Where-Object { $_ -and (Test-Path $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1

    if (-not $found) {
        Write-Err "Unable to find Liquit.Server.PowerShell.dll"
        Write-Host "           Looked in:" -ForegroundColor Gray
        $candidates | ForEach-Object { Write-Host "             $_" -ForegroundColor DarkGray }
        Write-Host ""
        Write-Host "    Install Application Workspace tooling on this machine, or pass the path:" -ForegroundColor White
        Write-Host "      -AwModulePath 'D:\path\to\Liquit.Server.PowerShell.dll'" -ForegroundColor Cyan
        Write-Host ""
        return $false
    }

    try {
        Import-Module $found -Global -ErrorAction Stop
        Write-Ok "Application Workspace module loaded"
        Write-Host "           $found" -ForegroundColor DarkGray
    }
    catch {
        Write-Err "Could not import the Application Workspace module: $($_.Exception.Message)"
        return $false
    }

    # The zone config script loads these for package handling. Harmless here, and keeps
    # behaviour consistent if a later call needs them.
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression") | Out-Null
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
    } catch { }

    return $true
}

function Connect-AwZone {
    <#
        Connects to an Application Workspace zone with Connect-LiquitWorkspace.

        Reuses the zone URL already collected for the app registration's redirect URI, so
        the operator is not asked for the same value twice.
    #>
    [CmdletBinding()]
    param(
        [string]$ZoneUri,
        [pscredential]$Credential
    )

    # Already connected? A cheap read confirms it without side effects.
    try {
        $null = Get-LiquitIdentitySource -ErrorAction Stop 2>$null
        Write-Ok "Already connected to an Application Workspace zone"
        return $true
    }
    catch {
        # Anything other than a missing connection is a real problem - surface it.
        if ($_.Exception.Message -notmatch 'No connection is available|LiquitContext') {
            Write-Warn "Unexpected error probing the zone connection: $($_.Exception.Message)"
        }
    }

    if (-not $ZoneUri) {
        do {
            $ZoneUri = (Read-Host "    Zone URI (e.g. https://yourzone.recastsoftware.cloud)").Trim()
        } until ($ZoneUri)
    }

    if (-not $Credential) {
        # local\admin is the built-in zone administrator and the usual answer here, so
        # make it the default rather than failing on an empty response.
        $defaultUser = 'local\admin'
        Write-Host "    API access account for the zone" -ForegroundColor Gray
        $awUser = (Read-Host "    Username [$defaultUser]").Trim()
        if (-not $awUser) { $awUser = $defaultUser }

        $awPass = Read-Host "    Password" -AsSecureString

        if (-not $awPass -or $awPass.Length -eq 0) {
            Write-Err "A password is required to connect to the zone."
            return $false
        }
        $Credential = New-Object System.Management.Automation.PSCredential($awUser, $awPass)
    }

    try {
        Write-Host "    Connecting to $ZoneUri ..." -ForegroundColor Gray
        $null = Connect-LiquitWorkspace -URI $ZoneUri -Credential $Credential -ErrorAction Stop
        Write-Ok "Connected to zone"
    }
    catch {
        Write-Err "Failed to connect to the zone: $($_.Exception.Message)"
        Write-Host "           Check the zone URI, the account, and that the account has" -ForegroundColor Gray
        Write-Host "           zone.access.api permission." -ForegroundColor Gray
        return $false
    }

    # Never trust the absence of an error - confirm the context actually works.
    try {
        $null = Get-LiquitIdentitySource -ErrorAction Stop 2>$null
        return $true
    }
    catch {
        Write-Err "Connected without error, but zone commands still fail: $($_.Exception.Message)"
        return $false
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
        [bool]$EnableGroupWrite = $false
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
    # sails past and reports success on nothing.
    if (-not (Connect-AwZone -ZoneUri $ZoneUri -Credential $ZoneCredential)) {
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
    # NOTE: the logout URI keeps a LITERAL ${slo.return.url} token - Application Workspace
    # substitutes it at sign-out time. The backtick stops PowerShell expanding it here.
    $tokenUri         = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $authorizationUri = "https://login.microsoftonline.com/$TenantId/oauth2/authorize"
    $logoutUri        = "https://login.microsoftonline.com/$TenantId/oauth2/logout?post_logout_redirect_uri=`${slo.return.url}"

    # --- Create, or skip if it already exists --------------------------------
    $existing = Get-LiquitIdentitySource -Name $Name -ErrorAction SilentlyContinue

    if (-not $existing) {
        # -ErrorAction Stop is ESSENTIAL here. The Liquit cmdlets write their failures as
        # NON-TERMINATING errors, so without it a failed create does not throw, the catch
        # never runs, and execution falls straight through to the success message. That is
        # exactly how this reported "Identity source 'CX' created" over a wall of
        # ArgumentException / NullReferenceException output.
        # Driven by the features chosen earlier, so a consented permission actually gets
        # used instead of sitting there switched off.
        #   User.Read.All            -> AzurePhotos    Enabled
        #   GroupMember.ReadWrite.All-> AzureWriteMode  GroupMembership
        $azurePhotos    = if ($EnablePhotos)     { 'Enabled' }        else { 'Disabled' }
        $azureWriteMode = if ($EnableGroupWrite) { 'GroupMembership' } else { 'Disabled' }

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

        # Never trust the absence of an exception. Confirm it is actually there.
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

    Write-Host ""
    Write-Host "   Identity source ready." -ForegroundColor Cyan
    Write-Host "     Name         : $Name" -ForegroundColor Gray
    Write-Host "     Display name : $(if ($final.DisplayName) { $final.DisplayName } else { $DisplayName })" -ForegroundColor Gray
    Write-Host "     Methods      : Federated, Login" -ForegroundColor Gray
    Write-Host "     AzurePhotos    : $azurePhotos" -ForegroundColor Gray
    Write-Host "     AzureWriteMode : $azureWriteMode" -ForegroundColor Gray
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

    # From is REQUIRED by the API and has no sensible default - it must be a real mailbox
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
#  ###############################################################################
#  #  UNVERIFIED API SURFACE                                                     #
#  #                                                                             #
#  #  The RMS API is not publicly documented. Every endpoint path, payload field #
#  #  name, and the secret encryption scheme below is an ASSUMPTION, isolated in #
#  #  $RmsApiContract so it can be corrected in one place.                       #
#  #                                                                             #
#  #  Run Show-RmsApiCapture for the two-minute procedure to capture the real    #
#  #  contract from your own RMS using browser devtools.                         #
#  #                                                                             #
#  #  HIGHEST RISK: SecretPadding. The wrong RSA padding still produces a valid  #
#  #  base64 blob the server accepts, so the connection is created successfully  #
#  #  and only fails later at auth time. Confirm before customer use.            #
#  ###############################################################################

$script:RmsApiContract = @{
    ApiBase = 'api'                                                              #>>> VERIFY

    ListProxies                    = 'Administration/ListProxies'                #>>> VERIFY
    CreateAzureAdServiceConnection = 'Administration/CreateAzureActiveDirectoryServiceConnection'  #>>> VERIFY
    TestServiceConnection          = 'Administration/TestServiceConnection'      #>>> VERIFY

    # CONFIRMED against ListProxies via RMS Administration > Test Tools > Action Tester.
    # Actual columns returned: Id, ComputerName, UserName, Certificate, Authorized,
    # Connected, Version, Internal.
    ProxyIdField          = 'Id'
    ProxyNameField        = 'ComputerName'
    ProxyAccountField     = 'UserName'          # NOT 'ServiceAccount' - corrected from live output
    ProxyCertificateField = 'Certificate'
    ProxyAuthorizedField  = 'Authorized'
    ProxyConnectedField   = 'Connected'
    ProxyVersionField     = 'Version'
    ProxyInternalField    = 'Internal'

    # CONFIRMED against CreateAzureActiveDirectoryServiceConnection via Action Tester.
    # Declared input schema:
    #   "Name": (String), "TenantID": (String), "ClientID": (String),
    #   "ClientSecret": (String), "Confirmed": (Boolean), "ProxyCertificate": (String)
    #
    # NOTE THE CASING: TenantID / ClientID use a capital D. Not TenantId / ClientId.
    #
    # NOTE THERE IS NO ProxyId. The API takes the proxy's CERTIFICATE string, which is
    # how the server identifies which proxy the connection belongs to - and which public
    # key the ClientSecret was encrypted against. That is why ListProxies must run first.
    Body = @{
        Name             = 'Name'
        TenantId         = 'TenantID'
        ClientId         = 'ClientID'
        ClientSecret     = 'ClientSecret'
        Confirmed        = 'Confirmed'
        ProxyCertificate = 'ProxyCertificate'
    }

    # ---------------------------------------------------------------- OPEN QUESTION
    # Does the CLIENT encrypt the secret, or does the SERVER?
    #
    # The declared schema field is plain "ClientSecret": (String) - not
    # "EncryptedClientSecret" - and the payload also carries "ProxyCertificate".
    # That reads as: hand the server the secret plus the certificate, and let the
    # server encrypt it against that proxy's public key.
    #
    # The competing reading is that the client is expected to encrypt first, and the
    # certificate is in the payload purely to identify the proxy.
    #
    # Default is $false (send as-is), because it matches the declared field name and
    # because it fails LOUDLY if wrong. Client-side encryption that the server did not
    # expect produces a connection that saves cleanly and then fails every auth attempt,
    # which is far harder to diagnose.
    #
    # If the connection is created but will not authenticate, flip this to $true.
    EncryptSecretClientSide = $false                                             #>>> VERIFY

    # Only used when EncryptSecretClientSide = $true.
    # 'OaepSHA256' | 'OaepSHA1' | 'Pkcs1'
    SecretPadding = 'OaepSHA256'                                                 #>>> VERIFY
}

function Show-RmsApiCapture {
    <# Prints how to capture the real RMS API contract from browser devtools. #>
    Write-Host ""
    Write-Host "  Capturing the real RMS API contract" -ForegroundColor White
    Write-Host "  -----------------------------------" -ForegroundColor DarkGray
    Write-Host "  The RMS web UI calls the same API this script does, so watch it once." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  1. Open RMS in a browser, press F12, Network tab." -ForegroundColor White
    Write-Host "  2. Tick 'Preserve log', filter to Fetch/XHR." -ForegroundColor White
    Write-Host "  3. Administration > Service Connections > Add service connection." -ForegroundColor White
    Write-Host "  4. Pick AzureActiveDirectory; watch the proxy dropdown populate." -ForegroundColor White
    Write-Host "       -> that call is ListProxies. Note the path and the proxy fields." -ForegroundColor DarkGray
    Write-Host "  5. Fill in throwaway values and submit." -ForegroundColor White
    Write-Host "       -> right-click > Copy > Copy as PowerShell for the exact payload." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Then correct `$RmsApiContract near the top of the RMS region." -ForegroundColor White
    Write-Host ""
    Write-Host "  Devtools will NOT reveal the secret padding mode - you only see the" -ForegroundColor Yellow
    Write-Host "  finished blob. Ask the RMS dev team, or test against CS-TEST-RMS and" -ForegroundColor Yellow
    Write-Host "  flip SecretPadding to 'Pkcs1' if auth fails on a connection that was" -ForegroundColor Yellow
    Write-Host "  created without error." -ForegroundColor Yellow
    Write-Host ""
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
        return Invoke-RestMethod @params
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
            $msg += "`n           A 404 usually means the endpoint path in `$RmsApiContract is wrong. Run Show-RmsApiCapture."
        }
        if ($detail) { $msg += "`n           Server said: $($detail.Trim())" }
        throw $msg
    }
}

function Test-RmsActionEnvelope {
    <#
        True when an object is an RMS action-result envelope rather than the payload.

        CONFIRMED shape, from dumping a live ListProxies response:
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
        ITS .Result. Unwrapping only the outer layer leaves you holding this, which is
        exactly why the proxy grid rendered as <unknown>.
    #>
    param($Object)

    if ($null -eq $Object -or -not $Object.PSObject) { return $false }
    $props = @($Object.PSObject.Properties.Name)
    return (($props -contains 'IsSuccessful') -and ($props -contains 'Result'))
}

function Expand-RmsResult {
    <#
        Unwraps an RMS response down to the actual payload objects.

        CONFIRMED shape from a live ListProxies dump - note the DOUBLE nesting:

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

        The response is an ACTION ENVELOPE, not a bare array - see Expand-RmsResult.
        An earlier version of this script returned the envelopes themselves, which is why
        every proxy rendered as <unknown>: it was reading ComputerName off an object whose
        only properties were InputParameters/Result/Index/Total.
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
        Get-RmsRawResponse -Server cs-rms.cs.recastsoftware.com -Endpoint 'Administration/ListProxies' -AllowSelfSignedCertificate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [int]$Port = 444,
        [Parameter(Mandatory)][string]$Endpoint,
        [pscredential]$Credential,
        [switch]$AllowSelfSignedCertificate
    )

    $baseUri = Resolve-RmsBaseUri -Server $Server -Port $Port
    $raw = Invoke-RmsApi -BaseUri $baseUri -Endpoint $Endpoint `
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
        Write-Host "           Run Show-RmsApiCapture for how to correct the contract." -ForegroundColor Gray
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

        CONFIRMED from a live ListProxies dump: the Certificate field is a 40-character
        SHA-1 THUMBPRINT, not a base64-encoded certificate:

            "Certificate": "0FD759ACCDBCFD231C89C389FEAAC40E3496C2F4"

        The built-in RMS entry is the special case:

            "ComputerName": "Recast Management Server",
            "Certificate":  "internal",
            "Internal":     true

        This has a hard consequence: a thumbprint carries NO PUBLIC KEY, so the client
        cannot encrypt the secret itself. The server must be doing the encryption, using
        this thumbprint to look up the proxy's certificate in its own store. That settles
        EncryptSecretClientSide = $false.
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

function Protect-RmsSecret {
    <#
        Encrypts the client secret with the proxy's public key, so only that proxy can
        decrypt it. See the risk note at the top of this region regarding padding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][string]$Secret
    )

    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
    if (-not $rsa) { throw "The proxy certificate does not expose an RSA public key." }

    $bytes    = [Text.Encoding]::UTF8.GetBytes($Secret)
    $maxBytes = ($rsa.KeySize / 8) - 66   # OAEP-SHA256 overhead
    if ($bytes.Length -gt $maxBytes) {
        throw "Secret is $($bytes.Length) bytes; max for this key with OAEP-SHA256 is $maxBytes."
    }

    $padding = switch ($script:RmsApiContract.SecretPadding) {
        'OaepSHA256' { [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256 }
        'OaepSHA1'   { [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA1 }
        'Pkcs1'      { [System.Security.Cryptography.RSAEncryptionPadding]::Pkcs1 }
        default      { throw "Unknown SecretPadding '$($script:RmsApiContract.SecretPadding)' in `$RmsApiContract." }
    }

    $encrypted = $rsa.Encrypt($bytes, $padding)
    Write-Ok "Secret encrypted with proxy public key ($($script:RmsApiContract.SecretPadding), $($rsa.KeySize)-bit)"
    return [Convert]::ToBase64String($encrypted)
}

function Add-RmsAzureAdServiceConnection {
    <#
    .SYNOPSIS
        End to end: connect to RMS, ListProxies, encrypt the secret against the chosen
        proxy certificate, then CreateAzureActiveDirectoryServiceConnection.

    .DESCRIPTION
        The proxy certificate step is not optional. RMS never stores service connection
        credentials in plain text - it encrypts them with the public key of the Recast
        Proxy that will use the connection, so only that proxy can decrypt them. That is
        why ListProxies has to run before the secret can be submitted.
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
        # Confirmed defaults to TRUE. A service connection created unconfirmed still has
        # to be confirmed by hand in RMS before it will be used, which defeats the point
        # of automating it. Pass -MarkConfirmed:$false to create it unconfirmed.
        [bool]$MarkConfirmed = $true,
        [switch]$TestAfterCreate
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
        Write-Host "      - Endpoint path wrong in `$RmsApiContract. Run Show-RmsApiCapture." -ForegroundColor Gray
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
    # RESOLVED. ListProxies returns Certificate as a 40-character SHA-1 THUMBPRINT, not a
    # certificate blob. A thumbprint contains no public key, so the client CANNOT encrypt
    # the secret - the server must do it, looking the certificate up by thumbprint in its
    # own store. That also explains the plain "ClientSecret": (String) field name.
    #
    # EncryptSecretClientSide is kept only for the case where some other RMS version
    # returns a full certificate blob instead. It is off by default and should stay off.
    if ($c.EncryptSecretClientSide) {
        if ($rawProxyCertificate -match '^[0-9A-Fa-f]{40}$' -or $rawProxyCertificate -ieq 'internal') {
            Write-Warn "EncryptSecretClientSide is on, but this proxy exposes only a thumbprint."
            Write-Host "           A thumbprint has no public key, so client-side encryption is not" -ForegroundColor Gray
            Write-Host "           possible. Sending the secret as-is instead." -ForegroundColor Gray
            $secretForBody = $ClientSecret
        }
        else {
            Write-Step "Encrypting the client secret for this proxy"
            $b64  = ($rawProxyCertificate -replace '-----BEGIN CERTIFICATE-----', '' `
                                          -replace '-----END CERTIFICATE-----', '' `
                                          -replace '\s', '')
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[Convert]::FromBase64String($b64))
            $secretForBody = Protect-RmsSecret -Certificate $cert -Secret $ClientSecret
        }
    }
    else {
        $secretForBody = $ClientSecret
        Write-Ok "Client secret sent as-is (server encrypts it using the proxy thumbprint)"
    }

    # --- Create --------------------------------------------------------------
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

    # The API identifies the proxy by its CERTIFICATE, not by an Id - so we send back the
    # raw certificate string exactly as ListProxies returned it.
    $f = $c.Body
    $body = @{
        $f.Name             = $Name
        $f.TenantId         = $TenantId
        $f.ClientId         = $ClientId
        $f.ClientSecret     = $secretForBody
        $f.Confirmed        = [bool]$MarkConfirmed
        $f.ProxyCertificate = $rawProxyCertificate
    }

    $created = Invoke-RmsApi -BaseUri $baseUri `
                             -Endpoint $c.CreateAzureAdServiceConnection `
                             -Method POST -Body $body `
                             -Credential $Credential `
                             -AllowSelfSignedCertificate:$AllowSelfSignedCertificate

    Write-Ok "Service connection created"

    # --- Optional test -------------------------------------------------------
    if ($TestAfterCreate -and $created) {
        $id = $created.Id
        if (-not $id) { $id = $created.ServiceConnectionId }
        if ($id) {
            Write-Step "Testing the new service connection"
            try {
                Invoke-RmsApi -BaseUri $baseUri `
                              -Endpoint "$($c.TestServiceConnection)/$id" -Method POST `
                              -Credential $Credential `
                              -AllowSelfSignedCertificate:$AllowSelfSignedCertificate | Out-Null
                Write-Ok "Connection test returned successfully"
            }
            catch {
                # A failed test is not automatically a problem - it exercises permissions
                # the app registration may not have needed for the selected features.
                Write-Warn "Connection test failed: $($_.Exception.Message)"
                Write-Host "           This can be expected. The test exercises permissions your app" -ForegroundColor Gray
                Write-Host "           registration may not need for the features you enabled." -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Host "   Next in RMS:" -ForegroundColor Cyan
    Write-Host "     Administration > Service Connections - confirm it shows as Confirmed" -ForegroundColor Gray
    Write-Host "     Administration > Routes - make sure a Recast Proxy route exists" -ForegroundColor Gray
    Write-Host ""

    return $created
}

#endregion

#region ------------------------------------------------------------- Execute

try {
    Write-Host ""
    Write-Host "  Recast Entra App Registration Builder" -ForegroundColor White
    Write-Host "  -------------------------------------" -ForegroundColor DarkGray

    Test-Prerequisites

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
    # DELEGATED sign-in, where the tool acts as the signed-in admin and needs an
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
    $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
    Write-Ok "Service principal object ID : $($sp.Id)"

    Start-Sleep -Seconds 10   # let replication settle before consenting

    # --- Consent -------------------------------------------------------------
    if ($SkipConsent) {
        Write-Step "Admin consent"
        Write-Warn "-SkipConsent specified. Permissions are staged but NOT consented."
        Write-Host "           Have a Privileged Role Administrator click 'Grant admin consent' in the portal." -ForegroundColor Gray
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
        $pw = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{
            DisplayName = $ProductDefaults[$product].SecretDisplayName
            EndDateTime = $secretExpiry
        } -ErrorAction Stop
        $secretValue = $pw.SecretText
        Write-Ok "Secret created, expires $($secretExpiry.ToString('yyyy-MM-dd'))"
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
        Write-Host "   Client secret VALUE      : $secretValue" -ForegroundColor Yellow
        Write-Host "   ^ This is the VALUE, not the Secret ID. It is shown once." -ForegroundColor Yellow
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
            Write-Host "     and a Client Secret VALUE." -ForegroundColor Gray
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

                Add-RmsAzureAdServiceConnection -Server $RmsServer -Port $RmsPort `
                    -Name $connName `
                    -TenantId $ctx.TenantId -ClientId $app.AppId -ClientSecret $secretValue `
                    -AllowSelfSignedCertificate:$AllowSelfSignedCertificate `
                    -TestAfterCreate | Out-Null
            }
            catch {
                Write-Err "RMS service connection failed: $($_.Exception.Message)"

                # Bare .Exception.Message is not enough for .NET binding errors like
                # "Argument types do not match" - it names no line and no type. Dump the
                # exception type, the failing line, and the script stack so the next
                # failure is diagnosable in one run instead of three.
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

            try {
                # ZoneUrl was already collected for the app registration's redirect URI,
                # so reuse it rather than asking for the same value twice.
                New-AwEntraIdentitySource -TenantId $ctx.TenantId `
                    -ClientId $app.AppId -ClientSecret $secretValue `
                    -Name $IdentitySourceName -DisplayName $IdentitySourceDisplayName `
                    -ZoneUri $ZoneUrl -ZoneCredential $ZoneCredential `
                    -ModulePath $AwModulePath `
                    -EnablePhotos $wantPhotos -EnableGroupWrite $wantGroupWrite
            }
            catch {
                Write-Err "Identity source creation failed: $($_.Exception.Message)"
                Write-Warn "The app registration is fine. Add the identity source manually:"
                Write-Host "           Manage > Identity Sources > Create > Microsoft Entra ID" -ForegroundColor Gray
            }

            # Mail.Send was granted, so stand up the Graph mail server too. Kept separate
            # from the identity source: a mail server failure should not obscure a
            # successful identity source, and vice versa.
            if ($wantMail) {
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
            "NOTE: The client secret VALUE is intentionally NOT written to this file."
            "      Store it in your password vault."
        )
        $lines | Out-File -FilePath $outFile -Encoding UTF8
        Write-Ok "Summary written to $outFile"
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

    # Do NOT call `exit` here. Under some hosts - and when the script is launched via
    # right-click > Run with PowerShell - `exit` terminates the WINDOW, taking the error
    # message with it before it can be read. Set the exit code and return instead.
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
