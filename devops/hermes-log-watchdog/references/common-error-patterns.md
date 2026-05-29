# Common Log-Error Patterns and Resolutions

Reference for agents processing hermes-log-watchdog alerts. When the watchdog reports
warnings/errors, cross-reference here before diagnosing from scratch.

---

## Pattern: Memory Tool Limit Exceeded

**What the log shows:**
```
WARNING agent.tool_executor: Tool memory returned error:
"Memory at X/1375 chars. Adding this entry (Y chars) would exceed the limit."
```
or
```
"Replacement would put memory at X/1375 chars."
```
or
```
"content is required for 'replace' action."
```

**Root cause:** `USER.md` (~/.hermes/memories/USER.md) or `MEMORY.md` is at or near
the configured char limit. The model tried to add a new entry and got refused.

**Resolution (step by step):**

1. **Read both memory files** to find which one is full:
   ```
   read_file ~/.hermes/memories/USER.md
   read_file ~/.hermes/memories/MEMORY.md
   ```

2. **Compact entries.** Common compaction techniques:
   - Merge related entries into one delimited by the `§` separator
   - Remove redundant phrasing, filler words, line breaks
   - Use shorthand for repeated concepts
   - Entries are markdown; `•` bullets → inline semicolons saves chars

3. **Increase the limit** (präventiv, not just to today's need):
   ```bash
   hermes config set memory.user_char_limit 2500
   # or
   hermes config set memory.memory_char_limit 3000
   ```
   NEVER use `patch` on config.yaml — it's protected. Use `hermes config set`.

4. **Verify:**
   ```bash
   wc -c ~/.hermes/memories/USER.md
   wc -c ~/.hermes/memories/MEMORY.md
   ```

**Pitfall:** `hermes config set` expects dotted paths like `memory.user_char_limit`,
not YAML section syntax. The `user_char_limit` defaults to 1375; `memory_char_limit` to 2200.

---

## Pattern: Config Write Denied

**What the log shows:**
```
Write denied: '/home/hermes/.hermes/config.yaml' is a protected system/credential file.
```

**Root cause:** Direct file writes to config.yaml are blocked.

**Resolution:** Always use the CLI:
```bash
hermes config set <dotted.path> <value>
hermes config show <section>   # to read current values
```

---

## Pattern: Model Makes Invalid Tool Calls

**What the log shows:**
Warnings from `tool_executor` with `{"error": "...", "success": false}` where the
error is a missing required parameter (e.g. `content is required for 'replace' action`).

**Root cause:** The model occasionally omits required parameters in tool calls.
This is a model quality issue, not a configuration problem.

**Resolution:** No persistent fix. These are transient model errors. The watchdog's
job is to surface them so the operator knows the model struggled. If they become
frequent (>5 per session), consider switching the primary model or adjusting
`reasoning_effort`.