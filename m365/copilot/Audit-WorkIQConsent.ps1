<#
.SYNOPSIS
  READ-ONLY. Audits what microsoft/work-iq Enable-WorkIQToolsForTenant.ps1 would create/grant,
  WITHOUT creating or granting anything. Only Get-* cmdlets; connects with read scopes only.

  Beyond Microsoft's Verify-WorkIQTenant.ps1 it also shows:
    - consent type (AllPrincipals = tenant-wide admin consent, Principal = one user) and who
    - EVERY client app holding grants to each MCP server (not just the Work IQ CLI)
    - which of the Enable script's grants are missing (= what running it would add)
    - existing scopes the Enable script would drop (it overwrites the scope string)

  Note: the Enable script consents ONLY to the Work IQ CLI client. Its grants do not apply to
  the Microsoft 365 Copilot web/app clients (e.g. m365.cloud.microsoft/chat).

.REQUIREMENTS
  Install-Module Microsoft.Graph -Scope CurrentUser
  Role: Global Reader (or any role that can read service principals and permission grants).

.SOURCE
  App IDs and scope lists copied from microsoft/work-iq scripts/Enable-WorkIQToolsForTenant.ps1
  at commit a48007cbbea3ba8b8030c1bd11b890b88f395b9b (2026-10-30). Re-check if Microsoft updates it.

.EXAMPLE
  ./Audit-WorkIQConsent.ps1            # results also written to .\workiq-consent-audit.csv
  ./Audit-WorkIQConsent.ps1 -UseDeviceCode
#>
param(
  [switch]$UseDeviceCode,
  [string]$OutputDirectory = (Get-Location).Path
)

$cp = @{ Scopes = 'Application.Read.All','Directory.Read.All'; NoWelcome = $true }
if ($UseDeviceCode) { $cp.UseDeviceCode = $true }
Connect-MgGraph @cp
Write-Host "Tenant: $((Get-MgContext).TenantId)  (read-only)" -ForegroundColor Green

# Values copied verbatim from microsoft/work-iq scripts/Enable-WorkIQToolsForTenant.ps1
$WorkIqCliAppId = 'ba081686-5d24-4bc6-a0d6-d034ecffed87'
$GraphAppId     = '00000003-0000-0000-c000-000000000000'
$Mcp = [ordered]@{
  'Work IQ Tools'              = 'ea9ffc3e-8a23-4a7d-836d-234d7c7565c1'
  'mcp_MailTools'              = '16b1878d-62c7-4009-aa25-68989d63bbad'
  'mcp_MeServer'               = '147dc821-b413-44c0-8009-1a3098378012'
  'mcp_CalendarTools'          = '910333d2-47e9-43ca-981f-6df2f4531ef4'
  'mcp_TeamsServer'            = 'ce5029ee-c1d3-45c0-bdcc-efb5a4245687'
  'mcp_OneDriveRemoteServer'   = 'b0b2a2bb-6361-4549-a00c-a018417eb8e2'
  'mcp_SharePointRemoteServer' = '292cff14-c0e8-4116-9e3b-99934ae05766'
  'mcp_AdminTools'             = '2dbeefeb-6462-48a4-abe6-1c4989699319'
  'mcp_WordServer'             = 'c2d0c2b6-8013-4346-9f8b-b81d3b754a29'
  'mcp_M365Copilot'            = 'ab7c82de-7946-4454-ac28-70249d17c95e'
}
$EnableGraphScopes = 'Sites.Read.All','Mail.Read','People.Read.All','OnlineMeetingTranscript.Read.All','Chat.Read','ChannelMessage.Read.All','ExternalItem.Read.All'
$EnableToolsScopes = 'McpServers.CopilotMCP.All','McpServers.Me.All','McpServers.Mail.All','McpServers.Calendar.All','McpServers.Teams.All','McpServers.Word.All','McpServers.OneDriveSharepoint.All','McpServers.SharepointLists.All','McpServers.SharePoint.All','McpServers.OneDrive.All','McpServers.Dataverse.All','McpServers.M365Admin.All','McpServers.Management.All'

$nameCache = @{}
function SpName($id) {
  if (-not $id) { return '' }
  if (-not $nameCache[$id]) { $s = Get-MgServicePrincipal -ServicePrincipalId $id -ErrorAction SilentlyContinue
    $nameCache[$id] = if ($s) { "$($s.DisplayName) [$($s.AppId)]" } else { $id } }
  $nameCache[$id]
}
function UserName($id) {
  if (-not $id) { return '(all users)' }
  $u = Get-MgUser -UserId $id -Property UserPrincipalName -ErrorAction SilentlyContinue
  if ($u) { $u.UserPrincipalName } else { $id }
}
$rows = @()

