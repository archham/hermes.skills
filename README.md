# hermes.skills

Generic, reusable Hermes Agent skills maintained by Chris/Bitbull.

This repository is intended to be copied or cloned into Hermes instances and profiles. It contains only generic skills plus helper scripts for operational setup.

## Scope: generic only

Skills in this repository must be reusable outside one specific customer, host, profile, or private environment.

Allowed:

- generic Hermes operations and troubleshooting workflows
- reusable scripts that derive paths from `HERMES_HOME` or `$HOME`
- examples with placeholders such as `<profile>`, `<repo>`, `<host>`, `<token>`
- public/open-source tooling knowledge

Not allowed:

- secrets, tokens, credentials, private URLs, private IPs, internal hostnames
- customer-specific runbooks or infrastructure details
- hardcoded local paths except standard Hermes paths like `~/.hermes/...`
- personal data or chat/session artifacts
- claims that require Chris's specific environment unless written as a generic example

If a skill needs local/private details, keep those in a separate private repo, Ansible inventory, environment variables, or profile-local config — not here. Git is forever-ish, and very good at remembering your mistakes. Annoyingly good.

## Repository layout

```text
skills/
  devops/
    hermes-log-watchdog/
      SKILL.md
      scripts/check_hermes_logs.py
scripts/
  install-skill.sh
```

## Install one skill into the default Hermes profile

From a clone of this repository:

```bash
./scripts/install-skill.sh devops/hermes-log-watchdog
```

This copies the skill to:

```text
~/.hermes/skills/devops/hermes-log-watchdog
```

## Install into a named Hermes profile

```bash
./scripts/install-skill.sh --profile myprofile devops/hermes-log-watchdog
```

This copies the skill to:

```text
~/.hermes/profiles/myprofile/skills/devops/hermes-log-watchdog
```

## Install the log watchdog runtime script

The skill includes a script, but Hermes cron executes scripts from `~/.hermes/scripts/` or the profile equivalent. After installing the skill:

Default profile:

```bash
mkdir -p ~/.hermes/scripts
cp ~/.hermes/skills/devops/hermes-log-watchdog/scripts/check_hermes_logs.py ~/.hermes/scripts/check_hermes_logs.py
chmod +x ~/.hermes/scripts/check_hermes_logs.py
~/.hermes/scripts/check_hermes_logs.py
```

Named profile:

```bash
profile=myprofile
mkdir -p ~/.hermes/profiles/$profile/scripts
cp ~/.hermes/profiles/$profile/skills/devops/hermes-log-watchdog/scripts/check_hermes_logs.py \
  ~/.hermes/profiles/$profile/scripts/check_hermes_logs.py
chmod +x ~/.hermes/profiles/$profile/scripts/check_hermes_logs.py
HERMES_HOME="$HOME/.hermes/profiles/$profile" ~/.hermes/profiles/$profile/scripts/check_hermes_logs.py
```

## Cron job for the log watchdog

Create a script-only cron job in Hermes:

```text
Name: Hermes log watchdog
Schedule: 0 8,20 * * *
Script: check_hermes_logs.py
No-agent/script-only: true
Delivery: origin or desired home channel
```

Important: the cron `script` field must be relative to the Hermes scripts directory. Use `check_hermes_logs.py`, not an absolute path.

## Maintenance conventions

- Keep skills under `skills/<category>/<skill-name>/SKILL.md`.
- Put supporting files under `scripts/`, `references/`, `templates/`, or `assets/` inside the skill directory.
- Validate skill frontmatter: it must start with `---`, include `name` and `description`, and have a non-empty body.
- Commit changes with concise conventional commit messages.

## License

This repository is licensed under the GNU Affero General Public License v3.0. See [`LICENSE`](LICENSE).

## Current skills

- `devops/hermes-log-watchdog`: checkpointed Hermes log monitoring via script-only cron job.
