RMS Role Manager (Robot Edition)
Overview
The **RMS Role Manager** is a standalone PowerShell GUI application designed to simplify the administration of Recast Management Server (RMS) roles. It replaces manual API calls with a user-friendly interface for creating, cloning, exporting, and deleting roles.

This version features a custom **"Pixel Robot" dark theme**, embedded assets for portability, and live color-coded logging.

Key Features
* **Role Management:** Clone existing roles, delete obsolete roles, and view permissions instantly.
* **Bulk Operations:** Import and Export roles via CSV.
* **Live Logging:** Real-time log stream at the bottom of the window (Red for Errors, Yellow for Warnings).
* **Smart Import:** Automatically detects CSV headers from older and newer export versions.
* **Portability:** All graphical assets (background images) are embedded directly into the script/executable. No external files required.
* **Security:** Supports both Windows Integrated Auth (Default) and Explicit Credentials.

Prerequisites
* **OS:** Windows 10 / Server 2016 or higher.
* **PowerShell:** Version 5.1.
* **Network:** Access to the RMS Server URL (HTTPS).
* **Permissions:** The account running the tool must have Administrator access within RMS to Create/Delete roles.

How to Run
Option 1: Running the Executable (Recommended)If compiled to `.exe`:

1. Double-click **RMS_Manager.exe**.
2. Click **Yes** on the UAC (Administrator) prompt.
3. Enter your RMS URL when prompted (defaults to the last known configuration).

###Option 2: Running the Script (.ps1)If running the raw script, you must ensure it runs with **Admin rights** and in **STA Mode**.

1. Right-click the script or shortcut.
2. Select **Run with PowerShell**.
3. *Note: The script contains self-elevation logic; if you are not Admin, it will attempt to restart itself as Administrator.*

Usage Guide
1. Authentication
* **Windows Default:** Uses the credentials of the currently logged-in Windows user.
* **Explicit Creds:** Select this radio button and click **Apply** to enter a different username/password.

2. Managing Roles
* **Clone Role:** Select a role from the list -> Click **Clone**. You will be asked for a new name. This copies all permissions from the source to the new role.
* **Delete Role:** Select a role -> Click **Delete**. *Warning: This is permanent.*
* **List Perms:** Opens a popup window showing every permission assigned to the selected role.

3. CSV Import/Export
* **Export:** select a role and click **Export**. A CSV file will be generated in `C:\temp\RMSRoles\`.
* **Import:** Click **Import**, select a CSV file, and provide a name for the new role.
* *Supported Headers:* The tool supports both `PermissionPlugin` (Old) and `PluginName` (New) headers for maximum compatibility.



Logs
* **Live Stream:** Viewable at the bottom of the application window.
* **Log File:** A persistent log history is saved to:
`C:\temp\RMSRoles\RMSRole.log`

Compiling to EXE (For Developers)To update the executable after modifying the `.ps1` script, use the **PS2EXE** module.

**Command Line:**

```powershell
Invoke-PS2EXE `
    -InputFile ".\RmsRoleManagerWpf.ps1" `
    -OutputFile ".\RMS_Manager.exe" `
    -Icon "C:\Windows\System32\imageres.dll,15" `
    -NoConsole `
    -RequireAdmin `
    -STA

```

* **-NoConsole:** Hides the background PowerShell window.
* **-RequireAdmin:** Forces the UAC shield overlay and prompt.
* **-STA:** Mandatory for WPF/GUI applications.

Troubleshooting
* **"Access Denied" / 403 Forbidden:** The account you are using does not have permission in RMS to perform that specific action (e.g., you can View roles but not Delete them). Check the Live Log for red error messages.
* **Script closes immediately:** Ensure you are running as Administrator. If using a shortcut, ensure the "Start In" directory is correct or use the compiled EXE.
* **Background image missing:** The image is embedded as Base64. If the background is black/blue, ensure the Base64 string in the script variable `$Base64RobotImage` is intact.