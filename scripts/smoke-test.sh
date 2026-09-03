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
  for command_name in bash git jq rg ssh tini; do
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
  "$IMAGE" remote-control --json >/dev/null
docker start "$TEST_CONTAINER" >/dev/null

sleep 5
remote_state="$(docker inspect --format '{{.State.Status}}' "$TEST_CONTAINER")"
remote_output="$(docker logs "$TEST_CONTAINER" 2>&1 || true)"
printf '%s\n' "$remote_output"

if grep -Eqi \
  'managed standalone Codex install not found|failed to record pid-managed|failed to read start time' \
  <<<"$remote_output"; then
  echo "Remote Control hit a known packaging or daemon regression" >&2
  exit 1
fi

if [[ "$remote_state" != running ]] && \
   ! grep -Eqi 'auth|login|sign in|credential' <<<"$remote_output"; then
  echo "Remote Control exited for an unexpected reason" >&2
  exit 1
fi

echo "Smoke tests passed"
