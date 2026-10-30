# utilities-scripts
Scripts and helper utilities

## Jamf

### Extension attributes

- [`jamf/extension-attributes/matlab_installs_ea.sh`](jamf/extension-attributes/matlab_installs_ea.sh) — reports every MATLAB `.app` on a Mac in any location (`/Applications`, `~/Applications`, Desktop, Homebrew `--appdir`) with its version, plus Homebrew caskroom entries. Input type: Script; data type: String. Smart Group: `MATLAB Installs` is not blank.
- [`jamf/extension-attributes/matlab_usage_ea.sh`](jamf/extension-attributes/matlab_usage_ea.sh) — lists per-user MATLAB preference folders (`~/Library/Application Support/MathWorks/MATLAB/<release>`) as `<user> <release> (last modified YYYY-MM-DD)`. These survive uninstall, so this shows who has run MATLAB and roughly when. Input type: Script; data type: String. Smart Group: `MATLAB Usage Evidence` is not blank.
