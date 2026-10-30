#!/bin/bash
# Jamf Extension Attribute: MATLAB Installs
#   Input type: Script   Data type: String
#   Smart Group criteria: "MATLAB Installs" is not "" (blank)
#
# Reports every MATLAB*.app on the machine, in any location (/Applications,
# ~/Applications, Homebrew --appdir, ad-hoc extracts), with its version, plus
# Homebrew caskroom entries.
#
# Local testing:
#   sudo ./matlab_installs_ea.sh                  # same view as the jamf binary (root)
#   sudo ./matlab_installs_ea.sh --include-usage  # also list per-user MathWorks prefs
#                                                 # (evidence of past use, even if uninstalled)
# Run as root: without sudo, other users' home folders are unreadable.
# The jamf binary needs Full Disk Access (PPPC) for find to see
# Desktop/Documents/Downloads.

include_usage=false
[ "$1" = "--include-usage" ] && include_usage=true

apps=$(
  {
    # Spotlight by bundle ID: catches renamed/relocated bundles
    /usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.mathworks.matlab*'" 2>/dev/null
    # Spotlight by name: Spotlight isn't blocked by TCC, so this still sees
    # Desktop/Documents/Downloads when the caller lacks Full Disk Access
    /usr/bin/mdfind "kMDItemFSName == 'MATLAB*.app'c" 2>/dev/null
    # Filesystem fallback in case Spotlight is off or hasn't indexed a home folder
    /usr/bin/find /Applications /Users /opt /usr/local -maxdepth 4 \
      -type d -iname 'MATLAB*.app' -prune 2>/dev/null
  } | grep -v '^/Volumes/' | grep -i '\.app$' | sort -u
)

out=""
while IFS= read -r app; do
  # A real app is a bundle directory; skip stray files named *.app
  [ -d "$app" ] || continue
  ver=$(/usr/bin/defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)
  out+="${app} (${ver:-unknown})"$'\n'
done <<< "$apps"

# Homebrew caskroom (the .app itself is caught above)
for c in /opt/homebrew/Caskroom/matlab* /usr/local/Caskroom/matlab*; do
  [ -e "$c" ] && out+="brew-cask: ${c}"$'\n'
done

if $include_usage; then
  for p in /Users/*/Library/Application\ Support/MathWorks/MATLAB/*; do
    [ -d "$p" ] && out+="prefs: ${p}"$'\n'
  done
fi

echo "<result>${out%$'\n'}</result>"
