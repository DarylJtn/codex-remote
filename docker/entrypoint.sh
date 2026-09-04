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

ensure_trusted_project() {
  project_path="$1"
  trust_header="[projects.\"${project_path}\"]"
  config_file="${CODEX_HOME}/config.toml"

  touch "${config_file}"
  if ! grep -Fqx "${trust_header}" "${config_file}"; then
    printf '\n%s\ntrust_level = "trusted"\n' "${trust_header}" >>"${config_file}"
  fi
}

scratch_root="${CODEX_SCRATCH_ROOT:-${HOME}/Documents/Codex}"
mkdir -p "${scratch_root}"

if ! git -C "${scratch_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${scratch_root}" init --initial-branch=master >/dev/null
fi

ensure_trusted_project "${scratch_root}"
ensure_trusted_project /workspace

run_remote_control_daemon() {
  daemon_dir="${CODEX_HOME}/app-server-daemon"
  daemon_pid_file="${daemon_dir}/app-server.pid"
  control_socket="${CODEX_HOME}/app-server-control/app-server-control.sock"

  stop_daemon() {
    trap - HUP INT TERM
    /usr/local/bin/codex remote-control stop --json || true
    exit 0
  }

  trap stop_daemon HUP INT TERM

  # Recover from an unclean container stop without deleting auth or project state.
  /usr/local/bin/codex remote-control stop --json >/dev/null 2>&1 || true
  rm -f \
    "${daemon_dir}/app-server.pid" \
    "${daemon_dir}/app-server-updater.pid" \
    "${control_socket}"

  # A relay error can be transient while a previous connection expires. The
  # daemon is healthy if it has created both its PID record and control socket.
  if ! /usr/local/bin/codex remote-control start --json; then
    if [ ! -S "${control_socket}" ] || [ ! -s "${daemon_pid_file}" ]; then
      echo "Codex app-server daemon failed to start" >&2
      exit 1
    fi
  fi

  while :; do
    daemon_pid="$(jq -r '.pid // empty' "${daemon_pid_file}" 2>/dev/null || true)"

    if [ -z "${daemon_pid}" ] || ! kill -0 "${daemon_pid}" 2>/dev/null; then
      echo "Codex app-server daemon exited unexpectedly" >&2
      exit 1
    fi

    if [ ! -S "${control_socket}" ]; then
      echo "Codex app-server control socket disappeared" >&2
      exit 1
    fi

    sleep 5 &
    wait "$!"
  done
}

if [ "$#" -eq 0 ]; then
  set -- remote-control-daemon
fi

case "$1" in
  remote-control-daemon)
    run_remote_control_daemon
    ;;
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
