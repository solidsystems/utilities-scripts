# Copilot mail-access investigation toolkit

Read-only PowerShell for investigating **"Microsoft 365 Copilot can't access my email"**. It is built for this symptom: Copilot works in one client (e.g. the iOS app), but `m365.cloud.microsoft/chat` replies:

> I can't directly access or read your email inbox with the tools available in this chat

Nothing here changes tenant configuration. Every Graph call is a `Get-*` cmdlet or a `GET` request. Exchange use is limited to `Get-EXOMailbox` and `Search-UnifiedAuditLog`.

| Script | Purpose |
|---|---|
| `Invoke-CopilotMailInvestigation.ps1` | **Start here.** Checks prerequisites, runs both audits into one folder, saves a transcript, zips the result. |
| `Audit-CopilotMailAccess.ps1` | Per-user and tenant audit (11 sections, below). |
| `Audit-WorkIQConsent.ps1` | What Microsoft's `Enable-WorkIQToolsForTenant.ps1` *would* create or grant, without doing it. Also lists every client with consent to each Work IQ MCP server. |

## Get it onto the admin workstation

```powershell
# Option A: clone
git clone https://github.com/solidsystems/utilities-scripts.git
cd utilities-scripts/m365/copilot

# Option B: download just these three files
$base = 'https://raw.githubusercontent.com/solidsystems/utilities-scripts/main/m365/copilot'
'Invoke-CopilotMailInvestigation.ps1','Audit-CopilotMailAccess.ps1','Audit-WorkIQConsent.ps1' |
  ForEach-Object { Invoke-WebRequest "$base/$_" -OutFile $_ }
Get-ChildItem *.ps1 | Unblock-File          # Windows: clear mark-of-the-web
```

Read the scripts before running them in a production tenant.

## Prerequisites

- PowerShell 7+ (Windows PowerShell 5.1 should work but is untested)
- `Install-Module Microsoft.Graph, ExchangeOnlineManagement -Scope CurrentUser`
- Roles: **Global Reader**, plus **Security Reader** (or Reports Reader) for sign-in logs, plus **View-Only Audit Logs** for the unified audit log
- Entra ID P1 for sign-in logs. Unified audit logging must be on.
- First run: Graph asks for consent to these **read** scopes: `User.Read.All`, `Directory.Read.All`, `Application.Read.All`, `AuditLog.Read.All`, `Policy.Read.All`, `ConsentRequest.Read.All`, `ServiceHealth.Read.All`, `ServiceMessage.Read.All`, `ExternalConnection.Read.All`, `AppCatalog.Read.All`. If your account can't consent, an admin must approve the *Microsoft Graph Command Line Tools* app for them.

## Run

```powershell
pwsh -ExecutionPolicy Bypass -File ./Invoke-CopilotMailInvestigation.ps1 -UserPrincipalName jane@contoso.com -Since 2026-10-20
# -UseDeviceCode  for a jump box without a browser
# -SkipExchange   if you don't have Exchange / audit-log roles
# -NoZip          to keep only the folder
```

**For the best evidence, reproduce first.** Shortly before running, have the user ask the same prompt (e.g. *"show me my last 5 emails"*) once on **iOS** (works) and once on **the web** (fails), and note the times. Sign-in logs lag about 15 minutes, and the unified audit log can lag up to several hours, so run it again later if section 11 is empty.

Output: `copilot-investigation-<user>-<timestamp>/` (and `.zip`):

```
run-info.json           parameters, who/where it ran
transcript.txt          full console output
mail-access/            Audit-CopilotMailAccess.ps1 CSV/JSON
workiq-consent/         workiq-consent-audit.csv
```

The output contains tenant configuration and the user's sign-in and audit data. Share it only with the investigation team.

## Reading the results

Work through these in order. Each row is a hypothesis, the file that tests it, and what confirms it.

