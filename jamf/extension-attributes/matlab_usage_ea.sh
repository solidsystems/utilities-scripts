#!/bin/bash
# Jamf Extension Attribute: MATLAB Usage Evidence
#   Input type: Script   Data type: String
#   Smart Group criteria: "MATLAB Usage Evidence" is not "" (blank)
#
# Lists per-user MATLAB preference folders
# (~/Library/Application Support/MathWorks/MATLAB/<release>). MATLAB creates
# one per release on first launch and leaves it behind on uninstall, so this
# shows who has run MATLAB, which release, and roughly when -- even if the app
# is gone. Pair with matlab_installs_ea.sh for what is installed now.
#
# Output, one line per user/release:
#   <user> <release> (last modified YYYY-MM-DD)
# "last modified" is the newest file in the prefs folder, a proxy for last use.
#
# Local testing:
#   sudo ./matlab_usage_ea.sh
# Run as root: without sudo, other users' home folders are unreadable.

out=""
for p in /Users/*/Library/Application\ Support/MathWorks/MATLAB/*; do
  [ -d "$p" ] || continue
  user=$(echo "$p" | cut -d/ -f3)
  release=$(basename "$p")
  newest=$(/usr/bin/find "$p" -type f -exec /usr/bin/stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
  [ -z "$newest" ] && newest=$(/usr/bin/stat -f '%m' "$p")
  out+="${user} ${release} (last modified $(/bin/date -r "$newest" +%Y-%m-%d))"$'\n'
done

echo "<result>${out%$'\n'}</result>"
