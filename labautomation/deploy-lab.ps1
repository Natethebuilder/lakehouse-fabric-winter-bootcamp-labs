<#
.SYNOPSIS
    Gives one participant an empty Fabric workspace on a dedicated, Active F2 capacity.

.DESCRIPTION
    The MicroHack platform runs this script once per participant, in parallel, with Az PowerShell
    and the Azure CLI already signed in to that participant's subscription. The script:
      1. deploys main.bicep (one Microsoft.Fabric/capacities F2) into the participant's resource
         group with region fallback; only the deploying identity administers the capacity;
      2. waits until the capacity is Active and resolves its Fabric capacity ID;
      3. creates or reuses the participant's event-unique Fabric workspace, assigns it to that
         capacity, keeps its Spark runtime on 2.0 and grants the participant the Contributor role;
      4. emits the workspace and capacity details as HackboxCredential entries, only after success.
    It creates no lakehouse or other item: Challenge 1 starts from the empty workspace.
    See README.md in this folder for tenant prerequisites, cost, quota and cleanup.
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('subscription','resourcegroup','resourcegroup-with-subscriptionowner')]
    [string]$DeploymentType,

    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$ResourceGroupName = "",

    [string[]]$PreferredLocation = @(),

    [string[]]$AllowedEntraUserIds = @()
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'fabric-lab-helpers.ps1')

$labSku = 'F2'
$labWorkspaceRole = 'Contributor'
$labRuntimeVersion = '2.0'

Assert-LabCommand -Name @(
    'Invoke-MhhDeploymentWithRegionFallback', 'Get-MhhStableHash', 'Get-MhhGroupName', 'Get-MhhLabUser',
    'Update-MhhToken', 'Get-AzContext', 'Get-AzAccessToken'
)

# Validate the platform inputs here: the param block stays exactly as the platform contract documents it.
if ($SubscriptionId -notmatch $LabGuidPattern) { throw "SubscriptionId '$SubscriptionId' is not a subscription ID." }
$participantIds = @(ConvertTo-LabParticipantIdList -Value $AllowedEntraUserIds)
if ($participantIds.Count -eq 0) { throw "AllowedEntraUserIds must contain the participant's Entra object ID." }
$regions = @(ConvertTo-LabRegionList -Value $PreferredLocation)
if ($regions.Count -eq 0) { throw 'PreferredLocation must contain at least one Azure region.' }
$context = Get-AzContext
if ($null -eq $context -or $context.Subscription.Id -ne $SubscriptionId) {
    throw "The Az context is not set to subscription $SubscriptionId; hooks never switch context."
}

try { $eventName = [string](Get-MhhGroupName).GroupName }
catch { throw "No MicroHack event ID is available (set MHH_EVENTID for a local test): $($_.Exception.Message)" }
if (-not $eventName) { throw 'Get-MhhGroupName returned no group name.' }

if ($DeploymentType -eq 'subscription') {
    # The platform creates no resource group in subscription mode: derive a stable one for this lab.
    $labResourceGroup = 'rg-zava-lakehouse-' + (Get-MhhStableHash -Value (@($eventName, $SubscriptionId) + $participantIds) -Length 12)
}
elseif ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw "DeploymentType '$DeploymentType' requires the participant's ResourceGroupName."
}
else {
    $labResourceGroup = $ResourceGroupName
}

