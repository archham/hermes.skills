---
name: hermes-backup-restore
description: "Backup und Restore von Hermes Agent Instanzen — config, skills, plugins, cron, memories, SSH-Keys und Shell-Config."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, backup, restore, disaster-recovery, migration]
    related_skills: [hermes-enterprise-linux-setup, hermes-log-watchdog]
    scripts: [scripts/hermes-backup.sh]
---

# Hermes Backup & Restore

Backup und Restore einer kompletten Hermes-Agent Installation in ein portables `tar.gz`-Archiv.

## Script

Das Script liegt unter `scripts/hermes-backup.sh` im Skill-Verzeichnis.
Installier es nach `~/bin/`:

```bash
cp "$(dirname "$(readlink -f "$0")")/scripts/hermes-backup.sh" ~/bin/hermes-backup
chmod +x ~/bin/hermes-backup
```

## Nutzung

### Backup

```bash
# Default: komprimiertes Archiv ins aktuelle Verzeichnis
hermes-backup backup

# Mit Zielpfad
hermes-backup backup /tmp/hermes-backup-20260530.tar.gz

# Debug-Mode (zeigt was gepackt wird, ohne zu archivieren)
hermes-backup backup --dry-run
```

Erzeugt: `hermes-backup-<hostname>-<date>.tar.gz` (ca. 5–50MB ohne Node/npm).

### Restore

```bash
# Entpackt und passt Pfade/User-Referenzen im Ziel-Home an
hermes-backup restore /tmp/hermes-backup-20260530.tar.gz

# Restore in anderes Home (z.B. frischer User)
sudo hermes-backup restore --target /home/fritz /tmp/hermes-backup.tar.gz
```

Der Restore erkennt beim Entpacken ob der Ziel-User ein anderer ist und patcht:
- `~/.hermes/.env` → Pfade zum neuen Home
- `~/.hermes/config.yaml` → User-Referenzen
- `~/.bashrc` → PS1, Aliase mit altem Usernamen

## Was wird gebackupt

| Pfad | Enthalten | Hinweis |
|---|---|---|
| `.hermes/config.yaml` | ✅ | Hauptkonfiguration |
| `.hermes/.env` | ✅ | Secrets, API-Keys, Tokens |
| `.hermes/auth.json` | ✅ | Authentifizierung |
| `.hermes/channel_directory.json` | ✅ | Channel-Mappings |
| `.hermes/skills/` | ✅ | Custom Skills |
| `.hermes/plugins/` | ✅ | Custom Plugins |
| `.hermes/cron/` | ✅ | Cron-Job Definitionen |
| `.hermes/memories/` | ✅ | User-Profile, Memory-Files |
| `.hermes/node/` | ⚠️ optional | Node.js + globale npm-Pakete (an/aus via --include-node) |
| `.ssh/` | ✅ | SSH-Keys (public+private) |
| `.bashrc`, `.profile` | ✅ | Shell-Config |
| `bin/` | ✅ | Custom Scripts |
| `playwright browsers` | ❌ | Wird via `playwright install` neu geladen |
| `pip packages` | ❌ | Wird via `pip install` neu geladen |

## Restore: automatische Patches

Beim Restore auf einen anderen User patcht das Script automatisch:

1. **`.env`**: Ersetzt `/home/alteruser/` → `/home/neueruser/`
2. **`config.yaml`**: Ersetzt alte Home-Pfade
3. **`auth.json`**: Prüft ob Pfade vorhanden sind und patcht
4. **Shell-Files**: `.bashrc` / `.profile` Pfad-Anpassungen
5. **SSH**: Setzt korrekte Permissions (`chmod 600`, `700`)

Danach wird empfohlen:
```bash
hermes setup    # Hermes neu registrieren (falls nötig)
hermes restart  # Hermes-Daemon neustarten
```

## Pitfalls

- **Secrets**: `.env` enthält API-Keys — Archiv sicher aufbewahren!
- **Channel-IDs**: `channel_directory.json` enthält Telegram/Discord Chat-IDs — bleiben beim Restore erhalten
- **Node.js**: `--include-node` packt ~200MB — nur wenn kein Internet für `npm install -g playwright` verfügbar
- **Playwright**: Browser-Binaries werden NIEMALS gebackupt (~600MB) — nach Restore `playwright install` laufen lassen
- **Root-Rechte**: Für Restore in fremdes Home wird `sudo` benötigt
- **Laufender Hermes**: Vor Restore besser stoppen (`hermes stop`), damit keine Dateien gleichzeitig geschrieben werden