#requires -version 5.1
<#
RMS Role Manager – "Robot Theme" Edition
- Includes all previous functionality (Delete, Live Log, 403 Error Handling)
- New "Create Role" Wizard mapped to Right Click Tools Categories
- Feature: Selecting a Category automatically selects all tools inside it
- Feature: Verification list now shows Category and Action Name
- Feature: Tools are listed in the exact order they appear in the RCT Menus
- Updated: Added full permission set for 'Remote Software Center'
- Updated: Create Role Wizard supports background image
- Updated: Fixed TaskSequenceInformation plugin mapping
- Updated: Added EvaluateConfigurationBaseline and StartTaskSequence permissions
- Updated: Comprehensive permission updates for AD, LocalActions, Graph, and Entra tools
- Updated: Replaced QueryAD with SearchADGroups; Removed MicrosoftGraph SyncAppAndCompliance
- Updated: Adjusted Azure Delete permissions and added Entra Group Membership permission
- Updated: Added GetAccountGroupMembership to AD Security Groups
- Updated: Added DeleteDeviceFromEntra to Azure tool
- Updated: Fully populated 'System Information' permissions
- Updated: Reordered 'Security Tools' to match RCT menu context
- Updated: Added all 'BitLocker Status' permissions to 'Remote Windows Security'
- Updated: Tree Structure: 'Device Management' now contains nested sub-menus for Actions/Tools/Console/Security
- Updated: Added User Management, App Management, and Content Distribution categories
- Updated: FIXED XAML - Replaced recursive DynamicResource with cascading StaticResources
- Updated: FIXED DUPLICATES - Tree generation now deduplicates tool names so multi-permission tools appear once
- Updated: ADDED REAL-TIME PROGRESS - Added ProgressBar and UI Refresh logic to show updates live
- Updated: DELETE SAFETY CHECK - Checks all users for role assignment before deletion
- Updated: FIXED API METHOD - Changed GetRolesForUser to GET with Query String parameters
- Updated: Moved Content tools to Application Management
- Updated: Added Open Content Source, Deployment Launcher, and full Content Distribution suite
- Updated: DUPLICATE CHECK - Prevents creating a role if the name already exists
- Updated: Added 'View Update Release Notes' to Application Management
- Updated: Added 'Console Dashboards' category and populated 'Active Directory Cleanup Tool' permissions
- Updated: Populated 'Hardware and Firmware Audit' permissions
- Updated: Populated 'Content Distribution Monitor' permissions
- Updated: ADDED EXPORT DEFINITIONS BUTTON - Exports master list of actions to CSV

Author: Chris Antoku
Updated: Added Export Definitions Button
#>

# ---------------------------- C# Class for TreeView Logic ----------------------------
$cSharpSource = @"
using System;
using System.Collections.ObjectModel;
using System.ComponentModel;

public class RmsTreeItem : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler PropertyChanged;
    private bool _isChecked;
    
    public string Name { get; set; }
    public string Category { get; set; }      
    public string PluginName { get; set; }    
    public string PermissionName { get; set; } 
    public ObservableCollection<RmsTreeItem> Children { get; set; }

    public RmsTreeItem()
    {
        Children = new ObservableCollection<RmsTreeItem>();
    }

    public bool IsChecked
    {
        get { return _isChecked; }
        set
        {
            if (_isChecked != value)
            {
                _isChecked = value;
                OnPropertyChanged("IsChecked");

                if (Children != null)
                {
                    foreach (var child in Children)
                    {
                        child.IsChecked = value;
                    }
                }
            }
        }
    }

    protected void OnPropertyChanged(string name)
    {
        if (PropertyChanged != null)
        {
            PropertyChanged(this, new PropertyChangedEventArgs(name));
        }
    }
}
"@
try { Add-Type -TypeDefinition $cSharpSource -Language CSharp } catch {}

# ---------------------------- Assembly Loads ----------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# ---------------------------- STA Check ----------------------------
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host "This GUI requires STA. Run: powershell -STA -File .\RmsRoleManagerWpf.ps1" -ForegroundColor Yellow
    return
}

