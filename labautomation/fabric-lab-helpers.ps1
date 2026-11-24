# Helpers shared by deploy-lab.ps1 and shared-deploy-lab.ps1. Dot-source this file:
# it only defines constants and functions and calls no Azure or Fabric API by itself.
# It needs PowerShell 7 and Az PowerShell; no Python, Azure CLI extension or module install.

Set-StrictMode -Version Latest

$LabArmEndpoint = 'https://management.azure.com'
$LabFabricEndpoint = 'https://api.fabric.microsoft.com'
$LabFabricArmApiVersion = '2023-11-01'
$LabProviderApiVersion = '2021-04-01'
$LabGuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

function Write-LabLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Platform job logs read the information stream; the output stream carries credentials only.')]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[zava-lakehouse] $Message"
}

function Assert-LabCommand {
    param([Parameter(Mandatory)][string[]]$Name)
    $missing = @($Name | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
    if ($missing.Count -gt 0) {
        throw "Required command(s) unavailable: $($missing -join ', '). Run this hook on the MicroHack platform or in the adminpwsh container."
    }
}

function ConvertTo-LabRegionList {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Value)
    $regions = @(foreach ($entry in @($Value)) {
            if ($null -eq $entry) { continue }
            foreach ($part in ([string]$entry).Split(',')) {
                $region = $part.Trim().ToLowerInvariant()
                if ($region) { $region }
            }
        })
    foreach ($region in $regions) {
        if ($region -notmatch '^[a-z0-9]+$') { throw "Invalid preferred Azure region '$region'." }
    }
    $regions | Select-Object -Unique
}

function ConvertTo-LabParticipantIdList {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Value)
    $ids = @(foreach ($entry in @($Value)) {
            if ($null -eq $entry) { continue }
            foreach ($part in ([string]$entry).Split(',')) {
                $id = $part.Trim().ToLowerInvariant()
                if ($id) { $id }
            }
        })
    foreach ($id in $ids) {
        if ($id -notmatch $LabGuidPattern) { throw "AllowedEntraUserIds contains '$id', which is not an Entra object ID." }
    }
    $ids | Select-Object -Unique | Sort-Object
}

function Get-LabValue {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-LabAccessToken {
    param([Parameter(Mandatory)][ValidateSet('Arm', 'Fabric')][string]$Audience)
    # Cheap no-op when the platform credential is still current; throws if a refresh fails.
    Update-MhhToken | Out-Null
    $resource = if ($Audience -eq 'Arm') { "$LabArmEndpoint/" } else { $LabFabricEndpoint }
    $access = Get-AzAccessToken -ResourceUrl $resource -ErrorAction Stop -WarningAction SilentlyContinue
    if ($access.Token -is [securestring]) {
        return [Net.NetworkCredential]::new('', $access.Token).Password
    }
    return [string]$access.Token
}

function Get-LabDeployingPrincipal {
    # Reads the oid claim of the caller's own ARM token: no Microsoft Graph permission is needed.
    $token = Get-LabAccessToken -Audience Arm
    try {
        $segments = $token.Split('.')
        if ($segments.Count -lt 2) { throw 'The Azure Resource Manager access token is not a JSON web token.' }
        $payload = $segments[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -AsHashtable
    }
    finally {
        $token = $null
    }
    $objectId = [string](Get-LabValue $claims 'oid')
    if ($objectId -notmatch $LabGuidPattern) { throw 'The deploying identity has no object ID (oid) claim.' }
    if ($claims.Contains('scp')) {
        # A delegated token means a signed-in user (local testing). Fabric capacity admins are UPNs for users.
        $upn = [string](Get-LabValue $claims 'upn')
        if (-not $upn) { $upn = [string](Get-LabValue $claims 'unique_name') }
        if ($upn -notmatch '^[^@\s#]+@[^@\s]+$') {
            throw 'Run local tests as a member user with a user principal name, or as a service principal.'
        }
        return [pscustomobject]@{ ObjectId = $objectId.ToLowerInvariant(); Kind = 'User'; CapacityAdministrator = $upn }
    }
    return [pscustomobject]@{ ObjectId = $objectId.ToLowerInvariant(); Kind = 'ServicePrincipal'; CapacityAdministrator = $objectId }
}

function Get-LabHeaderValue {
    param([AllowNull()][object]$Headers, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Headers) { return $null }
    foreach ($key in @($Headers.Keys)) {
        if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            $values = @($Headers[$key])
            if ($values.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$values[0])) { return [string]$values[0] }
        }
    }
    return $null
}

