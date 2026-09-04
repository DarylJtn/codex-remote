#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-codex-remote:local}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
TEST_VOLUME="codex-remote-smoke-$RANDOM-$$"
TEST_CONTAINER="codex-remote-smoke-$RANDOM-$$"

cleanup() {
  docker rm --force "$TEST_CONTAINER" >/dev/null 2>&1 || true
  docker volume rm --force "$TEST_VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker image inspect "$IMAGE" >/dev/null
docker volume create "$TEST_VOLUME" >/dev/null

if [[ -z "$EXPECTED_VERSION" ]]; then
  EXPECTED_VERSION="$(docker image inspect \
    --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' \
    "$IMAGE")"
fi

version_output="$(docker run --rm "$IMAGE" --version)"
printf '%s\n' "$version_output"
grep -F "$EXPECTED_VERSION" <<<"$version_output" >/dev/null

docker run --rm --entrypoint /bin/sh "$IMAGE" -c '
  set -eu
  test "$(. /etc/os-release && printf %s "$ID")" = ubuntu
  test "$(. /etc/os-release && printf %s "$VERSION_ID")" = 24.04
  test "$(id -u)" != 0
  test "$(id -un)" = codex
  test -x /usr/local/bin/codex
  test -x /opt/codex-home/packages/standalone/current/codex
  test -x /opt/codex-home/packages/standalone/current/bin/codex
  test "$(git -C /home/codex/Documents/Codex branch --show-current)" = master
  grep -Fqx "[projects.\"/home/codex/Documents/Codex\"]" \
    "$CODEX_HOME/config.toml"
  grep -Fqx "[projects.\"/workspace\"]" "$CODEX_HOME/config.toml"
  for command_name in bash bwrap git jq rg ssh tini; do
    command -v "$command_name" >/dev/null
  done
'

docker run --rm \
  --volume "$TEST_VOLUME:/home/codex/.codex" \
  "$IMAGE" sh -c '
    set -eu
    test -w "$CODEX_HOME"
    test "$(readlink "$CODEX_HOME/packages/standalone/current")" = \
      /opt/codex-home/packages/standalone/current
    printf persisted >"$CODEX_HOME/smoke-marker"
  '

docker run --rm \
  --volume "$TEST_VOLUME:/home/codex/.codex" \
  "$IMAGE" sh -c 'test "$(cat "$CODEX_HOME/smoke-marker")" = persisted'

docker create \
  --name "$TEST_CONTAINER" \
  --hostname codex-remote-smoke \
  --volume "$TEST_VOLUME:/home/codex/.codex" \
  "$IMAGE" >/dev/null
docker start "$TEST_CONTAINER" >/dev/null

for _ in {1..15}; do
  if docker exec "$TEST_CONTAINER" \
    test -S /home/codex/.codex/app-server-control/app-server-control.sock \
    2>/dev/null; then
    break
  fi
  sleep 1
done

remote_state="$(docker inspect --format '{{.State.Status}}' "$TEST_CONTAINER")"
remote_output="$(docker logs "$TEST_CONTAINER" 2>&1 || true)"
printf '%s\n' "$remote_output"

if grep -Eqi \
  'managed standalone Codex install not found|failed to record pid-managed|failed to read start time' \
  <<<"$remote_output"; then
  echo "Remote Control hit a known packaging or daemon regression" >&2
  exit 1
fi

if [[ "$remote_state" != running ]]; then
  echo "Remote Control supervisor exited unexpectedly" >&2
  exit 1
fi

docker exec "$TEST_CONTAINER" \
  test -S /home/codex/.codex/app-server-control/app-server-control.sock

docker exec "$TEST_CONTAINER" sh -c '
  pid_file="$CODEX_HOME/app-server-daemon/app-server.pid"
  daemon_pid="$(jq -r ".pid // empty" "$pid_file")"
  test -n "$daemon_pid"
  kill -0 "$daemon_pid"
  test "$(git -C /home/codex/Documents/Codex rev-parse --show-toplevel)" = \
    /home/codex/Documents/Codex
  test "$(git -C /home/codex/Documents/Codex branch --show-current)" = master
'

set +e
pair_output="$(docker exec "$TEST_CONTAINER" \
  codex remote-control pair --json 2>&1)"
pair_status=$?
set -e

if [[ "$pair_status" -eq 0 ]]; then
  jq -e '.environmentId and .manualPairingCode and .expiresAt' \
    <<<"$pair_output" >/dev/null
elif ! grep -Fq \
  'remote control pairing is unavailable until enrollment completes' \
  <<<"$pair_output"; then
  printf '%s\n' "$pair_output" >&2
  echo "Remote Control pairing endpoint failed unexpectedly" >&2
  exit 1
fi

echo "Managed app-server, control socket, and pairing endpoint passed"

echo "Smoke tests passed"