# ---------------------------- DEFINITIONS: Tool Mappings ----------------------------
$Global:RmsToolMap = @(
    # ========================== CLIENT ACTIONS ==========================
    [pscustomobject]@{ Cat="Client Actions"; Name="Application Deployment Evaluation Cycle"; Plugin="ConfigMgrClient"; Action="ApplicationDeploymentEvaluationCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Discovery Data Collection Cycle"; Plugin="ConfigMgrClient"; Action="DiscoveryDataCollectionCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="File Collection Cycle"; Plugin="ConfigMgrClient"; Action="FileCollectionCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Hardware Inventory Cycle"; Plugin="ConfigMgrClient"; Action="HardwareInventoryCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Machine Policy Retrieval and Evaluation Cycle"; Plugin="ConfigMgrClient"; Action="MachinePolicyRetrievalAndEvaluationCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Send Unsent State Messages"; Plugin="ConfigMgrClient"; Action="SendUnsentStateMessages" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Software Inventory Cycle"; Plugin="ConfigMgrClient"; Action="SoftwareInventoryCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Software Metering Usage Report Cycle"; Plugin="ConfigMgrClient"; Action="SoftwareMeteringUsageReportCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Software Updates Deployment Evaluation Cycle"; Plugin="ConfigMgrClient"; Action="SoftwareUpdatesDeploymentEvaluationCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Software Updates Scan Cycle"; Plugin="ConfigMgrClient"; Action="SoftwareUpdatesScanCycle" },
    [pscustomobject]@{ Cat="Client Actions"; Name="State Message Cache Cleanup"; Plugin="ConfigMgrClient"; Action="StateMessageCacheCleanup" },
    [pscustomobject]@{ Cat="Client Actions"; Name="Windows Installer Source List Update Cycle"; Plugin="ConfigMgrClient"; Action="WindowsInstallerSourceListUpdateCycle" },
    
    # ========================== CLIENT TOOLS ==========================
    [pscustomobject]@{ Cat="Client Tools"; Name="Add Device(s) to Collection"; Plugin="ConfigMgrServer"; Action="AddDevicestoCollectionbyResourceId" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Add Device(s) to Collection"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollections" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Add Device(s) to Collection"; Plugin="ConfigMgrServer"; Action="AddDevicesToCollection" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Add Device(s) to Collection"; Plugin="ConfigMgrServer"; Action="AddComputerNamesToCollection" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Add Device(s) to Collection"; Plugin="ConfigMgrServer"; Action="AddComputerResourceIdToCollection" },
    
    [pscustomobject]@{ Cat="Client Tools"; Name="Client Information"; Plugin="ConfigMgrServer"; Action="GetDistributedSoftwareUpdates" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Client Information"; Plugin="ConfigMgrClient"; Action="ChangeCacheSize" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Client Information"; Plugin="ConfigMgrClient"; Action="ClearCache" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Client Information"; Plugin="ConfigMgrClient"; Action="ClientInformation" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Client Information"; Plugin="ConfigMgrClient"; Action="RemoveItemsFromCache" },
    
    [pscustomobject]@{ Cat="Client Tools"; Name="Open Client Installation Log File Folder"; Plugin="LocalActions"; Action="OpenCShare" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Open Client Log File Folder"; Plugin="LocalActions"; Action="OpenCShare" },
    
    [pscustomobject]@{ Cat="Client Tools"; Name="Refresh Updates Compliance State"; Plugin="ConfigMgrClient"; Action="RefreshUpdatesComplianceState" },
    
    # --- REMOTE SOFTWARE CENTER ---
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="UninstallApplication" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="InstallSoftwareUpdatesByID" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="InstalledSoftware"; Action="UninstallSoftware" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="SystemInformation"; Action="ReadOnly" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="WMI"; Action="InvokeMethod" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="InstallSoftwareUpdates" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="InstallProgram" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrServer"; Action="GetApplicationsDeployedToUsers" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="InstallApplication" },
    
    # Corrected Plugin for TaskSequenceInformation
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="TaskSequenceInformation" },
    # Added EvaluateConfigurationBaseline and StartTaskSequence
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="EvaluateConfigurationBaseline" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="StartTaskSequence" },

    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="GetDeployedPrograms" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrServer"; Action="InstallApplication" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="Administration"; Action="GetAllSettings" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="WMI"; Action="ReadOnly" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="GetDeployedTaskSequences" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="InstallUserApplication" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrServer"; Action="GetDeployedApplicationsForUser" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="InstalledSoftware"; Action="ListSoftware" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="DeployedApplications" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="MissingSoftwareUpdates" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="PackageInformation" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrServer"; Action="GetConfigurationBaselines" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="GetUserPolicyEndpoint" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="SystemInformation"; Action="GetLoggedInUsers" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="GetConfigurationBaselines" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrClient"; Action="InstallApplicationOrProgram" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ActiveDirectory"; Action="GetAccountGroupMembership" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Remote Software Center"; Plugin="ConfigMgrServer"; Action="GetComanagedWorkloads" },

    [pscustomobject]@{ Cat="Client Tools"; Name="Rerun Deployment"; Plugin="ConfigMgrClient"; Action="RerunDeployment" },
    
    [pscustomobject]@{ Cat="Client Tools"; Name="Restart SMS Agent Host Service"; Plugin="ConfigMgrClient"; Action="RestartSMSAgentHost" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Run Client Check"; Plugin="ConfigMgrClient"; Action="RunCcmEval" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Stop ConfigMgr Client Activities"; Plugin="ConfigMgrClient"; Action="StopClientActivities" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Show Collections - Advanced"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionInformationforDevice" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Show Collections - Advanced"; Plugin="ConfigMgrServer"; Action="RemoveDevicesFromCollection" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Show Collections - Advanced"; Plugin="ConfigMgrServer"; Action="RemoveDevicesFromCollectionByResourceId" },
    
    [pscustomobject]@{ Cat="Client Tools"; Name="Repair Client"; Plugin="ConfigMgrClient"; Action="RepairConfigMgrClient" },
    [pscustomobject]@{ Cat="Client Tools"; Name="Uninstall SCCM Client"; Plugin="ConfigMgrClient"; Action="UninstallConfigMgrClient" },

    # ========================== CONSOLE TOOLS ==========================
    # AD Security Groups
    [pscustomobject]@{ Cat="Console Tools"; Name="AD Security Groups"; Plugin="ActiveDirectory"; Action="GetPrimaryGroupForAccount" },
    [pscustomobject]@{ Cat="Console Tools"; Name="AD Security Groups"; Plugin="ActiveDirectory"; Action="AddAccountToGroup" },
    [pscustomobject]@{ Cat="Console Tools"; Name="AD Security Groups"; Plugin="ActiveDirectory"; Action="RemoveAccountFromGroup" },
    [pscustomobject]@{ Cat="Console Tools"; Name="AD Security Groups"; Plugin="ActiveDirectory"; Action="SearchADGroups" },
    [pscustomobject]@{ Cat="Console Tools"; Name="AD Security Groups"; Plugin="ActiveDirectory"; Action="GetAccountGroupMembership" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Connect to C$"; Plugin="LocalActions"; Action="OpenCShare" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Interactive Command Prompt"; Plugin="LocalActions"; Action="InteractiveCommandPrompt" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Interactive PowerShell Prompt"; Plugin="LocalActions"; Action="InteractivePowerShellPrompt" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Manage Computer"; Plugin="LocalActions"; Action="ManageComputer" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Open Event Viewer"; Plugin="LocalActions"; Action="OpenEventViewer" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Open RegEdit"; Plugin="LocalActions"; Action="OpenRegEdit" },

    [pscustomobject]@{ Cat="Console Tools"; Name="Delete Device(s) from Active Directory"; Plugin="ActiveDirectory"; Action="DeleteAccount" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Delete Device(s) From ConfigMgr"; Plugin="ConfigMgrServer"; Action="DeleteDevice" },
    
    # Delete Device(s) From Azure (Full Permission Set)
    [pscustomobject]@{ Cat="Console Tools"; Name="Delete Device(s) From Azure (Intune/Entra)"; Plugin="MicrosoftGraph"; Action="DeleteDeviceFromIntune" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Delete Device(s) From Azure (Intune/Entra)"; Plugin="MicrosoftGraph"; Action="GetIntuneDevices" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Delete Device(s) From Azure (Intune/Entra)"; Plugin="MicrosoftGraph"; Action="DeleteDeviceFromEntra" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Disable Device(s) in Active Directory"; Plugin="ActiveDirectory"; Action="DisableAccount" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Enable Device(s) in Active Directory"; Plugin="ActiveDirectory"; Action="EnableAccount" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Group Policy Update"; Plugin="SystemInformation"; Action="GroupPolicyUpdate" },
    
    # Entra ID Security Groups
    [pscustomobject]@{ Cat="Console Tools"; Name="Entra ID Security Groups"; Plugin="MicrosoftGraph"; Action="AddToEntraGroup" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Entra ID Security Groups"; Plugin="MicrosoftGraph"; Action="GetEntraDevice" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Entra ID Security Groups"; Plugin="MicrosoftGraph"; Action="GetEntraGroups" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Entra ID Security Groups"; Plugin="MicrosoftGraph"; Action="RemoveFromEntraGroup" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Entra ID Security Groups"; Plugin="MicrosoftGraph"; Action="GetDeviceGroupMemberships" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Ping System(s)"; Plugin="Network"; Action="PingComputer" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Remove Device(s) from Autopilot"; Plugin="MicrosoftGraph"; Action="RemoveDeviceFromAutopilot" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Remove Device(s) from Autopilot"; Plugin="ConfigMgrServer"; Action="GetSerialNumbersForResourceIds" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Remove Device(s) from Autopilot"; Plugin="Administration"; Action="ListAzureActiveDirectoryServiceConnections" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Running Processes"; Plugin="SystemInformation"; Action="GetRunningProcesses" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Running Processes"; Plugin="SystemInformation"; Action="KillProcess" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Send Notification"; Plugin="SystemInformation"; Action="SendMessageAllUsers" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Send Notification"; Plugin="ConfigMgrClient"; Action="SendCmClientToastNotification" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Send Notification"; Plugin="SystemInformation"; Action="SendRecastToastNotification" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Set Autopilot Group Tag"; Plugin="Administration"; Action="ListAzureActiveDirectoryServiceConnections" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Set Autopilot Group Tag"; Plugin="ConfigMgrServer"; Action="GetSerialNumbersForResourceIds" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Set Autopilot Group Tag"; Plugin="MicrosoftGraph"; Action="UpdateGroupTagInAutopilot" },
    
    # Sync Intune App
    [pscustomobject]@{ Cat="Console Tools"; Name="Sync Intune App and Compliance Policy"; Plugin="IntuneClient"; Action="SyncAppAndCompliance" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Sync Intune App and Compliance Policy"; Plugin="MicrosoftGraph"; Action="SyncPolicyFromIntune" },

    # System Information (Above Wake On LAN)
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="InstalledSoftware"; Action="ListSoftware" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="InstalledSoftware"; Action="UninstallSoftware" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="Services"; Action="StartService" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="Services"; Action="ChangeStartMode" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="Services"; Action="RestartService" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="Services"; Action="StopService" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="Services"; Action="ListServices" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="SystemInformation"; Action="UpdateLocalGroupMembership" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="SystemInformation"; Action="DeleteProfile" },
    [pscustomobject]@{ Cat="Console Tools"; Name="System Information"; Plugin="SystemInformation"; Action="ReadOnly" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Wake On LAN"; Plugin="ConfigMgrServer"; Action="WakeonLAN" },
    
    [pscustomobject]@{ Cat="Console Tools"; Name="Cancel Pending Restart or Shutdown"; Plugin="SystemInformation"; Action="CancelShutdown" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Schedule Restart or Shutdown"; Plugin="SystemInformation"; Action="ScheduleShutdown" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Restart System(s)"; Plugin="SystemInformation"; Action="ShutdownComputer" },
    [pscustomobject]@{ Cat="Console Tools"; Name="Shutdown System(s)"; Plugin="SystemInformation"; Action="ShutdownComputer" },

    # ========================== SECURITY TOOLS ==========================
    # 1. Retrieve All BitLocker Keys
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="Administration"; Action="ListActiveDirectoryServiceConnections" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="Administration"; Action="ListMemcmServiceConnections" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="Administration"; Action="ListAzureActiveDirectoryServiceConnections" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="Administration"; Action="ListMbamServiceConnections" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="ConfigMgrServer"; Action="GetBitLockerRecoveryKeys" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="ActiveDirectory"; Action="GetBitLockerRecoveryData" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Retrieve All BitLocker Keys"; Plugin="MBAM"; Action="GetRecoveryKeysForDevice" },
    
    # 2. AD BitLocker Recovery Keys
    [pscustomobject]@{ Cat="Security Tools"; Name="AD BitLocker Recovery Keys"; Plugin="ActiveDirectory"; Action="GetBitLockerRecoveryData" },
    
    # 3. BitLocker Status
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="GetBitLockerStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="AddTPMAndSKKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="ConfigMgrServer"; Action="GetSystemsBitLockerEncryptionStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="DecryptVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="ResumeBitLockerVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="AddProtectorsAndEncrypt" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="ForceBitLockerRecovery" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="AddPassphraseKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="SystemInformation"; Action="ResetBitLockerRecoveryPassword" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="ActiveDirectory"; Action="GetADComputersBitLockerStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="EncryptVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="AddTPMAndPINKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="BackupProtectorToAD" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="AddTPMKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="BackupProtectorToAzureAD" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="RegenerateBitLockerRecoveryKey" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="SetVolumeIDField" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="AddNumericalPasswordKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="SuspendBitLockerVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="BitLocker Status"; Plugin="BitLocker"; Action="GetRecoveryPasswordFromDevice" },

    # 4. ConfigMgr BitLocker Recovery Keys
    [pscustomobject]@{ Cat="Security Tools"; Name="ConfigMgr BitLocker Recovery Keys"; Plugin="ConfigMgrServer"; Action="GetBitLockerRecoveryKeys" },
    
    # 5. Entra ID BitLocker Recovery Keys
    [pscustomobject]@{ Cat="Security Tools"; Name="Entra ID BitLocker Recovery Keys"; Plugin="MicrosoftGraph"; Action="GetBitlockerRecoveryKey" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Entra ID BitLocker Recovery Keys"; Plugin="MicrosoftGraph"; Action="GetDevicesWithBitlockerKeys" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Entra ID BitLocker Recovery Keys"; Plugin="Administration"; Action="ListAzureActiveDirectoryServiceConnections" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Entra ID BitLocker Recovery Keys"; Plugin="MicrosoftGraph"; Action="GetBitlockerKeyIdsForDevice" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Entra ID BitLocker Recovery Keys"; Plugin="ConfigMgrServer"; Action="GetEntraIdInfo" },

    # 6. MBAM BitLocker Recovery Keys
    [pscustomobject]@{ Cat="Security Tools"; Name="MBAM BitLocker Recovery Keys"; Plugin="MBAM"; Action="GetRecoveryKeysForDevice" },
    
    # 7. AD LAPS Password
    [pscustomobject]@{ Cat="Security Tools"; Name="AD LAPS Password"; Plugin="ActiveDirectory"; Action="GetADComputerWithLAPSData" },
    
    # 8. Remote Windows Security
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetSecureBootStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="EnableVirtualizationBasedSecurity" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="FullSCEPScan" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetCredentialGuardSettings" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="GatherSCEPLogs" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetSystemGuardSecureLaunchSettings" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="AddDefenderExclusion" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetVirtualizationBasedSecuritySettings" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="GetDefenderStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="StartDefenderScan" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="UpdateSCEPDefinitions" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SCEP"; Action="GetDefenderExclusions" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetWindowsFirewallProfiles" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="EnableSystemGuardSecureLaunch" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="EnableCredentialGuardSettings" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetAllVirtualizationBasedSecuritySettings" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetUefiSecureBootStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="EnableTpmAutoProvisioning" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="ProvisionTpm" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="ClearTpm" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetTpmStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="WindowsSecurity"; Action="GetWindowsFirewallRules" },
    # (BitLocker perms for RWS)
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="GetBitLockerStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="AddTPMAndSKKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="ConfigMgrServer"; Action="GetSystemsBitLockerEncryptionStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="DecryptVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="ResumeBitLockerVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="AddProtectorsAndEncrypt" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="ForceBitLockerRecovery" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="AddPassphraseKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="SystemInformation"; Action="ResetBitLockerRecoveryPassword" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="ActiveDirectory"; Action="GetADComputersBitLockerStatus" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="EncryptVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="AddTPMAndPINKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="BackupProtectorToAD" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="AddTPMKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="BackupProtectorToAzureAD" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="RegenerateBitLockerRecoveryKey" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="SetVolumeIDField" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="AddNumericalPasswordKeyProtector" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="SuspendBitLockerVolume" },
    [pscustomobject]@{ Cat="Security Tools"; Name="Remote Windows Security"; Plugin="BitLocker"; Action="GetRecoveryPasswordFromDevice" },

    # 9. Set LAPS Password Expiration
    [pscustomobject]@{ Cat="Security Tools"; Name="Set LAPS Password Expiration"; Plugin="ActiveDirectory"; Action="SetLapsPasswordExpiration" },

    # --- DEVICE MANAGEMENT (Specific Tools - these exist in 'Device Management' logical root) ---
    [pscustomobject]@{ Cat="Device Management"; Name="Open Computer in ServiceNow"; Plugin="TBD_Plugin"; Action="TBD_Action" },
    [pscustomobject]@{ Cat="Device Management"; Name="Device Status Messages"; Plugin="ConfigMgrServer"; Action="GetStatusMessageQueries" },
    [pscustomobject]@{ Cat="Device Management"; Name="Device Status Messages"; Plugin="ConfigMgrServer"; Action="RunStatusMessageQuery" },
    [pscustomobject]@{ Cat="Device Management"; Name="Device Status Messages"; Plugin="LocalActions"; Action="StatusMessages" },

    # ========================== USER MANAGEMENT ==========================
    [pscustomobject]@{ Cat="User Management"; Name="Open User in ServiceNow"; Plugin="TBD_Plugin"; Action="TBD_Action" },
    [pscustomobject]@{ Cat="User Management"; Name="Change Password"; Plugin="ActiveDirectory"; Action="ResetPassword" },
    [pscustomobject]@{ Cat="User Management"; Name="Email User"; Plugin="LocalActions"; Action="EmailUser" },
    [pscustomobject]@{ Cat="User Management"; Name="Enable / Disable Account"; Plugin="ActiveDirectory"; Action="IsAccountEnabled" },
    [pscustomobject]@{ Cat="User Management"; Name="Enable / Disable Account"; Plugin="ActiveDirectory"; Action="EnableAccount" },
    [pscustomobject]@{ Cat="User Management"; Name="Enable / Disable Account"; Plugin="ActiveDirectory"; Action="DisableAccount" },
    [pscustomobject]@{ Cat="User Management"; Name="Security Groups"; Plugin="ActiveDirectory"; Action="GetPrimaryGroupForAccount" },
    [pscustomobject]@{ Cat="User Management"; Name="Security Groups"; Plugin="ActiveDirectory"; Action="GetAccountGroupMembership" },
    [pscustomobject]@{ Cat="User Management"; Name="Security Groups"; Plugin="ActiveDirectory"; Action="RemoveAccountFromGroup" },
    [pscustomobject]@{ Cat="User Management"; Name="Security Groups"; Plugin="ActiveDirectory"; Action="SearchADGroups" },
    [pscustomobject]@{ Cat="User Management"; Name="Security Groups"; Plugin="ActiveDirectory"; Action="AddAccountToGroup" },
    [pscustomobject]@{ Cat="User Management"; Name="Unlock Account"; Plugin="ActiveDirectory"; Action="UnlockAccount" },
    [pscustomobject]@{ Cat="User Management"; Name="User Devices"; Plugin="ConfigMgrServer"; Action="GetUserDevices" },
    [pscustomobject]@{ Cat="User Management"; Name="User Status Messages"; Plugin="LocalActions"; Action="StatusMessages" },

    # ========================== APPLICATION MANAGEMENT ==========================
    # Added Tools (Open Content Source, Deployment Launcher, View Release Notes)
    [pscustomobject]@{ Cat="Application Management"; Name="Open Content Source Path"; Plugin="LocalActions"; Action="OpenContentSource" },
    [pscustomobject]@{ Cat="Application Management"; Name="Deployment Launcher"; Plugin="LocalActions"; Action="DeploymentLauncher" },
    [pscustomobject]@{ Cat="Application Management"; Name="View Update Release Notes"; Plugin="LocalActions"; Action="ViewReleaseNotes" },

    # Content Status (Updated: Added GetDistributionPointGroupStatusForPackage, GetDistributionPointStatusForPackage)
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="AddContentToDistributionPoint" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="AddContentToDistributionPointGroup" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="ContentDetails" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetAllContentStatus" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetAllDistributedContent" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetContentStatus" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetDistributionPointContent" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetDPGroupTaskSequenceContent" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetFailedContentOnDistributionPoint" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetTaskSequenceContent" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="RedistributeContenttoDistributionPoint" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="RedistributeContenttoDistributionPointGroup" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="RemoveContentfromDistributionPoint" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="RemoveContentfromDistributionPointGroup" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="UpdateContent" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="ValidateContentonDistributionPoint" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="ValidateContentonDistributionPointGroup" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetDistributionPointGroupStatusForPackage" },
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status"; Plugin="ConfigMgrServer"; Action="GetDistributionPointStatusForPackage" },

    # Content Status Messages (Updated)
    [pscustomobject]@{ Cat="Application Management"; Name="Content Status Messages"; Plugin="LocalActions"; Action="StatusMessages" },
    
    # Application Revision History (Updated)
    [pscustomobject]@{ Cat="Application Management"; Name="Application Revision History"; Plugin="ConfigMgrServer"; Action="GetApplicationRevisions" },
    [pscustomobject]@{ Cat="Application Management"; Name="Application Revision History"; Plugin="LocalActions"; Action="ApplicationRevisionHistory" },

    # ========================== CONTENT DISTRIBUTION ==========================
    # New Tools
    [pscustomobject]@{ Cat="Content Distribution"; Name="Task Sequence Content Info"; Plugin="ConfigMgrServer"; Action="GetTaskSequenceContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Task Sequence Content Info"; Plugin="ConfigMgrServer"; Action="GetDPGroupTaskSequenceContent" },

    # Distribution Content Status (Inherits Content Status perms)
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="AddContentToDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="AddContentToDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="ContentDetails" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetAllContentStatus" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetAllDistributedContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetContentStatus" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetDistributionPointContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetDPGroupTaskSequenceContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetFailedContentOnDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetTaskSequenceContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="RedistributeContenttoDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="RedistributeContenttoDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="RemoveContentfromDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="RemoveContentfromDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="UpdateContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="ValidateContentonDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="ValidateContentonDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetDistributionPointGroupStatusForPackage" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Content Status"; Plugin="ConfigMgrServer"; Action="GetDistributionPointStatusForPackage" },

    # Redistribute All Failed Content Transfers (Inherits Content Status perms)
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="AddContentToDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="AddContentToDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="ContentDetails" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetAllContentStatus" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetAllDistributedContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetContentStatus" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetDistributionPointContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetDPGroupTaskSequenceContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetFailedContentOnDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetTaskSequenceContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="RedistributeContenttoDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="RedistributeContenttoDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="RemoveContentfromDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="RemoveContentfromDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="UpdateContent" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="ValidateContentonDistributionPoint" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="ValidateContentonDistributionPointGroup" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetDistributionPointGroupStatusForPackage" },
    [pscustomobject]@{ Cat="Content Distribution"; Name="Redistribute All Failed Content Transfers"; Plugin="ConfigMgrServer"; Action="GetDistributionPointStatusForPackage" },

    # Distribution Point Status Messages (Inherits StatusMessages perm)
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Point Status Messages"; Plugin="LocalActions"; Action="StatusMessages" },

    # Distribution Point PXE Status Messages (Inherits StatusMessages perm)
    [pscustomobject]@{ Cat="Content Distribution"; Name="Distribution Point PXE Status Messages"; Plugin="LocalActions"; Action="StatusMessages" },

    # ========================== CONSOLE DASHBOARDS ==========================
    # Active Directory Cleanup Tool
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDevicesInOu" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDevices" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSystemBiosInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="LocalActions"; Action="ActiveDirectoryCleanupTool" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionFolders" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSystemOperatingSystemInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSystemConsoleUsageData" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSiteDeviceCollectionsWithFolders" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="SearchADGroups" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="SearchADComputers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADContainers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetAdContainerByDistinguishedNameCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADComputersInGroupCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionsCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetDomain" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSystemFirmwareStatus" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADComputers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetParentOUs" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDevicesCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADComputersInGroup" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionMembersByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="SearchOUs" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetAdContainerByDistinguishedName" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSites" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADComputersCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionsByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADOUs" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetAdContainerByObjectGuid" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetServersAndSiteSystemRoles" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADComputer" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetADContainersCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="GetAdContainerByObjectGuidCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ConfigMgrServer"; Action="GetSiteDeviceCollectionsWithFoldersByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="AddAccountToGroup" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Active Directory Cleanup Tool"; Plugin="ActiveDirectory"; Action="RemoveAccountFromGroup" },

    # BitLocker Compliance
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetCollectionById" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetCollectionFolderInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetCollectionsforDevice" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetDevicesByMeId" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetMachinesWithCmBlmKeys" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="MBAM"; Action="GetMachinesWithMBAMKeys" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="MBAM"; Action="GetMachinesWithMBAMKeys_v2" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="MBAM"; Action="GetMBAMCompliance" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="MBAM"; Action="GetMBAMComplianceForAllMachines" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetServersAndSiteSystemRoles" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADComputersBitLockerStatus" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetSystemsBitLockerEncryptionStatus" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="MicrosoftGraph"; Action="GetDevicesWithBitlockerKeys" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="Administration"; Action="ListActiveDirectoryServiceConnections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="Administration"; Action="ListMbamServiceConnections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="Administration"; Action="ListMemcmServiceConnections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionInformationforDevice" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADComputer" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADComputers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADComputersCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADComputersInGroup" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADComputersInGroupCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADContainers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADContainersCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ActiveDirectory"; Action="GetADOUs" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionsByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionsCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetAllDevicesCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionMembersByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="BitLocker Compliance"; Plugin="Administration"; Action="ListAzureActiveDirectoryServiceConnections" },

    # Content Distribution Monitor
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="ConfigMgrClient"; Action="TaskSequenceInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="TaskScheduler"; Action="ScheduleTaskMonthlyByOccurrence" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="Administration"; Action="GetEnrollmentSettings" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="SystemInformation"; Action="ShutdownComputer" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="ActiveDirectory"; Action="GetGroupMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="SystemInformation"; Action="SendRecastToastNotification" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="Administration"; Action="CreateActionExecutionGroup" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="Administration"; Action="ListMemcmServiceConnections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="SystemInformation"; Action="GetLoggedInUsers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="ConfigMgrServer"; Action="GetManufacturerCounts" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="BitLocker"; Action="SuspendBitLockerVolume" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="ConfigMgrServer"; Action="GetAllDistributedContent" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Content Distribution Monitor"; Plugin="Administration"; Action="SetRolePermissions" },
 
    # Hardware and Firmware Audit
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetActiveDirectoryForests" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetAllCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetAllDeploymentTypes" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetAllDevices" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetAllDevicesinOu" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetBaseboardInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetChassisInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetComputerSystemInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetComputerSystemProductInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionFolders" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionInformationforDevice" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionsinFolder" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetDevicesInCollectionScope" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetDevicesInSiteScope" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetSiteDeviceCollectionsWithFolders" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetSystemBiosInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetSystemConsoleUsageData" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetSystemOperatingSystemInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetUnknownDevices" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Hardware and Firmware Audit"; Plugin="ConfigMgrServer"; Action="GetSystemFirmwareStatus" },

    # LAPS Dashboard
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADComputerWithLAPSData" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADComputer" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADComputers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADComputersCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADComputersInGroup" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADComputersInGroupCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetAdContainerByDistinguishedName" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetAdContainerByDistinguishedNameCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetAdContainerByObjectGuid" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetAdContainerByObjectGuidCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADContainers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ActiveDirectory"; Action="GetADContainersCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetAllDevicesCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetComputersWithoutLapsClient" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetComputersWithX64LapsClient" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetComputersWithX86LapsClient" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetAllDevices" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetComputerSystemInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetAllDevicesInOu" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="LAPS Dashboard"; Plugin="ConfigMgrServer"; Action="GetSystemOperatingSystemInformation" },

    # Software Updates Deployment Status (SUDS)
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetCollectionById" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetCollectionsforDevice" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetInstalledSoftwareUpdates" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllSoftwareUpdates" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetNonCompliantUpdateStatuses" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetCompliantUpdateStatuses" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionsCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDevicesCore" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionInformationforDevice" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetRecentDevicesScanned" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionMembersByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollectionsByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSiteDeviceCollectionsWithFoldersByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSoftwareUpdatesInGroup" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetRequiredSoftwareUpdates" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDeviceCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSoftwareUpdatesByResourceIds" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSoftwareUpdatesByCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSoftwareUpdateGroups" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDistributedSoftwareUpdates" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetCollectionFolderInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionMembers" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllCollections" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionFolders" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDevices" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDeviceCollectionsinFolder" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetComputerSystemInformation" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSiteDeviceCollectionsWithFolders" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDevicesInCollectionScope" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetDevicesInSiteScope" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetUnknownDevices" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetAllDevicesInOu" },
    [pscustomobject]@{ Cat="Console Dashboards"; Name="Software Updates Deployment Status"; Plugin="ConfigMgrServer"; Action="GetSystemOperatingSystemInformation" }
)

