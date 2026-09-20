# Sandbox Setup Plan

## Overview

This plan covers every step from a clean host
through a fully working Azure AI Foundry–connected Python dev sandbox inside
Docker — reproducible on any machine.

**Scope:**
- Host one-time setup (SSH key, gitconfig, `.env`)
- Add a `.dockerignore` (missing, referenced in README)
- Build and smoke-test the Docker image
- Provision the Azure AI Foundry resource and project
- Log in to Azure inside the container and verify SDK connectivity
- Confirm the full end-to-end loop: Python → Foundry → response

**Non-goals:** production hardening, CI/CD pipelines, multi-user access.

---

## Sub-Tasks

---

### Sub-Task 1 — Host one-time setup

**Status:** `[x] done`

**Intent**
Establish the host-side prerequisites that `compose.yaml` expects to be present
before the first `docker compose build`. Without these, the build and runtime
volume mounts will fail or warn.

**Expected Outcomes**
- `~/.ssh/id_personal_github` exists with `600` permissions and the public key is
  registered in GitHub Settings → SSH keys.
- `~/.gitconfig-personal` exists with `[user]` name + email and
  `[init] defaultBranch = main`.
- `.env` exists in the project root (copied from `.env.example`); fields can be
  blank for now and filled in after Azure provisioning.

**Todo List**
1. Generate a personal ed25519 SSH key at `~/.ssh/id_personal_github`.
2. Set permissions: `chmod 600 ~/.ssh/id_personal_github`.
3. Add `~/.ssh/id_personal_github.pub` to GitHub → Settings → SSH keys.
4. Write `~/.gitconfig-personal` with `[user] name` / `email` and
   `[init] defaultBranch = main`.
5. `cp .env.example .env` in the project root (leave values blank for now).

**Relevant Context**
- [`compose.yaml`](compose.yaml) mounts `~/.ssh/id_personal_github` and
  `~/.gitconfig-personal` read-only — both paths must exist before `up`.
- [`README.md` §2](README.md) has the exact commands.
- `.env` is loaded via `env_file` in `compose.yaml`; the file must exist even
  with all values blank.

---

### Sub-Task 2 — Add `.dockerignore`

**Status:** `[x] done`

**Intent**
Prevent unnecessary files from being sent to the Docker build daemon. Without
this, the `work/` directory, `.git/`, `.DS_Store` files, and Python artifacts
inflate the build context and risk polluting the image layer cache.

**Expected Outcomes**
- `.dockerignore` exists at the project root.
- Build context excludes: `work/`, `.git/`, `.env`, `*.pyc`, `.DS_Store`,
  `.venv/`, and editor directories.
- `ghostty.terminfo` is explicitly **not** excluded (the Dockerfile `COPY`s it
  optionally).

**Todo List**
1. Create `.dockerignore` at the project root.
2. Add exclusions for: `.git/`, `work/`, `.env`, `.venv/`, `__pycache__/`,
   `*.py[cod]`, `.DS_Store`, `.idea/`, `.vscode/`.
3. Do **not** add `ghostty.terminfo` — the Dockerfile uses a bracket-glob to
   optionally copy it; excluding it would silently break that.
4. Verify with `docker build --no-cache .` that the context size is reasonable
   before declaring done.

**Relevant Context**
- [`Dockerfile`](Dockerfile) — the `COPY --chown=dev:dev ghostty.terminf[o]`
  line depends on the file being in the build context when it exists.
- [`README.md` §9](README.md) lists `.dockerignore` as "safe to commit".
- `.gitignore` already covers `work/`, `.env`, etc. — the `.dockerignore` should
  mirror the same set.

---

### Sub-Task 3 — Build and smoke-test the Docker image

**Status:** `[x] done`

**Intent**
Prove the `Dockerfile` and `compose.yaml` are correct by building the image and
verifying every baked-in tool responds correctly inside the container.

**Expected Outcomes**
- `docker compose build` completes with no errors on the host machine.
- Inside the container, all of the following return expected output:
  - `uv --version`
  - `uv python list` — shows the managed CPython 3.13 install
  - `nvim --version | head -1`
  - `az version`
  - `tmux -V`
  - `ssh -T git@github.com` greets the personal GitHub username
- The `dev` user owns `/home/dev` and can write to the bind-mounted `work/`
  directory.

**Todo List**
1. Optionally generate `ghostty.terminfo` on the host if using Ghostty (see
   README §3); skip if not.
2. Clone TPM on the host so the bind-mounted tmux config has it available:
   `git clone https://github.com/tmux-plugins/tpm dotfiles/tmux/plugins/tpm`.
   (`dotfiles/tmux/plugins/` is gitignored; this only needs doing once per machine.)
