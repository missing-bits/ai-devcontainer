# Workspace image for every environment profile (TD §2). Built through the
# shared Compose file with the host UID and GID from the profile's fragment.
FROM debian:trixie-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build-time only, so interactive tools in the container keep their default.
ARG DEBIAN_FRONTEND=noninteractive

# Base packages and the en_US.UTF-8 locale.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    zsh git curl gnupg ca-certificates openssh-client jq util-linux procps locales \
  && sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Docker CLI and Compose plugin from Docker's Debian repository; no daemon.
# The repository key is trusted only when it is exactly the one primary key
# with Docker's published fingerprint.
ARG DOCKER_APT_KEY_FINGERPRINT=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && GNUPGHOME="$(mktemp -d)" \
  && export GNUPGHOME \
  && fpr="$(gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc \
    | awk -F: '$1 == "pub" { primary = 1; next } $1 == "fpr" && primary { print $10 } { primary = 0 }')" \
  && rm -rf "${GNUPGHOME}" \
  && unset GNUPGHOME \
  && if [ "${fpr}" != "${DOCKER_APT_KEY_FINGERPRINT}" ]; then \
    echo "unexpected Docker apt key fingerprint '${fpr}'" >&2; exit 1; \
  fi \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && codename="$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)" \
  && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian %s stable\n' \
    "$(dpkg --print-architecture)" "$codename" > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/*

# mise, pinned by version and by the release asset's SHA-256 (values from the
# release's SHASUMS256.txt).
ARG TARGETARCH
ARG MISE_VERSION=2026.9.15
ARG MISE_SHA256_X64=2148d2485d1e6e48eb918729d86af4ecd438f9b5b63be360fb26005c85f0d853
ARG MISE_SHA256_ARM64=254f60912e73c9420f03be8bab90ac80c0056db6826814b1a91cb4a0f872c1db
RUN case "${TARGETARCH}" in \
    amd64) arch=x64 sum="${MISE_SHA256_X64}" ;; \
    arm64) arch=arm64 sum="${MISE_SHA256_ARM64}" ;; \
    *) echo "unsupported architecture '${TARGETARCH}'" >&2; exit 1 ;; \
  esac \
  && tmp="$(mktemp -d)" \
  && curl -fsSL -o "${tmp}/mise.tar.gz" \
    "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${arch}.tar.gz" \
  && echo "${sum}  ${tmp}/mise.tar.gz" | sha256sum -c - \
  && tar -xzf "${tmp}/mise.tar.gz" -C "${tmp}" \
  && install -m 0755 "${tmp}/mise/bin/mise" /usr/local/bin/mise \
  && rm -rf "${tmp}"

# oh-my-zsh, pinned by commit SHA and the release tarball's SHA-256 (the
# commit is GitHub's `ohmyzsh/ohmyzsh` master tip as of this pin; TD §3.6,
# §3.9), placed under /usr/share/oh-my-zsh, owned by root and read-only for
# other users. `/etc/zsh/zshrc` loads it for the `vscode` user.
ARG OMZ_COMMIT=83a0ec79ee3b1f64c6ae2e80dcb1fb27a55e5952
ARG OMZ_SHA256=958fb1f4ed53c1cdbce76368b58efbec6d77a72178199de86511e01639996a31
RUN tmp="$(mktemp -d)" \
  && curl -fsSL -o "${tmp}/omz.tar.gz" \
    "https://github.com/ohmyzsh/ohmyzsh/archive/${OMZ_COMMIT}.tar.gz" \
  && echo "${OMZ_SHA256}  ${tmp}/omz.tar.gz" | sha256sum -c - \
  && tar -xzf "${tmp}/omz.tar.gz" -C "${tmp}" \
  && install -d -o root -g root -m 0755 /usr/share/oh-my-zsh \
  && cp -R "${tmp}/ohmyzsh-${OMZ_COMMIT}/." /usr/share/oh-my-zsh/ \
  && chown -R root:root /usr/share/oh-my-zsh \
  && chmod -R a+rX,go-w /usr/share/oh-my-zsh \
  && rm -rf "${tmp}"

# Container scripts, agent CLI launchers, policy files and shell integration,
# owned by root (TD §3.6, §3.7, §3.9).
COPY bin/ /usr/local/lib/aidc/bin/
COPY lib/ /usr/local/lib/aidc/lib/
COPY launchers/ /usr/local/lib/aidc/launchers/
COPY policy/claude-managed-settings.json /etc/claude-code/managed-settings.json
COPY policy/codex-requirements.toml /etc/codex/requirements.toml
COPY policy/codex-config.toml /etc/codex/config.toml
COPY shell/zshrc /etc/zsh/zshrc
COPY shell/aidc-path.sh /etc/profile.d/aidc-path.sh
# COPY keeps the build context's modes, which a umask-077 checkout makes
# owner-only; everyone gets read (and execute where the owner has it), only
# root keeps write.
RUN chmod -R a+rX,go-w /usr/local/lib/aidc /etc/claude-code /etc/codex \
  && chmod 0644 /etc/claude-code/managed-settings.json /etc/codex/requirements.toml \
    /etc/codex/config.toml /etc/zsh/zshrc /etc/profile.d/aidc-path.sh

# The launcher directory leads PATH, so nothing installed under
# /opt/aidc/tools can shadow an agent CLI launcher (TD §3.6). Debian's
# /etc/profile resets PATH for login shells; /etc/profile.d/aidc-path.sh and
# the zshrc hooks restore the order.
ENV PATH=/usr/local/lib/aidc/launchers:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The vscode user carries the host UID and GID (AC2). Declared after the
# layers above, so a different UID or GID reuses them. Every mount point is
# owned by vscode, parents included, so an empty volume takes vscode's
# ownership (TD §3.2). debian:trixie-slim has no user or group named
# `vscode` and no account at UID/GID 1000, so the common host UID/GID does
# not collide with a base-image account (verified against the pinned base).
ARG USER_UID
ARG USER_GID
RUN if [ -z "${USER_UID}" ] || [ -z "${USER_GID}" ]; then \
    echo "USER_UID and USER_GID are required build arguments" >&2; exit 1; \
  fi \
  && case "${USER_UID}${USER_GID}" in \
    *[!0-9]*) echo "USER_UID and USER_GID must be numeric" >&2; exit 1 ;; \
  esac \
  && if [ "${USER_UID}" -eq 0 ]; then echo "the host user must not be root" >&2; exit 1; fi \
  && if [ "${USER_GID}" -eq 0 ]; then echo "the host group must not be root" >&2; exit 1; fi \
  && if user="$(getent passwd "${USER_UID}" | cut -d: -f1)" && [ -n "${user}" ]; then \
    echo "UID ${USER_UID} is already used by ${user} in the base image" >&2; exit 1; \
  fi \
  && if ! group="$(getent group "${USER_GID}" | cut -d: -f1)" || [ -z "${group}" ]; then \
    group=vscode && groupadd -g "${USER_GID}" "${group}"; \
  fi \
  && useradd -l -u "${USER_UID}" -g "${group}" -m -d /home/vscode -s /usr/bin/zsh vscode \
  && install -o vscode -g "${group}" -m 0644 /dev/null /home/vscode/.zshrc \
  && install -d -o root -g root -m 0755 /opt/aidc \
  && for dir in /home/vscode/.claude /home/vscode/.codex /home/vscode/.local /home/vscode/.local/state \
    /home/vscode/.local/state/shell /opt/aidc/tools /workspaces; do \
    install -d -o vscode -g "${group}" -m 0755 "${dir}"; \
  done

USER vscode
WORKDIR /home/vscode