# ---------------------------- Early Helper Functions ----------------------------
function To-TrimmedString {
    param([Parameter(ValueFromPipeline)][object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) { return '' }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($item in $Value) { if ($null -ne $item) { $s = $item.ToString(); if (-not [string]::IsNullOrWhiteSpace($s)) { return $s.Trim() } } }
        return ''
    }
    try { return ($Value.ToString()).Trim() } catch { return '' }
}

function Show-InputDialog {
    param([string]$Title, [string]$Prompt, [string]$Default = "")
    
    $dlgXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        Title='Input' Height='180' Width='460' WindowStartupLocation='CenterScreen' ResizeMode='NoResize'
        Background='#1a1a3d' Foreground='White'>
  <Grid Margin='12'>
    <Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/></Grid.RowDefinitions>
    <TextBlock Name='PromptText' Grid.Row='0' Margin='0,0,0,8' TextWrapping='Wrap' FontFamily='Consolas'/>
    <TextBox Name='InputText' Grid.Row='1' Width='400' Background='#333355' Foreground='White' CaretBrush='White'/>
    <StackPanel Grid.Row='2' Orientation='Horizontal' HorizontalAlignment='Right' Margin='0,10,0,0'>
      <Button Name='BtnOK' Content='OK' Width='80' Margin='0,0,8,0' IsDefault='True' Background='#4CC9F0' Foreground='Black'/>
      <Button Name='BtnCancel' Content='Cancel' Width='80' IsCancel='True' Background='#E07A5F' Foreground='Black'/>
    </StackPanel>
  </Grid>
</Window>
"@
    $r = [System.Xml.XmlReader]::Create([System.IO.StringReader]$dlgXaml)
    $dlg = [System.Windows.Markup.XamlReader]::Load($r)
    try { $dlg.Title = $Title } catch {}
    
    $p = [System.Windows.LogicalTreeHelper]::FindLogicalNode($dlg, 'PromptText')
    $i = [System.Windows.LogicalTreeHelper]::FindLogicalNode($dlg, 'InputText')
    $bo = [System.Windows.LogicalTreeHelper]::FindLogicalNode($dlg, 'BtnOK')
    $bc = [System.Windows.LogicalTreeHelper]::FindLogicalNode($dlg, 'BtnCancel')
    
    $p.Text = $Prompt; $i.Text = $Default
    try { $i.Focus() | Out-Null } catch {}
    
    $bo.Add_Click({$dlg.DialogResult=$true})
    $bc.Add_Click({$dlg.DialogResult=$false})
    
    if ($global:window) { try { $dlg.Owner = $global:window } catch {} }

    [void]$dlg.ShowDialog()
    
    if ($dlg.DialogResult -ne $true) { return $null }
    return (To-TrimmedString $i.Text)
}

