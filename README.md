# Python Dev Sandbox (uv + tmux + Neovim + Azure Foundry)

An interactive, CLI-only Linux container for personal Python
learning/experimentation, with all editing done in Neovim. Your code, dotfiles,
and credentials live on the **host** and are mounted in at runtime, so the image
carries nothing project-specific and you can rebuild or delete it freely.

Optimized for **low friction and "just works"**, not hardening — this isn't
deployed anywhere. It builds **natively on both Apple Silicon (arm64) and x86
Linux (amd64)**, so it's fast on all your machines.

- **Base:** `debian:trixie-slim` — glibc, so prebuilt wheels install without
  compiling. The low-friction default; Alpine's musl would fight you here.
- **Python + packages:** `uv`, managed CPython 3.13 baked in.
- **Editor:** Neovim 0.12.x (official build) + Treesitter/LSP tooling.
- **Multiplexer:** tmux, with persistence plugins + cross-device notes.
- **Cloud:** Azure CLI baked in; headless auth for Azure AI Foundry.
- **Git:** isolated **personal** GitHub identity + a dedicated SSH key.

Host layout:

```
.
├── Dockerfile
├── compose.yaml
├── .env                    # `cp .env.example .env` (Foundry vars; gitignored)
├── ghostty.terminfo        # optional; you generate this (§3)
├── work/                   # your course repo (its own git clone)
└── dotfiles/{nvim/init.lua, tmux/tmux.conf}
```

---

## 1. Prerequisites & cross-machine notes

Rancher Desktop with the **dockerd (moby)** runtime gives a normal `docker` CLI;
on **containerd** use `nerdctl` everywhere. Because the image builds natively per
machine, just run `docker compose build` on each — no cross-emulation.

- **Apple Silicon (work + personal MacBook):** builds arm64 automatically; file
  ownership is handled by the VM, so the `UID`/`GID` args don't matter.
- **x86 Linux desktop:** builds amd64. If your user isn't UID/GID 1000, set the
  matching values in `compose.yaml` so bind-mounted files stay owned by you.

