# utilities-scripts
Scripts and helper utilities

## Jamf

### Extension attributes

- [`jamf/extension-attributes/matlab_installs_ea.sh`](jamf/extension-attributes/matlab_installs_ea.sh) — reports every MATLAB `.app` on a Mac in any location (`/Applications`, `~/Applications`, Desktop, Homebrew `--appdir`) with its version, plus Homebrew caskroom entries. Input type: Script; data type: String. Smart Group: `MATLAB Installs` is not blank.
- [`jamf/extension-attributes/matlab_usage_ea.sh`](jamf/extension-attributes/matlab_usage_ea.sh) — lists per-user MATLAB preference folders (`~/Library/Application Support/MathWorks/MATLAB/<release>`) as `<user> <release> (last modified YYYY-MM-DD)`. These survive uninstall, so this shows who has run MATLAB and roughly when. Input type: Script; data type: String. Smart Group: `MATLAB Usage Evidence` is not blank.
- [`jamf/extension-attributes/gauss_installs_ea.sh`](jamf/extension-attributes/gauss_installs_ea.sh) — shadow-IT discovery for Aptech GAUSS (no sanctioned installs). Reports GAUSS app bundles (any location, with version), per-user GAUSS home folders (`~/gauss<NN>`, flagging `.lic` files), installer receipts with install date, Aptech prefs files, and downloaded GAUSS installers. Receipts, prefs and home folders survive app removal. Excludes Gaussian/GaussView. Input type: Script; data type: String. Smart Group: `GAUSS Installs` is not blank.

## Microsoft 365

### Copilot

Read-only toolkit for investigating "Copilot can't access my email". Start with [`m365/copilot/README.md`](m365/copilot/README.md) (download, run, interpret).

- [`m365/copilot/Invoke-CopilotMailInvestigation.ps1`](m365/copilot/Invoke-CopilotMailInvestigation.ps1) — one-command wrapper: checks prerequisites, runs both audits below into one folder with a transcript, and zips it for hand-off.
- [`m365/copilot/Audit-WorkIQConsent.ps1`](m365/copilot/Audit-WorkIQConsent.ps1) — **read-only** audit of Work IQ / MCP server provisioning. Shows what Microsoft's [`Enable-WorkIQToolsForTenant.ps1`](https://github.com/microsoft/work-iq/blob/main/scripts/Enable-WorkIQToolsForTenant.ps1) would create or grant, without changing anything: which of the 11 Work IQ service principals exist, the Work IQ CLI's consent per resource (scopes it would add, and existing scopes it would drop because it overwrites the scope string), every client app with consent to each MCP server (consent type and user), and which clients hold tenant-wide `Mail.Read`. Writes `workiq-consent-audit.csv`. Needs the `Microsoft.Graph` module and Global Reader.
- [`m365/copilot/Audit-CopilotMailAccess.ps1`](m365/copilot/Audit-CopilotMailAccess.ps1) — **read-only** audit of why Microsoft 365 Copilot can or can't read a user's mail. For one user (`-UserPrincipalName`) since a cutoff (`-Since`, default 14 days ago), it collects the user's license service plans, Work IQ / MCP / Copilot service principals and consent grants, the user consent policy and pending admin consent requests, Conditional Access policies (flagging recent changes), the user's interactive and non-interactive sign-ins, directory audit events (license / consent / CA / app changes), Copilot and Exchange message center posts and service health, and the mailbox type (`-SkipExchange` to omit). Writes CSV/JSON to `copilot-audit-<timestamp>/`. Needs the `Microsoft.Graph` and `ExchangeOnlineManagement` modules, Global Reader plus Security Reader for sign-ins, and Entra ID P1 for sign-in logs.
