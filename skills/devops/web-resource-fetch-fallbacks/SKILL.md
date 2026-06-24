---
name: web-resource-fetch-fallbacks
description: Ordered workflow for fetching unknown web resources with text HTTP first, Playwright Chromium second, and CloakBrowser CDP as stealth fallback.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [web, playwright, cloakbrowser, cdp, browser-automation, scraping, troubleshooting]
---

# Web Resource Fetch Fallbacks

Use this skill when the user gives a known URL or endpoint and you need to read, fetch, inspect, screenshot, or interact with it. The goal is to use the lowest-overhead method that works, then fall back deliberately when the resource cannot be fetched or rendered correctly.

Do not use this for URL discovery/search. This skill starts after a target URL/resource is already known.

## Default fallback order

1. **curl / Python requests**
   - Fastest and lowest overhead.
   - Best for static HTML, APIs, JSON, XML, CSV, raw files, redirects, headers, status codes, and downloads.
   - Use this first unless the user explicitly asks for browser interaction or screenshots.

2. **Playwright Chromium**
   - Use when the resource needs JavaScript rendering, browser cookies, forms, client-side routing, DOM interaction, or viewport behavior.
   - Prefer normal Playwright before stealth tooling when there is no evidence of blocking or fingerprint sensitivity.

3. **CloakBrowser CDP**
   - Use when normal HTTP or normal Playwright fails because the site is blocked, fingerprint-sensitive, bot-sensitive, or requires the stealth-patched Chromium path.
   - Also use when the active Hermes browser tools are configured to a CloakBrowser CDP endpoint.

Short form:

```text
curl / Python requests → Playwright Chromium → CloakBrowser CDP
```

## Reporting rule

If a fetch/render attempt fails or returns unusable content, report that fact briefly and continue to the next fallback when the task still has a reachable target.

Good pattern:

```text
curl returned a JavaScript shell with no article body, so I continued with Playwright rendering.
```

```text
Normal Playwright was blocked by a verification page, so I retried through CloakBrowser CDP.
```

Do not stop at the first failed method unless all fallback options are unavailable, unsafe, or outside the user's requested scope.

## Method 1: curl / Python requests

Use terminal HTTP clients for raw and reproducible fetches.

### curl examples

```bash
curl -fsSL -D /tmp/headers.txt -o /tmp/body.html 'https://example.com/resource'
python - <<'PY'
from pathlib import Path
print(Path('/tmp/headers.txt').read_text()[:4000])
print(Path('/tmp/body.html').read_text(errors='replace')[:4000])
PY
```

Check only headers/status:

```bash
curl -fsSIL 'https://example.com/resource'
```

Download a file:

```bash
curl -fL --retry 3 --connect-timeout 10 -o /tmp/download.bin 'https://example.com/file'
```

### Python requests examples

Use Python when parsing, custom headers, cookies, or structured output are useful:

```bash
python - <<'PY'
import requests
url = 'https://example.com/resource'
r = requests.get(url, timeout=30, allow_redirects=True, headers={
    'User-Agent': 'Mozilla/5.0',
})
print('status:', r.status_code)
print('final_url:', r.url)
print('content_type:', r.headers.get('content-type'))
print(r.text[:5000])
PY
```

For JSON APIs:

```bash
python - <<'PY'
import json, requests
r = requests.get('https://example.com/api', timeout=30)
r.raise_for_status()
print(json.dumps(r.json(), indent=2)[:10000])
PY
```

### When to fall back from text HTTP

Fall back to Playwright when:

- body is empty, too small, or only an app shell;
- content says JavaScript is required;
- expected data is loaded after client-side API calls;
- redirects/cookies/session behavior require a browser;
- HTTP returns 403/401/429/503 or a challenge page;
- visual confirmation, screenshots, forms, or clicks are needed.

## Method 2: Playwright Chromium

Use normal Playwright when JavaScript rendering or browser behavior is needed, but stealth is not yet required.

### Typical Node script

```bash
node --input-type=module - <<'JS'
import { chromium } from 'playwright';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
await page.goto('https://example.com', { waitUntil: 'domcontentloaded', timeout: 30000 });
console.log(JSON.stringify({
  title: await page.title(),
  url: page.url(),
  text: (await page.locator('body').innerText()).slice(0, 5000),
}, null, 2));
await browser.close();
JS
```

If only `playwright-core` is installed, import from `playwright-core` and provide an executable path to a Playwright-managed or system Chromium binary.

### Common Playwright setup patterns

Install browsers for the current user:

```bash
python -m playwright install chromium
# or
npx playwright install chromium
```

Use a deterministic browser cache path when standardising fresh agents:

```bash
export PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/ms-playwright"
npx playwright install chromium
```

Check existing Playwright browser paths:

```bash
python - <<'PY'
from pathlib import Path
for base in [Path.home()/'.cache/ms-playwright', Path.home()/'.playwright-browsers']:
    print(base, base.exists())
    if base.exists():
        for p in base.rglob('chrome'):
            if p.is_file():
                print(p)
PY
```

### When to fall back from Playwright

Fall back to CloakBrowser CDP when:

- normal Playwright gets a bot/challenge/verification page;
- `navigator.webdriver` or automation fingerprinting is likely relevant;
- the site reacts differently under normal Playwright than in a real browser;
- CDP/browser automation is detected;
- the user specifically requests the stealth-patched browser path.

## Method 3: CloakBrowser CDP

CloakBrowser is a patched Chromium binary plus wrapper. It is not the same as distro Chromium and not the same as the default Playwright browser cache. Use it as the final browser fallback for stealth/fingerprint-sensitive resources.

### Generic installation for a Hermes instance

Create a runner directory:

