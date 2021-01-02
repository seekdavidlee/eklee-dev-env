function CreateDesktopShortcut {
    param($LinkName, $TargetPath, $StackName)
    
    $user = $StackName + "admin"
    $Path = "C:\Users\$user\Desktop\$LinkName.lnk" 
    
    if (!(Test-Path $Path)) {
        $Shell = New-Object -ComObject ("WScript.Shell")
        $ShortCut = $Shell.CreateShortcut($Path)
        $ShortCut.TargetPath = $TargetPath
        $ShortCut.WindowStyle = 1;
        $ShortCut.Save()
    }
    else {
        Write-Host "$LinkName already exist"   
    }
}

$userProfileFilePath = "C:\dev\userprofile.json"
$user = Get-Content -Path $userProfileFilePath | ConvertFrom-Json

# https://docs.microsoft.com/en-us/powershell/scripting/windows-powershell/ise/how-to-use-profiles-in-windows-powershell-ise?view=powershell-7.1
if (!(Test-Path -Path $PROFILE)) {    

    $path = [System.IO.Path]::GetDirectoryName($PROFILE)
    If (!(Test-Path $path)) {
        New-Item -ItemType Directory -Force -Path $path
    }
    Copy-Item -Path "C:\dev\tools\ProfileContent.ps1" -Destination $PROFILE -Force    
}
else {
    Write-Host "Profile file exist."
}

# Setup Shortcuts
CreateDesktopShortcut -LinkName "Microsoft SQL Server Management Studio 18" -TargetPath "C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\Ssms.exe" `
    -StackName $user.stackName

git config --global user.name $user.name
git config --global user.email $user.username

$extList = code --list-extensions
$ext = @("hashicorp.terraform", "ms-azure-devops.azure-pipelines", 
    "msazurermtools.azurerm-vscode-tools", "ms-kubernetes-tools.vscode-kubernetes-tools",
    "ms-vscode.azure-account", "ms-vscode.powershell", "ms-azuretools.vscode-docker")

for ($i = 0; $i -lt $ext.Length; $i++) {
    $exItem = $ext[$i]
    if (!$extList -or !$extList.Contains($exItem)) {
        code --install-extension $exItem
    }    
}

$list = az account list | ConvertFrom-Json 

if ($list.Length -eq 0) { 
    az login --use-device-code 
}

if ((Get-ExecutionPolicy -Scope LocalMachine) -ne "Unrestricted") {
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force
}