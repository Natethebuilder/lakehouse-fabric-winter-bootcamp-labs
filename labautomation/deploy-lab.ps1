<#
.SYNOPSIS
    Shows one participant where their Fabric workspace for this lab is.

.DESCRIPTION
    Lab hook of the shared bootcamp Fabric contract (v1). Before the bootcamp, the organizer tooling
    gives every participant one Fabric capacity, shared by all of their bootcamp labs, and one empty
    workspace per lab on it, named adwb-<labKey>-<shortName>, with the lab account as Contributor.

    The MicroHack platform runs this script once per participant. It creates no Azure or Fabric
    resources and makes no Fabric API calls. It derives the participant's workspace name from the
    lab account and emits exactly three HackboxCredential entries: Fabric workspace, Fabric portal
    and Lab tenant ID. It never fails because it cannot see the workspace; it fails, before emitting
    anything, only when it cannot resolve the lab account or read the lab tenant ID.
    See README.md in this folder.
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
Set-StrictMode -Version Latest

# Contract v1: workspace adwb-<labKey>-<shortName>, available during the bootcamp running window.
$labKey = 'lakehouse'
$workspaceNote = 'Your empty workspace for this lab, on your own Fabric capacity. ' +
    "Available 08:00$([char]0x2013)16:00 CET on bootcamp Fridays."

function Write-LabLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The platform job log captures host output; the output stream carries only credentials.')]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[deploy-lab] $Message"
}

function Test-LabGuid {
    param([string]$Value)
    $parsed = [guid]::Empty
    return [guid]::TryParse($Value, [ref]$parsed)
}

$labScope = "Deployment type '{0}', subscription {1}, resource group '{2}', regions '{3}'." -f
    $DeploymentType, $SubscriptionId, $ResourceGroupName, ($PreferredLocation -join ', ')
Write-LabLog "$labScope This lab deploys nothing to Azure; the organizer tooling provides the Fabric capacity and workspace."

# Validate the platform inputs here: the param block stays exactly as the platform contract documents it.
$participantIds = @(@(foreach ($value in $AllowedEntraUserIds) {
            ([string]$value) -split '[,;\s]+' | Where-Object { $_ }
        }) | Select-Object -Unique)
if ($participantIds.Count -eq 0) { throw "AllowedEntraUserIds must contain the participant's Entra object ID." }
foreach ($participantId in $participantIds) {
    if (-not (Test-LabGuid $participantId)) { throw "AllowedEntraUserIds contains '$participantId', which is not an Entra object ID." }
}

try { $tenantId = [string](Get-AzContext).Tenant.Id } catch { $tenantId = '' }
if (-not (Test-LabGuid $tenantId)) {
    throw 'No Az context with a tenant ID. The platform signs in Az PowerShell before this script runs; for a local test, run Connect-AzAccount first.'
}

$labUsers = @(Get-MhhLabUser -UserId $participantIds)
if ($labUsers.Count -ne $participantIds.Count) { throw 'Get-MhhLabUser did not resolve every participant.' }

$workspaceNames = @(@(foreach ($labUser in $labUsers) {
        # The organizer tooling names workspaces with the ShortName exactly as Get-MhhLabUser returns it.
        $shortName = [string]$labUser.ShortName
        $userPrincipalName = [string]$labUser.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($shortName)) { throw "Get-MhhLabUser returned no ShortName for $($labUser.Id)." }
        if ($shortName -cne $userPrincipalName.Split('@')[0].ToLowerInvariant()) {
            Write-Warning ("ShortName '$shortName' is not the lowercase local part of '$userPrincipalName'. The organizer " +
                'tooling derives workspace names from the UPN, so the dashboard name may not match the workspace.')
        }
        "adwb-$labKey-$shortName"
    }) | Sort-Object -Unique)
if ($workspaceNames.Count -gt 1) {
    Write-Warning "This lab has $($workspaceNames.Count) participants; the Fabric workspace entry lists each of their workspaces."
}
$workspaceValue = $workspaceNames -join ', '
Write-LabLog "Fabric workspace: $workspaceValue; lab tenant $tenantId."

# Dashboard entries, emitted once every value is known.
@{ HackboxCredential = @{
        name  = 'Fabric workspace'
        value = $workspaceValue
        note  = $workspaceNote
    }
}
@{ HackboxCredential = @{
        name  = 'Fabric portal'
        value = 'https://app.fabric.microsoft.com'
        note  = 'Sign in with your lab account and open the workspace above.'
    }
}
@{ HackboxCredential = @{
        name  = 'Lab tenant ID'
        value = $tenantId
        note  = 'Use it with az login --tenant and your lab account.'
    }
}