# 1. Service principals the Enable script would create ------------------------
Write-Host "`n== 1. Service principals (Enable script step 1-2 would CREATE missing ones) ==" -ForegroundColor Cyan
$spByApp = @{}
foreach ($n in @($Mcp.Keys) + 'Work IQ CLI') {
  $appId = if ($n -eq 'Work IQ CLI') { $WorkIqCliAppId } else { $Mcp[$n] }
  $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue | Select-Object -First 1
  $spByApp[$appId] = $sp
  $state = if ($sp) { 'PRESENT' } else { 'MISSING (would be created)' }
  $col   = if ($sp) { 'Green' } else { 'Yellow' }
  Write-Host ("  {0,-28} {1}  {2}" -f $n, $appId, $state) -ForegroundColor $col
  $rows += [pscustomobject]@{ Check='ServicePrincipal'; Name=$n; AppId=$appId; State=$state; Enabled=$sp.AccountEnabled; Client=''; ConsentType=''; GrantedTo=''; Scopes=''; WouldAdd='' }
}

# 2. Grants the Enable script would create/overwrite for the Work IQ CLI -------
Write-Host "`n== 2. Work IQ CLI grants (Enable script steps 3-4 would ADD/OVERWRITE) ==" -ForegroundColor Cyan
$cli = $spByApp[$WorkIqCliAppId]
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'" | Select-Object -First 1
$cliGrants = if ($cli) { Get-MgOauth2PermissionGrant -Filter "clientId eq '$($cli.Id)'" -All -ErrorAction SilentlyContinue } else { @() }

$targets = @([pscustomobject]@{ Name='Microsoft Graph'; Sp=$graphSp; Want=$EnableGraphScopes })
foreach ($n in $Mcp.Keys) {
  $sp = $spByApp[$Mcp[$n]]
  $want = if ($n -eq 'Work IQ Tools') { $EnableToolsScopes } elseif ($sp) { @($sp.Oauth2PermissionScopes.Value) } else { @('(unknown until SP exists)') }
  $targets += [pscustomobject]@{ Name=$n; Sp=$sp; Want=$want }
}
foreach ($t in $targets) {
  $g = if ($t.Sp) { $cliGrants | Where-Object ResourceId -eq $t.Sp.Id | Select-Object -First 1 }
  $have = if ($g) { @($g.Scope -split ' ' | Where-Object { $_ }) } else { @() }
  $add  = $t.Want | Where-Object { $_ -notin $have }
  $extra = $have | Where-Object { $_ -notin $t.Want }   # Enable script REPLACES scope string -> these would be removed
  $state = if (-not $cli) { 'NO CLI SP' } elseif (-not $g) { 'NO GRANT' } elseif ($add) { 'PARTIAL' } else { 'OK' }
  $col = @{ 'OK'='Green'; 'PARTIAL'='Yellow' }[$state]; if (-not $col) { $col = 'Red' }
  Write-Host ("  {0,-28} {1,-9} type={2}" -f $t.Name, $state, $g.ConsentType) -ForegroundColor $col
  if ($add)   { Write-Host "      would ADD:    $($add -join ' ')" -ForegroundColor Yellow }
  if ($extra) { Write-Host "      would REMOVE: $($extra -join ' ')  (script overwrites scope string)" -ForegroundColor Magenta }
  $rows += [pscustomobject]@{ Check='CliGrant'; Name=$t.Name; AppId=$t.Sp.AppId; State=$state; Enabled=''; Client='Work IQ CLI'
    ConsentType=$g.ConsentType; GrantedTo=(UserName $g.PrincipalId); Scopes=$g.Scope; WouldAdd=($add -join ' ') }
}

# 3. ALL clients holding grants to each MCP server (incl. Copilot web/app clients)
Write-Host "`n== 3. Every client app with consent to each MCP server ==" -ForegroundColor Cyan
foreach ($n in $Mcp.Keys) {
  $sp = $spByApp[$Mcp[$n]]; if (-not $sp) { continue }
  $gs = Get-MgOauth2PermissionGrant -Filter "resourceId eq '$($sp.Id)'" -All -ErrorAction SilentlyContinue
  Write-Host "  $n : $(@($gs).Count) grant(s)"
  foreach ($g in $gs) {
    $c = SpName $g.ClientId; $who = UserName $g.PrincipalId
    Write-Host ("      {0,-55} {1,-13} {2}  [{3}]" -f $c, $g.ConsentType, $who, $g.Scope) -ForegroundColor Gray
    $rows += [pscustomobject]@{ Check='AnyClientGrant'; Name=$n; AppId=$Mcp[$n]; State='GRANT'; Enabled=''; Client=$c
      ConsentType=$g.ConsentType; GrantedTo=$who; Scopes=$g.Scope; WouldAdd='' }
  }
}

# 4. Who holds Mail.Read on Graph tenant-wide (context for the security review) -
Write-Host "`n== 4. Clients with TENANT-WIDE Mail.Read on Microsoft Graph ==" -ForegroundColor Cyan
Get-MgOauth2PermissionGrant -Filter "resourceId eq '$($graphSp.Id)'" -All |
  Where-Object { $_.ConsentType -eq 'AllPrincipals' -and ($_.Scope -split ' ') -contains 'Mail.Read' } |
  ForEach-Object { Write-Host "  $(SpName $_.ClientId)" -ForegroundColor Gray }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$csv = Join-Path $OutputDirectory 'workiq-consent-audit.csv'
$rows | Export-Csv $csv -NoTypeInformation
Write-Host "`nWrote $csv" -ForegroundColor Green
Disconnect-MgGraph | Out-Null
