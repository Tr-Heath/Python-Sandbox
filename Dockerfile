# syntax=docker/dockerfile:1

###############################################################################
# Python dev sandbox  (uv + tmux + Neovim + Azure CLI, Ghostty-aware)
#   Purpose : personal learning/experimentation. CLI-only, all editing in nvim.
#   Priority: lightweight + low-friction + "just works". Not hardened.
#   Portable: builds NATIVELY on amd64 (Linux desktop) and arm64 (Apple Silicon)
#             — the Neovim asset is auto-selected per architecture.
###############################################################################
FROM debian:trixie-slim

# uv — official multi-arch image; correct arch selected automatically
COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /uvx /bin/

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_CACHE_DIR=/home/dev/.cache/uv \
    PYTHONUNBUFFERED=1
ENV PATH="/home/dev/.local/bin:${PATH}"

# --- OS packages (grouped by purpose; trim freely) --------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git openssh-client curl less bash sudo \
      tmux ncurses-bin ncurses-term \
      build-essential ripgrep fd-find unzip \
      nodejs npm \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# --- Neovim: official static build, correct asset per architecture ----------
ARG NVIM_VERSION=0.12.3
ARG TARGETARCH
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) NV=x86_64 ;; \
      arm64) NV=arm64  ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/nvim.tgz \
      "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NV}.tar.gz"; \
    tar -C /opt -xzf /tmp/nvim.tgz; \
    ln -s "/opt/nvim-linux-${NV}/bin/nvim" /usr/local/bin/nvim; \
    rm /tmp/nvim.tgz

# --- Azure CLI (via uv, so it's arch- AND distro-agnostic) ------------------
# The `az` shim goes to /usr/local/bin (system PATH); its venv lives in /opt so
# no home-dir volume can shadow it. Pinned to a Python the CLI supports.
ENV UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin
# azure-cli ships `az` as a legacy setuptools script whose last line calls bare
# `python` — which only resolves if the script lives inside the venv's bin/.
# Installing to /usr/local/bin breaks that, so replace it with a wrapper that
# invokes the tool venv's interpreter explicitly.
#
# The --prerelease flag is load-bearing: azure-cli pins several dependencies to
# preview builds (azure-batch==15.0.0b1 and various azure-mgmt-* betas), and uv
# excludes pre-releases by default where pip would accept an explicit `==x.y.zbN`
# pin. Without it, no modern release is satisfiable and the resolver silently
# backtracks to azure-cli 2.0.67 (2019) — which installs cleanly, then dies on
# `time.clock()`, removed in Python 3.8.
#
# The >= floor is the tripwire: it keeps you on current releases while turning
# any future unsatisfiable resolution into a loud error rather than another
# silent walk back through eight years of releases.
RUN uv tool install --python 3.12 --prerelease=allow 'azure-cli>=2.90' \
 && printf '%s\n' \
      '#!/bin/sh' \
      'exec /opt/uv-tools/azure-cli/bin/python -m azure.cli "$@"' \
      > /usr/local/bin/az \
 && chmod 755 /usr/local/bin/az

# --- non-root user ----------------------------------------------------------
# NOT for hardening — it keeps bind-mounted files owned by YOU on Linux hosts
# (macOS remaps ownership via its VM either way). Passwordless sudo means ad-hoc
# `sudo apt install ...` just works mid-experiment (won't survive a rebuild).
ARG UID=1000
ARG GID=1000
RUN groupadd --gid "${GID}" dev \
 && useradd  --uid "${UID}" --gid "${GID}" --create-home --shell /bin/bash dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && chmod 440 /etc/sudoers.d/dev \
 && mkdir -p /opt/python /opt/uv-tools \
 && chown -R dev:dev /opt/python /opt/uv-tools /home/dev

USER dev
WORKDIR /home/dev/work

# managed CPython baked in so your first project is instant
RUN uv python install 3.13

# --- volume mountpoints -----------------------------------------------------
# Docker seeds a named volume from whatever is at its mountpoint in the image,
# INCLUDING ownership — and creates the path as root:root if it doesn't exist.
# Creating these as `dev` is what keeps `az login`, `uv add`, Neovim plugins,
# and nvim's undofile from failing with permission errors on first run.
RUN mkdir -p "$HOME/.azure" "$HOME/.cache/uv" \
             "$HOME/.local/share" "$HOME/.local/state" "$HOME/.local/bin"

# SSH: use ONLY the mounted personal key (keeps personal GitHub off work creds)
RUN mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" \
 && { echo 'Host github.com'; echo '  User git'; \
      echo '  IdentityFile ~/.ssh/id_personal'; \
      echo '  IdentitiesOnly yes'; \
      echo '  StrictHostKeyChecking accept-new'; } > "$HOME/.ssh/config" \
 && chmod 600 "$HOME/.ssh/config"

# Ghostty terminfo (optional): generate on the host with
#   infocmp -x xterm-ghostty > ghostty.terminfo
# The bracket-glob keeps this COPY optional so the build works without it.
COPY --chown=dev:dev ghostty.terminf[o] /tmp/tinfo/
RUN if [ -f /tmp/tinfo/ghostty.terminfo ]; then \
      tic -x -o "$HOME/.terminfo" /tmp/tinfo/ghostty.terminfo; fi; rm -rf /tmp/tinfo

# Fallback so tmux/clear/nvim never choke if xterm-ghostty terminfo is absent
RUN printf '%s\n' \
      'if [ "$TERM" = "xterm-ghostty" ] && ! infocmp xterm-ghostty >/dev/null 2>&1; then' \
      '  export TERM=xterm-256color' \
      'fi' >> "$HOME/.bashrc"

CMD ["bash"]
