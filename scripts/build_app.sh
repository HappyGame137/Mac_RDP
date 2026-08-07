#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
app_name="Mac Low Latency RDP"
destination_bundle="$project_root/dist/$app_name.app"
staging_root=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macrdp-app-build.XXXXXX")
trap '/bin/rm -rf "$staging_root"' EXIT
bundle="$staging_root/$app_name.app"
contents="$bundle/Contents"
binary_name="MacRDPLowLatency"

cd "$project_root"
swift build -c "$configuration"
binary_path=$(swift build -c "$configuration" --show-bin-path)/$binary_name

/bin/rm -rf "$bundle"
/bin/mkdir -p "$contents/MacOS" "$contents/Resources"
/bin/cp "$binary_path" "$contents/MacOS/$binary_name"

/usr/libexec/PlistBuddy -c 'Clear dict' "$contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string zh_CN' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Mac Low Latency RDP' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string MacRDPLowLatency' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.local.macrdp.lowlatency' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Mac Low Latency RDP' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.9.2' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 12' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string 将麦克风重定向到远程 Windows（仅在启用时）' "$contents/Info.plist"
/usr/bin/xattr -cr "$bundle"
# File Provider may immediately restore an empty FinderInfo attribute in
# Documents. codesign treats even that empty attribute as signing detritus.
/usr/bin/xattr -d com.apple.FinderInfo "$bundle" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "$bundle" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle"

/bin/rm -rf "$destination_bundle"
/usr/bin/ditto "$bundle" "$destination_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination_bundle"
print "$destination_bundle"
