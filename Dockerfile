# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04 AS codex-installer

ARG CODEX_RELEASE=0.153.0

ENV DEBIAN_FRONTEND=noninteractive \
    CODEX_HOME=/opt/codex-home \
    CODEX_INSTALL_DIR=/opt/codex-bin \
    CODEX_NON_INTERACTIVE=1

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl gzip tar \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${CODEX_HOME}" "${CODEX_INSTALL_DIR}" \
    && curl --fail --silent --show-error --location \
        https://chatgpt.com/codex/install.sh \
        --output /tmp/install-codex.sh \
    && sh /tmp/install-codex.sh --release "${CODEX_RELEASE}" \
    && test -x "${CODEX_HOME}/packages/standalone/current/codex" \
    && test -x "${CODEX_HOME}/packages/standalone/current/bin/codex" \
    && "${CODEX_INSTALL_DIR}/codex" --version | grep -F "${CODEX_RELEASE}" \
    && rm -f /tmp/install-codex.sh

FROM ubuntu:24.04

ARG CODEX_RELEASE=0.153.0
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        bubblewrap \
        ca-certificates \
        curl \
        git \
        inotify-tools \
        jq \
        less \
        openssh-client \
        procps \
        ripgrep \
        tini \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && if ! getent group "${USER_GID}" >/dev/null; then \
         groupadd --gid "${USER_GID}" codex; \
       fi \
    && existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)" \
    && if [ -n "${existing_user}" ]; then \
         if [ "${existing_user}" != codex ]; then \
           usermod --login codex "${existing_user}"; \
         fi; \
         usermod --home /home/codex --move-home \
           --gid "${USER_GID}" --shell /bin/bash codex; \
       else \
         useradd --uid "${USER_UID}" --gid "${USER_GID}" \
           --create-home --shell /bin/bash codex; \
       fi \
    && mkdir -p /home/codex/.codex /home/codex/Documents/Codex /workspace \
    && chown -R "${USER_UID}:${USER_GID}" /home/codex /workspace

COPY --from=codex-installer /opt/codex-home /opt/codex-home
COPY --from=codex-installer /opt/codex-bin /opt/codex-bin
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/codex-entrypoint

RUN ln -s /opt/codex-bin/codex /usr/local/bin/codex \
    && ln -s /opt/codex-home/packages/standalone/current/bin/codex-code-mode-host \
        /usr/local/bin/codex-code-mode-host

LABEL org.opencontainers.image.title="Codex Remote" \
      org.opencontainers.image.description="Persistent headless Codex Remote Control host" \
      org.opencontainers.image.version="${CODEX_RELEASE}"

ENV HOME=/home/codex \
    CODEX_HOME=/home/codex/.codex \
    PATH=/opt/codex-bin:/usr/local/bin:/usr/bin:/bin \
    TERM=xterm-256color

USER codex
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/codex-entrypoint"]
CMD ["remote-control-daemon"]
