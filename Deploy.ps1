param(
    [Parameter(Mandatory = $true)]$StackName, 
    [Parameter(Mandatory = $false)]$ImageSku, 
    [Parameter(Mandatory = $false)]$OpenToIP, 
    [Parameter(Mandatory = $false)]$GitReposFilePath, 
    [Parameter(Mandatory = $false)]$Location, 
    [Parameter(Mandatory = $false)]$ShutdownTime,
    [Parameter(Mandatory = $false)]$ShutdownTimeZoneId,
    [Parameter(Mandatory = $false)]$VmSize,
    [Switch]$UseVisualStudioCommunity, 
    [Switch]$SkipApplyResources, 
    [Switch]$ForcePasswordChange, 
    [Switch]$UseAltLocation)

$ErrorActionPreference = "Stop"

if ((az account list | ConvertFrom-Json).Length -eq 0) {
    az login
}

if (!$Location) {
    if ($UseAltLocation) {
        $Location = "Central US"
    }
    else {
        $Location = "South Central US"
    }
}

$exist = (az group exists --name $StackName) | ConvertFrom-Json

if (!$exist) {
    az group create --name $StackName --location $Location
    Write-Host "Created Resource Group $StackName"
}
else {
    Write-Host "Resource Group $StackName exist."
}

$objectId = ((az ad user list --upn (az account list | ConvertFrom-Json).user[0].name) | ConvertFrom-Json).objectId