3. Run `docker compose build` and confirm it exits 0.
4. Start the container in persistent mode: `docker compose up -d`.
5. Exec in: `docker compose exec pydev bash`.
6. Run each verification command from the list above; record any failures.
   - For Python: `uv python list` (confirms managed 3.13 is present); `uv run python --version`
     works once a uv project exists (step 6 of Sub-Task 5 initialises one).
   - Note: there is no system `python3` on PATH — `debian:trixie-slim` doesn't ship one and
     `UV_PYTHON_PREFERENCE=only-managed` keeps uv's CPython in `/opt/python` only.
7. Test GitHub SSH: `ssh -T git@github.com`.
8. Start a tmux session and confirm TPM plugins load (or note that `prefix + I`
   is needed on first run to install them).
9. Exit and confirm `docker compose down` (with volumes preserved) works cleanly.

**Relevant Context**
- [`Dockerfile`](Dockerfile) — Neovim version is ARG `NVIM_VERSION=0.12.3`;
  Azure CLI is installed via `uv tool install --python 3.12 --prerelease=allow 'azure-cli>=2.90'`
  (as root, before the `dev` user exists). `--prerelease=allow` is because
  without it uv silently resolves back to 2.0.67 (2019), whose setuptools-generated
  shim calls bare `python` and fails with `command not found`. The `>=2.90` floor
  turns any future bad resolution into a loud build error. The shim is replaced
  with a wrapper invoking the venv interpreter directly. The `chown -R dev:dev /home/dev`
  in the user-creation layer reclaims ownership of `/home/dev/.cache/uv`. A subsequent
  `mkdir -p` block (still as `USER dev`) pre-creates `~/.azure`, `~/.local/share`,
  `~/.local/state`, and `~/.local/bin` so Docker seeds those named volumes dev-owned
  rather than creating them root-owned at first mount.
- [`compose.yaml`](compose.yaml) — build args, volume declarations, `stdin_open`
  and `tty` flags required for persistent tmux server.
- [`dotfiles/tmux/tmux.conf`](dotfiles/tmux/tmux.conf) — TPM `run` line at the
  bottom requires TPM to be cloned first:
  `git clone https://github.com/tmux-plugins/tpm dotfiles/tmux/plugins/tpm`.

---

### Sub-Task 4 — Provision Azure AI Foundry resource and project

**Status:** `[ ] pending`

**Intent**
Create the Azure-side infrastructure needed to fill in `.env` and make the Python
SDK work. This is a one-time step per subscription.

**Expected Outcomes**
- An Azure AI Foundry **resource** exists in your subscription (not a Hub — use
  the new "Foundry resource" type, as Hub-based projects and connection strings
  are retired per the README).
- An AI Foundry **project** exists inside that resource.
- The project's **endpoint** is known, format:
  `https://<resource>.services.ai.azure.com/api/projects/<project-name>`.
- A model **deployment** (e.g. `gpt-4o-mini`) exists under Models + endpoints.
- `.env` is updated with `AZURE_AI_PROJECT_ENDPOINT` and `MODEL_DEPLOYMENT`.

**Todo List**
1. Register the `Microsoft.CognitiveServices` resource provider — required on
   any new subscription before creating a Foundry resource. The portal error when
   this is missing is not descriptive, so do it explicitly:
   ```
   az provider register --namespace Microsoft.CognitiveServices
   az provider show -n Microsoft.CognitiveServices --query registrationState
   ```
   Wait until the query returns `"Registered"` (usually under a minute; re-run
   to poll).
2. In the Azure Portal (or `az` CLI), create a resource group if one doesn't
   exist for this sandbox.
3. Create an **Azure AI Foundry** resource (not an Azure OpenAI resource, and not
   a Hub) inside that resource group.
4. Inside the Foundry resource, create a **project**.
5. Under Models + endpoints, deploy a model (e.g. `gpt-4o-mini`); note the
   deployment **name** (the "Name" column, not the model family name).
6. Copy the project endpoint from the project's Overview page.
7. Fill in `.env`:
   ```
   AZURE_AI_PROJECT_ENDPOINT=https://<resource>.services.ai.azure.com/api/projects/<project>
   MODEL_DEPLOYMENT=<deployment-name>
   ```
8. Restart the container (`docker compose down && docker compose up -d`) so the
   updated `.env` is picked up.

**Relevant Context**
- [`README.md` §6](README.md) explains the endpoint format and notes that
  Hub-based projects / connection strings are retired.
- [`.env.example`](.env.example) documents every variable and its expected
  format.
