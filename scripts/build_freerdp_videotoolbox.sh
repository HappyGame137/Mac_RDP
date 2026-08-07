#!/bin/zsh
set -euo pipefail

version="3.30.0"
cache_root="$HOME/Library/Caches/MacLowLatencyRDP"
archive="$cache_root/freerdp-$version.tar.gz"
source_root="$cache_root/source"
source_dir="$source_root/FreeRDP-$version"
build_dir="$cache_root/build-$version-videotoolbox"
install_prefix="$HOME/.local/share/mac-low-latency-rdp/freerdp-$version-videotoolbox"
expected_sha256="21b3f72bd688fcd1dbbef37b7129bfc9701906705572fce2a5a80b1e85ecc0ee"

/bin/mkdir -p "$cache_root"

if [[ ! -f "$archive" ]]; then
  /usr/bin/curl -fL "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/$version.tar.gz" -o "$archive"
fi

actual_sha256=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  print -u2 "FreeRDP 源码校验失败：$actual_sha256"
  exit 1
fi

if [[ ! -d "$source_dir" ]]; then
  /bin/rm -rf "$source_root"
  /bin/mkdir -p "$source_root"
  /usr/bin/tar -xzf "$archive" -C "$source_root"
fi

/bin/rm -rf "$build_dir"

/opt/homebrew/bin/cmake \
  -S "$source_dir" \
  -B "$build_dir" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$install_prefix" \
  -DCMAKE_PREFIX_PATH=/opt/homebrew \
  -DPKG_CONFIG_EXECUTABLE=/opt/homebrew/bin/pkg-config \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=ON \
  -DWITH_CLIENT=ON \
  -DWITH_CLIENT_COMMON=ON \
  -DWITH_CLIENT_SDL=ON \
  -DWITH_CLIENT_SDL2=OFF \
  -DWITH_CLIENT_SDL3=ON \
  -DWITH_CLIENT_MAC=OFF \
  -DWITH_X11=OFF \
  -DWITH_SERVER=OFF \
  -DWITH_SHADOW=OFF \
  -DWITH_PROXY=OFF \
  -DWITH_SAMPLE=OFF \
  -DWITH_FFMPEG=ON \
  -DWITH_VIDEO_FFMPEG=ON \
  -DWITH_DSP_FFMPEG=ON \
  -DWITH_SWSCALE=ON \
  -DWITH_VIDEOTOOLBOX=ON \
  -DWITH_VAAPI_H264_ENCODING=OFF \
  -DWITH_VERBOSE_WINPR_ASSERT=OFF \
  -DWITH_MACAUDIO=ON \
  -DWITH_CUPS=OFF \
  -DWITH_MANPAGES=OFF \
  -DWITH_WEBVIEW=OFF \
  -DWITH_JPEG=ON

/opt/homebrew/bin/cmake --build "$build_dir" --parallel "$(/usr/sbin/sysctl -n hw.logicalcpu)"
/bin/rm -rf "$install_prefix"
/opt/homebrew/bin/cmake --install "$build_dir"

"$install_prefix/bin/sdl-freerdp" /buildconfig | /usr/bin/grep 'WITH_VIDEOTOOLBOX=ON'
print "$install_prefix/bin/sdl-freerdp"
