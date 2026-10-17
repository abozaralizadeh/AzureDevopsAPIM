#### Update BS APIM Repo

$org_name = "my_org"
$proj_name = "my_proj"
$repo_name = "my_repo"

$ResourceGroupPre = "$(ResourceGroupPre)"
$ServiceNamePre = "$(ServiceNamePre)"
$ResourceGroupBS = "$(ResourceGroupBS)"
$ServiceNameBS = "$(ServiceNameBS)"

$SubscriptionId = (Get-AzContext).Subscription.id
$ExpiryTimespan = (New-Timespan -Hours 2)
$KeyType = 'primary'

# Clone from DevOps Repo
$exist = Test-Path "${repo_name}"
if ("${exist}" -eq "False") { 
echo "Doing Clone"
git clone https://$($env:SYSTEM_ACCESSTOKEN)@$($org_name).visualstudio.com/$($proj_name)/_git/$($repo_name)
}
else {
echo "Skip Clone"
}

# Go to the folder
cd $repo_name

# Get the right commit
git checkout $(ReleaseCommit)

echo "Clone is done!"

# Save to BS Repo
$apimContextBS = New-AzApiManagementContext -ResourceGroupName $ResourceGroupBS -ServiceName $ServiceNameBS

$context = $apimContextBS

$expiry = (Get-Date).ToUniversalTime() + $ExpiryTimespan
$parameters = @{
    "keyType"= $KeyType
    "expiry"= ('{0:yyyy-MM-ddTHH:mm:ss.000Z}' -f $expiry)
}

$resourceId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ApiManagement/service/{2}/users/git' -f $SubscriptionId,$ResourceGroupBS,$ServiceNameBS

$gitUsername = 'apim'
$gitPassword = (Invoke-AzResourceAction -Action 'token' -ResourceId $resourceId -Parameters $parameters -ApiVersion '2016-10-10' -Force).Value
Write-Host "##vso[task.setsecret]$gitPassword"

echo User is $gitUsername

$pwUrlencodedLowerCase = [System.Web.HttpUtility]::UrlEncode($gitPassword)
Write-Host "##vso[task.setsecret]$pwUrlencodedLowerCase"

$gitUrl = "https://${gitUsername}:${pwUrlencodedLowerCase}@${ServiceNameBS}.scm.azure-api.net"

echo "APIM Git host: ${ServiceNameBS}.scm.azure-api.net"

git remote set-url origin $gitUrl
git push -f origin $(ReleaseCommit):master
echo "Pushing commit $(ReleaseCommit):master to APIM"

# Deploy to BS
Publish-AzApiManagementTenantGitConfiguration -Context $apimContextBS -Branch 'master' -PassThru

echo "Deployment Done with success!"
