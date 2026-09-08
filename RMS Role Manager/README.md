# RMS Role Manager

## Overview

**RMS Role Manager** is a standalone Windows PowerShell WPF application for administering Recast Management Server roles, permissions, users, groups, and role assignments.

The application replaces repetitive RMS API work with a graphical interface for creating, editing, cloning, renaming, importing, exporting, and deleting roles. Administrators select recognizable Right Click Tools capabilities while the application resolves the underlying RMS plugins and permissions.

The current release includes the embedded **Pixel Robot** theme, dynamic Builder Actions, version-aware tool filtering, live color-coded logging, progress reporting, and safety controls designed to protect existing RMS configuration.

## Key Features

### Role Management

- List RMS roles and review assigned permissions.
- Create roles through a categorized checkbox-driven wizard.
- Edit roles in place without deleting and recreating them.
- Preview additions and removals before saving changes.
- Clone roles with permission-copy and verification progress.
- Rename existing roles.
- Import and export role definitions through CSV.
- Check assigned users and groups before deleting a role.
- Create a pre-edit CSV snapshot before permission changes.

### Safe Permission Editing

- Distinguishes fully granted, partially granted, and absent tool definitions.
- Produces no changes when a role is opened and saved without changing selections.
- Preserves partially granted permissions unless an explicit change is made.
- Preserves permissions that are unmapped, unavailable, or shared by another selected tool.
- Removes mapped permissions only after an explicit selection change.
- Reports permission failures by plugin and permission name.

### Dynamic Builder Actions

- Retrieves the RMS permission catalog through `GetAllPermissions`.
- Discovers permissions associated with the `BuilderAction` plugin.
- Displays Builder Actions in Create Role and Edit Role.
- Uses the action description as the friendly display label when available.
- Preserves the exact RMS permission value, including its unique identifier.
- Refreshes dynamic actions when either role wizard opens.

### Version-Aware Tool Filtering

- Detects the RMS host from the configured URL.
- Reads local uninstall registry data when RMS is installed on the computer running the utility.
- Uses PowerShell remoting and Remote Registry as remote-server fallbacks.
- Displays the detected RMS version in the lower-right footer.
- Combines `GetAllPermissions` with a maintained minimum-version catalog.
- Hides tools that are not supported by the connected environment.
- Preserves already assigned permissions that are unavailable in the current catalog.
- Skips version filtering when the installed RMS version cannot be determined reliably.

### Users, Groups, and Membership

- Lists users and groups registered with RMS.
- Displays assigned and available roles for the selected principal.
- Assigns and removes one or multiple roles.
- Registers new users and groups before role assignment.
- Preserves existing role IDs and scope filters during updates.
- Removes one or multiple principals from RMS.
- Provides a role-first membership view.
- Adds or removes role members and refreshes the membership grid immediately.
- Exports principal assignments and role membership to CSV.
- Prevents a registered principal from being silently left without a role.

### Authentication and Diagnostics

- Supports Windows default authentication and explicit credentials.
- Displays the current API identity as **Connected as** in the footer.
- Displays the active RMS URL and detected version in the footer.
- Converts authorization failures into a clear user-facing message.
- Provides live INFO, SUCCESS, WARN, and ERROR logging.
- Displays progress for long-running role and membership operations.

## Permission Categories

The Create Role and Edit Role wizards organize permissions into:

- Device Management
  - Client Actions
  - Client Tools
  - Console Tools
  - Security Tools
  - Remote Tools
- User Management
- Application Management
- Content Distribution
- Console Dashboards
- Builder Actions

Multi-permission capabilities appear once in the tree while retaining all required plugin and permission mappings.

## Remote Tools

### Remote File Explorer

- Browse (Read-Only)
- Modify Files
- Delete Files

### Remote Registry

- Browse (Read-Only)
- Modify Keys and Values
- Delete Keys and Values

Browse permissions are included when required by higher capability levels. Unsupported permission and ownership actions remain documented in the source but disabled.

## Prerequisites

- Windows 10, Windows Server 2016, or later.
- Windows PowerShell 5.1.
- STA mode for the WPF interface.
- Network access to the RMS URL.
- An RMS account authorized for the intended administrative operations.
- Windows host access when remote registry-based version detection is required.

PowerShell remoting and Remote Registry are optional. If neither is available for a remote RMS host, version filtering is skipped unless a verified fallback version is configured.

## Configuration

Review the configuration section near the beginning of the script before deployment.

### Default RMS URL

```powershell
$DefaultRMS = 'https://rms-server.contoso.com:444'
```

