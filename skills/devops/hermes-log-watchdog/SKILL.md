---
name: hermes-log-watchdog
description: Use when configuring Hermes instances to monitor their own logs with a checkpointed logtail-style cron watchdog that alerts only on new warnings/errors.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, logs, cron, watchdog, monitoring]
    related_skills: [hermes-agent]
---

# Hermes Log Watchdog

## Overview

This skill installs a small script-only Hermes cron job that scans `~/.hermes/logs/*.log` for new `WARNING`, `ERROR`, `CRITICAL`, `FATAL`, `EXCEPTION`, and `TRACEBACK` lines.

It behaves like a persistent `logtail`: every log file gets a byte-offset checkpoint, so old errors are not reported again on every run. The cron job is silent when nothing new is found and sends a compact alert only when new suspicious log lines appear.

## When to Use

Use this when:

- A Hermes instance should watch its own gateway/agent/error logs.
- The user wants alerts a few times per day, not continuous noise.
- Old/historical errors should not be repeatedly reported.
- You are configuring multiple Hermes profiles or hosts with the same watchdog pattern.

Do not use this for:

- Real-time production monitoring with paging/SLOs.
- Deep stacktrace analysis; this script reports matching log lines, it does not reconstruct full exceptions.
- Non-Hermes services unless you adapt `LOG_DIR` and patterns.

## Files and State

Runtime script location on each target instance:

```text
~/.hermes/scripts/check_hermes_logs.py
```

Checkpoint state:

```text
~/.hermes/state/log-watchdog-checkpoints.json
```

Log source:

```text
~/.hermes/logs/*.log
```

The first run initializes checkpoints at EOF and stays silent for existing files. That is intentional: it avoids sending historical log spam.

## Installation on One Hermes Instance

1. Copy the script from this skill to the target Hermes instance:

```bash
mkdir -p ~/.hermes/scripts
cp ~/.hermes/skills/devops/hermes-log-watchdog/scripts/check_hermes_logs.py ~/.hermes/scripts/check_hermes_logs.py
chmod +x ~/.hermes/scripts/check_hermes_logs.py
```

If the skill lives elsewhere, find it with:

```bash
hermes skills list | grep hermes-log-watchdog
```

2. Initialize the checkpoint and test that it stays silent on old logs:

```bash
~/.hermes/scripts/check_hermes_logs.py
```

Expected on first run: no output unless a log file cannot be read.

3. Create the script-only cron job:

```bash
hermes cron create '0 8,20 * * *'
```

Configure the job with:

- name: `Hermes log watchdog`
- script: `check_hermes_logs.py`
- no-agent/script-only mode: enabled
- delivery: origin/home channel as appropriate

If using the Hermes tool API, the equivalent is:

```json
{
  "action": "create",
  "name": "Hermes log watchdog",
  "schedule": "0 8,20 * * *",
  "script": "check_hermes_logs.py",
  "no_agent": true,
  "deliver": "origin",
  "prompt": "Script-only watchdog: scan Hermes logs and notify only when warnings/errors are found."
}
```

Important: cron `script` must be relative to `~/.hermes/scripts/`. Use `check_hermes_logs.py`, not `/home/user/.hermes/scripts/check_hermes_logs.py`.

4. Verify:

```bash
hermes cron list
python ~/.hermes/scripts/check_hermes_logs.py
```

## Installing for a Named Profile

Profiles have their own Hermes home under:

```text
~/.hermes/profiles/<profile>/
```

Copy the script into that profile:

```bash
profile=myprofile
mkdir -p ~/.hermes/profiles/$profile/scripts
cp ~/.hermes/skills/devops/hermes-log-watchdog/scripts/check_hermes_logs.py ~/.hermes/profiles/$profile/scripts/check_hermes_logs.py
chmod +x ~/.hermes/profiles/$profile/scripts/check_hermes_logs.py
```

Create the cron job under that profile:

```bash
hermes --profile "$profile" cron create '0 8,20 * * *'
```

Or via the cron tool, pass `profile: "myprofile"` when creating the job.

## Tuning

Edit the target script if needed:

- `MAX_READ_BYTES`: safety cap per file/run.
- `LEVEL_RE`: which severity words trigger alerts.
- `IGNORE_PATTERNS`: known-benign warnings to suppress.

Example ignore pattern:

```python
re.compile(r"Auxiliary: marking nous unhealthy for 60s", re.I),
```

Keep ignore rules conservative. The watchdog is only useful if it still reports genuinely broken things.

## Common Pitfalls

1. **Using an absolute script path in cron.** Hermes cron requires a path relative to `~/.hermes/scripts/`. Correct: `check_hermes_logs.py`. Wrong: `/home/hermes/.hermes/scripts/check_hermes_logs.py`.

2. **Expecting the first run to report existing history.** It intentionally checkpoints EOF on first run. If you want to scan historical logs, delete the checkpoint file or manually set offsets to `0`.

3. **Installing into the wrong profile.** Each profile has its own `scripts/`, `state/`, `logs/`, and cron jobs. Use `hermes --profile NAME ...` and copy the script into `~/.hermes/profiles/NAME/scripts/`.

4. **Too much noise from known warnings.** Add narrow regexes to `IGNORE_PATTERNS`; do not broadly ignore all warnings.

5. **Cron job not delivering.** Check `hermes cron list`, `hermes cron status`, gateway status, and the job's `last_delivery_error`.

## Verification Checklist

- [ ] `~/.hermes/scripts/check_hermes_logs.py` exists and is executable.
- [ ] Running the script once creates `~/.hermes/state/log-watchdog-checkpoints.json`.
- [ ] A second immediate run is silent when no new log issues were written.
- [ ] `hermes cron list` shows `Hermes log watchdog` enabled.
- [ ] Cron job uses `script: check_hermes_logs.py`, not an absolute path.
- [ ] Delivery target points to the intended home/origin channel.
