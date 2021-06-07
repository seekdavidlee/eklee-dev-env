# Introduction
Run the following PowerShell command in CloudShell (https://shell.azure.com) to create your Windows 10 Development Virtual Machine. Please feel free to fork out this repository and use this as a basis for creating your very own Development environment for your personal or organizational use.

```
.\Deploy.ps1 -StackName <StackName> -GitDisplayName <Display Name> -GitEmail <Email used in Git>
```

There is an optional parameter UserObjectId. This is necessary to establish the credentials to access Azure Key Vault where the password to login to the VM is stored. To find your UserObjectId, you can run the following command and look for your user.

```
az ad user list 
```

The following tools/dependenices are installed.

* Visual Studio 2019 (Community or Enterprise)
* Visual Studio Code (With several extensions)
* SQL Management Studio
* Docker Desktop
* Azure CLI
* Choco
* AzCopy
* Terraform
* Node
* NPM

## Switches

* Install the Enterprise version of Visual Studio 2019: -UseVisualStudioEnterprise
* Update with a new password: -ForcePasswordChange
* Skip running the ARM Template to create or update the VM. This is useful if you are simply trying to apply VM extensions: -SkipApplyResources
* Use alternate location to create Virtual machine i.e. Central US: -UseAltLocation

## VM with Default Settings

* Your Virtual machine will be created in South Central US. You can also change location: -Location <Location>
* Your Virtual machine will be created with Standard_D2s_v3, which will contain 2 cores and 8 GB of memory. You can also change VM size: -VmSize <VMSize>
* Your Virtual machine will shutdown daily at 9 PM Central Standard Time. You can also change this: -ShutdownTime <ShutdownTime> -ShutdownTimeZoneId <ShutdownTimeZoneId>
* Your Virtual machine will be configured with the IP of the machine where the script is running from to be allowed access. In this case, if you want your own PC access, use the following: -OpenToIP <YourIPAddress>

## Default git repos

If you would like to do a git clone automatically of public git repos that do not exist, you can pass in the following: -GitReposFilePath <FilePathToTxtFileContainingGitRepo>.