| # | Hypothesis | Evidence | Confirms it |
|---|---|---|---|
| 1 | **Client difference: web not grounding on mail** | `mail-access/copilot-interactions.csv` | iOS rows show mail-type `ResourceTypes` / mail `Plugins`. Web rows (`AppHost` = web / BizChat) for the same prompt show none. **This is the strongest single test.** If confirmed, the tenant is fine and the cause is the web client (open a Microsoft ticket with the `ThreadId`s). |
| 2 | Conditional Access blocking the browser path | `mail-access/signins.csv` | Web sign-ins with `ErrorCode` ≠ 0 or a `CAApplied` policy `:failure` that the iOS sign-ins don't have. Check `conditional-access.csv` for `ChangedSinceCutoff = True`. |
| 3 | New web client is a different app that isn't covered by CA or consent | `signins.csv` (`AppId` of web vs older rows), `consent-grants.csv` | Web sign-ins use an `AppId` not present in CA include lists or consent grants that the old client had. |
| 4 | Admin change around the start date | `directory-audit.csv`, `admin-audit-copilot-changes.csv`, `org-apps-agents.csv`, `copilot-packages.csv` | License, consent, CA, connector / MCP / agent or Copilot setting changes near the start date. |
| 5 | Work IQ tools not provisioned | `workiq-consent/workiq-consent-audit.csv` | `ServicePrincipal` rows `MISSING`, or no client holds grants to `mcp_MailTools`. Only relevant if failures are limited to Work IQ mode. The web currently fails in **both** modes, so this is unlikely to be the cause. |
| 6 | License / plan | `license-service-plans.csv` | A Copilot plan not `Success`. Unlikely if iOS works. |
| 7 | Mailbox type / location | `mailbox.json` | Not `UserMailbox` on Exchange Online. Unlikely if iOS works. |
| 8 | Microsoft-side rollout / incident | `message-center.csv`, `service-health.csv` | Posts or incidents about the Copilot web or app transition in the window. Quote the MC/incident IDs in the ticket. |

**Not scriptable. Check in the portal:**
- M365 admin center → **Copilot** → Settings and **Extensibility** (custom MCP connectors, agents, tool allow-list)
- M365 admin center → **Settings → Integrated apps**
- config.office.com → cloud policy *"Allow the use of connected experiences in Office that analyze content"*

**For a Microsoft ticket,** start from [`support-ticket-template.md`](support-ticket-template.md), and attach: the UPN, tenant ID, the timestamps of the iOS (working) and web (failing) attempts, the `ThreadId`s from `copilot-interactions.csv`, request or conversation IDs from browser DevTools, and the results of rows 1–3.

## Background and decisions

Context so a later reviewer can follow how this was built.

- **Symptom timeline:** worked until about 2026-10-27. iOS Copilot app (build released 10-23) still works. `m365.cloud.microsoft/chat` fails in both *Work IQ* and plain *Work* modes. The user's client switched back and forth between the old and new Copilot versions. The browser console showed no errors.
- **Ruled out by reasoning (verify with rows 6–7):** license, mailbox, and indexing, because the iOS app searches the same mailbox.
- **Oct 27 release notes:** nothing touched mailbox access, auth, or modes. The candidate item is *"Admins can create and deploy custom MCP connectors"* (new Copilot Extensibility admin surface), which is why section 10 and row 4 exist.
- **Why not run `Enable-WorkIQToolsForTenant.ps1`:** it grants **tenant-wide admin consent** (`Mail.Read`, `Chat.Read`, `ChannelMessage.Read.All`, `OnlineMeetingTranscript.Read.All`, `Sites.Read.All`, `People.Read.All`, `ExternalItem.Read.All`, plus all `McpServers.*`) **only to the Work IQ CLI client**. It doesn't change the Copilot web or app clients, so it wouldn't fix this symptom. It also overwrites existing scope strings. `Audit-WorkIQConsent.ps1` shows exactly what it would add or drop.
- **Why read-only:** the investigation runs in a production tenant from a separate environment. Collection must be safe to run without change approval.

### Open questions / follow-up

- [ ] Does the web client's `AppId` differ from the pre-10-27 client? (row 3)
- [ ] Do web `CopilotInteraction` records show **no** mail resources? (row 1)
- [ ] Is the beta `copilot/admin/catalog/packages` endpoint readable in this tenant? If not, check Copilot → Agents / Extensibility manually.
- [ ] Is a Message center post tracking the Copilot web transition for this tenant?
- [ ] Not yet run against a tenant. `CopilotInteraction` field names (`AppHost`, `AccessedResources`, `AISystemPlugin`, `Contexts`) follow Microsoft's audit schema as documented. Confirm against `copilot-interactions-sample-raw.json` on first run.