function Get-LabRetryDelay {
    param([AllowNull()][string]$RetryAfter, [int]$Attempt = 1, [int]$MaximumSeconds = 120)
    $seconds = 0
    if ($RetryAfter -and [int]::TryParse($RetryAfter, [ref]$seconds)) {
        return [Math]::Min([Math]::Max($seconds, 1), $MaximumSeconds)
    }
    $date = [DateTimeOffset]::MinValue
    if ($RetryAfter -and [DateTimeOffset]::TryParse($RetryAfter, [ref]$date)) {
        $wait = [int][Math]::Ceiling(($date - [DateTimeOffset]::UtcNow).TotalSeconds)
        return [Math]::Min([Math]::Max($wait, 1), $MaximumSeconds)
    }
    # Exponential backoff with jitter, so parallel labs do not retry in lockstep.
    $backoff = [Math]::Min([int][Math]::Pow(2, [Math]::Min($Attempt, 6)) * 2, $MaximumSeconds)
    return [Math]::Max(1, $backoff + (Get-Random -Minimum 0 -Maximum 5))
}

function Resolve-LabRequestUri {
    param([Parameter(Mandatory)][ValidateSet('Arm', 'Fabric')][string]$Audience, [Parameter(Mandatory)][string]$Uri)
    $endpoint = if ($Audience -eq 'Arm') { $LabArmEndpoint } else { $LabFabricEndpoint }
    if ($Uri.StartsWith('/')) { return "$endpoint$Uri" }
    $parsed = $null
    if (-not [uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -ne 'https' -or
        $parsed.Host -ne ([uri]$endpoint).Host) {
        throw "Refusing to send a $Audience token to an unexpected URL."
    }
    return $parsed.AbsoluteUri
}

function Format-LabRestError {
    param([string]$Method, [string]$Uri, [int]$StatusCode, [AllowNull()][object]$Body)
    $code = [string](Get-LabValue $Body 'errorCode')
    $message = [string](Get-LabValue $Body 'message')
    $requestId = [string](Get-LabValue $Body 'requestId')
    $armError = Get-LabValue $Body 'error'
    if ($null -ne $armError -and -not $code) {
        $code = [string](Get-LabValue $armError 'code')
        $message = [string](Get-LabValue $armError 'message')
    }
    $text = "$Method $Uri returned HTTP $StatusCode"
    if ($code) { $text += " $code" }
    if ($message) { $text += ": $message" }
    if ($requestId) { $text += " (request ID $requestId)" }
    return $text
}

function Invoke-LabRestRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('Arm', 'Fabric')][string]$Audience,
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Uri,
        [AllowNull()][object]$Body = $null,
        [int[]]$PassThruStatus = @(),
        [int]$TimeoutSeconds = 900
    )
    $requestUri = Resolve-LabRequestUri -Audience $Audience -Uri $Uri
    $payload = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { $null }
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $attempt = 0
    $networkFailures = 0
    while ($true) {
        $attempt++
        $request = @{
            Method             = $Method
            Uri                = $requestUri
            Headers            = @{ Authorization = "Bearer $(Get-LabAccessToken -Audience $Audience)" }
            SkipHttpErrorCheck = $true
            TimeoutSec         = 100
            ErrorAction        = 'Stop'
        }
        if ($null -ne $payload) {
            $request.Body = $payload
            $request.ContentType = 'application/json; charset=utf-8'
        }
        try {
            $response = Invoke-WebRequest @request
        }
        catch {
            # HTTP errors come back as responses; an exception here is a network failure or timeout.
            $networkFailures++
            if ($networkFailures -ge 6 -or [DateTimeOffset]::UtcNow -ge $deadline) {
                throw "$Method $requestUri failed: $($_.Exception.Message)"
            }
            $delay = Get-LabRetryDelay -Attempt $attempt
            Write-LabLog "$Method $requestUri failed ($($_.Exception.Message)); retrying in $delay s."
            Start-Sleep -Seconds $delay
            continue
        }
        $status = [int]$response.StatusCode
        $content = $response.Content
        if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
        $parsed = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$content)) {
            try { $parsed = $content | ConvertFrom-Json -AsHashtable -Depth 64 } catch { $parsed = $null }
        }
        if ($status -eq 429 -or $status -in 500, 502, 503, 504) {
            $delay = Get-LabRetryDelay -RetryAfter (Get-LabHeaderValue $response.Headers 'Retry-After') -Attempt $attempt
            if ([DateTimeOffset]::UtcNow.AddSeconds($delay) -ge $deadline) {
                throw (Format-LabRestError -Method $Method -Uri $requestUri -StatusCode $status -Body $parsed)
            }
            Write-LabLog "HTTP $status from $Method $requestUri; retrying in $delay s."
            Start-Sleep -Seconds $delay
            continue
        }
        if ($status -eq 202 -and $Audience -eq 'Fabric') {
            $location = Get-LabHeaderValue $response.Headers 'Location'
            if ($location) {
                return Wait-LabFabricOperation -Location $location -Deadline $deadline `
                    -RetryAfter (Get-LabHeaderValue $response.Headers 'Retry-After')
            }
        }
        if (($status -ge 200 -and $status -lt 300) -or $status -in $PassThruStatus) {
            return [pscustomobject]@{ StatusCode = $status; Body = $parsed; Headers = $response.Headers }
        }
        throw (Format-LabRestError -Method $Method -Uri $requestUri -StatusCode $status -Body $parsed)
    }
}

function Wait-LabFabricOperation {
    param(
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][DateTimeOffset]$Deadline,
        [AllowNull()][string]$RetryAfter
    )
    # Fabric long-running operations: poll the Location URL until the operation succeeds or fails.
    $attempt = 0
    while ($true) {
        $attempt++
        $delay = Get-LabRetryDelay -RetryAfter $RetryAfter -Attempt $attempt -MaximumSeconds 30
        if ([DateTimeOffset]::UtcNow.AddSeconds($delay) -ge $Deadline) {
            throw "Fabric operation $Location did not finish before the deadline."
        }
        Start-Sleep -Seconds $delay
        $state = Invoke-LabRestRequest -Audience Fabric -Uri $Location
        $status = [string](Get-LabValue $state.Body 'status')
        $RetryAfter = Get-LabHeaderValue $state.Headers 'Retry-After'
        if ($status -eq 'Succeeded') {
            $resultLocation = Get-LabHeaderValue $state.Headers 'Location'
            if ($resultLocation) { return Invoke-LabRestRequest -Audience Fabric -Uri $resultLocation }
            return $state
        }
        if ($status -eq 'Failed') {
            $failure = Get-LabValue $state.Body 'error'
            throw "Fabric operation $Location failed: $([string](Get-LabValue $failure 'errorCode')) $([string](Get-LabValue $failure 'message'))"
        }
    }
}

function Get-LabRestCollection {
    param(
        [Parameter(Mandatory)][ValidateSet('Arm', 'Fabric')][string]$Audience,
        [Parameter(Mandatory)][string]$Uri,
        [int]$MaximumPages = 100
    )
    $next = $Uri
    for ($page = 1; $next; $page++) {
        if ($page -gt $MaximumPages) { throw "Listing $Uri exceeded $MaximumPages pages." }
        $body = (Invoke-LabRestRequest -Audience $Audience -Uri $next).Body
        foreach ($item in @(Get-LabValue $body 'value')) {
            if ($null -ne $item) { $item }
        }
        # Fabric pages with continuationUri, Azure Resource Manager with nextLink.
        $next = [string](Get-LabValue $body 'continuationUri')
        if (-not $next) { $next = [string](Get-LabValue $body 'nextLink') }
    }
}

function Invoke-LabNotFoundRetry {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [int]$Attempts = 6, [int]$DelaySeconds = 10)
    # A workspace created seconds ago can briefly return 404 on its sub-resources.
    for ($attempt = 1; ; $attempt++) {
        try { return & $ScriptBlock }
        catch {
            if ($attempt -ge $Attempts -or $_.Exception.Message -notmatch 'returned HTTP 404') { throw }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Wait-LabProviderRegistration {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$Namespace,
        [int]$TimeoutSeconds = 900
    )
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $providerPath = "/subscriptions/$SubscriptionId/providers/$Namespace"
    $requested = $false
    while ($true) {
        $state = [string](Get-LabValue (Invoke-LabRestRequest -Audience Arm -Uri "${providerPath}?api-version=$LabProviderApiVersion").Body 'registrationState')
        if ($state -eq 'Registered') { return }
        if ($state -ne 'Registering' -and -not $requested) {
            Write-LabLog "Registering resource provider $Namespace (state '$state')."
            Invoke-LabRestRequest -Audience Arm -Method POST -Uri "$providerPath/register?api-version=$LabProviderApiVersion" | Out-Null
            $requested = $true
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Resource provider $Namespace is still '$state' after $TimeoutSeconds s."
        }
        Start-Sleep -Seconds 10
    }
}

function Get-LabFabricSkuRegion {
    param([Parameter(Mandatory)][string]$SubscriptionId, [Parameter(Mandatory)][string]$SkuName)
    $uri = "/subscriptions/$SubscriptionId/providers/Microsoft.Fabric/skus?api-version=$LabFabricArmApiVersion"
    foreach ($sku in @(Get-LabRestCollection -Audience Arm -Uri $uri)) {
        if ([string](Get-LabValue $sku 'name') -ne $SkuName) { continue }
        foreach ($location in @(Get-LabValue $sku 'locations')) {
            if ($location) { ([string]$location).Replace(' ', '').ToLowerInvariant() }
        }
    }
}

function Get-LabSkuCapacityUnit {
    param([Parameter(Mandatory)][string]$SkuName)
    if ($SkuName -notmatch '^F(\d+)$') { throw "Unsupported Fabric SKU '$SkuName'." }
    return [int]$Matches[1]
}

function Get-LabFabricQuota {
    param([Parameter(Mandatory)][string]$SubscriptionId, [Parameter(Mandatory)][string]$Region)
    $uri = "/subscriptions/$SubscriptionId/providers/Microsoft.Fabric/locations/$Region/usages?api-version=$LabFabricArmApiVersion"
    foreach ($usage in @(Get-LabRestCollection -Audience Arm -Uri $uri)) {
        if ([string](Get-LabValue (Get-LabValue $usage 'name') 'value') -eq 'CapacityQuota') {
            return [pscustomobject]@{
                Limit = [double](Get-LabValue $usage 'limit')
                Used  = [double](Get-LabValue $usage 'currentValue')
            }
        }
    }
    return $null
}

function Get-LabCapacityPath {
    param([string]$SubscriptionId, [string]$ResourceGroupName, [string]$Name)
    return "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Fabric/capacities/$Name"
}

function Get-LabCapacityResource {
    param([Parameter(Mandatory)][string]$SubscriptionId, [Parameter(Mandatory)][string]$ResourceGroupName, [Parameter(Mandatory)][string]$Name)
    $path = Get-LabCapacityPath -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Name $Name
    $response = Invoke-LabRestRequest -Audience Arm -Uri "${path}?api-version=$LabFabricArmApiVersion" -PassThruStatus 404
    if ($response.StatusCode -eq 404) { return $null }
    return $response.Body
}

function Wait-LabCapacityActive {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSeconds = 1200
    )
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $path = Get-LabCapacityPath -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Name $Name
    $resumeRequested = $false
    while ($true) {
        $capacity = Get-LabCapacityResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Name $Name
        if ($null -eq $capacity) { throw "Fabric capacity '$Name' does not exist in resource group '$ResourceGroupName'." }
        $properties = Get-LabValue $capacity 'properties'
        $state = [string](Get-LabValue $properties 'state')
        $provisioning = [string](Get-LabValue $properties 'provisioningState')
        if ($state -eq 'Active' -and $provisioning -eq 'Succeeded') { return $capacity }
        if ($state -eq 'Failed' -or $provisioning -in 'Failed', 'Canceled') {
            throw "Fabric capacity '$Name' is in state '$state' with provisioning state '$provisioning'."
        }
        if ($state -in 'Paused', 'Suspended' -and -not $resumeRequested) {
            Write-Warning "Fabric capacity '$Name' is $state. Resuming it: a lab is only ready with an Active capacity."
            Invoke-LabRestRequest -Audience Arm -Method POST -Uri "$path/resume?api-version=$LabFabricArmApiVersion" | Out-Null
            $resumeRequested = $true
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Fabric capacity '$Name' did not become Active within $TimeoutSeconds s (state '$state', provisioning state '$provisioning')."
        }
        Write-LabLog "Waiting for capacity '$Name' to become Active (state '$state', provisioning state '$provisioning')."
        Start-Sleep -Seconds 15
    }
}

function Resolve-LabFabricCapacity {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SkuName,
        [Parameter(Mandatory)][string]$Region,
        [int]$TimeoutSeconds = 1200
    )
    # The Fabric capacity ID is not an ARM property: find the capacity by name in the Fabric API.
    # List Capacities has a low per-caller limit and every parallel lab shares the platform identity,
    # so poll slowly with jitter; throttled calls back off on Retry-After.
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $found = @(Get-LabRestCollection -Audience Fabric -Uri '/v1/capacities' |
                Where-Object { [string](Get-LabValue $_ 'displayName') -ieq $Name })
        if ($found.Count -gt 1) {
            $found = @($found | Where-Object {
                    [string](Get-LabValue $_ 'sku') -eq $SkuName -and
                    ([string](Get-LabValue $_ 'region')).Replace(' ', '').ToLowerInvariant() -eq $Region
                })
        }
        if ($found.Count -gt 1) { throw "Several Fabric capacities named '$Name' are visible; refusing to guess." }
        $state = if ($found.Count -eq 1) { [string](Get-LabValue $found[0] 'state') } else { 'not listed yet' }
        if ($state -eq 'Active') { return $found[0] }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw ("Fabric does not list capacity '$Name' as Active ($state). The deploying identity must be its capacity " +
                "administrator, and the tenant setting 'Service principals can call Fabric public APIs' must include it.")
        }
        Write-LabLog "Waiting for Fabric to list capacity '$Name' as Active ($state)."
        Start-Sleep -Seconds (20 + (Get-Random -Minimum 0 -Maximum 15))
    }
}

function Find-LabWorkspace {
    param([Parameter(Mandatory)][string]$DisplayName)
    Get-LabRestCollection -Audience Fabric -Uri '/v1/workspaces?roles=Admin' | Where-Object {
        [string](Get-LabValue $_ 'type') -eq 'Workspace' -and [string](Get-LabValue $_ 'displayName') -ieq $DisplayName
    }
}

function Sync-LabWorkspaceCapacity {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$CapacityId,
        [int]$TimeoutSeconds = 900
    )
    # Converge the workspace onto the current capacity, for example after a region-fallback recreate.
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $requested = $false
    while ($true) {
        $workspace = (Invoke-LabRestRequest -Audience Fabric -Uri "/v1/workspaces/$WorkspaceId").Body
        $current = [string](Get-LabValue $workspace 'capacityId')
        $progress = [string](Get-LabValue $workspace 'capacityAssignmentProgress')
        if ($current -ieq $CapacityId) {
            if ($progress -in '', 'Completed') { return $workspace }
            if ($progress -eq 'Failed') { throw "Assigning workspace $WorkspaceId to capacity $CapacityId failed." }
        }
        elseif (-not $requested -and $progress -ne 'InProgress') {
            $from = if ($current) { "capacity $current" } else { 'no capacity' }
            Write-LabLog "Assigning workspace $WorkspaceId from $from to capacity $CapacityId."
            Invoke-LabRestRequest -Audience Fabric -Method POST -Uri "/v1/workspaces/$WorkspaceId/assignToCapacity" `
                -Body @{ capacityId = $CapacityId } | Out-Null
            $requested = $true
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            throw "Workspace $WorkspaceId is not assigned to capacity $CapacityId (capacity '$current', progress '$progress')."
        }
        Start-Sleep -Seconds 10
    }
}

