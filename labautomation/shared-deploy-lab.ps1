<#
.SYNOPSIS
    Prepares one subscription before the per-participant labs run.

.DESCRIPTION
    The MicroHack platform runs this script once per subscription, before any deploy-lab.ps1.
    It registers the Microsoft.Fabric resource provider once, so the parallel labs do not race on
    it, and logs the subscription's Fabric capacity-unit quota against the labs it will hold.
    It creates no resources and emits no credentials. Problems are reported as warnings rather
    than failures: a failed shared hook would stop every lab in every subscription, while each
    deploy-lab.ps1 re-checks the provider and fails only its own lab.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$PreferredLocation,

    [Parameter(Mandatory=$false)]
    [string[]]$AllowedEntraUserIds = @()
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'fabric-lab-helpers.ps1')

$labSku = 'F2'

Assert-LabCommand -Name @('Update-MhhToken', 'Get-AzContext', 'Get-AzAccessToken')
if ($SubscriptionId -notmatch $LabGuidPattern) { throw "SubscriptionId '$SubscriptionId' is not a subscription ID." }
$context = Get-AzContext
if ($null -eq $context -or $context.Subscription.Id -ne $SubscriptionId) {
    throw "The Az context is not set to subscription $SubscriptionId; hooks never switch context."
}
$regions = @()
$labCount = 0
try {
    $regions = @(ConvertTo-LabRegionList -Value $PreferredLocation)
    $labCount = @(ConvertTo-LabParticipantIdList -Value $AllowedEntraUserIds).Count
}
catch {
    Write-Warning "Unexpected hook input; the quota pre-flight uses what it could read: $($_.Exception.Message)"
}

try {
    Wait-LabProviderRegistration -SubscriptionId $SubscriptionId -Namespace 'Microsoft.Fabric'
    Write-LabLog "Microsoft.Fabric is registered in subscription $SubscriptionId."
}
catch {
    Write-Warning "Microsoft.Fabric registration did not complete: $($_.Exception.Message) Each lab re-checks it."
    return
}

# Read-only quota pre-flight: every lab needs its own F2 in whichever region it lands.
try {
    $needed = (Get-LabSkuCapacityUnit -SkuName $labSku) * [Math]::Max(1, $labCount)
    $skuRegions = @(Get-LabFabricSkuRegion -SubscriptionId $SubscriptionId -SkuName $labSku)
    foreach ($region in $regions) {
        if ($skuRegions -notcontains $region) {
            Write-Warning "Microsoft.Fabric does not offer $labSku in '$region' for this subscription; the labs skip that region."
            continue
        }
        $quota = Get-LabFabricQuota -SubscriptionId $SubscriptionId -Region $region
        if ($null -eq $quota) {
            Write-Warning "No Fabric capacity-unit quota information for '$region'."
            continue
        }
        Write-LabLog ("Fabric quota in ${region}: limit $($quota.Limit) CU, in use $($quota.Used) CU; " +
            "$labCount lab(s) in this subscription need $needed CU.")
        if ($quota.Limit -lt $needed) {
            Write-Warning ("The Fabric quota in '$region' ($($quota.Limit) CU) is below the $needed CU that $labCount $labSku " +
                'lab(s) need. Labs that do not fit fail or move to the next preferred region: request a Microsoft Fabric ' +
                'quota increase or lower labsPerSubscription.')
        }
    }
}
catch {
    Write-Warning "Fabric quota pre-flight skipped: $($_.Exception.Message)"
}
