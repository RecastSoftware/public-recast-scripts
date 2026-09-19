# New-RecastEntraAppRegistration

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

---

## Requirements

| | |
|---|---|
| **PowerShell** | 5.1 or later (Windows PowerShell or PowerShell 7) |
| **Modules** | `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications` — installed automatically if missing |
| **Entra roles** | Application Administrator to create the app; Privileged Role Administrator or Global Administrator to grant consent |
| **For RMS config** | A deployed Recast Proxy, and RMS permissions on your account |
| **For AW config** | `Liquit.Server.PowerShell.dll` and a zone API account |

> **Run in a standalone PowerShell window**, not the VS Code Integrated Console. That host keeps assemblies loaded between runs, which makes Graph SDK version conflicts unrecoverable without restarting the whole console. The script warns you if it detects this.

---

## Quick start

```powershell
# Interactive — walks through every prompt
.\New-RecastEntraAppRegistration.ps1

# Preview the permission set without touching the tenant
.\New-RecastEntraAppRegistration.ps1 -WhatIfOnly

# Recommended when switching between admin accounts
.\New-RecastEntraAppRegistration.ps1 -UseDeviceCode
```

---

## Feature catalog

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

---

## Post-creation configuration

### Right Click Tools → RMS service connection

Creates the `AzureActiveDirectory` service connection in Recast Management Server:

1. Calls `ListProxies` and displays the proxy grid
2. You pick the proxy that will use the connection
3. Submits `CreateAzureActiveDirectoryServiceConnection` with the proxy's certificate thumbprint

```powershell
.\New-RecastEntraAppRegistration.ps1 -CreateClientSecret `
    -ConfigureServiceConnection -RmsServer rms.contoso.com -AllowSelfSignedCertificate
```

Connections are created **Confirmed** by default — pass `-MarkConfirmed:$false` to leave one unconfirmed.

### Application Workspace → identity source + mail server

Loads the Liquit module, connects to the zone, and creates the Entra ID identity source. Settings follow the features you picked:

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
| `-WhatIfOnly` | Show the resolved permission set and exit. |

### Authentication

| Parameter | Description |
|---|---|
| `-UseDeviceCode` | Bypass the Windows WAM broker and sign in with a device code. |
| `-ReuseGraphSession` | Accept an existing Graph session instead of forcing a fresh sign-in. |
| `-Force` | Skip the "create in THIS tenant?" confirmation. |

### Module handling

| Parameter | Description |
|---|---|
| `-AutoInstallModules` | Install missing modules without prompting. |
| `-ModuleScope` | `CurrentUser` (default) or `AllUsers`. |
| `-CleanConflictingModules` | Remove mismatched `Microsoft.Graph.*` versions without prompting. |

### RMS

| Parameter | Description |
|---|---|
| `-ConfigureServiceConnection` | Create the RMS service connection after the app registration. |
| `-RmsServer` | RMS server, e.g. `rms.contoso.com`. |
| `-RmsPort` | Default 444. Dev installs often use 44339. |
| `-AllowSelfSignedCertificate` | Skip TLS validation for self-signed RMS certificates. |

### Application Workspace

| Parameter | Description |
|---|---|
| `-ConfigureIdentitySource` | Create the Entra ID identity source after the app registration. |
| `-IdentitySourceName` | Identity source name. Must match the NETBIOS name if hybrid-joined — case sensitive. |
| `-IdentitySourceDisplayName` | Friendly name shown on the sign-in button. |
| `-ZoneCredential` | Zone API account. Username defaults to `local\admin`. |
| `-AwModulePath` | Path to `Liquit.Server.PowerShell.dll` if not in a standard location. |
| `-MailServerName` | Mail server name. Defaults to `Microsoft Graph`. |
| `-MailServerFrom` | Sender address. Must be a real mailbox the app can send as. |

---

## Troubleshooting

### Sign-in hangs on "Just a moment..."

The Windows Web Account Manager broker is wedged. Close the dialog and re-run with `-UseDeviceCode`, which bypasses the broker entirely.

### `Method 'GetTokenAsync' ... does not have an implementation`

Two versions of the Graph SDK are visible to .NET in the same session. Close **all** PowerShell windows including the VS Code terminal, open a new elevated window, and run with `-CleanConflictingModules`. The disk cleanup persists; the poisoned session cannot be repaired because .NET cannot unload assemblies.

### `LiquitContext — No connection is available to service this operation`

The Liquit module is loaded but not connected to a zone. The script now detects this and stops rather than reporting false success. Supply `-ZoneCredential`, or connect first with `Connect-LiquitWorkspace`.

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

## Known gaps

- **Set Autopilot Group Tag** and **Remove Device(s) from Autopilot** are not separate catalog entries. Both operate on the same `windowsAutopilotDeviceIdentities` resource as *Register Device(s) in Autopilot*, so selecting feature 4 is expected to cover them — but Recast has not published this, so treat it as likely rather than confirmed.