# ---------------------------- UI Helper: Force Refresh (DoEvents) ----------------------------
function Refresh-UI {
    try {
        [System.Windows.Threading.DispatcherFrame]$frame = New-Object System.Windows.Threading.DispatcherFrame
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [Action[System.Windows.Threading.DispatcherFrame]]{ $args[0].Continue = $false },
            $frame
        ) | Out-Null
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch {}
}

# ---------------------------- Startup Configuration ----------------------------
$DefaultRMS = "https://cs-rms.cs.recastsoftware.com:444"
$InputRMS   = Show-InputDialog -Title "RMS Configuration" -Prompt "Enter Recast Management Server URL:" -Default $DefaultRMS

if ([string]::IsNullOrWhiteSpace($InputRMS)) { return }

$RMS         = $InputRMS
$date        = Get-Date -Format "MMddyyyy"
$rmsrolepath = "C:\temp\RMSRoles"
$logFile     = Join-Path $rmsrolepath 'RMSRole.log'

if (-not (Test-Path $rmsrolepath)) { New-Item -ItemType Directory -Path $rmsrolepath -Force | Out-Null }

# ---------------------------- Logging & UI Helpers ----------------------------
$Global:LogWriter = $null
$Global:TxtLogCtrl = $null 
$Global:StatusTextCtrl = $null
$Global:MainControls = @{} 

