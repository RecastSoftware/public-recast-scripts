# 🔐 New-RecastEntraAppRegistration

Interactive PowerShell script that creates a Microsoft Entra app registration for **Right Click Tools** or **Application Workspace**, grants only the Microsoft Graph permissions the selected features actually need, and optionally wires the result into the product that will consume it.

Built to replace the manual click-through in the Recast onboarding guides.

---

## What it does

1. **Checks prerequisites** — PowerShell version, required Graph modules, and Graph SDK version conflicts. Installs and repairs what it can.
2. **Asks which product** the app registration is for.
3. **Asks which features** are in use, and builds a de-duplicated permission set from only those.
4. **Signs you in** to Microsoft Graph, prompting every run so the target tenant is always explicit.
5. **Creates the app registration**, service principal, platform configuration, and optionally a client secret.
6. **Grants tenant-wide admin consent** for every permission it added.
7. **Optionally configures the product** — an RMS service connection for Right Click Tools, or an identity source and Graph mail server for Application Workspace.

Permission GUIDs are resolved **live** from the Microsoft Graph service principal in the target tenant. Nothing is hardcoded, so nothing drifts when Microsoft changes an ID. If a permission name cannot be resolved, the script aborts before writing anything.

Already have an app registration? See [Existing app registration mode](#existing-app-registration-mode) to skip straight to step 7, or to audit which product features an existing app can actually support.

---

## 📋 Requirements

| | |
|---|---|
| **PowerShell** | 5.1 or later (Windows PowerShell or PowerShell 7) |
| **Modules** | `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications` — installed automatically if missing |
| **Entra roles** | Application Administrator to create the app; Privileged Role Administrator or Global Administrator to grant consent |
| **For RMS config** | A deployed Recast Proxy, and RMS permissions on your account |
| **For AW config** | A zone API account. The Application Workspace PowerShell module is resolved automatically — see below. |

> **Run in a standalone PowerShell window**, not the VS Code Integrated Console. That host keeps assemblies loaded between runs, which makes Graph SDK version conflicts unrecoverable without restarting the whole console. The script warns you if it detects this.

### Application Workspace module resolution

You do **not** need to install anything by hand. When `-ConfigureIdentitySource` is used, the script resolves the module in this order:

1. **Already loaded** in the current session — used as-is.
2. **`Liquit.Server.PowerShell.dll` from a local Application Workspace install** — the standard `Program Files` locations, a path given with `-AwModulePath`, or a copy sitting alongside the script.
3. **The `Liquit.Server.PowerShell` module from PSGallery** — the script offers to install it if it is not already present.

The local DLL is preferred because on a machine with Application Workspace installed it is guaranteed to match the installed product version. The PSGallery route covers admin workstations that do not have the product installed locally. If a DLL is found but fails to import, the script falls through to PSGallery rather than giving up.

The gallery install runs through the same hardened path as the Graph modules — TLS 1.2, NuGet provider, PSGallery trust, and a PowerShellGet bootstrap where needed — and verifies the module is on disk afterward rather than trusting that no error was raised. Pass `-AutoInstallModules` to skip the prompt on unattended runs.

To install it yourself beforehand:

```powershell
Install-Module -Name Liquit.Server.PowerShell -Scope CurrentUser
```

---

## 🚀 Quick start

```powershell
# Interactive — walks through every prompt
.\New-RecastEntraAppRegistration.ps1

# Preview the permission set without touching the tenant
.\New-RecastEntraAppRegistration.ps1 -WhatIfOnly

# Recommended when switching between admin accounts
.\New-RecastEntraAppRegistration.ps1 -UseDeviceCode

# Audit an app registration that already exists — what can it actually do?
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '<app-id>' -WhatIfOnly
```

---

## 🔑 Feature catalog

Only the permissions for features you select are requested. Selecting several features de-duplicates the overlap.

### Right Click Tools

| # | Feature | Permissions |
|---|---|---|
| 1 | Add Device(s) to Entra Security Group | `Device.Read.All`, `Device.ReadWrite.All`, `Group.Read.All`, `Group.ReadWrite.All` |
| 2 | Delete Device(s) from Intune / Entra | `DeviceManagementManagedDevices.ReadWrite.All`, `Device.ReadWrite.All` |
| 3 | Entra ID BitLocker Recovery Keys | `Device.Read.All` + 5 delegated scopes |
| 4 | Register Device(s) in Autopilot | `DeviceManagementServiceConfig.ReadWrite.All` |
| 5 | Retrieve LAPS Passwords from Entra ID | `DeviceLocalCredential.Read.All` |
| 6 | Insights — Collect Intune warranty information | `DeviceManagementManagedDevices.Read.All` |
| 7 | Privileged Access — All features | `Device.Read.All`, `GroupMember.Read.All`, `User.Read.All` |
| 8 | Patching — All features | `DeviceManagementApps.ReadWrite.All`, `GroupMember.Read.All`, `DeviceManagementConfiguration.Read.All`, `Device.Read.All` |

Source: [Graph API Permissions for Right Click Tools](https://docs.recastsoftware.com/help/right-click-tools-graph-api-permissions)

**Feature 3 is special.** BitLocker key retrieval is the only Right Click Tools feature using *delegated* permissions — Microsoft provides no application-permission equivalent, because retrieving a recovery key must be attributable to a person. Selecting it adds the WAM broker redirect URI (`ms-appx-web://microsoft.aad.brokerplugin/<app-id>`) and enables public client flows. **Those are skipped entirely when no delegated permissions are selected**, so an application-only app registration comes out clean.

### Application Workspace

| # | Feature | Permissions |
|---|---|---|
| 1 | Entra ID identity source **(always included)** | `Directory.Read.All`, `User.Read` (delegated) |
| 2 | User profile photos | `User.Read.All` |
| 3 | Group editing from within Workspace | `GroupMember.ReadWrite.All` |
| 4 | Email notifications sent via Graph | `Mail.Send` |
| 5 | Migration Utility — Intune as a data source | `DeviceManagementApps.Read.All`, `DeviceManagementManagedDevices.Read.All` |

Application Workspace registrations also get a Web redirect URI built from your zone URL (`<zone>/api/auth/token/end`).

> `User.Read` delegated is added explicitly. The Azure **portal** adds it automatically to every new app registration — which is why it appears in the onboarding guide screenshots as "Microsoft Graph (5)" — but the Graph **API** does not. Without it, SSO sign-in is missing its baseline scope.

Sources:\
[How to Setup Microsoft Entra App Registration to use as an Application Workspace Identity Source](https://scribehow.com/o/xf43_qHmRXqaTl4dNDHGFA/viewer/How_to_Setup_Microsoft_Entra_App_Registration_to_use_as_an_Application_Workspace_Identity_Source__UmRbqg_rSqORT_QX2UTqZQ)\
[Configure Single Sign-On with Microsoft Entra ID](https://docs.recastsoftware.com/help/lws-login-single-sign-on-sso-with-azure)

## 🔍 Existing app registration mode

Use `-ExistingAppId` when the app registration already exists and only the product-side configuration is missing — a common situation when the app was created weeks earlier, or created by someone else.

```powershell
# RMS service connection against an existing app
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '<app-id>' `
    -ConfigureServiceConnection -RmsServer rms.contoso.com -AllowSelfSignedCertificate

# Application Workspace identity source against an existing app
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '<app-id>' `
    -ConfigureIdentitySource -ZoneUrl 'https://contoso.recastsoftware.cloud' `
    -IdentitySourceName 'EntraID' -IdentitySourceDisplayName 'Recast Software'
```

### What it skips

The feature catalog, app creation, service principal creation, permission assignment, and admin consent. The script branches immediately after the prerequisite check and goes straight to configuring the product.

**Nothing is written to the app registration.** It is read once to confirm it exists, and that is all.

### You will be prompted for the client secret

Entra reveals a secret value exactly once, at creation, and there is no API to read it back. So this mode has to ask. Either paste the value from your password vault, or add a new secret under **App registrations → Certificates & secrets** first and use that.

The prompt is masked and the value is never written to the summary file.

### Which product it configures

Inferred from the switch you pass:

| Switches given | Result |
|---|---|
| `-ConfigureServiceConnection` only | Right Click Tools → RMS service connection |
| `-ConfigureIdentitySource` only | Application Workspace → identity source |
| Both, or neither | Prompts you to choose (one product per run) |

### Validation and the feature coverage report

By default the script does a **read-only** Graph lookup — `Application.Read.All` and `DelegatedPermissionGrant.Read.All`, not the read-write scopes the creation flow needs — to confirm the app ID exists. This catches a mistyped GUID before it becomes a service connection that authenticates against nothing.

It then reads the permissions actually on the app registration, maps them back onto the feature catalog, and reports which product features will work:

```
==> Feature coverage for Right Click Tools
    Based on permissions actually consented in this tenant.

    Feature                                              Status         Missing
    --------------------------------------------------------------------------------
    RCT - Add Device(s) to Entra Security Group          Available
    RCT - Delete Device(s) from Intune / Entra           Available
    RCT - Entra ID BitLocker Recovery Keys               Not available  BitlockerKey.Read.All (delegated), ... (+4 more)
    RCT - Register Device(s) in Autopilot                Available
    RCT - Retrieve LAPS Passwords from Entra ID          Not available  DeviceLocalCredential.Read.All
    RCT Insights - Collect Intune warranty information   Available
    RCT Privileged Access - All features                 Partial        User.Read.All
    RCT Patching - All features                          Available

    5 available, 1 partial, 2 not available

    To enable the features above, add these Graph permissions:
      - BitlockerKey.Read.All (delegated)
      - DeviceLocalCredential.Read.All
      - User.Read.All
```

Each feature is **Available**, **Partial**, or **Not available**, with the specific permissions that are missing and a consolidated list of what to add to close every gap.

#### Requested vs. consented

The report distinguishes permissions that are *requested* on the app registration from permissions that have actually been *consented* — and reports against consent, because that is what determines whether a feature works at runtime.

This matters because the two are stored separately. `RequiredResourceAccess` on the app registration is a request, and it is what the portal shows under API permissions. The actual grant lives on the service principal: `appRoleAssignments` for application permissions, `oauth2PermissionGrants` for delegated ones. **A permission that is requested but never consented looks correct in the portal and still fails at runtime**, so anything in that state is called out separately:

```
    [WARN] These permissions are requested on the app but NOT consented:
             User.Read.All
           Grant admin consent in the portal:
             App registrations > API permissions > Grant admin consent
```

The report also lists any permissions present that no feature of the selected product uses — usually a sign the app registration is shared with another product or a custom integration.

If consent status cannot be read (for example your account lacks `DelegatedPermissionGrant.Read.All`), the report falls back to requested permissions and says so rather than implying more certainty than it has. An app registration with no service principal at all is flagged explicitly, since it cannot hold any grant.

#### Audit only

Combine `-ExistingAppId` with `-WhatIfOnly` to run the report and stop — no secret prompt, nothing configured:

```powershell
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '<app-id>' -WhatIfOnly
```

This is the fastest way to answer "what can this app registration actually do?" for an app someone else created.

#### Skipping validation

Pass `-SkipAppValidation` to avoid the sign-in entirely. You will be prompted for the tenant ID instead, or supply it with `-TenantId`. The coverage report is skipped too, since it depends on the same Graph lookup — so `-SkipAppValidation` cannot be combined with `-WhatIfOnly`.

### Application Workspace settings

Normally `AzurePhotos` and `AzureWriteMode` are derived from the feature catalog. There is no catalog selection in this mode, so the script asks directly:

```
Sync user profile photos?             (y/N)
Allow group editing from Workspace?   (y/N)
Create a Microsoft Graph mail server? (y/N)
```

Enable only what the app registration was actually granted. For unattended runs, use `-Force` with `-EnableAzurePhotos`, `-EnableGroupWrite`, and `-ConfigureMailServer`.

> `-ExistingAppId` cannot be combined with `-CreateClientSecret` — this mode never modifies the app registration. The script throws if both are given.

---

## 🔧 Post-creation configuration

### Right Click Tools → RMS service connection

Creates the `AzureActiveDirectory` service connection in Recast Management Server:

1. Calls `ListProxies` and displays the proxy grid
2. You pick the proxy that will use the connection
3. Submits `CreateAzureActiveDirectoryServiceConnection` with the proxy's certificate thumbprint

```powershell
.\New-RecastEntraAppRegistration.ps1 -CreateClientSecret `
    -ConfigureServiceConnection -RmsServer rms.contoso.com -AllowSelfSignedCertificate
```

### Application Workspace → identity source + mail server

Loads the Application Workspace module, connects to the zone, and creates the Entra ID identity source. Settings follow the features you picked:

| Feature selected | Setting applied |
|---|---|
| User profile photos | `-AzurePhotos Enabled` |
| Group editing from within Workspace | `-AzureWriteMode GroupMembership` |
| Email notifications sent via Graph | Creates a Microsoft Graph mail server |

```powershell
$cred = Get-Credential   # local\admin

.\New-RecastEntraAppRegistration.ps1 -CreateClientSecret `
    -ZoneUrl 'https://contoso.recastsoftware.cloud' `
    -ConfigureIdentitySource `
    -IdentitySourceName 'EntraID' -IdentitySourceDisplayName 'Recast Software' `
    -ZoneCredential $cred -MailServerFrom 'noreply@contoso.com'
```

If the identity source already exists it is **not** recreated — recreating one breaks sign-in for users who previously authenticated through it.

---

## Parameters

### App registration

| Parameter | Description |
|---|---|
| `-DisplayName` | Name for the app registration. Defaults per product. |
| `-TenantId` | Target tenant. Omit to use the signed-in account's tenant. |
| `-CreateClientSecret` | Create a client secret and display it once. |
| `-SecretMonths` | Secret lifetime in months. Default 12, max 24. |
| `-ZoneUrl` | Application Workspace zone URL, used for the Web redirect URI. |
| `-SkipConsent` | Stage permissions without granting admin consent. |
| `-WhatIfOnly` | Show the resolved permission set and exit. With `-ExistingAppId`, runs the feature coverage report and stops. |

### Existing app registration

| Parameter | Description |
|---|---|
| `-ExistingAppId` | Application (client) ID of an existing app. Skips creation, permissions, and consent. Cannot be used with `-CreateClientSecret`. |
| `-SkipAppValidation` | Skip the read-only Graph lookup that confirms the app exists. Avoids a sign-in; prompts for the tenant ID instead. Also skips the coverage report, so it cannot be combined with `-WhatIfOnly`. |
| `-EnableAzurePhotos` | Set `AzurePhotos` on the identity source. Prompted for unless `-Force`. |
| `-EnableGroupWrite` | Set `AzureWriteMode` to `GroupMembership`. Prompted for unless `-Force`. |
| `-ConfigureMailServer` | Also create the Graph mail server. Prompted for unless `-Force`. |

### Authentication

| Parameter | Description |
|---|---|
| `-UseDeviceCode` | Bypass the Windows WAM broker and sign in with a device code. |
| `-ReuseGraphSession` | Accept an existing Graph session instead of forcing a fresh sign-in. |
| `-Force` | Skip confirmation prompts. In `-ExistingAppId` mode, also takes the AW setting switches as given rather than asking. |

### Module handling

| Parameter | Description |
|---|---|
| `-AutoInstallModules` | Install missing modules without prompting. Applies to the Graph modules and the Application Workspace module. |
| `-ModuleScope` | `CurrentUser` (default) or `AllUsers`. |
| `-CleanConflictingModules` | Remove mismatched `Microsoft.Graph.*` versions without prompting. |

### RMS

| Parameter | Description |
|---|---|
| `-ConfigureServiceConnection` | Create the RMS service connection after the app registration. |
| `-RmsServer` | RMS server, e.g. `rms.contoso.com`. |
| `-RmsPort` | Default 444. Dev installs often use 44339. |
| `-AllowSelfSignedCertificate` | Skip TLS validation for self-signed RMS certificates. |
| `-MarkConfirmed` | Defaults to `$true`. Pass `-MarkConfirmed:$false` to create the connection unconfirmed. |

### Application Workspace

| Parameter | Description |
|---|---|
| `-ConfigureIdentitySource` | Create the Entra ID identity source after the app registration. |
| `-IdentitySourceName` | Identity source name. Must match the NETBIOS name if hybrid-joined — case sensitive. |
| `-IdentitySourceDisplayName` | Friendly name shown on the sign-in button. |
| `-ZoneCredential` | Zone API account. Username defaults to `local\admin`. |
| `-AwModulePath` | Path to a local `Liquit.Server.PowerShell.dll` in a non-standard location. Optional — the script falls back to PSGallery. |
| `-MailServerName` | Mail server name. Defaults to `Microsoft Graph`. |
| `-MailServerFrom` | Sender address. Must be a real mailbox the app can send as. |

---

## 🩺 Troubleshooting

### Sign-in hangs on "Just a moment..."

The Windows Web Account Manager broker is wedged. Close the dialog and re-run with `-UseDeviceCode`, which bypasses the broker entirely.

### `Method 'GetTokenAsync' ... does not have an implementation`

Two versions of the Graph SDK are visible to .NET in the same session. Close **all** PowerShell windows including the VS Code terminal, open a new elevated window, and run with `-CleanConflictingModules`. The disk cleanup persists; the poisoned session cannot be repaired because .NET cannot unload assemblies.

### `No app registration with Application (client) ID ... exists in this tenant`

In `-ExistingAppId` mode, either the GUID is wrong or you signed in to a different tenant. Confirm the **Application (client) ID** on the app registration Overview page — not the Object ID or the Directory (tenant) ID — and check the tenant reported at sign-in.

### `LiquitContext — No connection is available to service this operation`

The Application Workspace module is loaded but not connected to a zone. The script detects this and stops rather than reporting false success. Supply `-ZoneCredential`, or connect first with `Connect-LiquitWorkspace`.

### `Liquit.Server.PowerShell imported, but Connect-LiquitWorkspace is not available`

The installed gallery module version does not expose the cmdlets this script expects. Point at a local install instead:

```powershell
-AwModulePath 'C:\Program Files (x86)\Liquit Workspace\PowerShell\Liquit.Server.PowerShell.dll'
```

### Proxies display as `<unknown>`

The `Proxy*Field` names in `$RmsApiContract` do not match your RMS version. The script dumps the actual property names it found. Capture the real shape with:

```powershell
Get-RmsRawResponse -Server <rms> -Endpoint 'Administration/ListProxies' -AllowSelfSignedCertificate
```

### Module installs silently do nothing

Usually PowerShellGet 1.0.0.1, the stock version on Windows PowerShell 5.1, which reports provider failures as non-terminating errors. The script detects this and offers to bootstrap 2.2.5. Accept, then **close and reopen PowerShell** — the old version stays loaded in the current session.

---

## Notes on behaviour

- **The client secret is shown once** and is deliberately excluded from the optional summary file. Copy it into a password vault immediately.
- **Every write is verified.** The script never treats the absence of an exception as evidence of success — it reads objects back after creating them.
- **Sign-in prompts every run** by default. A cached MSAL token would otherwise silently reuse whichever account authenticated last, which is how an app registration ends up in the wrong tenant.
- **PSGallery trust is restored** to its original value on exit if the script temporarily changed it.

---