### Switch RMS Testing Mode

The **SWITCH RMS** button is intended for multi-environment testing and is hidden and disabled by default.

```powershell
$script:EnableRmsSwitch = $false
```

Enable the testing-only workflow with:

```powershell
$script:EnableRmsSwitch = $true
```

When enabled, Switch RMS validates the replacement URL, tests connectivity, clears environment-specific data, reloads permissions and roles, and restores the previous RMS environment if the switch fails.

### Version Detection Overrides

Use a host override when the RMS URL points to an alias, proxy, load balancer, or VIP:

```powershell
$Global:RmsVersionDiscoveryHost = 'RMS-SERVER-01'
```

Provide a fallback only when automatic detection is unavailable and the installed version has been verified:

```powershell
$Global:RmsConfiguredServerVersion = '5.12.2608.1403'
```

### Minimum-Version Catalog

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

Only add or change requirements after validating them against an authoritative product source.

## Running the Application

Run the script in Windows PowerShell 5.1 with STA mode:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\RMSRoleManager.ps1
```

The script includes elevation handling when administrative rights are required.

## Usage

### Authentication

- **Windows default:** Uses the current Windows identity.
- **Explicit creds:** Prompts for a different account after selecting **APPLY**.

The selected identity appears in the footer and Live Stream.

### Create a Role

1. Select **CREATE NEW ROLE**.
2. Select the required tools or categories.
3. Review the resolved permissions.
4. Enter a unique role name.
5. Create the role and monitor progress.

### Edit a Role

1. Select a role and choose **EDIT ROLE**.
2. Review the current selections.
3. Change the required tools.
4. Preview additions and removals.
5. Apply the changes.

Opening and saving an unchanged role should produce no permission changes.

### Clone a Role

1. Select the source role and choose **CLONE ROLE**.
2. Enter a unique destination name.
3. Monitor copy and verification progress.

### Manage Users and Groups

1. Select **MANAGE USERS & GROUPS**.
2. Select a registered principal.
3. Review assigned and available roles.
4. Assign, revoke, export, or remove as needed.

### View Role Members

1. Select a role and choose **VIEW MEMBERS**.
2. Add, remove, or export members.

When removing a principal's final role, the application requires a replacement role, principal removal, or cancellation.

### CSV Import and Export

- **EXPORT ROLE CSV:** Exports the selected role definition.
- **IMPORT ROLE CSV:** Creates a role from a selected CSV file.
- Output is written to the configured RMS role export directory.

## Compiling to EXE

Use the PS2EXE module:

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

## Troubleshooting

### User Is Not Authorized

The selected account is not authorized for the requested RMS API action. Apply a different authorized account or contact an RMS administrator.

### RMS Version Shows Unavailable

- Confirm that the RMS URL resolves to the Windows server hosting RMS.
- Verify that the **Recast Management Server** uninstall entry contains `DisplayVersion`.
- For remote RMS servers, verify PowerShell remoting or Remote Registry access.
- Set `$Global:RmsVersionDiscoveryHost` when the URL uses an alias or proxy.
- Use `$Global:RmsConfiguredServerVersion` only as a verified fallback.

### Builder Actions Do Not Appear

- Review the Live Stream for `GetAllPermissions` results.
- Confirm the catalog contains permissions using the `BuilderAction` plugin.
- Review the raw permission-catalog JSON when diagnostic output is enabled.

### A Tool Is Missing from Create or Edit

The tool may have been excluded because a required permission was absent from `GetAllPermissions` or the detected RMS version is below the maintained minimum version. Review the Live Stream for the exclusion reason.

### UI Appears Busy

RMS changes use individual synchronous API requests. The interface refreshes between requests, but it can pause while a single request is in progress.

### Background Image Is Missing

The images are embedded as Base64 values. Verify that the image variables in the script remain intact.

## Safety Notes

- Test changes with non-production roles and principals first.
- `UpdateUserRolesAndScopes` replaces a principal's complete role set. Existing role records and scope filters must be included in every update.
- Newly assigned roles receive the default unrestricted RMS filter unless additional scoping is configured.
- Unmanaged and unavailable permissions are preserved during role editing.
- Batch principal deletion performs one request per principal and can partially succeed.
- Internal RMS API routes may change between product releases.

## Author

**Chris Antoku**

Current enhancements include dynamic Builder Actions, version-aware filtering, safe in-place role editing, progress-enabled cloning and import, user and group administration, role membership management, connected identity display, and optional multi-environment RMS switching.