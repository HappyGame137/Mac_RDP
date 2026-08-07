#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
source_app="$project_root/dist/Mac Low Latency RDP.app"
target_app="/Applications/Mac Low Latency RDP.app"

if [[ ! -d "$source_app" ]]; then
  print -u2 "请先运行 ./scripts/build_app.sh release"
  exit 1
fi

/usr/bin/ditto "$source_app" "$target_app"
/usr/bin/xattr -cr "$target_app"
/usr/bin/codesign --force --deep --sign - "$target_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$target_app"
print "$target_app"