```bash
mkdir -p ~/.hermes/cloakbrowser-runner
cd ~/.hermes/cloakbrowser-runner
npm init -y
npm install cloakbrowser playwright-core
```

Create `~/.hermes/cloakbrowser-runner/start-cloakbrowser.mjs`:

```javascript
#!/usr/bin/env node
import { launch, binaryInfo } from 'cloakbrowser';

const host = process.env.CLOAKBROWSER_CDP_HOST || '127.0.0.1';
const port = Number(process.env.CLOAKBROWSER_CDP_PORT || '9242');
const headless = !['0', 'false', 'no'].includes(String(process.env.CLOAKBROWSER_HEADLESS || 'true').toLowerCase());

console.log('CloakBrowser binary info before launch:');
console.log(JSON.stringify(binaryInfo(), null, 2));

const browser = await launch({
  headless,
  args: [
    `--remote-debugging-address=${host}`,
    `--remote-debugging-port=${port}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-dev-shm-usage',
  ],
});

console.log(`CloakBrowser CDP listening at http://${host}:${port}`);
console.log('CloakBrowser binary info after launch:');
console.log(JSON.stringify(binaryInfo(), null, 2));

let closing = false;
async function shutdown(signal) {
  if (closing) return;
  closing = true;
  console.log(`Received ${signal}; closing CloakBrowser...`);
  try {
    await browser.close();
  } catch (error) {
    console.error('Error while closing CloakBrowser:', error);
  }
  process.exit(0);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('uncaughtException', async (error) => {
  console.error('Uncaught exception:', error);
  await shutdown('uncaughtException');
});
process.on('unhandledRejection', async (reason) => {
  console.error('Unhandled rejection:', reason);
  await shutdown('unhandledRejection');
});

await new Promise(() => {});
```

Make it executable and run it once:

```bash
chmod +x ~/.hermes/cloakbrowser-runner/start-cloakbrowser.mjs
~/.hermes/cloakbrowser-runner/start-cloakbrowser.mjs
```

First launch downloads the patched Chromium binary into `~/.cloakbrowser/`, for example:

```text
~/.cloakbrowser/chromium-146.0.7680.177.5/chrome
```

### Optional systemd user service

Create `~/.config/systemd/user/cloakbrowser.service`:

```ini
[Unit]
Description=CloakBrowser CDP sidecar for Hermes
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/.hermes/cloakbrowser-runner
Environment=CLOAKBROWSER_CDP_HOST=127.0.0.1
Environment=CLOAKBROWSER_CDP_PORT=9242
Environment=CLOAKBROWSER_HEADLESS=true
ExecStart=/usr/bin/node %h/.hermes/cloakbrowser-runner/start-cloakbrowser.mjs
Restart=on-failure
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=default.target
```

Enable it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now cloakbrowser.service
systemctl --user status cloakbrowser.service
```

Check CDP:

```bash
curl -fsS http://127.0.0.1:9242/json/version
```

### Configure Hermes browser tools to use CloakBrowser

```bash
hermes config set browser.cdp_url http://127.0.0.1:9242
hermes config set browser.cloud_provider local
```

Restart long-running Hermes processes that read config at startup, such as WebUI or gateway services.

### Use CloakBrowser from Playwright over CDP

```bash
cd ~/.hermes/cloakbrowser-runner
node --input-type=module - <<'JS'
import { chromium } from 'playwright-core';
const browser = await chromium.connectOverCDP('http://127.0.0.1:9242');
const context = browser.contexts()[0] || await browser.newContext();
const page = await context.newPage();
await page.goto('https://example.com', { waitUntil: 'domcontentloaded', timeout: 30000 });
console.log(JSON.stringify({
  title: await page.title(),
  url: page.url(),
  userAgent: await page.evaluate(() => navigator.userAgent),
  webdriver: await page.evaluate(() => navigator.webdriver),
}, null, 2));
await page.close();
await browser.close();
JS
```

Expected useful signal:

```text
"webdriver": false
```

### Use CloakBrowser through Hermes browser tools

When `browser.cdp_url` points at CloakBrowser, Hermes browser tools use the CDP override:

```text
browser_navigate → browser_snapshot → browser_console → browser_vision
```

Useful checks:

```javascript
({
  title: document.title,
  url: location.href,
  ua: navigator.userAgent,
  webdriver: navigator.webdriver,
})
```

If a long-running WebUI chat has a stale CDP session after the CloakBrowser service restarts, start a fresh chat/session or restart the WebUI process. Fresh tasks should resolve the current `/json/version` WebSocket URL from the stable HTTP endpoint.

## Verification checklist

After setup or before claiming success:

1. Confirm Playwright exists and can launch/connect.
2. Confirm CloakBrowser binary exists under `~/.cloakbrowser/.../chrome`.
3. Confirm the CDP endpoint returns `/json/version`.
4. Confirm a Playwright CDP script can navigate to `https://example.com`.
5. Confirm `navigator.webdriver` is `false` when using CloakBrowser.
6. If Hermes is configured for CloakBrowser, confirm `browser_navigate` returns `stealth_features: ["cdp_override"]`.
7. For screenshot capability, run `browser_vision` or a Playwright screenshot and verify the file exists.

## Pitfalls

- Distro Chromium from `dnf`/`apt` is not CloakBrowser's patched Chromium.
- Playwright-managed Chromium and CloakBrowser Chromium live in different caches.
- CloakBrowser `launch()` must not pass `--user-data-dir` directly; use persistent-context APIs when a persistent profile is needed.
- CloakBrowser wrapper-level `humanize=True` is not automatically applied when another client connects over CDP. CDP users get the patched Chromium binary and stealth flags, but not necessarily wrapper-level humanized input behavior.
- HTTP text fetch failures should be reported briefly, but should not stop the task when Playwright/CloakBrowser fallbacks are available.
