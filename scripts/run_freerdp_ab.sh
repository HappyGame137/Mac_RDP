#!/bin/zsh
set -euo pipefail

preset="${1:-video}"
session_mode="${2:-desktop}"
remote_program="${3:-}"

binary="$HOME/.local/share/mac-low-latency-rdp/freerdp-3.30.0-videotoolbox/bin/sdl-freerdp"
host="${MACRDP_HOST:-}"
port="${MACRDP_PORT:-3389}"
username="${MACRDP_USERNAME:-}"
credential_account="$username@$host:$port"
log_dir="$HOME/Library/Logs/MacLowLatencyRDP"
stamp=$(date '+%Y%m%d-%H%M%S')
log_path="$log_dir/ab-${preset}-${session_mode}-${stamp}.log"

[[ -x "$binary" ]] || { print -u2 "FreeRDP binary not found: $binary"; exit 1; }
[[ -n "$host" ]] || { print -u2 'Set MACRDP_HOST to the Windows host name or address.'; exit 2; }
[[ -n "$username" ]] || { print -u2 'Set MACRDP_USERNAME to the Windows account.'; exit 2; }
/bin/mkdir -p "$log_dir"

# Read the existing app-owned item without printing it. The secret is only
# included in FreeRDP's stdin payload and never appears in a process argument.
password=$(/usr/bin/security find-generic-password \
  -s 'com.local.macrdp.lowlatency' \
  -a "$credential_account" \
  -w)
trap 'unset password' EXIT

typeset -a args
args=(
  "/v:$host:$port"
  "/u:$username"
  "/network:lan"
  "/cert:tofu"
  "/sec:nla"
  "/bpp:32"
  "/gdi:sw"
  "/t:Mac Low Latency RDP A-B"
  "/log-level:INFO"
  "/log-filters:com.freerdp.core.multitransport:DEBUG,com.freerdp.channels.rdpgfx.client:DEBUG,com.freerdp.codec:INFO,com.freerdp.channels.video.client:DEBUG,com.freerdp.channels.rail.client:DEBUG,com.freerdp.channels.drdynvc.client:INFO"
  "+heartbeat"
  "+async-channels"
  "/clipboard"
  # FreeRDP 3.30 client-side UDP multitransport returns E_ABORT.
  "-multitransport"
  "+auto-reconnect"
  "/auto-reconnect-max-retries:5"
  "/scale-desktop:200"
  "/scale-device:180"
)

case "$preset" in
  latency)
    args+=("+async-update" "/frame-ack:1" "/w:4096" "/h:1716" "/gfx:AVC420" "/audio-mode:none" "-wallpaper" "-themes" "-menu-anims" "-window-drag" "+fonts")
    desktop_size='4096x1716'
    export SDL_RENDER_VSYNC=0
    ;;
  balanced)
    args+=("+async-update" "/frame-ack:2" "/w:3072" "/h:1288" "/gfx:AVC420" "/audio-mode:redirect" "-wallpaper" "-themes" "-menu-anims" "-window-drag" "+fonts")
    desktop_size='3072x1288'
    export SDL_RENDER_VSYNC=1
    ;;
  video)
    args+=("+async-update" "/frame-ack:4" "/w:4096" "/h:1716" "/gfx:AVC420" "+video" "/audio-mode:redirect" "-wallpaper" "-themes" "-menu-anims" "-window-drag" "+fonts")
    desktop_size='4096x1716'
    export SDL_RENDER_VSYNC=1
    ;;
  quality)
    args+=("-async-update" "/frame-ack:2" "/w:4096" "/h:1716" "/gfx:AVC444" "/audio-mode:redirect" "+wallpaper" "+themes" "+menu-anims" "+window-drag" "+fonts")
    desktop_size='4096x1716'
    export SDL_RENDER_VSYNC=1
    ;;
  *)
    print -u2 "Unknown preset: $preset (latency|balanced|video|quality)"
    exit 2
    ;;
esac

case "$session_mode" in
  desktop)
    args+=("+f" "/smart-sizing:$desktop_size")
    ;;
  app-launcher)
    [[ -n "$remote_program" ]] || remote_program='C:\Windows\System32\notepad.exe'
    args+=("-f" "/shell:$remote_program")
    ;;
  remoteapp)
    [[ -n "$remote_program" ]] || remote_program='||notepad'
    [[ "$remote_program" != *,* ]] || { print -u2 'RemoteApp program cannot contain commas'; exit 2; }
    args+=("-f" "/app:program:$remote_program,hidef:on")
    ;;
  *)
    print -u2 "Unknown session mode: $session_mode (desktop|app-launcher|remoteapp)"
    exit 2
    ;;
esac

args+=("/p:$password")
export SDL_RENDER_DRIVER=metal
export SDL_APP_ID=com.local.macrdp.lowlatency.session
export SDL_APP_NAME='Mac Low Latency RDP Session'
export WLOG_APPENDER=CONSOLE

{
  print "Mac Low Latency RDP A/B"
  print "Started: $(date -Iseconds)"
  print "Preset: $preset"
  print "Session: $session_mode"
  print "Host: $host:$port"
  print
} > "$log_path"

print "LOG_PATH=$log_path"
if [[ "${MACRDP_EXEC_REPLACE:-0}" == '1' ]]; then
  fifo_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macrdp-stdin.XXXXXX")
  fifo_path="$fifo_dir/args"
  /usr/bin/mkfifo "$fifo_path"
  (
    # Both FIFO endpoints are open before this block starts, so unlinking the
    # path is safe and leaves no credential-bearing temporary file behind.
    /bin/rm -f "$fifo_path"
    /bin/rmdir "$fifo_dir" 2>/dev/null || true
    for argument in "${args[@]}"; do
      print -r -- "$argument"
    done
  ) > "$fifo_path" &
  unset password
  exec "$binary" /args-from:stdin < "$fifo_path" >> "$log_path" 2>&1
else
  {
    for argument in "${args[@]}"; do
      print -r -- "$argument"
    done
  } | "$binary" /args-from:stdin >> "$log_path" 2>&1
fi
