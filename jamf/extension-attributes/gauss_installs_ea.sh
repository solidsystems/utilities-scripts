#!/bin/bash
# Jamf Extension Attribute: GAUSS Installs (Aptech GAUSS)
#   Input type: Script   Data type: String
#   Smart Group criteria: "GAUSS Installs" is not "" (blank)
#
# Built for shadow-IT discovery: we have no sanctioned GAUSS installs, and
# Aptech doesn't publish the app's bundle name or ID, so matching is broad
# and every hit carries its path for a human to review. Gaussian/GaussView
# (unrelated chemistry software) are excluded.
#
# Per Aptech's install docs, GAUSS on macOS is a .pkg (shipped as
# GAUSS_<NN>_MacOSX_64.zip) that installs a launcher in /Applications plus a
# per-user GAUSS home folder ~/gauss<NN> (src/, lib/, examples/, hostid.txt,
# and the .lic license file for v18 and older; /Users/Shared/gauss<NN> for
# network installs).
#
# Output, one line per hit:
#   app: <path> (<version>)            GAUSS app bundle, any location
#   home: <path> [license file]        GAUSS home folder
#   receipt: <pkg id> (installed YYYY-MM-DD)
#                                      installer receipt; survives app removal
#   prefs: <path>                      Aptech prefs/support files; survive removal
#   installer: <path>                  downloaded GAUSS zip/pkg/dmg
#
# Local testing:
#   sudo ./gauss_installs_ea.sh
# Run as root: without sudo, other users' home folders are unreadable.
# The jamf binary needs Full Disk Access (PPPC) for find to see
# Desktop/Documents/Downloads.

# True for names belonging to Gaussian/GaussView rather than GAUSS
is_gaussian() {
  case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
    *gaussian*|*gaussview*) return 0 ;;
  esac
  return 1
}

out=""

# --- App bundles ---
apps=$(
  {
    # Spotlight by bundle ID: catches renamed/relocated bundles
    /usr/bin/mdfind "kMDItemCFBundleIdentifier == '*aptech*'c || kMDItemCFBundleIdentifier == '*gauss*'c" 2>/dev/null
    # Spotlight by name: Spotlight isn't blocked by TCC, so this still sees
    # Desktop/Documents/Downloads when the caller lacks Full Disk Access
    /usr/bin/mdfind "kMDItemFSName == '*GAUSS*.app'c" 2>/dev/null
    # Filesystem fallback in case Spotlight is off or hasn't indexed a home folder
    /usr/bin/find /Applications /Users /opt /usr/local -maxdepth 4 \
      -type d -iname '*GAUSS*.app' -prune 2>/dev/null
  } | grep -v '^/Volumes/' | grep -i '\.app$' | sort -u
)
while IFS= read -r app; do
  # A real app is a bundle directory; skip stray files named *.app
  [ -d "$app" ] || continue
  is_gaussian "$app" && continue
  ver=$(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)
  out+="app: ${app} (${ver:-unknown})"$'\n'
done <<< "$apps"

# --- GAUSS home folders ---
# gauss<digits> directly under a home, /Users/Shared or /Applications.
# Require a GAUSS marker so an unrelated "gauss2" folder doesn't count.
homes=$(/usr/bin/find -E /Users /Applications -maxdepth 2 -type d \
  -iregex '.*/gauss[0-9]+' 2>/dev/null | sort -u)
while IFS= read -r h; do
  [ -z "$h" ] && continue
  [ -e "$h/hostid.txt" ] || [ -d "$h/src" ] || [ -d "$h/lib" ] || continue
  lic=""
  ls "$h"/*.lic >/dev/null 2>&1 && lic=" [license file]"
  out+="home: ${h}${lic}"$'\n'
done <<< "$homes"

# --- Installer receipts ---
receipts=$(/usr/sbin/pkgutil --pkgs 2>/dev/null | grep -iE 'aptech|gauss')
while IFS= read -r id; do
  [ -z "$id" ] && continue
  is_gaussian "$id" && continue
  t=$(/usr/sbin/pkgutil --pkg-info "$id" 2>/dev/null | awk '/^install-time:/ {print $2}')
  when=""
  [ -n "$t" ] && when=" (installed $(/bin/date -r "$t" +%Y-%m-%d))"
  out+="receipt: ${id}${when}"$'\n'
done <<< "$receipts"

# --- Aptech prefs / support files ---
for d in /Users/*/Library/Preferences /Users/*/Library/Application\ Support \
         /Library/Preferences /Library/Application\ Support; do
  [ -d "$d" ] || continue
  while IFS= read -r p; do
    [ -n "$p" ] && out+="prefs: ${p}"$'\n'
  done < <(/usr/bin/find "$d" -maxdepth 1 -iname '*aptech*' 2>/dev/null)
done

# --- Downloaded installers ---
installers=$(
  {
    /usr/bin/mdfind "kMDItemFSName == 'GAUSS*.zip'c || kMDItemFSName == 'GAUSS*.pkg'c || kMDItemFSName == 'GAUSS*.dmg'c" 2>/dev/null
    /usr/bin/find /Users -maxdepth 3 -type f \
      \( -iname 'GAUSS*.zip' -o -iname 'GAUSS*.pkg' -o -iname 'GAUSS*.dmg' \) 2>/dev/null
  } | grep -v '^/Volumes/' | sort -u
)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  is_gaussian "$f" && continue
  out+="installer: ${f}"$'\n'
done <<< "$installers"

echo "<result>${out%$'\n'}</result>"
