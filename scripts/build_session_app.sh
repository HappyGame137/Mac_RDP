#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_name='Mac Low Latency RDP Session'
destination_bundle="$project_root/dist/$app_name.app"
staging_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macrdp-session-build.XXXXXX")
trap '/bin/rm -rf "$staging_root"' EXIT
bundle="$staging_root/$app_name.app"
contents="$bundle/Contents"

/bin/mkdir -p "$contents/MacOS" "$contents/Resources"
/bin/cp "$project_root/scripts/session_launcher.zsh" "$contents/MacOS/SessionLauncher"
/bin/cp "$project_root/scripts/run_freerdp_ab.sh" "$contents/Resources/run_freerdp_ab.sh"
/bin/chmod 755 "$contents/MacOS/SessionLauncher" "$contents/Resources/run_freerdp_ab.sh"

/usr/libexec/PlistBuddy -c 'Clear dict' "$contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string zh_CN' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Mac Low Latency RDP Session' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string SessionLauncher' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.local.macrdp.lowlatency.session' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Mac Low Latency RDP Session' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.7.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$contents/Info.plist"

/usr/bin/xattr -cr "$bundle"
/usr/bin/codesign --force --deep --sign - "$bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle"
/bin/rm -rf "$destination_bundle"
/usr/bin/ditto "$bundle" "$destination_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination_bundle"
print "$destination_bundle"
