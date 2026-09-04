# Codex Remote

A small, persistent Docker host for running Codex Remote Control on an
always-on Linux server.

The image deliberately targets one lifecycle: it starts the managed Codex
app-server with Remote Control enabled and supervises that daemon as one Docker
service. It does not expose an inbound port and does not attempt to run the
ChatGPT Linux desktop GUI.

## Design

- Ubuntu 24.04 LTS runtime for broad Linux compatibility.
- Official standalone Codex installer with an exact release version.
- Distribution-provided `bubblewrap` for the supported Linux sandbox path.
- `codex remote-control start --json` to launch the managed app-server required
  by Remote clients, wrapped by a small PID/socket supervisor.
- Non-root runtime user.
- Persistent `CODEX_HOME` volume for auth, enrollment, configuration, sessions,
  skills, plugins, logs, and local MCP state.
- Persistent scratch volume at `~/Documents/Codex`, initialized as one trusted
  Git repository on `master`, so every generated **No project** chat inherits a
  stable trusted root.
- Stable hostname so container recreation does not change the Remote identity.
- Separate, disposable services for device login, login status, and a shell.
- No published ports, privileged mode, host networking, or Docker socket.

## Important status

Remote Control and the app-server commands are still marked experimental by the
CLI. Treat phone connectivity as an acceptance test for your account before
automating deployment.

## Prerequisites

- Docker Engine with the Compose plugin.
- A ChatGPT account with Codex and Remote access.
- Outbound DNS, HTTPS, and secure WebSocket access to ChatGPT.
- A host directory containing only the repositories Codex may access.

## Quick start

Create the local configuration:

```bash
cp .env.example .env
```

Edit `.env`, especially `WORKSPACE_PATH`, `PUID`, and `PGID`. The selected
numeric user must be able to read and write the mounted workspace.

Build the image:

```bash
docker compose build
```

Authenticate once. The login is saved in the `codex-remote-home` volume:

```bash
docker compose run --rm login
docker compose run --rm status
```

Start the persistent host:

```bash
docker compose up -d codex-remote
docker compose logs --follow codex-remote
```

The log should report daemon mode with `status` set to `connected`. A transient
connection error can appear while an old session expires; the daemon keeps
running and reconnects. Open Remote in the ChatGPT mobile app and confirm that
`codex-remote` appears.

## Acceptance test

Before treating the deployment as persistent infrastructure:

1. Start a disposable task from the phone.
2. Ask it to run `id`, `uname -a`, and `pwd`.
3. Ask it to create and remove a file inside a disposable repository.
4. Recreate the service with `docker compose up -d --force-recreate`.
5. Confirm the host returns without another login and retains its conversations.

## Operations

Open a shell with the same workspace and state volume:

```bash
docker compose run --rm shell
```

Stop or restart Remote Control:

```bash
docker compose stop codex-remote
docker compose restart codex-remote
```

Back up the named volume according to the Docker server's normal volume-backup
process. Treat the backup as a secret because it may contain credentials.

## Updates

`CODEX_RELEASE` is intentionally pinned. Renovate is configured to propose
new stable releases against the `master` branch, but automatic merging remains
disabled until an authenticated phone-to-container test has succeeded reliably.

To update manually:

1. Change `CODEX_RELEASE` consistently in `Dockerfile`, `compose.yaml`,
   `.env.example`, and the CI workflow.
2. Build and run `IMAGE=codex-remote:local bash scripts/smoke-test.sh`.
3. Rebuild and recreate the service.

Persistent user state is separate from the image, so rolling the image back
does not delete authentication, conversations, or projectless scratch files.

## Verification

Validate the Compose model and run the container smoke tests:

```bash
docker compose config --quiet
docker compose build
IMAGE=codex-remote:local bash scripts/smoke-test.sh
```

The smoke test verifies the managed app-server process, its control socket, and
the pairing endpoint. It cannot prove that the ChatGPT relay accepts a specific
account, so the phone acceptance test remains required after significant Remote
Control changes.

## Security

Read [SECURITY.md](SECURITY.md) before mounting real repositories. In
particular, do not mount the Docker socket or the host root filesystem.

## License

MIT. See [LICENSE](LICENSE).
