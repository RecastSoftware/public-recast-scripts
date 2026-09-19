# 🤖 RMS Role Manager

> **A practical PowerShell WPF utility for managing Recast Management Server roles, permissions, users, groups, and assignments.**

<p align="center">
  <strong>Role Management</strong> •
  <strong>Dynamic Builder Actions</strong> •
  <strong>Version-Aware Filtering</strong> •
  <strong>User &amp; Group Administration</strong>
</p>

---

## 📖 Overview

**RMS Role Manager** replaces repetitive RMS API work with a graphical interface for creating, editing, cloning, renaming, importing, exporting, and deleting roles.

Administrators select recognizable Right Click Tools capabilities while the utility resolves the underlying RMS plugin and permission mappings. The current release includes the embedded **Pixel Robot** theme, live color-coded logging, progress reporting, dynamic Builder Actions, version-aware filtering, and safeguards that protect existing RMS configuration.

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

### 🧭 Version-Aware Filtering

- Detect the RMS host from the configured URL.
- Read local uninstall registry data when RMS is installed locally.
- Use PowerShell remoting and Remote Registry for remote RMS hosts.
- Display the detected RMS version in the lower-right footer.
- Combine `GetAllPermissions` with a maintained minimum-version catalog.
- Hide tools that are unsupported by the connected environment.
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

The **SWITCH RMS** button is intended for multi-environment testing. It is hidden, disabled, and does not register its click handler by default.

```powershell
$script:EnableRmsSwitch = $false
```

Enable the testing-only workflow with:

```powershell
$script:EnableRmsSwitch = $true
```

When enabled, Switch RMS validates the new URL, tests connectivity, clears environment-specific data, reloads permissions and roles, and restores the previous RMS environment if the switch fails.

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

Minimum versions are maintained by friendly tool name because `GetAllPermissions` can expose permissions before the corresponding tool is available.

```powershell
$Global:RmsToolMinimumVersionCatalog = @{
    'console tools|restart intune management extension service' = @{
        MinimumVersion = '5.11.2606.2905'
        SourceType      = 'Minimum Right Click Tools Version'
        Source          = 'What''s New in Right Click Tools'
        Notes           = 'Restart the Intune Management Extension Service'
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

<details>
<summary><strong>🚫 User is not authorized</strong></summary>

The selected account is not authorized for the requested RMS API action. Apply a different authorized account or contact an RMS administrator.

</details>

<details>
<summary><strong>🏷️ RMS version shows Unavailable</strong></summary>

- Confirm the RMS URL resolves to the Windows server hosting RMS.
- Verify the **Recast Management Server** uninstall entry contains `DisplayVersion`.
- For a remote server, verify PowerShell remoting or Remote Registry access.
- Set `$Global:RmsVersionDiscoveryHost` when the URL uses an alias or proxy.
- Use `$Global:RmsConfiguredServerVersion` only as a verified fallback.

</details>

<details>
<summary><strong>🧩 Builder Actions do not appear</strong></summary>

- Review the Live Stream for `GetAllPermissions` results.
- Confirm the catalog contains permissions using the `BuilderAction` plugin.
- Review the raw permission-catalog JSON when diagnostic output is enabled.

</details>

<details>
<summary><strong>🔎 A tool is missing from Create or Edit</strong></summary>

The tool may have been excluded because a required permission was absent from `GetAllPermissions` or the detected RMS version is below the maintained minimum version. Review the Live Stream for the exclusion reason.

</details>

<details>
<summary><strong>⏳ The UI appears busy</strong></summary>

RMS changes use individual synchronous API requests. The interface refreshes between requests, but it can pause while a single request is in progress.

</details>

<details>
<summary><strong>🖼️ The background image is missing</strong></summary>

The theme images are embedded as Base64 values. Verify the image variables remain intact.

</details>

---

## ⚠️ Safety Notes

- Test changes with non-production roles and principals first.
- `UpdateUserRolesAndScopes` replaces a principal's complete role set. Existing role records and scope filters must be included in every update.
- Newly assigned roles receive the default unrestricted RMS filter unless additional scoping is configured.
- Unmanaged and unavailable permissions are preserved during role editing.
- Batch principal deletion performs one request per principal and can partially succeed.
- Internal RMS API routes may change between releases.

---

## 👨‍💻 Author

**Chris Antoku**

> Current enhancements include dynamic Builder Actions, version-aware filtering, safe in-place role editing, progress-enabled cloning and import, user and group administration, role membership management, connected identity display, and optional multi-environment RMS switching.
