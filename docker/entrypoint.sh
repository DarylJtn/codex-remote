#!/bin/sh
set -eu

umask 077

: "${CODEX_HOME:=${HOME}/.codex}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Refusing to run Codex Remote as root" >&2
  exit 1
fi

mkdir -p "${CODEX_HOME}/packages/standalone"

if [ ! -w "${CODEX_HOME}" ]; then
  echo "CODEX_HOME is not writable: ${CODEX_HOME}" >&2
  exit 1
fi

image_current=/opt/codex-home/packages/standalone/current
state_current="${CODEX_HOME}/packages/standalone/current"

if [ -L "${state_current}" ]; then
  if [ "$(readlink "${state_current}")" != "${image_current}" ]; then
    rm -f "${state_current}"
    ln -s "${image_current}" "${state_current}"
  fi
elif [ -e "${state_current}" ]; then
  echo "Incompatible managed install path in persistent state: ${state_current}" >&2
  echo "Move that path aside before starting this image." >&2
  exit 1
else
  ln -s "${image_current}" "${state_current}"
fi

if [ ! -x /usr/local/bin/codex ] || [ ! -x "${state_current}/codex" ]; then
  echo "Codex managed installation is missing or incomplete" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  set -- remote-control --json
fi

case "$1" in
  codex)
    shift
    exec /usr/local/bin/codex "$@"
    ;;
  sh | bash)
    exec "$@"
    ;;
  *)
    exec /usr/local/bin/codex "$@"
    ;;
esac
