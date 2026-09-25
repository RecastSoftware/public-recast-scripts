# 🤖 RMS Role Manager

> **A practical PowerShell WPF utility for managing Recast Management Server roles, permissions, users, groups, and assignments.**

Role Management • Dynamic Builder Actions • Privileged Access • Version-Aware Filtering • User & Group Administration

---

## 📖 Overview

**RMS Role Manager** replaces repetitive RMS API work with a graphical interface for creating, editing, cloning, renaming, importing, exporting, and deleting roles. Administrators select recognizable Right Click Tools capabilities while the utility resolves the underlying RMS plugin and permission mappings.

The current release includes the embedded **Pixel Robot** theme, live color-coded logging, progress reporting, dynamic Builder Actions, a dedicated Privileged Access permission model, version-aware filtering, and safeguards that protect existing RMS configuration.

---

## ✨ Key Features

### 🛡️ Role Management and Safe Editing
- List RMS roles and review assigned permissions.
- Create roles through a categorized checkbox-driven wizard.
- Edit roles in place without deleting and recreating them.
- Preview additions and removals before saving.
- Clone roles with permission-copy and verification progress.
- Rename, import, export, and safely delete roles.
- Create a pre-edit CSV snapshot.
- Preserve partially granted, unmapped, unavailable, and shared permissions.
- Produce no changes when a role is opened and saved unchanged.

### 🧩 Dynamic Builder Actions
- Retrieve the permission catalog through `GetAllPermissions`.
- Discover permissions associated with the `BuilderAction` plugin.
- Display Builder Actions in **Create Role** and **Edit Role**.
- Use action descriptions as friendly labels when available.
- Preserve the exact RMS permission value, including unique identifiers.
- Refresh dynamic actions whenever either role wizard opens.
- Append `RunSavedAction` to every Builder Action so the saved action window is accessible.
- Verify `RunSavedAction` exists in `GetAllPermissions` before appending it, so older servers are not filtered out.

### 🔐 Privileged Access
- Adds a dedicated **Privileged Access** category, nested by surface so the tree makes the distinction explicit:
  - **Right Click Tools** — ConfigMgr console extension actions (Generate Activation Code, Retrieve Local Account Password).
  - **Recast Management Server** — RMS web portal access, split into three tiers:
    - **View and Retrieve** — operator tier; agent lookup, activation code generation, password retrieval.
    - **Modify Configuration** — administrator tier; targets, target groups, user/group/self-service rules, local accounts, and global settings.
    - **Read Reports** — reporting tier; historical activation code and password-retrieval activity.
- Shares RMS console-shell permissions (`GetAllSettings`, `GetGlobalConfigurationIssues`) across all three Recast Management Server tiers so each renders correctly when held independently, without portal configuration errors.
- Renders Privileged Access last in both Create Role and Edit Role so the standard categories stay on top.
- Excludes only the specific permission that is unavailable or below the required RMS version — not the entire tool — so a tier with one unsupported permission still appears with the rest of its capabilities intact.

### 🧭 Version-Aware Filtering
- Detect the RMS host from the configured URL.
- Read local uninstall registry data when RMS is installed locally.
- Use PowerShell remoting and Remote Registry for remote RMS hosts.
- Display the detected RMS version in the lower-right footer.
- Combine `GetAllPermissions` with a maintained minimum-version catalog, evaluated per permission.
- Hide only the individual permissions unsupported by the connected environment.
- Preserve already assigned permissions that are unavailable in the current catalog.

### 👥 Users, Groups, and Membership
- List users and groups registered with RMS.
- Display assigned and available roles.
- Assign or remove one or multiple roles.
- Register new users and groups before assignment.
- Preserve existing role IDs and scope filters.
- Remove one or multiple principals from RMS.
- Open a role-first membership view.
- Add or remove members and refresh the grid immediately.
- Export principal assignments and role membership to CSV.
- Prevent a registered principal from being silently left without a role.

### 🔐 Authentication and Diagnostics
- Support Windows default authentication and explicit credentials.
- Display the current API identity as **Connected as** in the footer.
- Display the active RMS URL and detected RMS version in the footer.
- Convert authorization failures into clear user-facing messages.
- Provide live `INFO`, `SUCCESS`, `WARN`, and `ERROR` logging.
- Display progress for long-running operations.

---

## 🗂️ Permission Categories

The Create Role and Edit Role wizards organize permissions into:

- **Device Management**
  - Client Actions
  - Client Tools
  - Console Tools
  - Security Tools
  - Remote Tools
