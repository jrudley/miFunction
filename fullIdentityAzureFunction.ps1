#https://learn.microsoft.com/en-us/azure/azure-functions/functions-identity-based-connections-tutorial
#https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference?tabs=queue#local-development-with-identity-based-connections

$location = 'usgovvirginia'
$rgName = 'azfunctest'
$kvName = 'azfuncvault1'
$identityName = 'uami-func'
$funcName = 'functest'
$subscriptionId = (get-azcontext).Subscription.Id
New-AzResourceGroup -name $rgName -Location $location

$kv = New-AzKeyVault -VaultName $kvName  -ResourceGroupName $rgName -Location $location

Update-AzKeyVault -ResourceGroupName $rgName -Name $kvName  -EnableRbacAuthorization $true

$uami = New-AzUserAssignedIdentity -name $identityName -ResourceGroupName $rgName -Location $location 

$roleAssignment = New-AzRoleAssignment -ObjectId $uami.PrincipalId -RoleDefinitionName 'Key Vault Secrets User' -Scope $kv.ResourceId

$random=([char[]]([char]'a'..[char]'z') + 0..9 | sort {get-random})[0..4] -join ''

$template = get-content -raw C:\temp\func\template.json

$template = $template -replace 'VAULT_NAME',$kvName
$template = $template -replace 'IDENTITY_RESOURCE_ID',$uami.id 
$template = $template -replace 'SUBSCRIPTION_ID',$subscriptionId
$template = $template -replace 'FUNC_SHARE',"$funcName$random"

$template | Set-Content -Path C:\temp\func\armfunc.json

$parameters = get-content -raw C:\temp\func\parameters.json | ConvertFrom-Json
$parameters.parameters.serverFarmResourceGroup.value = $rgName
$parameters.parameters.location.value = $location
$parameters.parameters.subscriptionId.value = $subscriptionId
$parameters.parameters.hostingPlanName.value = "ASP-$funcName-$random"
$parameters.parameters.storageAccountName.value = "$funcName$random"
$parameters.parameters.name.value = $funcName
$parameters | ConvertTo-Json -depth 100 | Out-File "c:\temp\func\armparameters.json"

New-AzResourceGroupDeployment -TemplateFile C:\temp\func\armfunc.json -TemplateParameterFile C:\temp\func\armparameters.json -Verbose -ResourceGroupName $rgName

#setup storage account for managed identity

$func = Get-AzFunctionApp -Name $funcName -ResourceGroupName $rgName
$storageAccountName = $parameters.parameters.storageAccountName.value
$stg = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $rgName
$roleAssignment = New-AzRoleAssignment -ObjectId $func.IdentityPrincipalId -RoleDefinitionName 'Storage Account Contributor' -Scope $stg.Id
$roleAssignment = New-AzRoleAssignment -ObjectId $func.IdentityPrincipalId -RoleDefinitionName 'Storage Blob Data Owner' -Scope $stg.Id
$roleAssignment = New-AzRoleAssignment -ObjectId $func.IdentityPrincipalId -RoleDefinitionName 'Storage Queue Data Contributor' -Scope $stg.Id

$appSettings = @{
    "AzureWebJobsStorage__blobServiceUri" = "$($stg.PrimaryEndpoints.Blob.TrimEnd("/"))"
    "AzureWebJobsStorage__queueServiceUri" = "$($stg.PrimaryEndpoints.Queue.TrimEnd("/"))"
    "AzureWebJobsStorage__tableServiceUri" = "$($stg.PrimaryEndpoints.Table.TrimEnd("/"))"
  }

  #add 3 entries per ms doc for managed identity for host storage
  Update-AzFunctionAppSetting -ResourceGroupName $rgName -Name $funcName -AppSetting $appSettings

  #remove default AzureWebJobsStorage setting name
  Remove-AzFunctionAppSetting -ResourceGroupName $rgName -Name $funcName -AppSettingName AzureWebJobsStorage -Force

<#
  #add settings for queue trigger
  #reference blog for editing function.json, etc
  $appSettings = @{
    "AzureWebJobs$($storageAccountName)__queueServiceUri" = "$($stg.PrimaryEndpoints.Queue.TrimEnd("/"))"
  }
  Update-AzFunctionAppSetting -ResourceGroupName $rgName -Name $funcName -AppSetting $appSettings
  #>