# Only the deploying identity administers the capacity; participants never do.
$principal = Get-LabDeployingPrincipal
if ($participantIds -contains $principal.ObjectId) {
    throw "The deploying identity is also a participant. For a local test, pass another test user's object ID in AllowedEntraUserIds."
}
$labUsers = @(Get-MhhLabUser -UserId $participantIds)
if ($labUsers.Count -ne $participantIds.Count) { throw 'Get-MhhLabUser did not resolve every participant.' }
$primaryUser = $labUsers | Sort-Object -Property Id | Select-Object -First 1
$shortName = (([string]$primaryUser.ShortName).ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if ($shortName.Length -gt 24) { $shortName = $shortName.Substring(0, 24).Trim('-') }
if (-not $shortName) { $shortName = 'participant' }
$userNames = ($labUsers | ForEach-Object { [string]$_.UserPrincipalName }) -join ', '

# Workspaces are tenant-wide and outlive the resource group. Naming each one per event and participant
# lets a rerun reuse its own workspace while a later event never inherits an earlier participant's.
$workspaceName = "zava-lakehouse-$shortName-" + (Get-MhhStableHash -Value (@($eventName) + $participantIds) -Length 12)
$capacityName = 'zavalh' + (Get-MhhStableHash -Value (@($eventName, $SubscriptionId, $labResourceGroup) + $participantIds) -Length 12)
if ($capacityName -notmatch '^[a-z][a-z0-9]{2,62}$') { throw "Capacity name '$capacityName' breaks the Fabric naming rules." }
$workspaceDescription = "Zava Lakehouse MicroHack workspace for $userNames. Event $eventName. Capacity $capacityName " +
    "in resource group $labResourceGroup, subscription $SubscriptionId. Created by labautomation/deploy-lab.ps1; " +
    'delete it after the event.'
Write-LabLog "Participant(s) $userNames; workspace '$workspaceName'; capacity '$capacityName' in '$labResourceGroup'."

# shared-deploy-lab.ps1 registers Microsoft.Fabric once per subscription. Re-check here, and register
# only if that hook did not run, for example in a local test.
Wait-LabProviderRegistration -SubscriptionId $SubscriptionId -Namespace 'Microsoft.Fabric'

# Keep only the preferred regions that offer the SKU, so region fallback never recycles the group for nothing.
$skuRegions = @(Get-LabFabricSkuRegion -SubscriptionId $SubscriptionId -SkuName $labSku)
$candidateRegions = @(foreach ($region in $regions) {
        if ($skuRegions -contains $region) { $region }
        else { Write-Warning "Skipping region '$region': Microsoft.Fabric does not offer $labSku there for this subscription." }
    })
if ($candidateRegions.Count -eq 0) {
    throw "None of the preferred regions offers Fabric $labSku for this subscription: $($regions -join ', ')."
}

# On a rerun after organizers paused the capacity, resume it before the template updates it.
$existingCapacity = Get-LabCapacityResource -SubscriptionId $SubscriptionId -ResourceGroupName $labResourceGroup -Name $capacityName
if ($null -ne $existingCapacity -and
    [string](Get-LabValue (Get-LabValue $existingCapacity 'properties') 'state') -in 'Paused', 'Suspended') {
    Wait-LabCapacityActive -SubscriptionId $SubscriptionId -ResourceGroupName $labResourceGroup -Name $capacityName | Out-Null
}

Write-LabLog "Deploying capacity '$capacityName' ($labSku); regions in order: $($candidateRegions -join ', ')."
$deployment = Invoke-MhhDeploymentWithRegionFallback `
    -PreferredLocations $candidateRegions `
    -ResourceGroupName $labResourceGroup `
    -RgOwnerEntraObjectIds $participantIds `
    -TemplateFile (Join-Path $PSScriptRoot 'main.bicep') `
    -TemplateParameterObject @{
        capacityName           = $capacityName
        skuName                = $labSku
        capacityAdministrators = @($principal.CapacityAdministrator)
    } `
    -DeploymentNamePrefix 'zavalh'
Write-LabLog "Template deployed in region '$([string](Get-LabValue $deployment 'LocationUsed'))'."

$capacity = Wait-LabCapacityActive -SubscriptionId $SubscriptionId -ResourceGroupName $labResourceGroup -Name $capacityName
$capacityRegion = ([string](Get-LabValue $capacity 'location')).Replace(' ', '').ToLowerInvariant()
$fabricCapacity = Resolve-LabFabricCapacity -Name $capacityName -SkuName $labSku -Region $capacityRegion
$fabricCapacityId = [string](Get-LabValue $fabricCapacity 'id')
if ($fabricCapacityId -notmatch $LabGuidPattern) { throw "Fabric returned no capacity ID for '$capacityName'." }
Write-LabLog "Capacity '$capacityName' is Active in '$capacityRegion' (Fabric capacity ID $fabricCapacityId)."

$found = @(Find-LabWorkspace -DisplayName $workspaceName)
if ($found.Count -gt 1) { throw "Several workspaces are named '$workspaceName'; resolve them manually before rerunning." }
if ($found.Count -eq 1) {
    $workspaceId = [string](Get-LabValue $found[0] 'id')
    Write-LabLog "Reusing workspace '$workspaceName' ($workspaceId)."
}
else {
    $createRequest = @{ displayName = $workspaceName; description = $workspaceDescription; capacityId = $fabricCapacityId }
    $created = Invoke-LabRestRequest -Audience Fabric -Method POST -Uri '/v1/workspaces' -Body $createRequest `
        -PassThruStatus 400, 401, 403, 409
    if ($created.StatusCode -in 200, 201) {
        $workspaceId = [string](Get-LabValue $created.Body 'id')
        Write-LabLog "Created workspace '$workspaceName' ($workspaceId)."
    }
    else {
        # A response lost during an earlier attempt can leave the workspace behind: look once more.
        $found = @(Find-LabWorkspace -DisplayName $workspaceName)
        if ($found.Count -ne 1) {
            throw ((Format-LabRestError -Method POST -Uri '/v1/workspaces' -StatusCode $created.StatusCode -Body $created.Body) +
                ". Check that the tenant settings 'Service principals can create workspaces, connections, and deployment " +
                "pipelines' and 'Service principals can call Fabric public APIs' include the platform service principal, " +
                "and that no workspace outside its access already uses the name '$workspaceName'.")
        }
        $workspaceId = [string](Get-LabValue $found[0] 'id')
        Write-LabLog "Found workspace '$workspaceName' ($workspaceId) from an earlier attempt."
    }
}
if ($workspaceId -notmatch $LabGuidPattern) { throw "Fabric returned no workspace ID for '$workspaceName'." }

# Assign the workspace to the current capacity, including after a region-fallback recreate.
Invoke-LabNotFoundRetry { Sync-LabWorkspaceCapacity -WorkspaceId $workspaceId -CapacityId $fabricCapacityId } | Out-Null

# The lab specification relies on Fabric Runtime 2.0, the default for new workspaces.
try {
    $currentRuntime = Invoke-LabNotFoundRetry { Get-LabWorkspaceRuntime -WorkspaceId $workspaceId }
}
catch {
    $currentRuntime = $null
    Write-Warning "Could not read the workspace Spark runtime; new workspaces default to $labRuntimeVersion. $($_.Exception.Message)"
}
if ($null -ne $currentRuntime -and $currentRuntime -ne $labRuntimeVersion) {
    Write-LabLog "Setting the workspace Spark runtime from '$currentRuntime' to $labRuntimeVersion."
    Sync-LabWorkspaceRuntime -WorkspaceId $workspaceId -RuntimeVersion $labRuntimeVersion
}

# Contributor covers every lab step: lakehouse, OneLake files, notebooks, jobs, pipeline and semantic model.
foreach ($participantId in $participantIds) {
    $outcome = Invoke-LabNotFoundRetry {
        Grant-LabWorkspaceRole -WorkspaceId $workspaceId -PrincipalId $participantId -Role $labWorkspaceRole
    }
    Write-LabLog "Workspace role $labWorkspaceRole for ${participantId}: $outcome."
}

$regionLabel = [string](Get-LabValue $fabricCapacity 'region')
if (-not $regionLabel) { $regionLabel = $capacityRegion }
Write-LabLog "Lab ready: workspace '$workspaceName' on capacity '$capacityName' ($labSku, $regionLabel)."

# Dashboard entries, emitted only now that the workspace, capacity and role are in place.
@{ HackboxCredential = @{
        name  = 'Fabric workspace'
        value = $workspaceName
        note  = 'Your own empty workspace. Use this name wherever a lab prompt says <assigned workspace name>.'
    }
}
@{ HackboxCredential = @{
        name  = 'Fabric workspace URL'
        value = "https://app.fabric.microsoft.com/groups/$workspaceId"
        note  = 'Open it with your lab account.'
    }
}
@{ HackboxCredential = @{
        name  = 'Fabric workspace role'
        value = $labWorkspaceRole
        note  = 'Lets you create and run the lab items. Organizers administer the capacity.'
    }
}
@{ HackboxCredential = @{
        name  = 'Fabric capacity'
        value = $capacityName
        note  = 'Dedicated to your workspace and already Active. Do not pause, resize or reassign it.'
    }
}
@{ HackboxCredential = @{
        name  = 'Fabric capacity SKU'
        value = $labSku
        note  = 'Run one Spark workload at a time.'
    }
}
@{ HackboxCredential = @{
        name  = 'Fabric capacity region'
        value = $regionLabel
        note  = "Azure region $capacityRegion."
    }
}
if ($DeploymentType -eq 'subscription') {
    @{ HackboxCredential = @{
            name  = 'Lab Resource Group'
            value = $labResourceGroup
            note  = 'Holds your Fabric capacity.'
        }
    }
}