function Get-LabWorkspaceRuntime {
    param([Parameter(Mandatory)][string]$WorkspaceId)
    $settings = (Invoke-LabRestRequest -Audience Fabric -Uri "/v1/workspaces/$WorkspaceId/spark/settings").Body
    return [string](Get-LabValue (Get-LabValue $settings 'environment') 'runtimeVersion')
}

function Sync-LabWorkspaceRuntime {
    param([Parameter(Mandatory)][string]$WorkspaceId, [Parameter(Mandatory)][string]$RuntimeVersion)
    Invoke-LabRestRequest -Audience Fabric -Method PATCH -Uri "/v1/workspaces/$WorkspaceId/spark/settings" `
        -Body @{ environment = @{ runtimeVersion = $RuntimeVersion } } | Out-Null
}

function Grant-LabWorkspaceRole {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][ValidateSet('Viewer', 'Contributor', 'Member')][string]$Role
    )
    # Converges one user's role; check first so that a rerun never fails on an existing assignment.
    $existing = @(Get-LabRestCollection -Audience Fabric -Uri "/v1/workspaces/$WorkspaceId/roleAssignments" |
            Where-Object { [string](Get-LabValue (Get-LabValue $_ 'principal') 'id') -ieq $PrincipalId })
    if ($existing.Count -eq 0) {
        Invoke-LabRestRequest -Audience Fabric -Method POST -Uri "/v1/workspaces/$WorkspaceId/roleAssignments" `
            -Body @{ principal = @{ id = $PrincipalId; type = 'User' }; role = $Role } | Out-Null
        return 'added'
    }
    $currentRole = [string](Get-LabValue $existing[0] 'role')
    if ($currentRole -eq $Role) { return 'already assigned' }
    $assignmentId = [string](Get-LabValue $existing[0] 'id')
    Invoke-LabRestRequest -Audience Fabric -Method PATCH -Uri "/v1/workspaces/$WorkspaceId/roleAssignments/$assignmentId" `
        -Body @{ role = $Role } | Out-Null
    return "changed from $currentRole"
}
