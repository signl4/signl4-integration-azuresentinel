# This script:
# - Creates a new registered app in Azure AD (AzureAD)
# - Adds a password credential to it (AzureAD)
# - Creates a service principal for that app (Microsoft.Graph.Applications)
# - Creates a new dedicated role for that service principal which has only access to Azure Sentinel stuff (Az)
# - Assigns the service principal to that role (Az)

# Tested date 02/09/2022
# You'll need to auth to Azure with an Azure tenant amdin account multiple times because three different modules / tech stacks are used
# If modules below are not installed in your environment use these commands:
# Install-Module -Name Microsoft.Graph.Applications     # tested with 1.9.2
# Install-Module -Name AzureAD                          # tested with 2.0.2.16
# Install-Module -Name Az                               # tested with 7.2.0


# #################################################################################
# NOTE: After this script has completed you may need to 
# - log in to Azure Portal
# - navigate to AzureAD -> App registrations -> <createdApp> -> API permissions
# - click the button 'Grant admin consent for <your tenant name>
# #################################################################################


$SIGNL4AppNameAzure = "AzureSentinel and LogAnalytics Client for SIGNL4"
$SIGNL4AzureRoleName = "Access to Azure Sentinel and Log Analytics API for 3rd party systems";
$SIGNL4AppIdentifierUri = "api://AzureSentinelandLogAnalyticsClientforSIGNL4"


$s4config = [pscustomobject]@{
SubscriptionId = ''
TenantId = ''
ClientId = ''
ClientSecret = ''
}

# Login to Azure
Connect-AzAccount #For PS Module 'Az'
Connect-AzureAD #For PS Module 'AzureAD'
Connect-MgGraph -Scope "Directory.AccessAsUser.All" #For PS Module 'Microsoft.Graph.Applications'


# Read and display all subscriptions
$subscriptions = Get-AzSubscription
$subscriptions | Format-Table -Property SubscriptionId,Name,State,TenantId

$subIndex = Read-Host -Prompt "Please enter row number of subscription to use (starting from 1)"


# Sets the tenant, subscription, and environment for cmdlets to use in the current session
Set-AzContext -SubscriptionId $subscriptions[$subIndex-1].SubscriptionId

$s4config.SubscriptionId = $subscriptions[$subIndex-1].SubscriptionId
$s4config.TenantId = $subscriptions[$subIndex-1].TenantId


$subScope = "/subscriptions/" + $s4config.SubscriptionId


# Create the App in the sub
Write-Output "Creating a new Application for SIGNL4 in Azure AD..this will take 1 minute.."
$app = New-AzureADApplication -DisplayName $SIGNL4AppNameAzure -IdentifierUris $SIGNL4AppIdentifierUri
Start-Sleep -s 60 # Needed as it is otherwise not usable due to Azure APIU latency

# Add an app password
Write-Output "Adding a password to the SIGNL4 Application in Azure AD.."
$spnPwd = New-Guid
New-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId -Value $spnPwd


# Add required app API permissions for GraphAPI SecurityEvents/Alerts
Write-Output "Adding required app API permissions for GraphAPI SecurityEvents/Alerts.." 
Add-AzADAppPermission -ApiId '00000003-0000-0000-c000-000000000000' -PermissionId '34bf0e97-1971-4929-b999-9e2442d941d7' -ObjectId $app.ObjectId -Type 'Role'
Add-AzADAppPermission -ApiId '00000003-0000-0000-c000-000000000000' -PermissionId '45cc0394-e837-488b-a098-1918f48d186c' -ObjectId $app.ObjectId -Type 'Role'
Add-AzADAppPermission -ApiId '00000003-0000-0000-c000-000000000000' -PermissionId 'ed4fca05-be46-441f-9803-1873825f8fdb' -ObjectId $app.ObjectId -Type 'Role'
Add-AzADAppPermission -ApiId '00000003-0000-0000-c000-000000000000' -PermissionId '472e4a4d-bb4a-4026-98d1-0b0d74cb74a5' -ObjectId $app.ObjectId -Type 'Role'
Add-AzADAppPermission -ApiId '00000003-0000-0000-c000-000000000000' -PermissionId 'd903a879-88e0-4c09-b0c9-82f6a1333f84' -ObjectId $app.ObjectId -Type 'Role'
Add-AzADAppPermission -ApiId '00000003-0000-0000-c000-000000000000' -PermissionId 'bf394140-e372-4bf9-a898-299cfc7564e5' -ObjectId $app.ObjectId -Type 'Role'

### Create the SPN in the sub
Write-Output "Creating an SPN for the SIGNL4 Application Azure AD.."
$params = @{
	AppId = $app.appId
}
$spn = New-MgServicePrincipal -BodyParameter $params



Write-Output "App and SPN created in Azure:"
$spn | Format-Table -Property AppId,DisplayName,Id

$s4config.ClientId = $spn.AppId
$s4config.ClientSecret = $spnPwd





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


# Sleep a little while and wait until the new role is completely populated and available in Azure. Otherwise consider adding the role assignment manually in Azure Portal. The SPN shows up for assignement..
Start-Sleep -s 60


# Assign SPN to that role
Write-Output "Role created in Azure, adding SPN to that role..."
New-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName $SIGNL4AzureRoleName -Scope $subScope

Start-Sleep -s 10

# Also add to Azure Sentinal Contributor role to be able to read Cases 
New-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName "Microsoft Sentinel Contributor" -Scope $subScope



Write-Output ""
Write-Output ""
Write-Output ""
Write-Output "*** All set, please enter these details in the SIGNL4 AzureMonitor App config... ***"
$s4config | Format-List -Property SubscriptionId,TenantId,ClientId,ClientSecret