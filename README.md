# hermes.skills

Personal/shared Hermes Agent skills maintained by Chris/Bitbull.

This repository is intended to be copied or cloned into Hermes instances and profiles. It currently contains reusable skills plus helper scripts for operational setup.

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

## Current skills

- `devops/hermes-log-watchdog`: checkpointed Hermes log monitoring via script-only cron job.
