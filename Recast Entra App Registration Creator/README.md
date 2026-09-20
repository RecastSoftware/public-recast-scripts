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
7. **Optionally configures the product** — an RMS service connection for Right Click Tools, or an identity source and Graph mail server for Application Workspace. Both paths verify the result and offer a guided retry or cleanup if something is wrong, rather than just reporting success.

Permission GUIDs are resolved **live** from the Microsoft Graph service principal in the target tenant. Nothing is hardcoded, so nothing drifts when Microsoft changes an ID. If a permission name cannot be resolved, the script aborts before writing anything.

Already have an app registration? See [Existing app registration mode](#-existing-app-registration-mode) to skip straight to step 7, or to audit which product features an existing app can actually support.

---

## 📋 Requirements

| | |
|---|---|
| **PowerShell** | 5.1 or later (Windows PowerShell or PowerShell 7) |
| **Modules** | `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications` — installed automatically when Microsoft Graph access is required. Not required when using `-ExistingAppId` together with `-SkipAppValidation`. |
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
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '' -WhatIfOnly

# Configure an existing RMS service connection without loading Graph modules
.\New-RecastEntraAppRegistration.ps1 `
    -ExistingAppId '' `
    -TenantId '' `
    -SkipAppValidation `
    -ConfigureServiceConnection `
    -RmsServer rms.contoso.com `
    -AllowSelfSignedCertificate

# Configure an existing Application Workspace identity source without Graph modules
.\New-RecastEntraAppRegistration.ps1 `
    -ExistingAppId '' `
    -TenantId '' `
    -SkipAppValidation `
    -ConfigureIdentitySource `
    -ZoneUrl 'https://contoso.recastsoftware.cloud' `
    -IdentitySourceName 'EntraID' `
    -IdentitySourceDisplayName 'Recast Software'
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
[How to Setup Microsoft Entra App Registration to use as an Application Workspace Identity Source](https://scribehow.com/o/xf43\_qHmRXqaTl4dNDHGFA/viewer/How\_to\_Setup\_Microsoft\_Entra\_App\_Registration\_to\_use\_as\_an\_Application\_Workspace\_Identity\_Source\_\_UmRbqg\_rSqORT\_QX2UTqZQ)\
[Configure Single Sign-On with Microsoft Entra ID](https://docs.recastsoftware.com/help/lws-login-single-sign-on-sso-with-azure-active-directory)

---

## 🔍 Existing app registration mode

Use `-ExistingAppId` when the app registration already exists and only the product-side configuration is missing — a common situation when the app was created weeks earlier, created by someone else, or **owned by a different team than the one running this script** (see [Segregated ownership](#segregated-ownership--restricted-accounts) below).

```powershell
# RMS service connection against an existing app
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '' `
    -ConfigureServiceConnection -RmsServer rms.contoso.com -AllowSelfSignedCertificate

# Application Workspace identity source against an existing app
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '' `
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

#### Segregated ownership / restricted accounts

A common real-world scenario: the app registration was created by one team (or one tenant admin), and the person running this script to configure RMS or Application Workspace has only the client ID, tenant ID, and a client secret — **not** rights to read the app registration itself in Entra.

The script is designed to degrade gracefully in every one of these cases rather than stop:

| What fails | What happens |
|---|---|
| Graph sign-in itself fails (no rights in the tenant at all) | Warns, prompts for the Directory (tenant) ID if not supplied with `-TenantId`, and continues using the supplied values. |
| Sign-in succeeds, but reading the app registration returns Access Denied / 403 | Warns that permissions and feature coverage cannot be verified, and continues using the supplied App ID. |
| The app registration is not returned by Graph (wrong ID, wrong tenant, or no read rights) | Warns with the possible causes, and continues rather than assuming the ID is wrong. |

In every case above, configuration still proceeds using the App ID, tenant ID, and secret you supplied — it just cannot show you the feature coverage report, since that report requires reading the app's actual permission grants. If you want to skip the sign-in attempt entirely (for example, you already know the account has no rights), use `-SkipAppValidation` instead of waiting for it to fail.

#### Audit only

Combine `-ExistingAppId` with `-WhatIfOnly` to run the report and stop — no secret prompt, nothing configured:

```powershell
.\New-RecastEntraAppRegistration.ps1 -ExistingAppId '' -WhatIfOnly
```

This is the fastest way to answer "what can this app registration actually do?" for an app someone else created. If the account cannot read the app (see above), the report cannot run, and the script says so rather than returning an empty or misleading result.

#### Skipping validation and Graph module checks

Pass `-SkipAppValidation` together with `-ExistingAppId` to enter **configuration-only mode**.

In this mode the script:

- Does **not** install or import Microsoft Graph modules.
- Does **not** clean or align Graph SDK versions.
- Does **not** connect to Microsoft Graph.
- Does **not** validate the app registration.
- Does **not** build the feature coverage report.
- Does **not** modify the app registration or grant consent.

Instead, the script goes directly to configuring RMS or Application Workspace using the supplied:

- Application (client) ID
- Directory (tenant) ID
- Client secret value

This mode is intended for implementation teams that have been provided credentials but do not have permission to read or manage the Entra application itself.

For RMS, no Microsoft Graph or Application Workspace module is required.

For Application Workspace, only `Liquit.Server.PowerShell` is required.

You will be prompted for the Directory (tenant) ID if `-TenantId` is omitted.

`-SkipAppValidation` cannot be combined with `-WhatIfOnly`, because the feature coverage report requires Microsoft Graph.

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

1. Connects to RMS and calls `ListProxies`, displaying the proxy grid.
2. You pick the proxy that will use the connection (its certificate thumbprint protects the client secret).
3. **Checks for a duplicate** — a connection already pointed at the *same tenant and same client ID* — before creating anything.
4. Validates the credentials against RMS, then creates (or updates) the connection and tests it.

```powershell
.\New-RecastEntraAppRegistration.ps1 -CreateClientSecret `
    -ConfigureServiceConnection -RmsServer rms.contoso.com -AllowSelfSignedCertificate
```

Connections are created **Confirmed** by default — pass `-MarkConfirmed:$false` to leave one unconfirmed.

#### Duplicate detection

RMS does not upsert on create — submitting the same tenant/client twice creates a **second row**, not an update to the first. The script checks for an existing connection matching the *same tenant and same client ID* (matching on tenant alone would be a false positive: one tenant can legitimately hold several connections against different app registrations, e.g. one per product). If a match is found, you are asked:

```
    (U)pdate the existing connection, (C)reate a new one anyway, or (Q)uit? [U/c/q]
```

Update is the default and the confirmed-working path for correcting a connection's client ID, secret, or proxy in place.

#### Retry and cleanup on a failed credential test

After creating or updating the connection, the script tests it. If the test fails (most commonly a pasted Secret ID instead of the Secret value, or an expired secret), the script:

1. Identifies whether the failure is one that re-entering the secret could plausibly fix (a bad or expired secret, wrong tenant/client) versus one it can't (missing admin consent).
2. If retryable, offers to re-enter the client secret and try again — up to 3 attempts, applied via an in-place **update** to the same connection rather than creating another row.
3. If you decline to retry, the failure isn't retryable, or attempts are exhausted, offers to **delete** the unconfirmed connection rather than leave a known-broken row sitting in Service Connections indefinitely.

```
    [FAIL] Synchronization failed: ... AADSTS7000215: Invalid client secret provided...
    [WARN] The secret VALUE was rejected - likely the Secret ID was entered instead.
    Re-enter the client secret and try again? (Y/n):
```

#### A note on test results

RMS's own **Audit Log** (Administration → Audit Log) is the confirmed, reliable source of truth for whether a credential test passed or failed. The synchronous HTTP response body for the test actions has not been reliably confirmed to carry an accurate signal in every case, so the script treats a test call that did not throw an exception as **"submitted for validation,"** not as a confirmed pass — and points you at the Audit Log to check the real result:

```
    [ OK ] Credentials submitted for validation
           Confirm the result in RMS: Administration > Audit Log
```

A confirmed **failure** (the credentials were rejected outright, surfaced as a thrown error) is always trustworthy and drives the retry/cleanup flow above.

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

#### Sync verification, retry, and cleanup

Creating the identity source only *stores* configuration — Application Workspace does not actually present the client secret to Entra until it **synchronizes**. The script triggers that sync immediately afterward and classifies the result into one of three outcomes, bounded by a short timeout so a slow-but-legitimate sync does not block the rest of the run:

- **Confirmed success** — the sync task reports a `Success` state. The script prints `[ OK ] Identity source '<name>' synchronized successfully.` and moves on immediately; nothing further is required.
- **Confirmed failure** (bad secret, wrong tenant) — these have been observed to surface quickly. The script offers to re-enter the secret and retry, up to 3 attempts, correcting the same identity source in place rather than creating a duplicate. If you decline, the failure isn't retryable (e.g. missing admin consent), or attempts run out, it offers to **delete the identity source** rather than leave a broken one in the UI.
- **Unresolved when the timeout is hit** — treated as "probably a normal sync still running in the background," *not* a failure. The script does **not** retry or prompt in this case; it logs a note and moves on. A Microsoft Graph mail server (if selected) is still created in this case — only a *confirmed* sync failure blocks it.

```
==> Synchronizing identity source 'CO' (attempt 1 of 3, up to 20 sec)
    [ OK ] Identity source 'CO' synchronized successfully.
```

If the secret is wrong, you'll instead see the sync fail with the real Entra error, followed by a chance to correct it in place:

```
==> Synchronizing identity source 'CX' (attempt 1 of 3, up to 20 sec)
    [FAIL] Synchronization failed: ... AADSTS7000215: Invalid client secret provided...
    [WARN] The secret VALUE was rejected - likely the Secret ID was entered instead.
    Re-enter the client secret and try again? (Y/n): y
    [ OK ] Client secret updated on 'CX'.

==> Synchronizing identity source 'CX' (attempt 2 of 3, up to 20 sec)
    [ OK ] Identity source 'CX' synchronized successfully.
```

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
| `-SkipAppValidation` | When combined with `-ExistingAppId`, activates configuration-only mode. Skips Graph module installation/import, Graph sign-in, app validation, and the feature coverage report. Prompts for the tenant ID if it is not supplied. Cannot be combined with `-WhatIfOnly`. |
| `-EnableAzurePhotos` | Set `AzurePhotos` on the identity source. Prompted for unless `-Force`. |
| `-EnableGroupWrite` | Set `AzureWriteMode` to `GroupMembership`. Prompted for unless `-Force`. |
| `-ConfigureMailServer` | Also create the Graph mail server. Prompted for unless `-Force`. |

### Authentication

| Parameter | Description |
|---|---|
| `-UseDeviceCode` | Bypass the Windows WAM broker and sign in with a device code. |
| `-ReuseGraphSession` | Accept an existing Graph session instead of forcing a fresh sign-in. |
| `-Force` | Skip confirmation prompts. In `-ExistingAppId` mode, also takes the AW setting switches as given rather than asking, and suppresses the interactive retry/cleanup prompts on RMS and Application Workspace failures in favor of automatic behavior. |

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

### The feature coverage report did not run / "permissions cannot be verified"

The signed-in account does not have rights to read the app registration in Entra — a normal situation when the app was created by a different team than the one running this script. Configuration still proceeds using the App ID, tenant ID, and secret you supply; only the report is skipped. See [Segregated ownership / restricted accounts](#segregated-ownership--restricted-accounts).

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
Get-RmsRawResponse -Server  -Endpoint 'Administration/ListProxies' -AllowSelfSignedCertificate
```

### RMS reports "Credentials submitted for validation" instead of a clear pass/fail

This is expected. RMS's synchronous test response has not been reliably confirmed to carry an accurate pass/fail signal in every case, so the script reports the call as submitted rather than guessing. Check **Administration → Audit Log** in RMS for the authoritative result. A confirmed failure (the call throwing an error) is always trusted and will trigger the retry/cleanup flow automatically.

### The Application Workspace zone connection fails with a credential error

If the zone username or password is wrong, the script now retries automatically — up to 3 attempts — rather than failing the whole run on the first typo. If it still fails after 3 attempts, double-check the account has `zone.access.api` permission and that the zone URI is correct; those are not fixable by re-entering the same password.

### An RMS service connection or AW identity source keeps failing and I want to start clean

Let the script's retry flow run its course — after 3 attempts, or if the failure is non-retryable (e.g. missing admin consent), it offers to delete the connection or identity source it created. Accept that offer, fix the underlying issue (grant consent, correct the secret in your vault), then re-run.

### Graph modules are still being requested in configuration-only mode

Configuration-only mode is activated only when **both** of the following are supplied:

```powershell
-ExistingAppId ''
-SkipAppValidation
```

Example:

```powershell
.\New-RecastEntraAppRegistration.ps1 `
    -ExistingAppId '' `
    -TenantId '' `
    -SkipAppValidation `
    -ConfigureIdentitySource
```

Application Workspace configuration-only mode may still install or import `Liquit.Server.PowerShell`, but it should not install or import Microsoft Graph modules.

RMS configuration-only mode should not require either Microsoft Graph or Application Workspace modules.

### Module installs silently do nothing

Usually PowerShellGet 1.0.0.1, the stock version on Windows PowerShell 5.1, which reports provider failures as non-terminating errors. The script detects this and offers to bootstrap 2.2.5. Accept, then **close and reopen PowerShell** — the old version stays loaded in the current session.

---

## Notes on behaviour

- **The client secret is shown once** and is deliberately excluded from the optional summary file. Copy it into a password vault immediately.
- **Every write is verified.** The script never treats the absence of an exception as evidence of success — it reads objects back after creating them, and destructive actions (delete) are verified by re-querying afterward rather than trusting the action's own reported result.
- **Sign-in prompts every run** by default. A cached MSAL token would otherwise silently reuse whichever account authenticated last, which is how an app registration ends up in the wrong tenant.
- **Validation failures degrade gracefully, not fatally.** If the account running the script cannot read the app registration in Entra — a normal situation across segregated teams — configuration still proceeds with the values you supplied; only the verification report is skipped.
- **Failed connections and identity sources are not silently left behind.** When a credential test fails and cannot be corrected in the current run, the script offers to remove what it created rather than leave a known-broken configuration in place.
- **Application Workspace sync results are classified into exactly three outcomes** — confirmed success, confirmed failure, or unresolved/still-running — with no default fallthrough between them, so a successful sync is always reported as success rather than mistaken for a failure.
- **Zone connection retries on a bad password**, the same way RMS and Entra secret failures do, rather than failing the whole run on a single typo.
- **Configuration-only mode skips Microsoft Graph prerequisites entirely.** Use `-ExistingAppId` together with `-SkipAppValidation` to configure RMS or Application Workspace without installing, importing, or using the Microsoft Graph SDK.
- **PSGallery trust is restored** to its original value on exit if the script temporarily changed it.
