#!/bin/zsh
set -euo pipefail

resource_dir="${0:A:h:h}/Resources"
export MACRDP_EXEC_REPLACE=1
exec "$resource_dir/run_freerdp_ab.sh" "$@"

