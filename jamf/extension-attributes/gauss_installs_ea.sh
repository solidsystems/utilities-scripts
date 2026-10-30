#!/bin/bash
# Jamf Extension Attribute: GAUSS Installs (Aptech GAUSS)
#   Input type: Script   Data type: String
#   Smart Group criteria: "GAUSS Installs" is not "" (blank)
#
# GAUSS on macOS has two parts (per Aptech's install docs):
#   - a launcher app in /Applications (bundle name varies by version)
#   - a per-user GAUSS home folder, ~/gauss<NN> (e.g. /Users/jdoe/gauss26),
#     holding src/, lib/, examples/, hostid.txt and, for v18 and older, the
#     .lic license file. Network installs use /Users/Shared/gauss<NN>.
# The home folder can exist without the app (and survives app removal), so
# both are reported:
#   app: <path> (<version>)
#   home: <path> [license file]
#
# Gaussian/GaussView (a different product) are excluded.
#
# Local testing:
#   sudo ./gauss_installs_ea.sh
# Run as root: without sudo, other users' home folders are unreadable.
# The jamf binary needs Full Disk Access (PPPC) for find to see
# Desktop/Documents/Downloads.

apps=$(
  {
    # Spotlight by bundle ID (Aptech): catches renamed/relocated bundles
    /usr/bin/mdfind "kMDItemCFBundleIdentifier == '*aptech*'c" 2>/dev/null
    # Spotlight by name: Spotlight isn't blocked by TCC, so this still sees
    # Desktop/Documents/Downloads when the caller lacks Full Disk Access
    /usr/bin/mdfind "kMDItemFSName == 'GAUSS*.app'c" 2>/dev/null
    # Filesystem fallback in case Spotlight is off or hasn't indexed a home folder
    /usr/bin/find /Applications /Users /opt /usr/local -maxdepth 4 \
      -type d -iname 'GAUSS*.app' -prune 2>/dev/null
  } | grep -v '^/Volumes/' | grep -i '\.app$' | sort -u
)

out=""
while IFS= read -r app; do
  # A real app is a bundle directory; skip stray files named *.app
  [ -d "$app" ] || continue
  # Gaussian / GaussView are unrelated chemistry software
  case "$(basename "$app" | tr '[:upper:]' '[:lower:]')" in
    gaussian*|gaussview*) continue ;;
  esac
  ver=$(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)
  out+="app: ${app} (${ver:-unknown})"$'\n'
done <<< "$apps"

# GAUSS home folders: gauss<digits> directly under a home, /Users/Shared or
# /Applications. Require a GAUSS marker so an unrelated "gauss2" folder
# doesn't count.
homes=$(/usr/bin/find -E /Users /Applications -maxdepth 2 -type d \
  -iregex '.*/gauss[0-9]+' 2>/dev/null | sort -u)
while IFS= read -r h; do
  [ -z "$h" ] && continue
  [ -e "$h/hostid.txt" ] || [ -d "$h/src" ] || [ -d "$h/lib" ] || continue
  lic=""
  ls "$h"/*.lic >/dev/null 2>&1 && lic=" [license file]"
  out+="home: ${h}${lic}"$'\n'
done <<< "$homes"

echo "<result>${out%$'\n'}</result>"
