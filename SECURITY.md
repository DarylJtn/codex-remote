# Security

This container gives Codex write access to every mounted workspace and may run
commands approved through ChatGPT Remote.

- Mount only directories Codex is allowed to change.
- Do not mount the Docker socket, the host root filesystem, or SSH private-key
  directories unless that access is deliberately required.
- Treat the `codex_home` volume as a secret. It can contain authentication,
  enrollment, configuration, session, skill, plugin, and MCP state.
- Keep the container unprivileged. Investigate host user-namespace support
  before adding capabilities to work around sandbox failures.
- Pin deployed images and retain the previous image for rollback.

Report suspected vulnerabilities privately to the repository owner. Do not
include authentication files, tokens, enrollment data, or complete logs in a
public issue.