- **User Management**
- **Application Management**
- **Content Distribution**
- **Console Dashboards**
- **Builder Actions**
- **Privileged Access**
  - Right Click Tools
  - Recast Management Server
    - View and Retrieve
    - Modify Configuration
    - Read Reports

> Multi-permission capabilities appear once in the tree while retaining every required plugin and permission mapping.

---

## 🖥️ Remote Tools

### 📁 Remote File Explorer
- Browse (Read-Only)
- Modify Files
- Delete Files

### 🧰 Remote Registry
- Browse (Read-Only)
- Modify Keys and Values
- Delete Keys and Values

Browse permissions are included when required by higher capability levels. Unsupported permission and ownership actions remain documented in the source but disabled.

---

## ✅ Prerequisites

- Windows 10, Windows Server 2016, or later.
- Windows PowerShell 5.1.
- STA mode for WPF.
- Network access to the RMS URL.
- An RMS account authorized for the intended operations.
- Windows host access when remote registry-based version detection is required.

> **Note:** If neither PowerShell remoting nor Remote Registry is available for a remote RMS host, version filtering is skipped unless a verified fallback version is configured.

---

## ⚙️ Configuration

### 🌐 Default RMS URL
```powershell
$DefaultRMS = 'https://rms-server.contoso.com:444'
```

### 🧪 Switch RMS Testing Mode

The **SWITCH RMS** button is intended for multi-environment testing. It is hidden and disabled by default.

**Persistent (survives restarts):**
```powershell
$script:EnableRmsSwitch = $false
```

Enable the testing-only workflow persistently with:
```powershell
$script:EnableRmsSwitch = $true
```

**Session-only reveal — no configuration required:**

Press **F9** at any time to toggle Switch RMS visibility for the current session only. The button returns to hidden the next time the application launches, regardless of whether F9 was used previously. This is the recommended way to access the control for one-off testing without editing the script.

When enabled or revealed, Switch RMS validates the new URL, tests connectivity, clears environment-specific data, reloads permissions and roles, and restores the previous RMS environment if the switch fails.

### 🏷️ Version Detection Overrides

Use a host override when the RMS URL points to an alias, proxy, load balancer, or VIP:
```powershell
$Global:RmsVersionDiscoveryHost = 'RMS-SERVER-01'
```

Provide a verified fallback only when automatic detection is unavailable:
```powershell
$Global:RmsConfiguredServerVersion = '5.12.2608.1403'
```

### 📚 Minimum-Version Catalog

Minimum versions are maintained per friendly tool and, where only a single permission within a tool is version-gated, per individual permission — because `GetAllPermissions` can expose a permission on some servers before the rest of the tool's capability is available elsewhere.

```powershell
$Global:RmsToolMinimumVersionCatalog = @{
    'console tools|restart intune management extension service' = @{
        MinimumVersion = '5.11.2606.2905'
        SourceType      = 'Minimum Right Click Tools Version'
        Source          = 'What''s New in Right Click Tools'
        Notes           = 'Restart the Intune Management Extension Service'
    }
}

$Global:RmsPermissionMinimumVersionCatalog = @{
    'privilegemanager|refreshsettings' = @{
        MinimumVersion = '5.12.2607.2401'
        SourceType      = 'Minimum Right Click Tools Version'
        Source          = 'What''s New in Right Click Tools'
        Notes           = 'Refresh Agent Settings'
    }
}
```

> Add or change minimum-version requirements only after validating them against an authoritative product source.

---