if (!$SkipApplyResources) {

    if (!$ImageSku) {        
        if ($UseVisualStudioCommunity) {
            $ImageSku = "vs-2019-comm-latest-win10-n"
        }
        else {
            $ImageSku = "vs-2019-ent-latest-win10-n"
        }        
    }
    
    # It is important to note that this is a "throw-away" password because we will reset the password again after the completing the ARM Template deployment. 
    # Hence, we are not required to show it for any useful purposes.
    $plainText = [guid]::NewGuid().ToString("N").Substring(0, 7).ToUpper() + "!" + [guid]::NewGuid().ToString("N").Substring(0, 7).ToLower()

    if (!$OpenToIP) {
        $OpenToIP = Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip
    }

    if (!$ShutdownTime) {
        $ShutdownTime = "2100"
    }

    if (!$ShutdownTimeZoneId) {
        $ShutdownTimeZoneId = "Central Standard Time"
    }

    if (!$VmSize) {
        $VmSize = "Standard_D2s_v3"
    }

    az deployment group create --resource-group $StackName --template-file ./deployment/dev-vm.json `
        --parameters stackName=$StackName loginPassword=$plainText objectId=$objectId myIP=$OpenToIP imageSku=$ImageSku shutdownTime=$ShutdownTime shutdownTimeZoneId=$ShutdownTimeZoneId vmSize=$VmSize | ConvertFrom-Json
}

$secrets = az keyvault secret list --vault-name $StackName --query "[].{Name:name}" | ConvertFrom-Json

$findName = "$StackName-login-password"
$foundName = $secrets | Where-Object { $_.name -eq $findName }

if (!$foundName -Or $ForcePasswordChange) {

    $plainText = [guid]::NewGuid().ToString("N").Substring(0, 7).ToUpper() + "!" + [guid]::NewGuid().ToString("N").Substring(0, 7).ToLower()

    az keyvault secret set --vault-name $StackName --name "$StackName-login-password" --value "$plainText" | Out-Null

    Write-Host "Setting new password"

    az vm user update -n $StackName -g $StackName -u ($StackName + "admin") -p $plainText
}
else {
    Write-Host "Password exist in key vault and will be used."
}

$key1 = (az storage account keys list -g $StackName -n $StackName | ConvertFrom-Json)[0].value
$setupFile = "Setup.ps1"
$setupSrcFilePath = Join-Path -Path (Join-Path -Path (Get-Location).Path -ChildPath "scripts") -ChildPath $setupFile
$setupDestFilePath = Join-Path -Path (Join-Path -Path (Get-Location).Path -ChildPath "temp") -ChildPath $setupFile

$content = Get-Content $setupSrcFilePath
$content = $content.Replace("%StackName%", "$StackName")

$temp = "temp"
$tempPath = Join-Path -Path (Get-Location).Path -ChildPath $temp

New-Item -ItemType Directory -Force -Path $tempPath

Set-Content -Path $setupDestFilePath -Value $content

$uploadList = @()
az storage blob upload -f $setupDestFilePath -c "scripts" -n $setupFile --account-name $StackName --account-key $key1
$uploadList += "https://$StackName.blob.core.windows.net/scripts/$setupFile"

$initFileName = "InitLogin.ps1"
$initFilePath = Join-Path -Path (Join-Path -Path (Get-Location).Path -ChildPath "scripts") -ChildPath $initFileName
az storage blob upload -f $initFilePath -c "scripts" -n $initFileName --account-name $StackName --account-key $key1
$uploadList += "https://$StackName.blob.core.windows.net/scripts/$initFileName"

$profileContent = "ProfileContent.ps1"
$profileContentFilePath = Join-Path -Path (Join-Path -Path (Get-Location).Path -ChildPath "scripts") -ChildPath $profileContent
az storage blob upload -f $profileContentFilePath -c "scripts" -n $profileContent --account-name $StackName --account-key $key1
$uploadList += "https://$StackName.blob.core.windows.net/scripts/$profileContent"

if (!$GitReposFilePath -and (Test-Path $GitReposFilePath)) {
    az storage blob upload -f $GitReposFilePath -c "scripts" -n "gitrepos.txt" --account-name $StackName --account-key $key1
    $uploadList += "https://$StackName.blob.core.windows.net/scripts/gitrepos.txt"
}

$settings = @{ "fileUris" = $uploadList; } | ConvertTo-Json -Compress
$settings = $settings.Replace("""", "'")

$user = az ad user list --upn (az account list | ConvertFrom-Json).user[0].name | ConvertFrom-Json
$gitUser = $user.displayName
$gitEmail = $user.userPrincipalName

$cmd = "powershell -ExecutionPolicy Unrestricted -File $setupFile -StackName $StackName -GitConfigUser $gitUser -GitConfigEmail $gitEmail -UserObjectId $objectId"

$protectedSettings = @{"commandToExecute" = $cmd; "storageAccountName" = $StackName; "storageAccountKey" = $key1 } | ConvertTo-Json -Compress
$protectedSettings = $protectedSettings.Replace("""", "'")

Write-Host "Running VM extensions"
# See: https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
az vm extension set -n CustomScriptExtension --publisher Microsoft.Compute --vm-name $StackName --resource-group $StackName `
    --protected-settings $protectedSettings --settings $settings --force-update

Write-Host "Script executed. Looking up logs..."

$statusList = (az vm get-instance-view --name $StackName --resource-group $StackName --query instanceView.extensions | ConvertFrom-Json)
$customScript = $statusList | Where-Object { $_.name -eq "CustomScriptExtension" }

$wsl2Failure = $false
for ($i = 0; $i -lt $customScript.substatuses.Length; $i ++) {
    $s = $customScript.substatuses[$i]

    if ($s.displayStatus -eq "Provisioning succeeded") {
        $s.message

        if ($s.message.Contains("The install of wsl2 was NOT successful.")) {
            $wsl2Failure = $true
        }
    }
    else {
        $s
    }
}

if ($wsl2Failure) {

    Start-Sleep -Seconds 10

    $counter = 0
    $vmStatus = (az vm get-instance-view --name $StackName --resource-group $StackName --query instanceView.statuses[1] | ConvertFrom-Json).code
    while ($vmStatus -ne "PowerState/running") {

        if ( $counter -eq 30) {
            throw "Timeout! VM status = $vmStatus"
        }

        Start-Sleep -Seconds 3
        $vmStatus = (az vm get-instance-view --name $StackName --resource-group $StackName --query instanceView.statuses[1] | ConvertFrom-Json).code

        $counter += 1
    }

    Write-Host "Running VM extensions again..."
    # See: https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
    az vm extension set -n CustomScriptExtension --publisher Microsoft.Compute --vm-name $StackName --resource-group $StackName `
        --protected-settings $protectedSettings --settings $settings --force-update

    Write-Host "DEV VM is being created..."
}
else {
    Write-Host "DEV VM created successfully."
}