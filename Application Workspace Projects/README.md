# Application_Workspace_Projects
This repo will be to store all my custom scripts I write for Application Workspace.

For all my scripts that use the powershell commands for Application Workspace, the account for use with the APIACCESS may need the following permissions:

1. API Access
2. View Connectors
3. Create Packages
4. View Packages
5. Modify Packages
6. Remove Packages
7. View Resources
8. View Devices
9. View Device Collections
10. Modify Device Collections
11. Create Device Collections

You can create a custom Access Policy and assign it to the apiuser account that you create for this process.

## Disclaimer

All scripts contained in this repo are examples of what you can do. You may need to use these as a base and modify for your needs from here. There is no warranty or support available for these scripts. I can try to help, however, these are not supported by Recast Software.

## Move-AWStages.ps1 

This script that can automate the process of moving packages through the stages in Application Workspace. You define the number of days that you want between the stages. It will take the last date modified as it's starting point and then progress from there. This assumes that you have a synchronize connector syncing packages to the Test Stage and then after so many days in Test, it moves to Acceptance and then after so many days it moves to Production. This would be set as a scheduled task on a Utility server that can run on whatever schedule you want it to run on.

## Sync-EntraGroupWithAWCollection.ps1 

This script will assist in syncing devices in an Entra AD group to a matcing Device Collection in Application Workspace. This will need to be modified from its original version if you want to support multiple Entra AD Groups and multiple Device Collections. This is just a starting point. This will require someone to sign in with the right permissions. If you wanted to, you could modify this to support an app registration and secret key so that you can run this as a scheduled task. This will remove any members that have been taken out of that Entra group, and add those that have been added. This will also create the Device Collection if it doesn't already exist to match the displayName of the Entra AD Group.

## Import-ConfigMgrPackages.ps1 (soon to be replaced with a new tool)

This script will attempt to import in applications and packages from ConfigMgr into Application Workspace. It will not create "Launch" actions as those don't exist in ConfigMgr. This will create the install action and create all the steps for that install action based on the install command line in the ConfigMgr package/application. It will also create an uninstall action "if" there is an uninstall command specified in the ConfigMgr application. Currently there is a bug in the script that if in the install command line or the uninstall command line there is a .\ in the command, it fails to create correctly.

## Sync-MultipleEntraGroupsToAW.ps1

This script uses an app registration and a secret key so that you can automate the process of syncing Entra Groups to Application Workspace Groups. You will need to specify the correct groups you want to sync to. I tried to document each action so that it makes sense... This will add if there are new objects and remove if any have been removed from the Entra AD groups. In this example, Entra is the source of truth...

## Sync-ConfigMgrCollectionsToAWUserCollections.ps1

This script will query ConfigMgr for all collections and give you the option to recreate them in AW as user collections. This will take the devices' primary user or last logged on user and add them to a User Collection in AW. It has an option to just sync the ones that you have already brought in so that you can just run it on a schedule and make sure to add any other devices' users down the road. This is currently not working for User Groups, only Device Groups. I will work on that.

## Create-TakeOverPackage.ps1

This script is designed to assist in "taking over" applications that may already be installed. This script creates a single "take over" package that can be ran against machines. The package it creates will in essence run the install package step for every package within your AW environment and marks it as installed through AW. During that process, it will update existing versions to the version released in AW. This will only do this for applications that are installed on that machine and ignore any that are not installed. This script can also add more actions that will create user collections for each "package" and create entitlements to the original package to that user collection. It can then also add the user that runs it to that collection so that when you take over the application, you can also have an inventory of who has which application installed.

## Create-WorkspaceIconPackages.ps1

This script can create a package for all applications on a machine, in essence creating smart icons for any existing application installed, until such time as you replace with managed packages, but give you the ability to start using AW smart icons with existing installed applications.

## Export-AWDataForReporting.ps1

This script is just built to gather a bunch of information from AW and export them to files so that you can create reporting from that data.

## Install-AWDynamicFromCloud_macOS.sh

This script can be ran as a platform script as an installation script to install AW on new machines. It does all the work needed to install, no need to package up any files for installation.

