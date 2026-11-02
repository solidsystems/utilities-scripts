<#
.SYNOPSIS
  READ-ONLY audit of why Microsoft 365 Copilot can or can't read a user's mail.
  Makes no changes. Writes CSV/JSON to .\copilot-audit-<timestamp>\

.DESCRIPTION
  For one user and the tenant, collects:
    1. License SKUs and service plans (Copilot plan parts disabled?)
    2. Work IQ / MCP / Copilot service principals present in Entra
    3. Delegated consent grants to/from those service principals
    4. User consent policy and pending admin consent requests
    5. Conditional Access policies, flagging ones modified since -Since
    6. The user's interactive + non-interactive sign-ins since -Since (beta endpoint)
    7. Directory audit events (license / consent / CA / app changes) since -Since
    8. Message center posts and service health issues mentioning Copilot / Exchange
    9. Mailbox type and location (Exchange Online)
   10. Copilot extensibility: Copilot connectors (external connections), org-deployed
       Teams/Copilot apps & agents, and the Copilot package catalog (beta, best effort)
   11. Unified audit log (Exchange): the user's CopilotInteraction records - AppHost
       (web vs iOS vs Teams) and which resources/plugins each answer actually used -
       plus admin events mentioning connectors / MCP / agents / Copilot settings
  For the Work IQ CLI / MCP server consent detail, see Audit-WorkIQConsent.ps1.

.REQUIREMENTS
  Install-Module Microsoft.Graph -Scope CurrentUser
  Install-Module ExchangeOnlineManagement -Scope CurrentUser   (or use -SkipExchange)
  Role: Global Reader (+ Security Reader/Reports Reader for sign-in logs). Sign-in logs need Entra ID P1.
  Section 11 needs the "View-Only Audit Logs" (or "Audit Logs") role in Exchange/Purview and auditing on.

.EXAMPLE
  ./Audit-CopilotMailAccess.ps1 -UserPrincipalName jane@contoso.com
  ./Audit-CopilotMailAccess.ps1 -UserPrincipalName jane@contoso.com -Since 2026-10-20 -SkipExchange
