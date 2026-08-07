#!/bin/zsh
set -euo pipefail

installed_app='/Applications/Moonlight.app'
backup_root="${1:-${MOONLIGHT_BACKUP_ROOT:-}}"
if [[ -z "$backup_root" ]]; then
  print -u2 'Usage: restore_moonlight_3.1.4.sh /path/to/moonlight-backup'
  exit 2
fi
old_app="$backup_root/Moonlight-3.1.4.app"
current_safety="$backup_root/Moonlight-current-before-rollback.app"

if [[ ! -d "$old_app" ]]; then
  print -u2 "Rollback copy not found: $old_app"
  exit 1
fi
if [[ -e "$current_safety" ]]; then
  print -u2 "Safety copy already exists: $current_safety"
  exit 1
fi

if [[ -d "$installed_app" ]]; then
  mv "$installed_app" "$current_safety"
fi
if ! ditto "$old_app" "$installed_app"; then
  if [[ -d "$current_safety" && ! -e "$installed_app" ]]; then
    mv "$current_safety" "$installed_app"
  fi
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$installed_app"
spctl -a -vv "$installed_app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_app/Contents/Info.plist"
print "Moonlight restored. The replaced version remains at: $current_safety"
