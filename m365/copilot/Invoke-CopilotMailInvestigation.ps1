<#
.SYNOPSIS
  One-command, READ-ONLY investigation of "Copilot can't access my email" for one user.
  Runs Audit-CopilotMailAccess.ps1 and Audit-WorkIQConsent.ps1 into a single folder,
  records a transcript, and zips the result for hand-off.

.DESCRIPTION
  Does not install modules or change tenant configuration. Checks prerequisites first and
  stops with the exact Install-Module command if something is missing.
  See README.md in this folder for how to read the output.

.EXAMPLE
  ./Invoke-CopilotMailInvestigation.ps1 -UserPrincipalName jane@contoso.com
  ./Invoke-CopilotMailInvestigation.ps1 -UserPrincipalName jane@contoso.com -Since 2026-10-20 -UseDeviceCode
#>
param(
  [Parameter(Mandatory)] [string]$UserPrincipalName,
  [datetime]$Since = (Get-Date).Date.AddDays(-14),
  [switch]$SkipExchange,
  [switch]$UseDeviceCode,
  [switch]$NoZip
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# --- Prerequisites (commands, not module names, so partial Graph installs are caught) ---
$need = @{
  'Get-MgUserLicenseDetail'                  = 'Microsoft.Graph.Users'
  'Get-MgServicePrincipal'                   = 'Microsoft.Graph.Applications'
  'Get-MgOauth2PermissionGrant'              = 'Microsoft.Graph.Identity.SignIns'
  'Get-MgIdentityConditionalAccessPolicy'    = 'Microsoft.Graph.Identity.SignIns'
  'Get-MgPolicyAuthorizationPolicy'          = 'Microsoft.Graph.Identity.SignIns'
  'Get-MgIdentityGovernanceAppConsentRequest'= 'Microsoft.Graph.Identity.Governance'
  'Get-MgAuditLogDirectoryAudit'             = 'Microsoft.Graph.Reports'
  'Get-MgServiceAnnouncementMessage'         = 'Microsoft.Graph.Devices.ServiceAnnouncement'
  'Get-MgExternalConnection'                 = 'Microsoft.Graph.Search'
  'Get-MgAppCatalogTeamApp'                  = 'Microsoft.Graph.Teams'
  'Invoke-MgGraphRequest'                    = 'Microsoft.Graph.Authentication'
}
if (-not $SkipExchange) { $need['Connect-ExchangeOnline'] = 'ExchangeOnlineManagement' }
$missing = $need.Keys | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
if ($missing) {
  $mods = $missing | ForEach-Object { $need[$_] } | Sort-Object -Unique
  Write-Host "Missing commands: $($missing -join ', ')" -ForegroundColor Red
  Write-Host "Install with:  Install-Module $((@('Microsoft.Graph') + ($mods | Where-Object { $_ -notlike 'Microsoft.Graph*' })) -join ', ') -Scope CurrentUser" -ForegroundColor Yellow
  throw "Prerequisites missing."
}
foreach ($s in 'Audit-CopilotMailAccess.ps1','Audit-WorkIQConsent.ps1') {
  if (-not (Test-Path (Join-Path $here $s))) { throw "$s not found next to this script ($here)." }
}

# --- Run ---
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safeUser = $UserPrincipalName -replace '[^A-Za-z0-9._-]', '_'
$out = Join-Path (Get-Location) "copilot-investigation-$safeUser-$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

[pscustomobject]@{
  UserPrincipalName = $UserPrincipalName
  Since             = $Since.ToString('o')
  RunAtUtc          = (Get-Date).ToUniversalTime().ToString('o')
  RunBy             = [Environment]::UserName
  Machine           = [Environment]::MachineName
  PowerShell        = $PSVersionTable.PSVersion.ToString()
  GraphModule       = (Get-Module -ListAvailable Microsoft.Graph.Authentication | Sort-Object Version | Select-Object -Last 1).Version.ToString()
  SkipExchange      = [bool]$SkipExchange
} | ConvertTo-Json | Out-File (Join-Path $out 'run-info.json')

Start-Transcript -Path (Join-Path $out 'transcript.txt') | Out-Null
try {
  $ErrorActionPreference = 'Continue'
  Write-Host "`n##### Mail-access audit #####" -ForegroundColor Magenta
  & (Join-Path $here 'Audit-CopilotMailAccess.ps1') -UserPrincipalName $UserPrincipalName -Since $Since `
      -SkipExchange:$SkipExchange -UseDeviceCode:$UseDeviceCode -OutputDirectory (Join-Path $out 'mail-access')

  Write-Host "`n##### Work IQ consent audit #####" -ForegroundColor Magenta
  & (Join-Path $here 'Audit-WorkIQConsent.ps1') -UseDeviceCode:$UseDeviceCode -OutputDirectory (Join-Path $out 'workiq-consent')
}
finally {
  Stop-Transcript | Out-Null
}

if (-not $NoZip) {
  Compress-Archive -Path (Join-Path $out '*') -DestinationPath "$out.zip" -Force
  Write-Host "`nZipped: $out.zip" -ForegroundColor Green
}
Write-Host "Output folder: $out" -ForegroundColor Green
Write-Host "Contains tenant config, sign-in and audit data for $UserPrincipalName - share only with the investigation team." -ForegroundColor Yellow
