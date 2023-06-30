###
# Update the Devops Repo from the APIM Repo (PRE)
###

# memorize the current artifact commit
$url = "$(System.TeamFoundationServerUri)$(System.TeamProjectId)/_apis/Release/releases/$(Release.ReleaseId)?api-version=6.0-preview.8"

Write-Host "URL: $url"
$pipeline = Invoke-RestMethod -Uri $url -Headers @{
	Authorization = "Bearer $(System.AccessToken)" # Provided by ADO thanks to OAuth checkbox
}

# Change the value of artifact_alias to your's
$pipeline.variables.RollBackCommit.value = "$(Release.Artifacts.artifact_alias.SourceVersion)"

$json = @($pipeline) | ConvertTo-Json -Depth 99
Invoke-RestMethod -Uri $url -Method Put -Body $json -ContentType "application/json" -Headers @{Authorization = "Bearer $(System.AccessToken)"}

#### Update Repo
$org_name = "my_org"
$proj_name = "my_proj"
$repo_name = "my_repo"

$SubscriptionId = (Get-AzContext).Subscription.id

$ResourceGroupPre = $(ResourceGroupPre)
$ServiceNamePre = $(ServiceNamePre)
$ResourceGroupProd = $(ResourceGroupProd)
$ServiceNameProd = $(ServiceNameProd)

$ExpiryTimespan = (New-Timespan -Hours 2)
$KeyType = 'primary'

# Save Pre to Repository
$apimContextPre = New-AzApiManagementContext -ResourceGroupName $ResourceGroupPre -ServiceName $ServiceNamePre
Save-AzApiManagementTenantGitConfiguration -Context $apimContextPre -Branch 'master' -PassThru

# Clone
$context = $apimContextPre

$expiry = (Get-Date).ToUniversalTime() + $ExpiryTimespan
$parameters = @{
    "keyType"= $KeyType
    "expiry"= ('{0:yyyy-MM-ddTHH:mm:ss.000Z}' -f $expiry)
}

$resourceId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ApiManagement/service/{2}/users/git' -f $SubscriptionId,$ResourceGroupPre,$ServiceNamePre

$gitUsername = 'apim'
$gitPassword = (Invoke-AzResourceAction -Action 'token' -ResourceId $resourceId -Parameters $parameters -ApiVersion '2016-10-10' -Force).Value

$pwUrlencodedLowerCase = [System.Web.HttpUtility]::UrlEncode($gitPassword)

$gitUrl = "https://${gitUsername}:${pwUrlencodedLowerCase}@${ServiceNamePre}.scm.azure-api.net"

echo $gitUrl
git clone $gitUrl

# Go to folder
cd "${ServiceNamePre}.scm.azure-api.net"
git pull

echo "Clone is done!"

# Save tu Devops Repo
git remote set-url origin https://$($env:SYSTEM_ACCESSTOKEN)@$(org_name).visualstudio.com/$(proj_name)/_git/$(repo_name)
git push -f

# memorize the release commit

$url = "$(System.TeamFoundationServerUri)$(System.TeamProjectId)/_apis/Release/releases/$(Release.ReleaseId)?api-version=6.0-preview.8"

Write-Host "URL: $url"
$pipeline = Invoke-RestMethod -Uri $url -Headers @{
	Authorization = "Bearer $(System.AccessToken)" # Provided by ADO thanks to OAuth checkbox
}

$pipeline.variables.ReleaseCommit.value = "$(git rev-parse --verify HEAD)"

$json = @($pipeline) | ConvertTo-Json -Depth 99
Invoke-RestMethod -Uri $url -Method Put -Body $json -ContentType "application/json" -Headers @{Authorization = "Bearer $(System.AccessToken)"}