function Initialize-Logger {
    try {
        $fs  = New-Object System.IO.FileStream($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $enc = New-Object System.Text.UTF8Encoding($true)
        $Global:LogWriter = New-Object System.IO.StreamWriter($fs, $enc)
        $Global:LogWriter.AutoFlush = $true
    } catch { Write-Host "Logger init failed." -ForegroundColor Yellow }
}

function Dispose-Logger {
    try { if ($Global:LogWriter) { $Global:LogWriter.Flush(); $Global:LogWriter.Dispose(); $Global:LogWriter = $null } } catch {}
}

function Log-Message {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line      = "$timestamp [$Level] - $Message"

    if ($Global:LogWriter) { try { $Global:LogWriter.WriteLine($line) } catch {} }
    else { try { [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine) } catch {} }

    if ($Global:TxtLogCtrl) {
        try {
            $Global:TxtLogCtrl.Dispatcher.Invoke([Action]{
                $bgBrush = [System.Windows.Media.Brushes]::Transparent
                $fgBrush = [System.Windows.Media.Brushes]::Lime

                if ($Level -eq 'WARN') { $bgBrush = [System.Windows.Media.Brushes]::Yellow; $fgBrush = [System.Windows.Media.Brushes]::Black }
                elseif ($Level -eq 'ERROR') { $bgBrush = [System.Windows.Media.Brushes]::Red; $fgBrush = [System.Windows.Media.Brushes]::White }
                elseif ($Level -eq 'SUCCESS') { $fgBrush = [System.Windows.Media.Brushes]::Lime }

                $run = New-Object System.Windows.Documents.Run($line)
                $run.Background = $bgBrush
                $run.Foreground = $fgBrush
                $para = New-Object System.Windows.Documents.Paragraph($run)
                $para.Margin = New-Object System.Windows.Thickness(0) 

                $Global:TxtLogCtrl.Document.Blocks.Add($para)
                $Global:TxtLogCtrl.ScrollToEnd()
            })
        } catch {}
    }
}

function Set-Status {
    param([string]$Text)
    if ($Global:StatusTextCtrl) { $Global:StatusTextCtrl.Text = $Text }
}

function Set-Busy {
    param([bool]$Busy)
    if ($global:window) {
        $c = if($Busy){[System.Windows.Input.Cursors]::Wait}else{[System.Windows.Input.Cursors]::Arrow}
        $global:window.Cursor = $c
    }
    if ($Global:MainControls.Count -gt 0) {
        foreach ($ctrl in $Global:MainControls.Values) { if ($ctrl) { $ctrl.IsEnabled = -not $Busy } }
    }
}

# ---------------------------- UI Functions (Permissions & Creation) ----------------------------
function Show-PermissionsDialog {
    param([string]$RoleName, [object[]]$Rows)
    $pxaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Height='520' Width='800' WindowStartupLocation='CenterOwner' Background='#1a1a3d'>

  <Window.Resources>
     <SolidColorBrush x:Key='BrushAccentBlue'>#4CC9F0</SolidColorBrush>
     <SolidColorBrush x:Key='BrushAccentOrange'>#F05928</SolidColorBrush>
     
     <Style TargetType='DataGrid'>
        <Setter Property='Background' Value='#801a1a3d'/>
        <Setter Property='RowBackground' Value='#80252545'/>
        <Setter Property='AlternatingRowBackground' Value='#80303050'/>
        <Setter Property='Foreground' Value='White'/>
        <Setter Property='GridLinesVisibility' Value='None'/>
        <Setter Property='HeadersVisibility' Value='Column'/>
        <Setter Property='BorderBrush' Value='{StaticResource BrushAccentBlue}'/>
        <Setter Property='BorderThickness' Value='1'/>
     </Style>
     
     <Style TargetType='DataGridColumnHeader'>
        <Setter Property='Background' Value='{StaticResource BrushAccentBlue}'/>
        <Setter Property='Foreground' Value='Black'/>
        <Setter Property='FontWeight' Value='Bold'/>
        <Setter Property='Padding' Value='6,4'/>
     </Style>
     
     <Style TargetType='DataGridCell'>
         <Style.Triggers>
            <Trigger Property='IsSelected' Value='True'>
                <Setter Property='Background' Value='{StaticResource BrushAccentOrange}'/>
                <Setter Property='Foreground' Value='Black'/>
            </Trigger>
         </Style.Triggers>
     </Style>
  </Window.Resources>

  <Grid Margin='8'>
    <DataGrid Name='GridPerms' AutoGenerateColumns='False' IsReadOnly='True'>
      <DataGrid.Columns>
        <DataGridTextColumn Header='Category'    Binding='{Binding Category}' Width='120'/>
        <DataGridTextColumn Header='Action Name' Binding='{Binding ToolName}' Width='200'/>
        <DataGridTextColumn Header='Plugin'      Binding='{Binding PluginName}' Width='120'/>
        <DataGridTextColumn Header='Permission'  Binding='{Binding PermissionName}' Width='*'/>
      </DataGrid.Columns>
    </DataGrid>
  </Grid>
</Window>
"@
    $r = [System.Xml.XmlReader]::Create([System.IO.StringReader]$pxaml)
    $d = [System.Windows.Markup.XamlReader]::Load($r)
    $d.FindName('GridPerms').ItemsSource = $Rows; $d.Title = "Permissions: $RoleName"
    if ($global:window) { $d.Owner = $global:window }
    [void]$d.ShowDialog()
}

function Show-CreateRoleDialog {
    # 1. Build the Tree Items using the C# Class (RmsTreeItem)
    # 2. Also handle the Background Image for the Wizard
    
    $treeItems  = New-Object System.Collections.ObjectModel.ObservableCollection[RmsTreeItem]

    # --- 1. DEVICE MANAGEMENT ROOT ---
    $dmRoot = New-Object RmsTreeItem
    $dmRoot.Name = "Device Management"
    
    # Define the sub-categories we want to nest inside "Device Management"
    $dmSubCats = @("Client Actions", "Client Tools", "Console Tools", "Security Tools")
    
    foreach ($subCatName in $dmSubCats) {
        $subCatNode = New-Object RmsTreeItem
        $subCatNode.Name = $subCatName
        $subCatNode.Category = "Device Management" 
        
        # Find tools belonging to this original category
        $itemsInCat = $Global:RmsToolMap | Where-Object { $_.Cat -eq $subCatName }
        # FIX: Select UNIQUE names to prevent duplicates in the tree
        $uniqueActions = $itemsInCat | Select-Object -ExpandProperty Name -Unique
        
        foreach ($actName in $uniqueActions) {
            $child = New-Object RmsTreeItem
            $child.Name = $actName
            $child.Category = $subCatName 
            $subCatNode.Children.Add($child)
        }
        $dmRoot.Children.Add($subCatNode)
    }

    # Add specific "Device Management" tools directly to the root (at the bottom)
    $dmDirectTools = $Global:RmsToolMap | Where-Object { $_.Cat -eq "Device Management" }
    # FIX: Select UNIQUE names here too (Device Status Messages appears 3 times in map)
    $dmUniqueTools = $dmDirectTools | Select-Object -ExpandProperty Name -Unique

    foreach ($toolName in $dmUniqueTools) {
        $child = New-Object RmsTreeItem
        $child.Name = $toolName
        $child.Category = "Device Management"
        $dmRoot.Children.Add($child)
    }
    
    $treeItems.Add($dmRoot)

    # --- 2. OTHER ROOT CATEGORIES (User, App, Content, Dashboards) ---
    $otherCats = @("User Management", "Application Management", "Content Distribution", "Console Dashboards")
    
    foreach ($catName in $otherCats) {
        $rootNode = New-Object RmsTreeItem
        $rootNode.Name = $catName
        
        $itemsInCat = $Global:RmsToolMap | Where-Object { $_.Cat -eq $catName }
        # FIX: Select UNIQUE names
        $uniqueActions = $itemsInCat | Select-Object -ExpandProperty Name -Unique
        
        foreach ($actName in $uniqueActions) {
            $child = New-Object RmsTreeItem
            $child.Name = $actName
            $child.Category = $catName
            $rootNode.Children.Add($child)
        }
        $treeItems.Add($rootNode)
    }

    $cxaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Create New Role - Select Tools' Height='650' Width='550' WindowStartupLocation='CenterOwner' 
        Background='#1a1a3d' Foreground='White'>

  <Window.Resources>
     <SolidColorBrush x:Key='BrushAccentBlue'>#4CC9F0</SolidColorBrush>
     <SolidColorBrush x:Key='BrushAccentOrange'>#F05928</SolidColorBrush>

     <Style TargetType='Button'>
        <Setter Property='Background' Value='#3a3a5e'/>
        <Setter Property='Foreground' Value='White'/>
        <Setter Property='BorderBrush' Value='{StaticResource BrushAccentBlue}'/>
        <Setter Property='BorderThickness' Value='1'/>
        <Setter Property='FontFamily' Value='Consolas'/>
        <Setter Property='FontWeight' Value='Bold'/>
        <Setter Property='Margin' Value='5'/>
        <Setter Property='Padding' Value='10,5'/>
        <Setter Property='Template'>
            <Setter.Value>
                <ControlTemplate TargetType='Button'>
                    <Border Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1' CornerRadius='2'>
                        <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property='IsMouseOver' Value='True'><Setter Property='Background' Value='#5a5a7e'/></Trigger>
                        <Trigger Property='IsPressed' Value='True'><Setter Property='Background' Value='{StaticResource BrushAccentBlue}'/><Setter Property='Foreground' Value='Black'/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
     </Style>

     <Style TargetType='CheckBox'>
        <Setter Property='Foreground' Value='White'/>
        <Setter Property='Margin' Value='0,2,0,2'/>
     </Style>

     <HierarchicalDataTemplate x:Key='RmsLevel3Template'>
        <StackPanel Orientation='Horizontal'>
            <CheckBox IsChecked='{Binding IsChecked, Mode=TwoWay}' VerticalAlignment='Center'/>
            <TextBlock Text='{Binding Name}' Foreground='White' Margin='5,0,0,0' VerticalAlignment='Center'/>
        </StackPanel>
     </HierarchicalDataTemplate>

     <HierarchicalDataTemplate x:Key='RmsLevel2Template' ItemsSource='{Binding Children}' ItemTemplate='{StaticResource RmsLevel3Template}'>
        <StackPanel Orientation='Horizontal'>
            <CheckBox IsChecked='{Binding IsChecked, Mode=TwoWay}' VerticalAlignment='Center'/>
            <TextBlock Text='{Binding Name}' FontWeight='Bold' Foreground='{StaticResource BrushAccentBlue}' Margin='5,0,0,0' VerticalAlignment='Center'/>
        </StackPanel>
     </HierarchicalDataTemplate>

     <HierarchicalDataTemplate x:Key='RmsLevel1Template' ItemsSource='{Binding Children}' ItemTemplate='{StaticResource RmsLevel2Template}'>
        <StackPanel Orientation='Horizontal'>
            <CheckBox IsChecked='{Binding IsChecked, Mode=TwoWay}' VerticalAlignment='Center'/>
            <TextBlock Text='{Binding Name}' FontSize='14' FontWeight='Bold' Foreground='White' Margin='5,0,0,0' VerticalAlignment='Center'/>
        </StackPanel>
     </HierarchicalDataTemplate>

  </Window.Resources>

  <Grid Margin='15'>
    <Grid.RowDefinitions>
        <RowDefinition Height='Auto'/>
        <RowDefinition Height='*'/>
        <RowDefinition Height='Auto'/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row='0' Text='Select Right Click Tools Actions:' FontFamily='Consolas' FontSize='14' Margin='0,0,0,10'/>

    <Border Grid.Row='1' BorderBrush='{StaticResource BrushAccentBlue}' BorderThickness='1' Background='#80252545'>
        <TreeView Name='TreePerms' Background='Transparent' BorderThickness='0' ItemTemplate='{StaticResource RmsLevel1Template}'/>
    </Border>

    <StackPanel Grid.Row='2' Orientation='Vertical' Margin='0,15,0,0'>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width='*'/>
                <ColumnDefinition Width='*'/>
                <ColumnDefinition Width='*'/>
            </Grid.ColumnDefinitions>
            <ProgressBar Name='ProgressCreate' Grid.Column='0' Grid.ColumnSpan='3' Height='5' Margin='0,0,0,10' Visibility='Hidden' Background='Transparent' Foreground='{StaticResource BrushAccentBlue}' BorderThickness='0'/>
            
            <Button Name='BtnListSelected' Grid.Column='0' Content='LIST PERMISSIONS' Height='35'/>
            <Button Name='BtnCreate'       Grid.Column='1' Content='CREATE ROLE'   Height='35' BorderBrush='{StaticResource BrushAccentOrange}' Foreground='{StaticResource BrushAccentOrange}'/>
            <Button Name='BtnClose'        Grid.Column='2' Content='EXIT'          Height='35'/>
        </Grid>
    </StackPanel>
  </Grid>
</Window>
"@
    $r = [System.Xml.XmlReader]::Create([System.IO.StringReader]$cxaml)
    $w = [System.Windows.Markup.XamlReader]::Load($r)
    if ($global:window) { $w.Owner = $global:window }
    
    $tree = $w.FindName('TreePerms')
    $prog = $w.FindName('ProgressCreate') # Reference to the new Progress Bar
    $tree.ItemsSource = $treeItems

    # --- Load Wizard Background (Check New Var first, then fallback to Main) ---
    $wizImg = if (-not [string]::IsNullOrWhiteSpace($global:Base64WizardImage) -and $global:Base64WizardImage -ne "PASTE_WIZARD_BG_HERE") { $global:Base64WizardImage } else { $global:Base64RobotImage }

    if (-not [string]::IsNullOrWhiteSpace($wizImg) -and $wizImg -ne "PASTE_YOUR_BASE64_STRING_HERE") {
        try {
            $bytes = [Convert]::FromBase64String($wizImg)
            $stream = New-Object System.IO.MemoryStream(,$bytes)
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage; $bmp.BeginInit(); $bmp.StreamSource = $stream; $bmp.EndInit()
            $brush = New-Object System.Windows.Media.ImageBrush; $brush.ImageSource = $bmp; $brush.Stretch = "UniformToFill"
            $w.Background = $brush
        } catch { Log-Message "Failed to load wizard bg: $_" "WARN" }
    }

    # --- Recursive Helper to Resolve Checked Items ---
    function Get-CheckedLeaves($nodes) {
        $leaves = @()
        foreach ($node in $nodes) {
            if ($node.Children.Count -eq 0) {
                # Leaf node: check if selected
                if ($node.IsChecked) { $leaves += $node }
            } else {
                # Branch node: recurse
                $leaves += Get-CheckedLeaves $node.Children
            }
        }
        return $leaves
    }

    function Resolve-Selection {
        $apiList = @()
        $checkedNodes = Get-CheckedLeaves $treeItems
        
        foreach ($node in $checkedNodes) {
            # Find matching tool in global map using Name AND Category
            # (Use Name primarily, filter by Cat if ambiguous, though names should be unique within cats)
            $matches = $Global:RmsToolMap | Where-Object { $_.Name -eq $node.Name -and $_.Cat -eq $node.Category }
            
            foreach ($m in $matches) {
                 $apiList += [pscustomobject]@{ 
                    Category = $m.Cat
                    ToolName = $m.Name
                    PluginName = $m.Plugin
                    PermissionName = $m.Action
                 }
            }
        }
        return $apiList
    }

    # --- Event Handlers ---
    $w.FindName('BtnClose').Add_Click({ $w.Close() })

    $w.FindName('BtnListSelected').Add_Click({
        $resolved = Resolve-Selection
        if ($resolved.Count -eq 0) { [System.Windows.MessageBox]::Show("No tools selected.", "Info"); return }
        Show-PermissionsDialog "New Role Preview (Resolved API Actions)" $resolved
    })

    $w.FindName('BtnCreate').Add_Click({
        $resolved = Resolve-Selection
        if ($resolved.Count -eq 0) { [System.Windows.MessageBox]::Show("No tools selected.", "Error"); return }

        $newName = Show-InputDialog "Create Role" "Enter Name for New Role:"
        if (-not $newName) { return }
        if (Is-InvalidRoleName $newName) { [System.Windows.MessageBox]::Show("Invalid name.", "Error"); return }

        try {
            Set-Busy $true
            
            # --- DUPLICATE CHECK START ---
            Refresh-UI
            $existingRoles = Get-ExistingRoles
            $roleExists = $false
            if ($existingRoles) {
                foreach ($r in $existingRoles) {
                    $rName = Get-RoleDisplayName $r
                    if ($rName -eq $newName) { $roleExists = $true; break }
                }
            }

            if ($roleExists) {
                [System.Windows.MessageBox]::Show("The role '$newName' already exists.`nPlease choose a different name.", "Duplicate Role", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                Set-Busy $false
                return # Stop execution
            }
            # --- DUPLICATE CHECK END ---

            # Setup Progress Bar
            $prog.Visibility = 'Visible'
            $prog.Minimum = 0
            $prog.Maximum = $resolved.Count
            $prog.Value = 0
            Refresh-UI # Force initial draw

            if (Add-Role $newName) {
                $count = 0
                foreach ($perm in $resolved) {
                    Add-Permission -Role $newName -Permission @{PluginName=$perm.PluginName; Permission=$perm.PermissionName} | Out-Null
                    $count++
                    
                    # UPDATE PROGRESS & LOG LIVE
                    $prog.Value = $count
                    Refresh-UI 
                }
                Log-Message "Created '$newName' with $count permissions." "SUCCESS"
                Set-Status "Role Created."
                Load-Roles # Refresh main window
                $w.Close()
            } else {
                [System.Windows.MessageBox]::Show("Failed to create role.", "Error")
            }
        } catch {
            Log-Message "Error in creation: $_" "ERROR"
        } finally {
            Set-Busy $false
            $prog.Visibility = 'Hidden'
        }
    })

    [void]$w.ShowDialog()
}

Initialize-Logger

# ---------------------------- Other Helpers ----------------------------
function Sanitize-FileName { param([string]$Name); return ($Name -replace '[^A-Za-z0-9\.\-_ ]','_') }

function Is-InvalidRoleName {
    param([string]$Name)
    $s = To-TrimmedString $Name
    if ([string]::IsNullOrWhiteSpace($s)) { return $true }
    return ($s -match '^(?i:true|false|system\.object\[\])$')
}

# ---------------------------- Auth & API Helpers ----------------------------
$Global:RmsCred         = $null
$Global:UseDefaultCreds = $true 

function Set-ApiAuth {
    param([bool]$UseDefault, [switch]$PromptCredential)
    if ($UseDefault) { $Global:UseDefaultCreds = $true; $Global:RmsCred = $null; Log-Message "Auth set: Windows default." "INFO" }
    else {
        $Global:UseDefaultCreds = $false
        if ($PromptCredential) { $Global:RmsCred = Get-Credential -Message "RMS API Creds" }
        if (-not $Global:RmsCred) { $Global:RmsCred = Get-Credential -Message "RMS API Creds" }
        Log-Message "Auth set: Explicit credentials." "INFO"
    }
}

function Invoke-RmsApi {
    param([string]$Uri, [string]$Method, [object]$Body = $null)
    try {
        $params = @{ Uri = $Uri; Method = $Method; Headers = @{ Accept = 'application/json' }; TimeoutSec = 90; ErrorAction = 'Stop' }
        if ($Global:UseDefaultCreds) { $params.UseDefaultCredentials = $true } else { $params.Credential = $Global:RmsCred }
        if ($null -ne $Body) { $params.ContentType = 'application/json; charset=utf-8'; $params.Body = ($Body | ConvertTo-Json -Depth 10) }
        return (Invoke-RestMethod @params)
    } catch {
        try { 
            $resp = $_.Exception.Response
            if ($resp) { $r = New-Object System.IO.StreamReader($resp.GetResponseStream()); Log-Message "API Error Body: $($r.ReadToEnd())" "ERROR" }
        } catch {}
        Log-Message "API call failed [$Method $Uri]: $_" "ERROR"
        throw
    }
}

# ---------------------------- API Functions ----------------------------
function Get-ExistingRoles {
    try { return (Invoke-RmsApi -Uri "$RMS/api/Administration/GetRoles" -Method GET).result.result } 
    catch { Log-Message "GetRoles failed: $_" "ERROR"; throw }
}

function Get-RoleDisplayName {
    param([object]$RoleItem)
    $n = if ($RoleItem.PSObject.Properties['Name']) { $RoleItem.Name } elseif ($RoleItem.PSObject.Properties['Role']) { $RoleItem.Role } else { $RoleItem.DisplayName }
    return (To-TrimmedString $n)
}

function Get-PermissionsForRole {
    param([string]$RoleName)
    try {
        $resp = Invoke-RestMethod -Uri "$RMS/api/Administration/GetPermissionsForRole" -Method GET -Body @{Role=$RoleName} -UseDefaultCredentials:$Global:UseDefaultCreds -Credential:$Global:RmsCred
        $rows = $resp.result.result
        if ($rows -isnot [System.Collections.IEnumerable]) { $rows = @($rows) }
        
        # --- LOOKUP LOGIC ADDED HERE ---
        $norm = foreach($p in $rows) { 
            $plug = To-TrimmedString $p.PluginName
            $perm = To-TrimmedString $p.RoleName
            
            # Find the first match in our tool map for this Plugin/Action pair
            $match = $Global:RmsToolMap | Where-Object { $_.Plugin -eq $plug -and $_.Action -eq $perm } | Select-Object -First 1
            
            [pscustomobject]@{
                Category       = if ($match) { $match.Cat } else { "Unknown" }
                ToolName       = if ($match) { $match.Name } else { $perm } # Fallback to permission name
                PluginName     = $plug
                PermissionName = $perm
            } 
        }
        return ($norm | Where-Object { $_.PluginName -ne '' -and $_.PermissionName -ne '' })
    } catch { Log-Message "GetPermissions failed for '$RoleName': $_" "ERROR"; throw }
}

function Get-AllUsers {
    try { return (Invoke-RmsApi -Uri "$RMS/api/Administration/GetUsers" -Method GET).result.result }
    catch { Log-Message "GetUsers failed: $_" "ERROR"; return @() }
}

function Get-RolesForUser {
    param($Sid)
    # Changed to GET with Query String based on user feedback
    try {
        return (Invoke-RmsApi -Uri "$RMS/api/Administration/GetRolesForUser?Sid=$Sid" -Method GET).result.result
    } catch {
        Log-Message "GetRolesForUser failed for $($Sid): $_" "WARN"
        return @()
    }
}

function Get-UsersInRole {
    param($RoleName)
    $users = Get-AllUsers
    $assignedUsers = @()
    
    foreach ($u in $users) {
        $sid = $u.Sid 
        $name = if ($u.Name) { $u.Name } else { $u.UserName }
        
        # Refresh UI to keep it responsive during loop
        Refresh-UI
        
        $roles = Get-RolesForUser -Sid $sid
        # Check if $RoleName is in the returned list
        $match = $roles | Where-Object { ($_.Role -eq $RoleName) -or ($_.RoleName -eq $RoleName) -or ($_.Name -eq $RoleName) }
        
        if ($match) {
            $assignedUsers += $name
        }
    }
    return $assignedUsers
}

function Add-Role {
    param([object]$Role)
    $rn = To-TrimmedString $Role
    if (!$rn) { return $false }
    try {
        Log-Message "Adding role: $rn" "INFO"
        $r = Invoke-RmsApi -Uri "$RMS/api/Administration/AddRole" -Method POST -Body @{Role=$rn}
        $ok = if($r.Result){$r.Result.IsSuccessful}else{$r.IsSuccessful}; 
        if($ok){Log-Message "Role '$rn' added." "SUCCESS"; return $true} else {Log-Message "Failed to add '$rn'." "ERROR"; return $false}
    } catch { if("$($_)" -match "403|Forbidden"){throw} Log-Message "Error adding '$rn': $_" "ERROR"; return $false }
}

function Delete-Role {
    param([object]$Role)
    $rn = To-TrimmedString $Role
    if (!$rn) { return $false }
    try {
        Log-Message "Deleting role: $rn" "INFO"
        $r = Invoke-RmsApi -Uri "$RMS/api/Administration/DeleteRole" -Method POST -Body @{Role=$rn}
        $ok = if($r.Result){$r.Result.IsSuccessful}else{$r.IsSuccessful}; 
        if($ok){Log-Message "Role '$rn' deleted." "SUCCESS"; return $true} else {Log-Message "Failed to delete '$rn'." "ERROR"; return $false}
    } catch { if("$($_)" -match "403|Forbidden"){throw} Log-Message "Error deleting '$rn': $_" "ERROR"; return $false }
}

function Add-Permission {
    param([object]$Role, [hashtable]$Permission)
    $rn = To-TrimmedString $Role
    try {
        $pl = To-TrimmedString $Permission.PluginName; $pm = To-TrimmedString $Permission.Permission
        $r = Invoke-RmsApi -Uri "$RMS/api/Administration/AddPermissionToRole" -Method POST -Body @{PluginName=$pl;Permission=$pm;PermissionName=$pm;Role=$rn}
        $ok = if($r.Result){$r.Result.IsSuccessful}else{$r.IsSuccessful};
        if($ok){Log-Message "Perm added [$pl/$pm]" "SUCCESS"; return $true}else{Log-Message "Perm failed [$pl/$pm]" "ERROR"; return $false}
    } catch { if("$($_)" -match "403|Forbidden"){throw} Log-Message "Error adding perm: $_" "ERROR"; return $false }
}

function Ensure-Permission {
    param($Role, $Permission, $ExistingSet)
    $k = ("{0}|{1}" -f (To-TrimmedString $Permission.PluginName), (To-TrimmedString $Permission.Permission)).ToLower()
    if ($ExistingSet -and $ExistingSet[$k]) { Log-Message "Skip $k (exists)" "INFO"; return }
    if (Add-Permission -Role $Role -Permission $Permission) { if($ExistingSet){$ExistingSet[$k]=$true} }
}

function Get-ExistingPermissionSet {
    param($RoleName)
    $rows = Get-PermissionsForRole -RoleName $RoleName
    $s=@{}; foreach($r in $rows){ $s[("{0}|{1}" -f $r.PluginName,$r.PermissionName).ToLower()]=$true }; return $s
}

function Export-RoleToCsv {
    param($RoleName)
    $rows = Get-PermissionsForRole -RoleName $RoleName
    if(!$rows){return}
    $p = Join-Path $rmsrolepath ("RMS_Role_{0}_{1}.csv" -f (Sanitize-FileName $RoleName), $date)
    $rows | Select @{n='RoleName';e={$RoleName}},PluginName,PermissionName | Export-Csv $p -NoTypeInformation
    Log-Message "Exported to $p" "SUCCESS"
}

# ---------------------------- XAML (Themed) ----------------------------
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='RMS Role Manager (Robot Edition)' Height='750' Width='1000' WindowStartupLocation='CenterScreen'
        Background='#1a1a3d' Foreground='White'>
  
  <Window.Resources>
     <SolidColorBrush x:Key='BrushAccentBlue'>#4CC9F0</SolidColorBrush>
     <SolidColorBrush x:Key='BrushAccentOrange'>#F05928</SolidColorBrush>
     <SolidColorBrush x:Key='BrushPanelBg'>#CC252545</SolidColorBrush>

     <Style TargetType='Button'>
        <Setter Property='Background' Value='#3a3a5e'/>
        <Setter Property='Foreground' Value='White'/>
        <Setter Property='BorderBrush' Value='{StaticResource BrushAccentBlue}'/>
        <Setter Property='BorderThickness' Value='1'/>
        <Setter Property='FontFamily' Value='Consolas'/>
        <Setter Property='FontSize' Value='12'/>
        <Setter Property='FontWeight' Value='Bold'/>
        <Setter Property='Template'>
            <Setter.Value>
                <ControlTemplate TargetType='Button'>
                    <Border Background='{TemplateBinding Background}' 
                            BorderBrush='{TemplateBinding BorderBrush}' 
                            BorderThickness='{TemplateBinding BorderThickness}' 
                            CornerRadius='2'>
                        <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property='IsMouseOver' Value='True'>
                            <Setter Property='Background' Value='#5a5a7e'/>
                            <Setter Property='BorderBrush' Value='#FFFFFF'/>
                        </Trigger>
                        <Trigger Property='IsPressed' Value='True'>
                            <Setter Property='Background' Value='{StaticResource BrushAccentBlue}'/>
                            <Setter Property='Foreground' Value='#000000'/>
                        </Trigger>
                        <Trigger Property='IsEnabled' Value='False'>
                            <Setter Property='Opacity' Value='0.5'/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
     </Style>

     <Style TargetType='TextBox'>
        <Setter Property='Background' Value='#80000000'/>
        <Setter Property='Foreground' Value='#4CC9F0'/>
        <Setter Property='BorderBrush' Value='#4CC9F0'/>
        <Setter Property='CaretBrush' Value='White'/>
        <Setter Property='FontFamily' Value='Consolas'/>
     </Style>

     <Style TargetType='DataGrid'>
        <Setter Property='Background' Value='#801a1a3d'/>
        <Setter Property='RowBackground' Value='#80252545'/>
        <Setter Property='AlternatingRowBackground' Value='#80303050'/>
        <Setter Property='Foreground' Value='White'/>
        <Setter Property='GridLinesVisibility' Value='None'/>
        <Setter Property='HeadersVisibility' Value='Column'/>
        <Setter Property='BorderBrush' Value='{StaticResource BrushAccentBlue}'/>
        <Setter Property='BorderThickness' Value='1'/>
     </Style>
     
     <Style TargetType='DataGridColumnHeader'>
        <Setter Property='Background' Value='{StaticResource BrushAccentBlue}'/>
        <Setter Property='Foreground' Value='Black'/>
        <Setter Property='FontWeight' Value='Bold'/>
        <Setter Property='Padding' Value='6,4'/>
     </Style>
     
     <Style TargetType='DataGridCell'>
         <Style.Triggers>
            <Trigger Property='IsSelected' Value='True'>
                <Setter Property='Background' Value='{StaticResource BrushAccentOrange}'/>
                <Setter Property='Foreground' Value='Black'/>
            </Trigger>
         </Style.Triggers>
     </Style>
  </Window.Resources>

  <DockPanel>
    <StatusBar DockPanel.Dock='Bottom' Background='{StaticResource BrushPanelBg}' Foreground='White'>
      <StatusBarItem>
        <TextBlock Name='StatusText' Text='Ready.' FontFamily='Consolas'/>
      </StatusBarItem>
    </StatusBar>
    
    <Grid Margin='10'>
      <Grid.RowDefinitions>
        <RowDefinition Height='Auto'/>
        <RowDefinition Height='Auto'/>
        <RowDefinition Height='2*'/>
        <RowDefinition Height='1*'/>
      </Grid.RowDefinitions>

      <GroupBox Header='Authentication' Grid.Row='0' Margin='0,0,0,8' Foreground='{StaticResource BrushAccentBlue}' BorderBrush='{StaticResource BrushAccentBlue}'>
        <StackPanel Orientation='Horizontal' Margin='8'>
          <RadioButton Name='RbDefault' Content='Windows default' IsChecked='True' Margin='0,0,16,0' Foreground='White'/>
          <RadioButton Name='RbExplicit' Content='Explicit creds' Foreground='White'/>
          <Button Name='BtnApplyAuth' Content='Apply' Width='80' Margin='16,0,0,0'/>
        </StackPanel>
      </GroupBox>

      <StackPanel Grid.Row='1' Orientation='Horizontal' Margin='0,0,0,8'>
        <Label Content='Filter:' VerticalAlignment='Center' Foreground='White' FontFamily='Consolas' FontWeight='Bold'/>
        <TextBox Name='TxtFilter' Width='300' Margin='8,0,8,0'/>
        <Button Name='BtnRefresh' Content='REFRESH ROLES' Width='140'/>
      </StackPanel>

      <Grid Grid.Row='2'>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width='3*'/>
          <ColumnDefinition Width='2*'/>
        </Grid.ColumnDefinitions>

        <DataGrid Name='GridRoles' Grid.Column='0' AutoGenerateColumns='False' IsReadOnly='True' SelectionMode='Single' Margin='0,0,10,0'>
          <DataGrid.Columns>
            <DataGridTextColumn Header='#'   Binding='{Binding Index}' Width='40'/>
            <DataGridTextColumn Header='Role' Binding='{Binding Name}'  Width='*'/>
          </DataGrid.Columns>
        </DataGrid>

        <StackPanel Grid.Column='1'>
          <Button Name='BtnCreateNew'  Content='CREATE NEW ROLE'       Margin='0,0,0,8' Height='35' BorderBrush='#00FF00'/>
          <Button Name='BtnClone'      Content='CLONE ROLE'          Margin='0,0,0,8' Height='35'/>
          <Button Name='BtnImportCsv'  Content='IMPORT ROLE CSV'     Margin='0,0,0,8' Height='35'/>
          <Button Name='BtnExport'     Content='EXPORT ROLE CSV'     Margin='0,0,0,8' Height='35'/>
          <Button Name='BtnList'       Content='LIST ROLE PERMS'     Margin='0,0,0,8' Height='35'/>
          <Button Name='BtnDelete'     Content='DELETE ROLE'         Margin='0,0,0,8' Height='35' BorderBrush='{StaticResource BrushAccentOrange}' Foreground='{StaticResource BrushAccentOrange}'/>
          <Separator Margin='0,8,0,8'  Background='{StaticResource BrushAccentBlue}'/>
          <Button Name='BtnExit'       Content='EXIT'            Margin='0,0,0,8' Height='35'/>
        </StackPanel>
      </Grid>
      
      <GroupBox Header='Live Stream' Grid.Row='3' Margin='0,8,0,0' Foreground='{StaticResource BrushAccentBlue}' BorderBrush='{StaticResource BrushAccentBlue}'>
          <RichTextBox Name='TxtLog' IsReadOnly='True' VerticalScrollBarVisibility='Auto' 
                       Background='#99000000' BorderThickness='0' Padding='4'>
             <FlowDocument FontFamily='Consolas' FontSize='11' PagePadding='0' TextAlignment='Left'/>
          </RichTextBox>
      </GroupBox>
    </Grid>
  </DockPanel>
</Window>
"@

# ---------------------------- UI Load ----------------------------
$xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
$global:window = [System.Windows.Markup.XamlReader]::Load($xmlReader)

# --- LOAD BACKGROUND IMAGE (EMBEDDED) ---
$Base64RobotImage = "iVBORw0KGgoAAAANSUhEUgAAB4AAAAQ4CAIAAABnsVYUAAAgAElEQVR4nOzYQQ3AIADAQEDEvgjDv4+ZWEOy3Cnou/PZZwAAAAAAwNfW7QAAAAAAAP7JgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAAAEgY0AAAAAAAJAxoAAAAAAASBjQAAAAAAAkDGgAAAACAhAENAAAAAEDCgAYAAAAAIGFAAwAAAACQMKABAAAA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"
$Base64WizardImage = "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AAAghAANAAAAAEAIARoAAAAAgBACNAAAAAAAIQRoAAAAAABCCNAAAAAAAIQQoAEAAAAACCFAAwAAAAAQQoAGAAAAACCEAA0AAAAAQAgBGgAAAACAEAI0AAAAAAAhBGgAAAAAAEII0AAAAAAAhBCgAQAAAAAIIUADAAAAABBCgAYAAAAAIIQADQAAAABACAEaAAAAAIAQAjQAAAAAACEEaAAAAAAAQgjQAAAAAACEEKABAAAAAAghQAMAAAAAEEKABgAAAAAghAANAAAAAEAIARoAAAAAgBACNAAAAAAAIQRoAAAAAABCCNAAAAAAAIQQoAEAAAAACCFAAwAAAAAQQoAGAAAAACCEAA0AAAAAQAgBGgAAAACAEAI0AAAAAAAhBGgAAAAAAEII0AAAAAAAhBCgAQAAAAAIIUADAAAAABBCgAYAAAAAIIQADQAAAABACAEaAAAAAIAQAjQAAAAAACEEaAAAAAAAQgjQAAAAAACEEKABAAAAAAghQAMAAAAAEEKABgAAAAAghAANAAAAAEAIARoAAAAAgBACNAAAAAAAIQRoAAAAAABCCNAAAAAAAIQQoAEAAAAACCFAAwAAAAAQQoAGAAAAACCEAA0AAAAAQAgBGgAAAACAEAI0AAAAAAAhBGgAAAAAAEII0AAAAAAAhBCgAQAAAAAIIUADAAAAABBCgAYAAAAAIIQADQAAAABACAEaAAAAAIAQAjQAAAAAACEEaAAAAAAAQgjQAAAAAACEEKABAAAAAAghQAMAAAAAEEKABgAAAAAghAANAAAAAEAIARoAAAAAgBACNAAAAAAAIQRoAAAAAABCCNAAAAAAAIQQoAEAAAAACCFAAwAAAAAQQoAGAAAAACCEAA0AAAAAQAgBGgAAAACAEAI0AAAAAAAhBGgAAAAAAEII0AAAAAAAhBCgAQAAAAAIIUADAAAAABBCgAYAAAAAIIQADQAAAABACAEaAAAAAIAQAjQAAAAAACEEaAAAAAAAQgjQAAAAAACEEKABAAAAAAghQAMAAAAAEEKABgAAAAAghAANAAAAAEAIARoAAAAAgBACNAAAAAAAIQRoAAAAAABCCNAAAAAAAIQQoAEAAAAACCFAAwAAAAAQQoAGAAAAACCEAA0AAAAAQAgBGgAAAACAEAI0AAAAAAAhBGgAAAAAAEII0AAAAAAAhBCgAQAAAAAIIUAD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IUADAAAAABAhQAMAAAAAECFAAwAAAAAQIUADAAAAABAhQAMAAAAAECFAAwAAAAAQIUADAAAAABAhQAMAAAAAECFAAwAAAAAQIUADAAAAABDRrj2gjtnV27UnlFLK/u5e7QkjML3Ta/e26m5o7T4ceqb6yFLK1GAw5MDBoPrO1vZm3QEjVP1hlke49JNiene7+j8wpvd3h56ZiEs/OCWXfiJM7+5MwqWfDpPwJKd3e7UnAAAAIza1dPV67Q0AAAAAAJxCXsEBAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQAy86i4QAAAk1JREFUDQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAhAANAAAAAECEAA0AAAAAQIQADQAAAABAxP8C+SMHt+aJLIYAAAAASUVORK5CYII="

try {
    if (-not [string]::IsNullOrWhiteSpace($Base64RobotImage) -and $Base64RobotImage -ne "PASTE_YOUR_BASE64_STRING_HERE") {
        $bytes = [Convert]::FromBase64String($Base64RobotImage)
        $stream = New-Object System.IO.MemoryStream(,$bytes)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.StreamSource = $stream
        $bmp.EndInit()
        $imgBrush = New-Object System.Windows.Media.ImageBrush
        $imgBrush.ImageSource = $bmp
        $imgBrush.Stretch = "UniformToFill" 
        $global:window.Background = $imgBrush
    }
} catch {
    Log-Message "Could not load embedded background image: $_" "WARN"
}

# --- CONTROL BINDINGS ---
$Global:StatusTextCtrl = $global:window.FindName('StatusText')
$Global:TxtLogCtrl     = $global:window.FindName('TxtLog')
$Global:MainControls = @{
    'ApplyAuth' = $global:window.FindName('BtnApplyAuth');
    'Refresh'   = $global:window.FindName('BtnRefresh');
    'Create'    = $global:window.FindName('BtnCreateNew'); # NEW
    'Clone'     = $global:window.FindName('BtnClone');
    'Export'    = $global:window.FindName('BtnExport');
    'List'      = $global:window.FindName('BtnList');
    'Import'    = $global:window.FindName('BtnImportCsv');
    'Delete'    = $global:window.FindName('BtnDelete');
    'Exit'      = $global:window.FindName('BtnExit');
}
$RbDefault  = $global:window.FindName('RbDefault')
$RbExplicit = $global:window.FindName('RbExplicit')
$TxtFilter  = $global:window.FindName('TxtFilter')
$GridRoles  = $global:window.FindName('GridRoles')

# ---------------------------- EVENT HANDLERS ----------------------------
$Global:MainControls.ApplyAuth.Add_Click({
    try {
        if ($RbDefault.IsChecked) { Set-ApiAuth -UseDefault:$true; Set-Status "Auth: Default" } 
        else { Set-ApiAuth -UseDefault:$false -PromptCredential; Set-Status "Auth: Explicit" }
    } catch { Log-Message "Auth Error: $_" "ERROR" }
})

function Load-Roles {
    try {
        Set-Busy $true; Set-Status "Loading..."; $roles = Get-ExistingRoles
        $display = @(); $i=1; $filter = To-TrimmedString $TxtFilter.Text
        if ($roles) {
            if ($filter) { $roles = $roles | Where { (Get-RoleDisplayName $_) -like "*$filter*" } }
            foreach ($r in $roles) { $n = Get-RoleDisplayName $r; if($n){$display+=[pscustomobject]@{Index=$i;Name=$n};$i++} }
        }
        $GridRoles.ItemsSource = $display; Set-Status "Roles: $($display.Count)"
    } catch { Log-Message "Load Error: $_" "ERROR"; Set-Status "Error." } finally { Set-Busy $false }
}
$Global:MainControls.Refresh.Add_Click({ Load-Roles })

$Global:MainControls.List.Add_Click({
    try {
        $s = $GridRoles.SelectedItem; if(!$s){Set-Status "Select role.";return}
        $rn = $s.Name; Set-Busy $true; $rows = Get-PermissionsForRole $rn
        if($rows){Show-PermissionsDialog $rn $rows}else{Set-Status "No perms found."}
    } catch { if("$($_)" -match "403|Forbidden"){Set-Status "Access Denied."}else{Set-Status "Error."} Log-Message $_ "ERROR" } finally {Set-Busy $false}
})

$Global:MainControls.Create.Add_Click({
    try {
        # Opens the Create Wizard with hardcoded Tree Items
        Show-CreateRoleDialog
    } catch { 
        Log-Message "Error opening Create Wizard: $_" "ERROR"
    }
})

$Global:MainControls.Export.Add_Click({
    try {
        $s = $GridRoles.SelectedItem; if(!$s){Set-Status "Select role.";return}
        $rn = $s.Name; Set-Busy $true; Export-RoleToCsv $rn; Set-Status "Exported."
    } catch { if("$($_)" -match "403|Forbidden"){Set-Status "Access Denied."}else{Set-Status "Error."} Log-Message $_ "ERROR" } finally {Set-Busy $false}
})

$Global:MainControls.Clone.Add_Click({
    try {
        $s = $GridRoles.SelectedItem; if(!$s){Set-Status "Select role.";return}
        $src = $s.Name
        $new = Show-InputDialog "Clone Role" "New Name:" "$src - Copy"
        if(!$new){return}; if(Is-InvalidRoleName $new){Set-Status "Invalid Name.";return}
        Set-Busy $true; $perms = Get-PermissionsForRole $src
        if(!$perms){Set-Status "Source has no perms.";return}
        if(!(Add-Role $new)){Set-Status "Create failed.";return}
        $ex = Get-ExistingPermissionSet $new
        foreach($p in $perms){ Ensure-Permission $new @{PluginName=$p.PluginName;Permission=$p.PermissionName} $ex }
        Set-Status "Cloned."; Load-Roles
    } catch { if("$($_)" -match "403|Forbidden"){Set-Status "Access Denied."}else{Set-Status "Error."} Log-Message $_ "ERROR" } finally {Set-Busy $false}
})

$Global:MainControls.Import.Add_Click({
    try {
        Set-Busy $true; $ofd = New-Object Microsoft.Win32.OpenFileDialog; $ofd.Filter="CSV|*.csv"; $ofd.InitialDirectory=$rmsrolepath
        if(!$ofd.ShowDialog()){return}; $csv = Import-Csv $ofd.FileName
        if(!$csv){Set-Status "Empty CSV.";return}
        $def = ($csv|select -first 1).RoleName
        $new = Show-InputDialog "Import" "Role Name:" $def; if(!$new){return}
        if(!(Add-Role $new)){Set-Status "Create failed.";return}
        $ex = Get-ExistingPermissionSet $new
        foreach($r in $csv){
             $plugin = if ($r.PSObject.Properties['PermissionPlugin']) { $r.PermissionPlugin } else { $r.PluginName }
             Ensure-Permission $new @{PluginName=$plugin;Permission=$r.PermissionName} $ex 
        }
        Set-Status "Imported."; Load-Roles
    } catch { if("$($_)" -match "403|Forbidden"){Set-Status "Access Denied."}else{Set-Status "Error."} Log-Message $_ "ERROR" } finally {Set-Busy $false}
})

$Global:MainControls.Delete.Add_Click({
    $s = $GridRoles.SelectedItem; if(!$s){Set-Status "Select role.";return}
    $rn = $s.Name
    
    try { 
        Set-Busy $true
        Set-Status "Checking assignments..."
        Refresh-UI
        
        # --- NEW CHECK: Are any users assigned? ---
        $assigned = Get-UsersInRole $rn
        Set-Busy $false
        
        $confirm = $false
        
        if ($assigned.Count -gt 0) {
            $msg = "The role '$rn' is currently assigned to the following users:`n`n" + ($assigned -join "`n") + "`n`nAre you SURE you want to delete it?"
            $res = [System.Windows.MessageBox]::Show($msg, "Warning: Role in Use", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($res -eq 'Yes') { $confirm = $true }
        } else {
            $msg = "Permanently delete '$rn'?"
            $res = [System.Windows.MessageBox]::Show($msg, "Confirm", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
            if ($res -eq 'Yes') { $confirm = $true }
        }
        
        if ($confirm) {
            Set-Busy $true
            if (Delete-Role $rn) { Set-Status "Deleted."; Load-Roles } else { Set-Status "Failed." }
        }
        
    } catch { 
        if("$($_)" -match "403|Forbidden"){ Set-Status "Access Denied." } else { Set-Status "Error." } 
        Log-Message $_ "ERROR" 
    } finally { 
        Set-Busy $false 
    }
})

$Global:MainControls.Exit.Add_Click({ Dispose-Logger; $global:window.Close() })

$global:window.Add_SourceInitialized({ try{Set-ApiAuth -UseDefault:$true}catch{}; Load-Roles })
$app = New-Object System.Windows.Application
$app.Run($global:window) | Out-Null