## 🚀 Running the Application

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\RMSRoleManager.ps1
```

The script includes elevation handling when administrative rights are required.

---

## 🧭 Common Workflows

### ➕ Create a Role
1. Select **CREATE NEW ROLE**.
2. Select the required tools or categories.
3. Review the resolved permissions.
4. Enter a unique role name.
5. Create the role and monitor progress.

### ✏️ Edit a Role
1. Select a role and choose **EDIT ROLE**.
2. Review the current selections.
3. Change the required tools.
4. Preview additions and removals.
5. Apply the changes.

> Opening and saving an unchanged role should produce no permission changes.

### 🧬 Clone a Role
1. Select the source role and choose **CLONE ROLE**.
2. Enter a unique destination name.
3. Monitor copy and verification progress.

### 👤 Manage Users and Groups
1. Select **MANAGE USERS & GROUPS**.
2. Select a registered principal.
3. Review assigned and available roles.
4. Assign, revoke, export, or remove as needed.

### 👀 View Role Members
1. Select a role and choose **VIEW MEMBERS**.
2. Add, remove, or export members.

When removing a principal's final role, the utility requires a replacement role, principal removal, or cancellation.

### 🔐 Grant Privileged Access
1. Select **CREATE NEW ROLE** or **EDIT ROLE**.
2. Expand **Privileged Access** at the bottom of the tree.
3. Choose **Right Click Tools** for console extension actions, or **Recast Management Server** for portal access.
4. Under Recast Management Server, select **View and Retrieve** for day-to-day operator use, **Modify Configuration** for administrative changes, and/or **Read Reports** for reporting-only access.
5. Save the role as usual.

### 🧪 Reveal Switch RMS for Testing
1. Press **F9** from the main window.
2. Use **SWITCH RMS** in the upper-right to connect to a different environment.
3. Press **F9** again to hide it, or simply relaunch the application — the reveal does not persist.

### 📄 CSV Import and Export
- **EXPORT ROLE CSV:** Exports the selected role definition.
- **IMPORT ROLE CSV:** Creates a role from a selected CSV file.
- Output is written to the configured export directory.

---

## 📦 Compiling to EXE

```powershell
Invoke-PS2EXE `
    -InputFile '.\RMSRoleManager.ps1' `
    -OutputFile '.\RMSRoleManager.exe' `
    -Icon 'C:\Windows\System32\imageres.dll,15' `
    -NoConsole `
    -RequireAdmin `
    -STA
```

- `-NoConsole` hides the PowerShell console.
- `-RequireAdmin` requests elevation.
- `-STA` is required for WPF.

---

## 🩺 Troubleshooting

**🚫 User is not authorized**
The selected account is not authorized for the requested RMS API action. Apply a different authorized account or contact an RMS administrator.

**🏷️ RMS version shows Unavailable**
- Confirm the RMS URL resolves to the Windows server hosting RMS.
- Verify the **Recast Management Server** uninstall entry contains `DisplayVersion`.
- For a remote server, verify PowerShell remoting or Remote Registry access.
- Set `$Global:RmsVersionDiscoveryHost` when the URL uses an alias or proxy.
- Use `$Global:RmsConfiguredServerVersion` only as a verified fallback.

**🧩 Builder Actions do not appear**
- Review the Live Stream for `GetAllPermissions` results.
- Confirm the catalog contains permissions using the `BuilderAction` plugin.
- Review the raw permission-catalog JSON when diagnostic output is enabled.

**🔎 A tool or permission is missing from Create or Edit**
The specific permission may have been excluded because it was absent from `GetAllPermissions` on the connected server, or the detected RMS version is below its maintained minimum version. Only the affected permission is hidden — the rest of the tool's capabilities remain available. Review the Live Stream for the exact exclusion reason.

**🔐 A Privileged Access tier appears with fewer options than expected**
This is expected behavior on older RMS builds. For example, **View and Retrieve** will render without Refresh Agent Settings on servers older than 5.12.2607.2401, while its other permissions remain available. Check the Live Stream for a line identifying the specific excluded permission and its minimum version.

**⌨️ F9 does not reveal Switch RMS**
Confirm the main window has focus. Some remote session tools intercept certain key combinations; F9 alone was chosen specifically to reduce this conflict, but on-screen keyboard input can be used as a fallback in remote sessions where hardware keys are intercepted before reaching the guest application.

**⏳ The UI appears busy**
RMS changes use individual synchronous API requests. The interface refreshes between requests, but it can pause while a single request is in progress.

**🖼️ The background image is missing**
The theme images are embedded as Base64 values. Verify the image variables remain intact.

---

## ⚠️ Safety Notes

- Test changes with non-production roles and principals first.
- `UpdateUserRolesAndScopes` replaces a principal's complete role set. Existing role records and scope filters must be included in every update.
- Newly assigned roles receive the default unrestricted RMS filter unless additional scoping is configured.
- Unmanaged and unavailable permissions are preserved during role editing.
- Batch principal deletion performs one request per principal and can partially succeed.
- Internal RMS API routes may change between releases.
- Privileged Access grants elevated capability over agent credentials and configuration. Assign **Modify Configuration** only to administrators who require it.

---

## 👨‍💻 Author

**Chris Antoku**

> Current enhancements include dynamic Builder Actions, a dedicated Privileged Access permission model with per-tier RMS console access, per-permission version-aware filtering, an F9 session-only Switch RMS reveal, safe in-place role editing, progress-enabled cloning and import, user and group administration, role membership management, and connected identity display.