- The model name in `MODEL_DEPLOYMENT` must match the deployment **name** in
  Foundry, not the underlying model name (they can differ).

---

### Sub-Task 5 — Azure login and SDK end-to-end verification

**Status:** `[ ] pending`

**Intent**
Log in to Azure inside the container, verify data-plane RBAC is in place, add
the Foundry SDK packages to a uv project, and confirm a live model call
succeeds — proving the full stack works.

**Expected Outcomes**
- `az account show` inside the container returns the correct subscription.
- `az login` tokens persist across container restarts (stored in `az-config`
  volume).
- Your user principal has the **Azure AI Developer** role assigned on the
  Foundry resource group (or narrower scope) — confirmed before running Python.
- A minimal Python script using `AIProjectClient` + `DefaultAzureCredential`
  returns a model response without errors.

**Todo List**
1. Exec into the running container: `docker compose exec pydev bash`.
2. Log in to Azure: `az login --use-device-code`. Open the printed URL on any
   device, enter the code, complete the browser flow.
3. Set the active subscription:
   `az account set --subscription "<your-sub-name-or-id>"`.
4. Verify: `az account show` should show the correct subscription.
5. **Check data-plane RBAC before running any Python.** Being subscription Owner
   does not grant data-plane access — the built-in Owner role has `"actions": ["*"]`
   but an empty `dataActions` array, and model inference is a data action. A missing
   role causes a 401/403 that looks like an auth bug but is not.
   - Check first (Foundry sometimes auto-assigns the creator, don't assume it):
     ```
     az role assignment list --assignee "<your-upn>" --all -o table
     ```
   - If `Azure AI Developer` is not listed for your Foundry resource group (or the
     resource itself), assign it:
     ```
     az role assignment create \
       --assignee "<your-upn>" \
       --role "Azure AI Developer" \
       --scope /subscriptions/<sub-id>/resourceGroups/<rg>
     ```
   - Role propagation can take 1–2 minutes; wait before proceeding.
6. In `/home/dev/work`, initialise a uv project (if not already done):
   `uv init --bare && uv python pin 3.13`.
7. Add the Foundry SDK:
   `uv add azure-ai-projects azure-identity openai`.
8. Write a minimal test script (e.g. `hello_foundry.py`) using the snippet in
   README §6, sourcing `AZURE_AI_PROJECT_ENDPOINT` and `MODEL_DEPLOYMENT` from
   the environment.
9. Run it: `uv run hello_foundry.py`. Expect a text response from the model.
   - If a 401/403 is returned despite `az account show` succeeding, re-check the
     role assignment from step 5 — this is the most common failure at this stage.
10. Detach from the container and restart it (`docker compose down && docker compose up -d`),
    then re-exec and confirm `az account show` still works without re-logging in
    (proving the `az-config` volume persisted the tokens).

**Relevant Context**
- [`README.md` §6](README.md) — full Python snippet and auth explanation.
- [`compose.yaml`](compose.yaml) — `az-config:/home/dev/.azure` volume is what
  persists the login tokens; if this volume is deleted, login must be redone.
- `DefaultAzureCredential` checks `EnvironmentCredential` (service principal env
  vars) before the Azure CLI credential — if the SP vars are blank in `.env`,
  it falls through to CLI auth, which is the expected learning-mode path.
- **Control plane vs. data plane RBAC:** Azure RBAC has two permission categories.
  `actions` govern control-plane operations (create/delete resources, read
  metadata). `dataActions` govern data-plane operations (reading secrets, calling
  model endpoints, writing blobs). Owner/Contributor cover control plane only.
  Foundry model inference is a data-plane operation — it requires a role that
  explicitly lists it in `dataActions`, such as `Azure AI Developer` or the
  narrower `Cognitive Services OpenAI User`. This split is by design: it lets you
  grant infra management without data access (and vice versa). It is also a
  frequently tested concept in the Azure AI-103 / AI Engineer exam.

---

## File Inventory (final state after all sub-tasks)

| File | In repo | Notes |
|---|---|---|
| `Dockerfile` | ✅ | No changes needed |
| `compose.yaml` | ✅ | No changes needed |
| `.env.example` | ✅ | No changes needed |
| `.env` | ❌ gitignored | Created locally in sub-task 1 |
| `.gitignore` | ✅ | No changes needed |
| `.dockerignore` | ✅ | Created in sub-task 2 |
| `dotfiles/nvim/init.lua` | ✅ | No changes needed |
| `dotfiles/tmux/tmux.conf` | ✅ | No changes needed |
| `README.md` | ✅ | No changes needed |
