param($StackName, $GitConfigUser, $GitConfigEmail, $UserObjectId)

$ErrorActionPreference = "Stop"

function CreateStartupShortcut {
    param($LinkName, $TargetPath, $TargetArgs)
    
    $Path = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\$LinkName.lnk"   
    
    if (!(Test-Path $Path)) {
        $Shell = New-Object -ComObject ("WScript.Shell")
        $ShortCut = $Shell.CreateShortcut($Path)
        $ShortCut.TargetPath = $TargetPath
        $ShortCut.WindowStyle = 1;

        if ($TargetArgs) {
            $ShortCut.Arguments = $TargetArgs
        }

        $ShortCut.Save()
    }
    else {
        Write-Host "$LinkName already exist"   
    }
}

function InstallIfNotExist {
    param (
        $list,
        $name,
        $version
    )

    if ($list.GetType().ToString() -ne "System.String") {

        for ($i = 0; $i -lt $list.Length; $i++) {
            $item = $list[$i].Split('|')[0]
    
            if ($item -eq $name) {
                Write-Host "$name already installed"    
                return
            }
        }
    }

    if ($name -eq "wsl2") {
        choco install wsl2 --params "/Version:2 /Retry:true" -y
    }
    else {
        if ($version -eq "latest") {
            choco install $name -y
        }
        else {
            choco install $name --version=$version -y
        }        
    }    
}

function Install-WindowsFeatureIfNotExist {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)] [string]$FeatureName 
    )  
    if ((Get-WindowsOptionalFeature -FeatureName $FeatureName -Online).State -eq "Enabled") {
        Write-Host "$FeatureName already installed"
        return $false
    }
    else {
        Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart
        return $true
    }
}

$start = Get-Date

if ((Get-PackageProvider -Name NuGet -Force).version -lt 2.8.5.201 ) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force 
}
else {
    Write-Host "Version of NuGet installed = " (Get-PackageProvider -Name NuGet).version
}

if (Get-Module -ListAvailable -Name SqlServer) {
    Write-Host "SQL already installed"
} 
else {
    Install-Module -Name SqlServer -AllowClobber -Force     
}

if (Get-Module -ListAvailable -Name Az) {
    Write-Host "Az already installed"
}
else {
    Install-Module -Name Az -AllowClobber -Force
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "Choco already installed"
}
else {    
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

$toolsDir = "C:\dev\tools"
if (!(Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Force -Path $toolsDir

    # Add toolsDir to the System Path if it does not exist
    if ($env:PATH -notcontains $toolsDir ) {
        $path = ($env:PATH -split ";")
        if (!($path -contains $toolsDir )) {
            $path += $toolsDir 
            $env:PATH = ($path -join ";")
            $env:PATH = $env:PATH -replace ';;', ';'
        }
        [Environment]::SetEnvironmentVariable("Path", ($env:path), [System.EnvironmentVariableTarget]::Machine)
    }
}

if (!(Test-Path "$toolsDir\azcopy.exe")) {
    $zip = "$toolsDir\AzCopy.Zip"

    Start-BitsTransfer -Source "https://aka.ms/downloadazcopy-v10-windows" -Destination $zip
    Expand-Archive $zip $toolsDir -Force
    Get-ChildItem "$($toolsDir)\*\*" | Move-Item -Destination "$($toolsDir)\" -Force

    #Cleanup - delete ZIP and old folder
    Remove-Item $zip -Force -Confirm:$false
}
else {
    Write-Host "AzCopy already installed"
}

$genPassFilePath = "$toolsDir\GenPass.ps1"
if (!(Test-Path $genPassFilePath) ) {
    # Useful script to generate password as needed.
    Set-Content -Path $genPassFilePath -Value "Add-Type -AssemblyName 'System.Web'; [System.Web.Security.Membership]::GeneratePassword(20,0)" -Force
}

$initialLoginFilePath = "$toolsDir\InitLogin.ps1"
if (!(Test-Path $initialLoginFilePath) ) {   
    Copy-Item -Path .\InitLogin.ps1 -Destination $initialLoginFilePath
}

$profileContentFilePath = "$toolsDir\ProfileContent.ps1"
if (!(Test-Path $profileContentFilePath) ) {   
    Copy-Item -Path .\ProfileContent.ps1 -Destination $profileContentFilePath
}

$dir = "C:\windows\system32\config\systemprofile\AppData\Local\Temp"
if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir
}

$restart = $false
if (Install-WindowsFeatureIfNotExist -FeatureName "Microsoft-Hyper-V") {
    $restart = $true
}
if (Install-WindowsFeatureIfNotExist -FeatureName "VirtualMachinePlatform") {
    $restart = $true
}
if (Install-WindowsFeatureIfNotExist -FeatureName "Microsoft-Windows-Subsystem-Linux") {
    $restart = $true
}

$list = (choco list -l -r)

$reqs = @(
    @{"name" = "vscode"; "version" = "latest" }, 
    @{"name" = "git"; "version" = "" }, 
    @{"name" = "sql-server-management-studio"; "version" = "latest" }, 
    @{"name" = "terraform"; "version" = "latest" }, 
    @{"name" = "docker-desktop"; "version" = "latest" }, 
    @{"name" = "azure-cli"; "version" = "2.16.0" }, 
    @{"name" = "kubernetes-helm"; "version" = "latest" },
    @{"name" = "wsl2"; "version" = "latest" })

for ($i = 0; $i -lt $reqs.Length; $i++) {
    $req = $reqs[$i]
    InstallIfNotExist -list $list -name $req.name -version $req.version
}

$username = $StackName + "admin"

# Ensure member is part of docker-users group
if (!(Get-LocalGroupMember -Group "docker-users" -Member $username -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group "docker-users" -Member $username
}
else {
    Write-Host "$username is already part of the docker-users group."
}

$devPath = "C:\dev"
if (!(Test-Path $devPath)) {
    New-Item -ItemType Directory -Force -Path $devPath
}

$userProfileFilePath = "C:\dev\userprofile.json"
if (!(Test-Path $userProfileFilePath) ) {
    # This is used internally by the various workloads.
    $userProfile = @{"username" = $GitConfigEmail; "objectId" = $UserObjectId; "stackName" = $StackName; "name" = $GitConfigUser; }
    $userProfile | ConvertTo-Json | Out-File $userProfileFilePath 
}

if (Test-Path .\gitrepos.txt) {
    $repos = Get-Content .\gitrepos.txt
    $repos | ForEach-Object {
        $repo = $_
        $repoPath = "$devPath\$repo"

        if (!(Test-Path $repoPath)) {                
            git clone "$baseRepo/$repo"
        }
        else {
            Write-Host "$repo already installed"
        }
    }
}
else {
    Write-Host "No git repos to clone"
}

CreateStartupShortcut -LinkName "Docker Desktop" -TargetPath "C:\Program Files\Docker\Docker\Docker Desktop.exe"
CreateStartupShortcut -LinkName "Initial Login Script" -TargetPath "powershell" -TargetArgs "-ExecutionPolicy ByPass -File $initialLoginFilePath"

$end = Get-Date
$totalSecs = (New-TimeSpan -Start $start -End $end).TotalMinutes
"It took $totalSecs mins to process this."

if ($restart ) {
    Restart-Computer -Force
}
