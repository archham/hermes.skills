---
name: hermes-log-watchdog
description: Use when configuring Hermes instances to monitor their own logs with a checkpointed logtail-style cron watchdog. When errors are found, the LLM agent analyzes root cause, searches for solutions, and delivers a structured summary.
version: 2.0.0
author: Hermes Agent
license: AGPL-3.0-only
metadata:
  hermes:
    tags: [hermes, logs, cron, watchdog, monitoring]
    related_skills: [hermes-agent]
---

# Hermes Log Watchdog

## Overview

This skill installs an LLM-driven Hermes cron job that scans `~/.hermes/logs/*.log` for new `WARNING`, `ERROR`, `CRITICAL`, `FATAL`, `EXCEPTION`, and `TRACEBACK` lines.

It behaves like a persistent `logtail`: every log file gets a byte-offset checkpoint, so old errors are not reported again on every run. The cron job is silent when nothing new is found and sends a compact alert only when new suspicious log lines appear.

**New in v2.0:** The watchdog is now LLM-driven. When errors are found, the agent analyzes each pattern, searches for root causes, proposes concrete fixes, and delivers a structured summary (Problem → Ursache → Lösung). When no errors are found, it responds with a simple "alles sauber" confirmation.

## When to Use

Use this when:

- A Hermes instance should watch its own gateway/agent/error logs.
- The user wants alerts with root-cause analysis, not just raw log lines.
- Old/historical errors should not be repeatedly reported.
- You are configuring multiple Hermes profiles or hosts with the same watchdog pattern.

Do not use this for:

- Real-time production monitoring with paging/SLOs.
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

## How It Works

1. The `check_hermes_logs.py` script scans log files incrementally (byte-offset checkpointing).
2. When warnings/errors are found, the script outputs matching patterns and examples.
3. The LLM agent receives this output and:
   - Analyzes each unique error/warning pattern
   - Searches for root causes (configs, system state, recent changes)
   - Finds or proposes concrete solutions
   - Delivers a structured summary in German (Swiss style):
     - **Problem:** was ist passiert
     - **Ursache:** warum ist es passiert
     - **Lösung:** wie wird es behoben
4. When no errors are found, the agent responds: "✅ Keine neuen Fehler oder Warnungen in den Hermes-Logs."

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

3. Create the cron job:

```bash
hermes cron create '0 8,20 * * *'
```

Configure the job with:

- name: `Hermes log watchdog`
- script: `check_hermes_logs.py`
- no-agent: **disabled** (LLM-driven, not script-only)
- delivery: origin/home channel as appropriate
- prompt: the analysis prompt (see below)

If using the Hermes tool API, the equivalent is:

```json
{
  "action": "create",
  "name": "Hermes log watchdog",
  "schedule": "0 8,20 * * *",
  "script": "check_hermes_logs.py",
  "no_agent": false,
  "deliver": "origin",
  "prompt": "The script check_hermes_logs.py scans Hermes logs incrementally and outputs any new warnings/errors found since the last check.\n\n## Your task\nIf the script output contains warnings or errors:\n1. Analyze each unique error/warning pattern\n2. For each distinct issue: search for the root cause (check configs, recent changes, system state)\n3. Find or propose a concrete solution for each issue\n4. Deliver a clear summary in German (Swiss style, ss not ß):\n\n**Zusammenfassung:**\n- **Problem:** was ist passiert\n- **Ursache:** warum ist es passiert\n- **Lösung:** wie wird es behoben\n\nIf the script output is empty (no errors found), respond with only: \"✅ Keine neuen Fehler oder Warnungen in den Hermes-Logs.\"\n\nKeep it concise. Prioritize actionable fixes over noise."
}
```

Important: cron `script` must be relative to `~/.hermes/scripts/`. Use `check_hermes_logs.py`, not `/home/user/.hermes/scripts/check_hermes_logs.py`.

4. Verify:

```bash
hermes cron list
python ~/.hermes/scripts/check_hermes_logs.py
```

## Upgrading from v1.0 (script-only) to v2.0 (LLM-driven)

If you already have a v1.0 watchdog running, update it:

```bash
hermes cron update <job-id> --no-agent=false --prompt "<analysis prompt from above>"
```

Or via the cron tool API:

```json
{
  "action": "update",
  "job_id": "<job-id>",
  "no_agent": false,
  "prompt": "..."
}
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

6. **Leaving no_agent=true after upgrading.** The v2.0 watchdog requires `no_agent: false` so the LLM can analyze errors. If no_agent stays true, you only get raw script output without root-cause analysis.

## Verification Checklist

- [ ] `~/.hermes/scripts/check_hermes_logs.py` exists and is executable.
- [ ] Running the script once creates `~/.hermes/state/log-watchdog-checkpoints.json`.
- [ ] A second immediate run is silent when no new log issues were written.
- [ ] `hermes cron list` shows `Hermes log watchdog` enabled.
- [ ] Cron job uses `no_agent: false` (LLM-driven mode).
- [ ] Cron job uses `script: check_hermes_logs.py`, not an absolute path.
- [ ] Delivery target points to the intended home/origin channel.