#>
param(
  [Parameter(Mandatory)] [string]$UserPrincipalName,
  [datetime]$Since = (Get-Date).Date.AddDays(-14),
  [switch]$SkipExchange,
  [switch]$UseDeviceCode,
  [string]$OutputDirectory = (Join-Path (Get-Location) ("copilot-audit-" + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = 'Continue'
$out = $OutputDirectory
New-Item -ItemType Directory -Path $out -Force | Out-Null
$sinceIso = $Since.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
function Save($obj, $name) {
  $rows = @($obj | Where-Object { $_ })
  if (-not $rows.Count) { Write-Host "  -> $name : no rows"; return }
  $rows | Export-Csv (Join-Path $out "$name.csv") -NoTypeInformation
  Write-Host "  -> $name.csv ($($rows.Count) rows)"
}
function Section($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

Connect-MgGraph -NoWelcome -UseDeviceCode:$UseDeviceCode -Scopes @(
  'User.Read.All','Directory.Read.All','Application.Read.All','AuditLog.Read.All',
  'Policy.Read.All','ConsentRequest.Read.All','ServiceHealth.Read.All','ServiceMessage.Read.All',
  'ExternalConnection.Read.All','AppCatalog.Read.All'
)

# 1. License + Copilot service plans -------------------------------------------
Section "1. Licenses / service plans for $UserPrincipalName"
$lic = Get-MgUserLicenseDetail -UserId $UserPrincipalName
$plans = foreach ($l in $lic) { foreach ($p in $l.ServicePlans) {
  [pscustomobject]@{ Sku = $l.SkuPartNumber; Plan = $p.ServicePlanName; Status = $p.ProvisioningStatus } } }
Save $plans 'license-service-plans'
$plans | Where-Object { $_.Plan -match 'COPILOT|GRAPH_CONNECTORS|EXCHANGE' } | Format-Table -AutoSize

# 2. Work IQ / MCP service principals ------------------------------------------
Section "2. Work IQ / MCP service principals"
$workIqAppId = 'fdcc1f02-fc51-4226-8753-f668596af7f7'   # Work IQ (Microsoft Learn: enable-work-iq)
$sps = @()
$sps += Get-MgServicePrincipal -Filter "appId eq '$workIqAppId'" -ErrorAction SilentlyContinue
foreach ($term in 'Work IQ','MCP','Copilot') {
  $sps += Get-MgServicePrincipal -Search "`"displayName:$term`"" -ConsistencyLevel eventual -All -ErrorAction SilentlyContinue
}
$sps = $sps | Where-Object { $_ } | Sort-Object Id -Unique
if (-not ($sps | Where-Object AppId -eq $workIqAppId)) { Write-Warning "Work IQ service principal ($workIqAppId) NOT present -> tenant one-time setup never done." }
Save ($sps | Select-Object DisplayName, AppId, Id, AccountEnabled, AppOwnerOrganizationId, ServicePrincipalType) 'service-principals'

# 3. Delegated permission grants (consent) for those SPs -----------------------
Section "3. Consent grants (who consented to what)"
$spName = @{}
$grants = foreach ($sp in $sps) {
  $asClient   = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue
  $asResource = Get-MgOauth2PermissionGrant -Filter "resourceId eq '$($sp.Id)'" -All -ErrorAction SilentlyContinue
  foreach ($g in @($asClient) + @($asResource) | Where-Object { $_ }) {
    foreach ($id in $g.ClientId, $g.ResourceId) {
      if (-not $spName[$id]) { $spName[$id] = (Get-MgServicePrincipal -ServicePrincipalId $id -ErrorAction SilentlyContinue).DisplayName }
    }
    [pscustomobject]@{
      Client = $spName[$g.ClientId]; Resource = $spName[$g.ResourceId]
      ConsentType = $g.ConsentType   # AllPrincipals = admin/tenant-wide; Principal = single user
      PrincipalId = $g.PrincipalId; Scopes = $g.Scope; GrantId = $g.Id
    }
  }
}
$grants = $grants | Sort-Object GrantId -Unique
Save $grants 'consent-grants'
$grants | Where-Object { $_.Scopes -match 'Mail' } | Format-Table Client, Resource, ConsentType, Scopes -AutoSize

# 4. User consent policy + pending admin consent requests ----------------------
Section "4. User consent policy / pending admin consent requests"
$authz = Get-MgPolicyAuthorizationPolicy | Select-Object -First 1
Write-Host ("  User consent policies assigned: " + (@($authz.PermissionGrantPolicyIdsAssignedToDefaultUserRole) -join ', '))
Write-Host "  (empty = users cannot consent; requests go to the admin consent workflow)"
$reqs = Get-MgIdentityGovernanceAppConsentRequest -All -ErrorAction SilentlyContinue |
  Select-Object AppDisplayName, AppId, ConsentType, @{n='PendingScopes';e={($_.PendingScopes.DisplayName) -join ' '}}
Save $reqs 'admin-consent-requests'

# 5. Conditional Access policies (flag recently modified) ----------------------
Section "5. Conditional Access policies"
$ca = Get-MgIdentityConditionalAccessPolicy -All | ForEach-Object {
  [pscustomobject]@{
    Name = $_.DisplayName; State = $_.State
    Modified = $_.ModifiedDateTime; ChangedSinceCutoff = ($_.ModifiedDateTime -ge $Since)
    IncludeApps = ($_.Conditions.Applications.IncludeApplications -join ',')
    ExcludeApps = ($_.Conditions.Applications.ExcludeApplications -join ',')
    ClientAppTypes = ($_.Conditions.ClientAppTypes -join ',')
    Platforms = ($_.Conditions.Platforms.IncludePlatforms -join ',')
    Grant = ($_.GrantControls.BuiltInControls -join ',')
    Session = ($_.SessionControls | ConvertTo-Json -Compress -Depth 3)
  } }
Save $ca 'conditional-access'
$ca | Where-Object ChangedSinceCutoff | Format-Table Name, State, Modified, IncludeApps, ClientAppTypes -AutoSize

# 6. Sign-ins for the user (interactive + non-interactive) ---------------------
Section "6. Sign-ins since $sinceIso (beta endpoint, incl. non-interactive)"
$filter = "userPrincipalName eq '$UserPrincipalName' and createdDateTime ge $sinceIso and (signInEventTypes/any(t: t eq 'interactiveUser' or t eq 'nonInteractiveUser'))"
$uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$top=500&`$filter=" + [uri]::EscapeDataString($filter)
$signins = @()
while ($uri) { $r = Invoke-MgGraphRequest -Uri $uri -Method GET; $signins += $r.value; $uri = $r.'@odata.nextLink' }
$si = $signins | ForEach-Object {
  [pscustomobject]@{
    Time = $_.createdDateTime; App = $_.appDisplayName; AppId = $_.appId
    Resource = $_.resourceDisplayName; ClientApp = $_.clientAppUsed
    Browser = $_.deviceDetail.browser; OS = $_.deviceDetail.operatingSystem
    ErrorCode = $_.status.errorCode; Failure = $_.status.failureReason
    CAStatus = $_.conditionalAccessStatus
    CAApplied = (($_.appliedConditionalAccessPolicies | Where-Object result -in 'failure','success' |
                  ForEach-Object { "$($_.displayName):$($_.result)" }) -join '; ')
    EventType = ($_.signInEventTypes -join ',')
  } }
Save $si 'signins'
$si | Where-Object { $_.ErrorCode -ne 0 -or $_.App -match 'Copilot|Work IQ|MCP|Substrate' } |
  Group-Object App, Resource, ErrorCode | Sort-Object Count -Descending |
  Select-Object Count, Name -First 25 | Format-Table -AutoSize

# 7. Directory audit: license / consent / CA / SP changes since cutoff ---------
Section "7. Directory audit changes since $sinceIso"
$audit = Get-MgAuditLogDirectoryAudit -Filter "activityDateTime ge $sinceIso" -All |
  Where-Object { $_.ActivityDisplayName -match 'license|consent|conditional access|policy|service principal|delegated permission|app role' } |
  ForEach-Object { [pscustomobject]@{
    Time = $_.ActivityDateTime; Activity = $_.ActivityDisplayName; Result = $_.Result
    By = ($_.InitiatedBy.User.UserPrincipalName, $_.InitiatedBy.App.DisplayName | Where-Object { $_ }) -join ''
    Targets = ($_.TargetResources | ForEach-Object { $_.DisplayName + $_.UserPrincipalName }) -join '; '
  } }
Save $audit 'directory-audit'

# 8. Message center + service health (Copilot / Exchange) ----------------------
Section "8. Message center / service health"
$mc = Get-MgServiceAnnouncementMessage -All |
  Where-Object { $_.LastModifiedDateTime -ge $Since.AddDays(-30) -and ($_.Title -match 'Copilot|Work IQ|MCP|agent' -or ($_.Services -join ',') -match 'Copilot') } |
  Select-Object Id, Title, StartDateTime, LastModifiedDateTime, @{n='Services';e={$_.Services -join ','}}, Category
Save $mc 'message-center'
$mc | Format-Table Id, StartDateTime, Title -AutoSize
$sh = Get-MgServiceAnnouncementIssue -All |
  Where-Object { $_.StartDateTime -ge $Since.AddDays(-7) -and $_.Service -match 'Copilot|Exchange|Microsoft 365 suite' } |
  Select-Object Id, Service, Title, Status, StartDateTime, EndDateTime, ImpactDescription
Save $sh 'service-health'

# 10. Copilot extensibility: connectors, org apps/agents, package catalog --------
Section "10. Copilot extensibility (connectors / agents / packages)"
$conns = Get-MgExternalConnection -All -ErrorAction SilentlyContinue |
  Select-Object Id, Name, State, Description, ConnectorId
Save $conns 'copilot-connectors'
$conns | Format-Table Id, Name, State -AutoSize

$orgApps = Get-MgAppCatalogTeamApp -All -Filter "distributionMethod eq 'organization'" -ExpandProperty AppDefinitions -ErrorAction SilentlyContinue |
  ForEach-Object { $d = $_.AppDefinitions | Sort-Object LastModifiedDateTime | Select-Object -Last 1
    [pscustomobject]@{ Name = $_.DisplayName; Id = $_.Id; ExternalId = $_.ExternalId
      Version = $d.Version; PublishingState = $d.PublishingState; LastModified = $d.LastModifiedDateTime
      ChangedSinceCutoff = ($d.LastModifiedDateTime -ge $Since); Bot = [bool]$d.Bot } }
Save $orgApps 'org-apps-agents'
$orgApps | Where-Object ChangedSinceCutoff | Format-Table Name, Version, PublishingState, LastModified -AutoSize

# Copilot package catalog (beta). Endpoint/permission may not exist in every tenant - best effort.
try {
  $pk = @(); $u = 'https://graph.microsoft.com/beta/copilot/admin/catalog/packages'
  while ($u) { $r = Invoke-MgGraphRequest -Uri $u -Method GET -ErrorAction Stop; $pk += $r.value; $u = $r.'@odata.nextLink' }
  $pkRows = $pk | ForEach-Object { [pscustomobject]@{
    Name = $_.displayName; Id = $_.id; Type = $_.type; Publisher = $_.publisher
    IsBlocked = $_.isBlocked; AvailableTo = $_.availableTo; Deployed = $_.deployedTo
    LastModified = $_.lastModifiedDateTime; Hosts = ($_.supportedHosts -join ',') } }
  Save $pkRows 'copilot-packages'
  $pkRows | Where-Object { "$($_.Type) $($_.Name)" -match 'mcp|connector' -or $_.LastModified -ge $Since } |
    Format-Table Name, Type, Publisher, IsBlocked, LastModified -AutoSize
} catch {
  Write-Warning "Copilot package catalog not readable ($($_.Exception.Message.Split([Environment]::NewLine)[0])). Check M365 admin center > Copilot > Agents / Extensibility manually."
}

# 9 + 11. Exchange: mailbox, unified audit log ----------------------------------
if (-not $SkipExchange) {
  Section "9. Mailbox"
  Connect-ExchangeOnline -ShowBanner:$false -Device:$UseDeviceCode
  $mbx = Get-EXOMailbox -Identity $UserPrincipalName -Properties Database, ArchiveStatus, WhenMailboxCreated, AccountDisabled
  $mbx | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails, Database, ArchiveStatus, WhenMailboxCreated, AccountDisabled | Format-List
  $mbx | Select-Object * | ConvertTo-Json -Depth 3 | Out-File (Join-Path $out 'mailbox.json')

  Section "11a. Unified audit: $UserPrincipalName CopilotInteraction since $sinceIso"
  # Each Copilot prompt/response is logged with the client (AppHost) and the resources/plugins it used.
  # Compare a working iOS interaction with a failing web one: does the web one show no mail resources/plugins?
  $ci = Search-UnifiedAuditLog -StartDate $Since -EndDate (Get-Date) -RecordType CopilotInteraction `
          -UserIds $UserPrincipalName -ResultSize 5000 -ErrorAction SilentlyContinue
  $ciRows = foreach ($rec in $ci) {
    $d = $rec.AuditData | ConvertFrom-Json; $e = $d.CopilotEventData
    [pscustomobject]@{
      Time = $rec.CreationDate; Operation = $rec.Operations
      AppHost = $e.AppHost; ThreadId = $e.ThreadId
      Contexts = (@($e.Contexts) | ForEach-Object { "$($_.Type):$($_.Id)" }) -join ' | '
      ResourceTypes = (@($e.AccessedResources) | ForEach-Object { $_.Type } | Sort-Object -Unique) -join ','
      ResourceCount = @($e.AccessedResources).Count
      Plugins = (@($e.AISystemPlugin) | ForEach-Object { $_.Name }) -join ','
      ModelProvider = (@($e.ModelTransparencyDetails) | ForEach-Object { $_.ModelProviderName } | Sort-Object -Unique) -join ','
    } }
  Save $ciRows 'copilot-interactions'
  $ciRows | Group-Object AppHost, ResourceTypes | Sort-Object Count -Descending |
    Select-Object Count, Name -First 20 | Format-Table -AutoSize
  if ($ci) { $ci | Select-Object -First 3 | ForEach-Object { $_.AuditData } | Out-File (Join-Path $out 'copilot-interactions-sample-raw.json') }

  Section "11b. Unified audit: admin changes (connectors / MCP / agents / Copilot settings) since $sinceIso"
  $adm = foreach ($term in 'MCP','Connector','Copilot','Agent','Work IQ') {
    Search-UnifiedAuditLog -StartDate $Since -EndDate (Get-Date) -FreeText $term -ResultSize 2000 -ErrorAction SilentlyContinue |
      Where-Object { $_.RecordType -ne 'CopilotInteraction' } }
  $admRows = $adm | Sort-Object Identity -Unique | ForEach-Object {
    [pscustomobject]@{ Time = $_.CreationDate; User = $_.UserIds; RecordType = $_.RecordType
      Operation = $_.Operations; AuditData = $_.AuditData } }
  Save $admRows 'admin-audit-copilot-changes'
  $admRows | Group-Object RecordType, Operation | Sort-Object Count -Descending |
    Select-Object Count, Name -First 25 | Format-Table -AutoSize

  Disconnect-ExchangeOnline -Confirm:$false
}

Write-Host "`nDone. Output: $out" -ForegroundColor Green
Write-Host "Manual (not scriptable): M365 admin center > Copilot > Settings and Extensibility (agents, MCP connectors,"
Write-Host "  tool allow-list), Settings > Integrated apps, and config.office.com cloud policy"
Write-Host "  'Allow the use of connected experiences in Office that analyze content'."