Everything below uses `~`-relative host paths, so the same compose file works on
all three machines (each resolves to that machine's home dir).

---

## 2. One-time host setup (personal GitHub)

```bash
ssh-keygen -t ed25519 -C "you@personal-email" -f ~/.ssh/id_personal_github
chmod 600 ~/.ssh/id_personal_github
# add ~/.ssh/id_personal_github.pub to GitHub → Settings → SSH keys

cat > ~/.gitconfig-personal <<'EOF'
[user]
    name  = Your Name
    email = you@personal-email
[init]
    defaultBranch = main
EOF

mkdir -p work
git clone git@github.com:<you>/<your-repo>.git work
```

`IdentitiesOnly yes` + the dedicated mounted key means SSH only ever offers your
personal key to github.com — your work key isn't in the container at all.

---

## 3. One-time host setup (Ghostty terminfo) — optional

Ghostty sets `TERM=xterm-ghostty`, which Debian doesn't ship yet. Export it into
the build context so it's compiled into the image:

```bash
infocmp -x xterm-ghostty > ghostty.terminfo
```

> **macOS before Sonoma:** `brew install ncurses`, then use
> `/opt/homebrew/opt/ncurses/bin/infocmp -x xterm-ghostty > ghostty.terminfo`.

Skip it and the build still works — a `.bashrc` fallback drops `TERM` to
`xterm-256color`; you just lose Ghostty-only extras like styled underlines.

---

## 4. Build & run

```bash
cp .env.example .env        # fill in your Foundry values (or leave blank for now)
docker compose build
```

**A. Quick, ephemeral shell:**

```bash
docker compose run --rm pydev
```

**B. Persistent box** (needed for cross-device tmux, §6):

```bash
docker compose up -d
docker compose exec pydev tmux new -A -s main
```

Verify:

```bash
uv --version && nvim --version | head -1 && az version
ssh -T git@github.com       # should greet your PERSONAL username
```

---

## 5. uv workflow

One project at the repo root, one folder per experiment, sharing one env:

```bash
cd /home/dev/work
uv init --bare
uv python pin 3.13
uv add requests rich        # add packages as you go — never `pip install`
uv run day05/main.py        # auto-syncs .venv on first use
```

Commit `pyproject.toml` + `uv.lock`, never `.venv/`. `uvx <tool>` runs one-off
tools (`uvx ruff check .`). `uv sync` rebuilds the exact env after a clone. Note
that `.venv` lives inside `./work`, which is bind-mounted, so your project envs
persist on the host automatically.

---

## 6. Azure AI Foundry

The Azure CLI is baked in, and auth is designed to work **headless** (no browser
in the container).

**Log in once** (persists in the `az-config` volume across rebuilds):

```bash
az login --use-device-code   # prints a code; open the URL on any device
az account set --subscription "<your-sub>"
```

Python code authenticates with `DefaultAzureCredential`, whose chain includes the
Azure CLI credential — so once `az login` is done, the SDK "just works" with no
keys in your code. Per project:

```bash
uv add azure-ai-projects azure-identity openai
```

```python
import os
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

project = AIProjectClient(
    endpoint=os.environ["AZURE_AI_PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential(),
)
openai = project.get_openai_client()          # authenticated OpenAI client
resp = openai.responses.create(
    model=os.environ.get("MODEL_DEPLOYMENT", "gpt-5-mini"),
    input="Say hello from my sandbox.",
)
print(resp.output_text)
```

Set `AZURE_AI_PROJECT_ENDPOINT` and `MODEL_DEPLOYMENT` in `.env` (see
`.env.example`); the endpoint is on your Foundry project's Overview, format
`https://<resource>.services.ai.azure.com/api/projects/<project>`. For
unattended runs, use a service principal instead (below). (Hub-based projects /
connection strings are retired; use a Foundry resource project endpoint.)

### Hands-off auth with a service principal

`az login --use-device-code` is ideal while learning, but its tokens expire and
it needs you present. For scripts that run unattended, create a **service
principal** — a non-human identity in Microsoft Entra ID that carries its own
credential and can be granted RBAC roles like a user:

```bash
az ad sp create-for-rbac --name "foundry-sandbox" \
  --role "Azure AI Developer" \
  --scopes /subscriptions/<sub-id>/resourceGroups/<your-rg>
```

That prints `appId`, `password`, and `tenant`. Map them into `.env` as
`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, and `AZURE_TENANT_ID`. When all three
are set, `DefaultAzureCredential` authenticates non-interactively through its
`EnvironmentCredential` link — no device code, no browser, nothing cached to
expire. Scope the role narrowly (a single resource group or the one Foundry
resource) and to the least privilege your calls need — check the exact role, e.g.
model inference may want `Cognitive Services OpenAI User`. The secret is a real
credential: treat it like a password (see §10), it expires (~1 year by default),
and a client certificate is the more secure variant if you'd rather not hold a
shared secret.

---

## 7. tmux across devices — how it actually works

A tmux **session** belongs to a tmux **server** running on one machine (here,
inside the container). "Sharing across devices" just means clients on other
devices **attach to that same server**, so the server must be persistent and each
device must be able to reach the machine it runs on. That one server covers both
the **sequential** case (detach on desktop, reattach on laptop) and the
**simultaneous** case (two clients at once). Simultaneous clients share the same
active window by default; for independent views of the same session, attach a
**grouped session** (`tmux new-session -t main`) — `aggressive-resize` in the
config stops a small client from shrinking everyone.

**Model 1 — container on this machine, long-running (start here).** Use run mode
**B**. Same machine: `docker compose exec pydev tmux new -A -s main`. Another
device: `ssh -t you@this-machine 'docker exec -it pydev-sandbox tmux new -A -s main'`.
Caveat: this machine must be awake and SSH-reachable (work networks often block
inbound SSH).

**Model 2 — run it on an always-on host (real "from anywhere").** Put this same
container on a box that's always up (your home Docker server, or a VPS), SSH in
from any device, and `tmux new -A -s main`. Add **mosh** in front of SSH so the
session survives IP changes and sleep — mosh handles roaming, tmux handles
persistence.

**Model 3 — tmate** spins up a shareable session over a generated SSH URL with
zero setup; good for ad-hoc pairing, not a daily driver.

**Surviving reboots:** the config wires **tmux-resurrect** + **tmux-continuum**
(auto-save every 15 min, auto-restore on server start); state lives in
`~/.local/share/tmux` on a volume. One-time TPM setup:

```bash
git clone https://github.com/tmux-plugins/tpm dotfiles/tmux/plugins/tpm
# then inside tmux: prefix + I
```

---

## 8. Neovim notes

Config is `~/.config/nvim/init.lua`, mounted from `dotfiles/nvim/` so you edit and
version-control it on the host. The starter is options + keymaps + OSC 52
system-clipboard yank, **no plugins** — the clean base your tutorial builds on.

Before ThePrimeagen's *"0 to LSP: Neovim RC From Scratch"*: it uses **Packer**
(now unmaintained — lazy.nvim is the current standard) and predates Neovim
0.11/0.12's native LSP API and built-in `vim.pack` manager. `nvim-lspconfig` +
`mason` still work as shown, so you can follow along literally. For a Python LSP,
install `pyright` via Mason (that's why `nodejs` is in the image) or use a
node-free option (`uv tool install python-lsp-server`, or `ruff`). Plugins and
Mason LSP servers persist in `~/.local/share/nvim` (a volume), so the first-run
download happens once.

Clipboard: yank to `"+` (or `<leader>y`) reaches your host clipboard via OSC 52
through tmux + Ghostty. Paste from host needs Ghostty's `clipboard-read = allow`;
otherwise in-editor registers work normally.

---

## 9. Syncing across machines & repo safety

The design keeps every secret **out** of these files by construction:
credentials live on the host or in Docker volumes and are only *referenced* by
`compose.yaml`, never stored in it. So the project is safe to version-control.

**Safe to commit** (the point of the repo): `Dockerfile`, `compose.yaml`,
`.env.example`, `.gitignore`, `.dockerignore`, `dotfiles/nvim/init.lua`,
`dotfiles/tmux/tmux.conf`, `README.md`.

**Never commit** (all gitignored): `.env` (your endpoint and any SP secret),
`ghostty.terminfo`, anything matching `id_*` / `*.pem` / `*.key` / `*.pfx`. Your
SSH private key and `~/.gitconfig-personal` aren't in the repo at all — they're
host-side mounts.

Because secrets sit outside the repo, cloning it onto a new machine does **not**
bring them — you re-run the one-time host setup there (SSH key §2,
`ghostty.terminfo` §3, `cp .env.example .env` §4). That separation is the trade
for keeping git clean.

For a repo you'll sync across machines:

- **Prefer a private repo.** It costs nothing, syncs identically, and removes the
  whole "oops, committed a secret" risk class. Nothing here needs to be public
  unless you want to share it.
- **If public,** the `.gitignore` is load-bearing — keep it intact, glance at
  `git status` before committing, and leave GitHub's push protection / secret
  scanning enabled (free on public repos; blocks many known secret patterns).
  Keep real identifiers (tenant/subscription IDs, resource endpoints, your email)
  in `.env` only, not in committed files. If a credential ever reaches history,
  **rotate it immediately** — deleting it later doesn't help once it's been
  public.

---

## 10. Troubleshooting

- **`Permissions 0644 ... too open`** → `chmod 600 ~/.ssh/id_personal_github`.
- **Bind-mounted files owned by root (Linux)** → set matching `UID`/`GID` args
  and rebuild.
- **`missing or unsuitable terminal: xterm-ghostty`** → do §3 and rebuild, or
  `export TERM=xterm-256color`.
- **`az login` opens nothing** → that's expected headless; use
  `--use-device-code` and open the URL on any device.
- **SDK auth fails** → confirm `az account show` works inside the container; if
  the `az-config` volume is fresh you need to `az login` again.
- **`docker compose exec` says not running** → start with `up -d` (mode B).
- **containerd runtime** → use `nerdctl` / `nerdctl compose`.
- **Ad-hoc `sudo apt install` gone after rebuild** → expected; add lasting
  packages to the Dockerfile's apt line.
