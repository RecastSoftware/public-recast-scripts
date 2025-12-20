# RMS Role Manager (Robot Edition v2.1)

## Overview

The **RMS Role Manager** is a standalone PowerShell GUI application designed to simplify the administration of Recast Management Server (RMS) roles. It replaces manual API calls with a user-friendly interface for creating, cloning, exporting, and deleting roles.

This version features a custom **"Pixel Robot" dark theme**, embedded assets for portability, live color-coded logging, and a **new hierarchical wizard** for building roles without needing to know specific API permissions.

## 🚀 New Features (v2.1)

* **Create Role Wizard:** A checkbox-driven interface to build roles by selecting logical tools (e.g., "Remote Software Center", "BitLocker Compliance") rather than raw permissions.
* **Safety Checks:**
* **Duplicate Protection:** Automatically checks if a role name already exists before creation to prevent conflicts.
* **Delete Safety:** Before deleting a role, the tool queries the RMS API to see if any users are currently assigned to it. If users are found, a warning lists them and requires explicit confirmation.


* **Console Dashboards:** Full permission mapping for all major dashboards (AD Cleanup, Hardware Audit, Content Monitor, BitLocker, LAPS, SUDS).
* **Real-Time Progress:** Added logic for the live stream to show individual actions, so it doesn't wait till the end to add them all, in large action sets, it is now easy to see the tool is working, instead of freezing up the UI.

## 🛠️ Tool Categories

The Create Role Wizard maps permissions to the following logical structure:

### 1. Device Management

* **Client Actions/Tools:** Application/Discovery Cycles, Remote Software Center, Repair Client, Client Info.
* **Console Tools:** AD/Entra Groups, System Info, Delete Devices, Ping, Restart/Shutdown.
* **Security Tools:** BitLocker Keys (AD/MBAM/ConfigMgr), LAPS Password, Remote Windows Security.

### 2. User Management

* Unlock Account, Reset Password, Add/Remove from Groups, User Devices, User Status Messages.

### 3. Application Management

* **Content Status:** Full suite (Add/Remove/Validate/Redistribute content).
* **Tools:** Deployment Launcher, Open Content Source Path, View Release Notes, Application Revision History.

### 4. Content Distribution

* **Tools:** Task Sequence Content Info, Distribution Point Status Messages (Standard & PXE).
* **Actions:** Redistribute All Failed Content Transfers, Distribution Content Status.

### 5. Console Dashboards

* **Active Directory Cleanup Tool** (includes 30+ dependency permissions)
* **Hardware and Firmware Audit**
* **Content Distribution Monitor**
* **BitLocker Compliance**
* **LAPS Dashboard**
* **Software Updates Deployment Status (SUDS)**

## 📋 Prerequisites

* **OS:** Windows 10 / Server 2016 or higher.
* **PowerShell:** Version 5.1 (Required for WPF).
* **Network:** Access to the RMS Server URL (HTTPS).
* **Permissions:** The account running the tool must have Administrator access within RMS to Create/Delete roles.

## ⚙️ Configuration

At the top of the script, you can toggle specific settings:

```powershell
$DefaultRMS = "https://cs-rms.cs.recastsoftware.com:444"

```

## 🏃 How to Run

### Option 1: Running the Executable (Recommended)

If compiled to `.exe`:

1. Double-click **RMS_Manager.exe**.
2. Click **Yes** on the UAC (Administrator) prompt.
3. Enter your RMS URL when prompted (defaults to the last known configuration).

### Option 2: Running the Script (.ps1)

If running the raw script, you must ensure it runs with **Admin rights** and in **STA Mode**.

1. Right-click the script or shortcut.
2. Select **Run with PowerShell**.
3. *Note: The script contains self-elevation logic; if you are not Admin, it will attempt to restart itself as Administrator.*

## 📖 Usage Guide

### 1. Authentication

* **Windows Default:** Uses the credentials of the currently logged-in Windows user.
* **Explicit Creds:** Select this radio button and click **Apply** to enter a different username/password.

### 2. Managing Roles

* **Create New Role:** Opens the new Wizard. Select the tools you want, and the script automatically assigns the dozens of underlying permissions required.
* **Clone Role:** Select a role -> Click **Clone**. Copies all permissions to a new name.
* **Delete Role:** Select a role -> Click **Delete**. *Checks for assigned users first.*
* **List Perms:** Opens a popup window showing every permission assigned to the selected role.

### 3. CSV Import/Export

* **Export:** Select a role and click **Export**. A CSV file will be generated in `C:\temp\RMSRoles\`.
* **Import:** Click **Import**, select a CSV file, and provide a name for the new role.

## 📦 Compiling to EXE (For Developers)

To update the executable after modifying the `.ps1` script, use the **PS2EXE** module.

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

## ⚠️ Troubleshooting

**"The term '...' is not recognized"**

* *Cause:* Script execution order issue in older versions.
* *Fix:* Ensure you are using the latest version (v2.1) where functions are defined *before* the execution block.

**"Access Denied" / 403 Forbidden**

* *Cause:* The account you are using does not have permission in RMS to perform that specific action. Check the Live Log for details.

**UI Freezes during creation**

* *Cause:* Large roles take time to process API calls.
* *Fix:* The v2.1 update includes a Progress Bar and background refreshing to prevent "Not Responding" states.

**Background image missing**

* *Fix:* The image is embedded as Base64. If the background is black/blue, ensure the Base64 string in the script variable `$Base64RobotImage` is intact.