# utilities-scripts
Scripts and helper utilities

## Jamf

### Extension attributes

- [`jamf/extension-attributes/matlab_installs_ea.sh`](jamf/extension-attributes/matlab_installs_ea.sh) — reports every MATLAB `.app` on a Mac in any location (`/Applications`, `~/Applications`, Desktop, Homebrew `--appdir`) with its version, plus Homebrew caskroom entries. Input type: Script; data type: String. Smart Group: `MATLAB Installs` is not blank.
- [`jamf/extension-attributes/matlab_usage_ea.sh`](jamf/extension-attributes/matlab_usage_ea.sh) — lists per-user MATLAB preference folders (`~/Library/Application Support/MathWorks/MATLAB/<release>`) as `<user> <release> (last modified YYYY-MM-DD)`. These survive uninstall, so this shows who has run MATLAB and roughly when. Input type: Script; data type: String. Smart Group: `MATLAB Usage Evidence` is not blank.
- [`jamf/extension-attributes/gauss_installs_ea.sh`](jamf/extension-attributes/gauss_installs_ea.sh) — shadow-IT discovery for Aptech GAUSS (no sanctioned installs). Reports GAUSS app bundles (any location, with version), per-user GAUSS home folders (`~/gauss<NN>`, flagging `.lic` files), installer receipts with install date, Aptech prefs files, and downloaded GAUSS installers. Receipts, prefs and home folders survive app removal. Excludes Gaussian/GaussView. Input type: Script; data type: String. Smart Group: `GAUSS Installs` is not blank.

## Microsoft 365

### Copilot

- [`m365/copilot/Audit-WorkIQConsent.ps1`](m365/copilot/Audit-WorkIQConsent.ps1) — **read-only** audit of Work IQ / MCP server provisioning. Shows what Microsoft's [`Enable-WorkIQToolsForTenant.ps1`](https://github.com/microsoft/work-iq/blob/main/scripts/Enable-WorkIQToolsForTenant.ps1) would create or grant, without changing anything: which of the 11 Work IQ service principals exist, the Work IQ CLI's consent per resource (scopes it would add, and existing scopes it would drop because it overwrites the scope string), every client app with consent to each MCP server (consent type and user), and which clients hold tenant-wide `Mail.Read`. Writes `workiq-consent-audit.csv`. Needs the `Microsoft.Graph` module and Global Reader.
