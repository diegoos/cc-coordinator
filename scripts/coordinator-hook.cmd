: << 'CMDBLOCK'
@echo off
setlocal
set "ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"

if /I "%ARCH%"=="AMD64" (
  set "TARGET=windows-x64"
) else if /I "%ARCH%"=="ARM64" (
  set "TARGET=windows-arm64"
) else (
  echo coordinator-hook: unsupported architecture: %ARCH% 1>&2
  exit /b 0
)

set "BIN=%~dp0bin\hook-%TARGET%.exe"
if not exist "%BIN%" (
  echo coordinator-hook: binary not found: %BIN% 1>&2
  exit /b 0
)

"%BIN%" %*
exit /b %ERRORLEVEL%
CMDBLOCK

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
os=$(uname -s)
arch=$(uname -m)

case "$arch" in
  x86_64|amd64) arch=x64 ;;
  arm64|aarch64) arch=arm64 ;;
  *)
    echo "coordinator-hook: unsupported architecture: $arch" >&2
    exit 0
    ;;
esac

case "$os" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  MINGW*|MSYS*|CYGWIN*) os=windows ;;
  *)
    echo "coordinator-hook: unsupported system: $os" >&2
    exit 0
    ;;
esac

if [ "$os" = macos ] && [ "$arch" = x64 ]; then
  translated=$(sysctl -n sysctl.proc_translated 2>/dev/null || true)

  if [ "$translated" = 1 ]; then
    arch=arm64
  fi
fi

if [ "$os" = windows ]; then
  bin="$dir/bin/hook-windows-$arch.exe"
else
  bin="$dir/bin/hook-$os-$arch"
fi

if [ ! -f "$bin" ]; then
  echo "coordinator-hook: binary not found: $bin" >&2
  exit 0
fi

exec "$bin" "$@"
