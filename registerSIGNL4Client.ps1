Import-Module Az.Resources # Imports the PSADPasswordCredential object

$SIGNL4AppNameAzure = "SIGNL4AzureSentinelLogAnalyticsAPI"
$SIGNL4AzureRoleName = "Access to Azure Sentinel and Log Analytics API for S4";

$s4config = [pscustomobject]@{
SubscriptionId = ''
TenantId = ''
ClientId = ''
ClientSecret = ''
}

# Login to Azure
Connect-AzAccount

# Read and display all subscriptions
$subscriptions = Get-AzSubscription
$subscriptions | Format-Table -Property SubscriptionId,Name,State,TenantId

$subIndex = Read-Host -Prompt "Please enter row number of subscription to use (starting from 1)"


$s4config.SubscriptionId = $subscriptions[$subIndex-1].SubscriptionId
$s4config.TenantId = $subscriptions[$subIndex-1].TenantId


$subScope = "/subscriptions/" + $s4config.SubscriptionId


# Create the SPN in the sub
$spnPwd = New-Guid
$credentials = New-Object Microsoft.Azure.Commands.ActiveDirectory.PSADPasswordCredential -Property @{ StartDate=Get-Date; EndDate=Get-Date -Year 2020; Password=$spnPwd}
$spn = New-AzADServicePrincipal -DisplayName $SIGNL4AppNameAzure -PasswordCredential $credentials


Write-Output "SPN created in Azure:"
$spn | Format-Table -Property ApplicationId,DisplayName,Id,ServicePrincipalNames

$s4config.ClientId = $spn.ApplicationId
$s4config.ClientSecret = $spnPwd #$spn.Secret | ConvertFrom-SecureString





# Remove contributor role from the SPN which is added by deefault :-S
$roles = Get-AzRoleAssignment -ObjectId $s4config.ClientId
foreach ($role in $roles) 
{
    Write-Output "Removing following role from the SPN that was added by default: " + $role.RoleDefinitionName
    Remove-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName $role.RoleDefinitionName -Scope $role.Scope
}


# Create new Role. It needs access to SecurityInsights to read the cases and to 
$role = Get-AzRoleDefinition -Name "Contributor"
$role.Id = $null
$role.Name = $SIGNL4AzureRoleName
$role.Description = "Search using new engine."
$role.Actions.RemoveRange(0,$role.Actions.Count)
$role.Actions.Add("Microsoft.OperationalInsights/workspaces/query/read")
$role.Actions.Add("Microsoft.OperationalInsights/workspaces/query/*/read");
$role.Actions.Add("Microsoft.OperationalInsights/workspaces/read");
$role.AssignableScopes.Clear()
$role.AssignableScopes.Add($subScope)


Write-Output "Creating new role in Azure, which may take some seconds..."
New-AzRoleDefinition -Role $role

Start-Sleep -s 20


# Assign SPN to that role
Write-Output "Role created in Azure, adding SPN to that role..."
New-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName $SIGNL4AzureRoleName -Scope $subScope

Start-Sleep -s 10

# Also add to Azure Sentinal Contributor role to be able to read Cases 
New-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName "Azure Sentinel Contributor" -Scope $subScope



Write-Output ""
Write-Output ""
Write-Output ""
Write-Output "*** All set, please enter these details in the SIGNL4 AzureMonitor App config... ***"
$s4config | Format-List -Property SubscriptionId,TenantId,ClientId,ClientSecret