#### Update Prod APIM Repo

$org_name = "my_org"
$proj_name = "my_proj"
$repo_name = "my_repo"

$ResourceGroupPre = $(ResourceGroupPre)
$ServiceNamePre = $(ServiceNamePre)
$ResourceGroupProd = $(ResourceGroupProd)
$ServiceNameProd = $(ServiceNameProd)

$SubscriptionId = (Get-AzContext).Subscription.id
$ExpiryTimespan = (New-Timespan -Hours 2)
$KeyType = 'primary'

# Save tu DevOps Repo
$exist = Test-Path "${ServiceNamePre}.scm.azure-api.net"
if ("${exist}" -eq "False") { 
echo "Doing Clone"
git clone https://$($env:SYSTEM_ACCESSTOKEN)@$(org_name).visualstudio.com/$(proj_name)/_git/$(repo_name)
}
else {
echo "Skip Clone"
}

# Go to the folder
cd $repo_name

# get the right commit
git checkout $(ReleaseCommit)
echo "Clone is done!"

# Save to Prod Repo
$apimContextProd = New-AzApiManagementContext -ResourceGroupName $ResourceGroupProd -ServiceName $ServiceNameProd

$context = $apimContextProd

$expiry = (Get-Date).ToUniversalTime() + $ExpiryTimespan
$parameters = @{
    "keyType"= $KeyType
    "expiry"= ('{0:yyyy-MM-ddTHH:mm:ss.000Z}' -f $expiry)
}

$resourceId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ApiManagement/service/{2}/users/git' -f $SubscriptionId,$ResourceGroupProd,$ServiceNameProd

$gitUsername = 'apim'
$gitPassword = (Invoke-AzResourceAction -Action 'token' -ResourceId $resourceId -Parameters $parameters -ApiVersion '2016-10-10' -Force).Value

$pwUrlencodedLowerCase = [System.Web.HttpUtility]::UrlEncode($gitPassword)

$gitUrl = "https://${gitUsername}:${pwUrlencodedLowerCase}@${ServiceNameProd}.scm.azure-api.net"
echo $gitUrl

git remote set-url origin $gitUrl
git push -f origin $(ReleaseCommit):master
echo "Pushing commit $(ReleaseCommit):master to APIM"

# Deploy to Prod
Publish-AzApiManagementTenantGitConfiguration -Context $apimContextProd -Branch 'master' -PassThru

echo "Deployment Done with success!"
