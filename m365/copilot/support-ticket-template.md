# Microsoft support ticket: Copilot web can't access mailbox

> Template. Copy it into the ticket. Items in **[brackets]** are unverified or need filling in. Remove those before submitting.
> To fill them, run [`Invoke-CopilotMailInvestigation.ps1`](Invoke-CopilotMailInvestigation.ps1)
> (see [README.md](README.md)) after a fresh repro
> (one failing web attempt and one working iOS attempt, a few minutes apart). Its output covers:
> - `copilot-interactions.csv`: conversation IDs, and whether each answer read any mail
> - `signins.csv`: the sign-in comparison
> - `message-center.csv`: post IDs
> - `workiq-consent-audit.csv`: Work IQ service principals present or missing
>
> Attach only those specific CSVs, not the whole zip. The full output contains tenant configuration and the user's audit data.

---

**Title:** Copilot Chat on the web can't read mailbox ("tools available in this chat") since about 2026-10-27, while the iOS app works for the same user

**Product / area:** Microsoft 365 Copilot – Copilot Chat on the web (`m365.cloud.microsoft/chat`), Work IQ

**Tenant ID:** [tenant ID]
**Affected user(s):** [UPN] [and whether other licensed users are also affected]
**Started:** about 2026-10-27. It worked as expected before that.
**Severity / impact:** [e.g. Sev B] The affected user can't get answers about their own mail from Copilot on the web.

## Problem

In Copilot Chat on the web, the prompt *"show me my last 5 emails"* returns:

> "I can't directly access or read your email inbox with the tools available in this chat"

The same user, with the same prompt and the same account, gets a correct answer in the **Microsoft Copilot iOS app** (the build released around 2026-10-23).

## What we've observed

1. **Web fails in both modes:** the failure happens in Work IQ mode and also with Work IQ turned off (Work mode).
2. **Version keeps switching:** the user's Copilot keeps switching back and forth between the previous version and the updated one. The previous version reads mail correctly. The updated version fails.
3. **No browser errors:** the browser console shows no errors when the failure happens. [Network tab: no AADSTS / sign-in errors seen — confirm]
4. **Tenant basics look fine:** we believe the license, the mailbox (on Exchange Online) and mailbox search are fine, because the iOS app reads the same mailbox.
5. **Release notes:** we reviewed the Copilot release notes for Oct 13–27, 2026. The only related item is custom MCP connectors in the Copilot Extensibility admin section. [We have / have not created or deployed any custom MCP connectors]
6. **Work IQ setup:** we have **not** run `Enable-WorkIQToolsForTenant.ps1`. It grants tenant-wide consent only to the Work IQ CLI client, not the Copilot web or app clients, so we don't expect it to affect this. [Our read-only audit shows the Work IQ / MCP service principals are: PRESENT / MISSING]

## Diagnostics we can provide

- [UTC time of a failing web attempt] / [UTC time of a working iOS attempt, same prompt]
- [Copilot conversation / thread IDs for both attempts, from the Copilot activity records in the audit log]
- [Request or correlation IDs from browser DevTools for the failing attempt]
- [Sign-in log comparison between the web and iOS attempts: app ID, Conditional Access result, error code]
- [Message center post IDs related to the Copilot web/app update, if any]

## Questions for Microsoft

1. Is this user, or our tenant, in the staged rollout of the updated Copilot web experience? Is there a known issue with mailbox grounding in it?
2. Does the updated web client need tenant configuration that the previous client didn't to read mail? For example: Work IQ / MCP service provisioning, admin consent, an MCP tool allow-list in the admin center, or a new client app ID that our Conditional Access policies would need to include.
3. Can you trace the failing web conversation(s) on your side and confirm why mail access wasn't used?
4. Until this is fixed, is there a supported way to keep affected users on the previous web experience?

## Workaround in use

The Copilot iOS app [/ Copilot in Teams / Copilot in Outlook on the web — confirm which ones work].
