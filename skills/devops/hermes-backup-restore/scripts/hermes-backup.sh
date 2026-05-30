#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Hermes Backup & Restore
# ──────────────────────────────────────────────
# Backup:   hermes-backup backup [ziel]
# Restore:  hermes-backup restore <archiv> [--target /home/benutzer]
# Dry-Run:  hermes-backup backup --dry-run
#
# (c) 2026 Bitbull Open Source — MIT License
# ──────────────────────────────────────────────

VERSION="1.0.0"
HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
DATE="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
INCLUDE_NODE=false
TARGET_HOME="${HOME}"

usage() {
    cat <<EOF
Usage:
  hermes-backup backup [ziel] [--dry-run] [--include-node]
  hermes-backup restore <archiv> [--target /home/user]

Options:
  --dry-run       Nur auflisten, nichts packen (backup only)
  --include-node  Node.js + globale npm-Pakete mitbackupen (ca. +200MB)
  --target PATH   Ziel-Home für Restore (default: aktuelles \$HOME)

Examples:
  hermes-backup backup
  hermes-backup backup /tmp/hermes-sicherung.tar.gz
  hermes-backup backup --dry-run
  hermes-backup restore ~/hermes-backup-dgx-20260530.tar.gz
  sudo hermes-backup restore /tmp/backup.tar.gz --target /home/neueruser
EOF
    exit 1
}

# ── Argumente parsen ─────────────────────────
MODE=""
ARCHIVE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        backup)       MODE="backup"; shift ;;
        restore)      MODE="restore"; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --include-node) INCLUDE_NODE=true; shift ;;
        --target)     TARGET_HOME="$2"; shift 2 ;;
        --target=*)   TARGET_HOME="${1#*=}"; shift ;;
        -h|--help)    usage ;;
        -*)
            echo "❌ Unbekannte Option: $1"
            usage
            ;;
        *)
            ARCHIVE="$1"
            shift
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "❌ Bitte 'backup' oder 'restore' angeben."
    usage
fi

# ──────────────────────────────────────────────
# BACKUP
# ──────────────────────────────────────────────
do_backup() {
    local src="${HOME}"
    local default_archive="${src}/hermes-backup-${HOSTNAME}-${DATE}.tar.gz"
    local archive="${ARCHIVE:-${default_archive}}"
    local tmpfile
    tmpfile="$(mktemp /tmp/hermes-filelist-XXXXXX.txt)"
    trap "rm -f '${tmpfile}'" EXIT

    echo "🔍 Hermes Backup v${VERSION} — ${HOSTNAME} — ${DATE}"
    echo "   Source: ${src}"
    echo "   Target: ${archive}"
    [[ "$DRY_RUN" == true ]] && echo "   ⚠️  DRY-RUN — keine Dateien werden gepackt"
    echo ""

    # ── File-Liste bauen ──
    local files=()

    # Config & Secrets
    [[ -f "${src}/.hermes/config.yaml" ]]            && files+=(".hermes/config.yaml")
    [[ -f "${src}/.hermes/.env" ]]                   && files+=(".hermes/.env")
    [[ -f "${src}/.hermes/auth.json" ]]               && files+=(".hermes/auth.json")
    [[ -f "${src}/.hermes/channel_directory.json" ]]  && files+=(".hermes/channel_directory.json")

    # Skills, Plugins, Cron, Memories
    [[ -d "${src}/.hermes/skills" ]]      && files+=(".hermes/skills")
    [[ -d "${src}/.hermes/plugins" ]]     && files+=(".hermes/plugins")
    [[ -d "${src}/.hermes/cron" ]]        && files+=(".hermes/cron")
    [[ -d "${src}/.hermes/memories" ]]    && files+=(".hermes/memories")

    # Optional: Node.js
    if [[ "$INCLUDE_NODE" == true ]]; then
        if [[ -d "${src}/.hermes/node" ]]; then
            files+=(".hermes/node")
            echo "   📦 Node.js inkludiert"
        else
            echo "   ⚠️  --include-node gesetzt, aber ~/.hermes/node existiert nicht"
        fi
    fi

    # SSH
    if [[ -d "${src}/.ssh" ]]; then
        local ssh_files=()
        while IFS= read -r -d '' f; do
            local rel="${f#${src}/}"
            ssh_files+=("${rel}")
        done < <(find "${src}/.ssh" -maxdepth 1 -type f \( -name "id_*" -o -name "authorized_keys" -o -name "config" -o -name "known_hosts" \) -print0)
        if [[ ${#ssh_files[@]} -gt 0 ]]; then
            files+=("${ssh_files[@]}")
        fi
    fi

    # Shell-Config
    [[ -f "${src}/.bashrc" ]]    && files+=(".bashrc")
    [[ -f "${src}/.bash_profile" ]] && files+=(".bash_profile")
    [[ -f "${src}/.profile" ]]   && files+=(".profile")
    [[ -f "${src}/.bash_logout" ]] && files+=(".bash_logout")

    # Custom Scripts
    if [[ -d "${src}/bin" ]]; then
        files+=("bin")
    fi

    # ── Dateien auflisten ──
    printf "%s\n" "${files[@]}" | sort > "${tmpfile}"

    local count
    count=$(wc -l < "${tmpfile}")
    echo "   📋 ${count} Einträge in der Backup-Liste"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo "── Dateien ──────────────────────────────"
        cat "${tmpfile}"
        echo "──────────────────────────────────────────"
        local total_size=0
        while IFS= read -r f; do
            if [[ -f "${src}/${f}" ]]; then
                sz=$(stat -c%s "${src}/${f}" 2>/dev/null || echo 0)
                total_size=$((total_size + sz))
            elif [[ -d "${src}/${f}" ]]; then
                sz=$(du -sb "${src}/${f}" 2>/dev/null | cut -f1 || echo 0)
                total_size=$((total_size + sz))
            fi
        done < "${tmpfile}"
        echo ""
        echo "   Geschätzte Grösse: $(numfmt --to=iec "${total_size}" 2>/dev/null || echo "${total_size} bytes")"
        return 0
    fi

    # ── Packen ──
    echo "   📦 Packe Archiv..."
    tar czf "${archive}" \
        --owner=0 --group=0 \
        --transform "s|^|hermes-backup-${HOSTNAME}-${DATE}/|" \
        --files-from "${tmpfile}" \
        -C "${src}" 2>&1

    local archive_size
    archive_size=$(stat -c%s "${archive}" 2>/dev/null || echo 0)
    echo ""
    echo "✅ Backup fertig: ${archive}"
    echo "   Größe: $(numfmt --to=iec "${archive_size}" 2>/dev/null || echo "${archive_size} bytes")"
    echo ""
    echo "⚠️  Wichtig: Archiv sicher aufbewahren — enthält API-Keys und Secrets!"
}

# ──────────────────────────────────────────────
# RESTORE
# ──────────────────────────────────────────────
do_restore() {
    local archive="${ARCHIVE:-}"
    local target="${TARGET_HOME}"

    if [[ -z "$archive" ]]; then
        echo "❌ Kein Archiv angegeben."
        echo "   Usage: hermes-backup restore <archiv.tar.gz> [--target /home/user]"
        exit 1
    fi

    if [[ ! -f "$archive" ]]; then
        echo "❌ Archiv nicht gefunden: ${archive}"
        exit 1
    fi

    if [[ ! -d "$target" ]]; then
        echo "❌ Zielverzeichnis existiert nicht: ${target}"
        exit 1
    fi

    echo "🔧 Hermes Restore v${VERSION}"
    echo "   Archiv: ${archive}"
    echo "   Ziel:   ${target}"
    echo ""

    # ── Top-Level-Dir im Archiv ermitteln ──
    local topdir
    topdir=$(tar tzf "${archive}" | head -1 | cut -d/ -f1)
    if [[ -z "$topdir" ]]; then
        echo "❌ Leeres Archiv oder nicht lesbar."
        exit 1
    fi

    # ── Extraktion ──
    echo "   📦 Extrahiere Archiv..."
    tar xzf "${archive}" -C "${target}"

    local src_prefix="${target}/${topdir}"

    if [[ ! -d "$src_prefix" ]]; then
        echo "❌ Extraktionsordner nicht gefunden: ${src_prefix}"
        exit 1
    fi

    # ── Verschiebe Inhalt ins Home ──
    echo "   🔄 Verschiebe Dateien nach ${target}..."
    # rsync-artig: mv den Inhalt, nicht den Container-Ordner
    shopt -s dotglob
    for item in "${src_prefix}"/*; do
        local name
        name=$(basename "${item}")
        # Überspringe wenn Ziel bereits existiert — user hat bewusst entschieden
        # Bei .hermes/ jedoch ist das der Normalfall, also merge
        if [[ -e "${target}/${name}" && "${name}" == ".hermes" ]]; then
            # Für .hermes: kopieren ohne existierende Dateien zu überschreiben
            cp -rn "${item}/." "${target}/${name}/" 2>/dev/null || true
        elif [[ -e "${target}/${name}" ]]; then
            echo "   ⚠️  Überspringe ${name} (existiert bereits in ${target})"
        else
            mv "${item}" "${target}/"
        fi
    done
    shopt -u dotglob

    # Container-Ordner löschen
    rmdir "${src_prefix}" 2>/dev/null || true

    # ── User-Referenzen patchen ──
    local old_user=""
    local new_user
    new_user=$(basename "$target")

    # Alten Usernamen aus Archiv-Pfaden raten
    # Suche nach /home/xxx/ in .env
    if [[ -f "${target}/.hermes/.env" ]]; then
        old_user=$(grep -oP "/home/\K[^/]+(?=/)" "${target}/.hermes/.env" | head -1 || true)
    fi

    if [[ -z "$old_user" ]]; then
        # Fallback: aus config.yaml
        if [[ -f "${target}/.hermes/config.yaml" ]]; then
            old_user=$(grep -oP "/home/\K[^/]+(?=/)" "${target}/.hermes/config.yaml" | head -1 || true)
        fi
    fi

    if [[ -n "$old_user" && "$old_user" != "$new_user" ]]; then
        echo ""
        echo "   🔄 User-Migration erkannt: $old_user → $new_user"
        echo "   Passe Pfade in Konfigurationsdateien an..."

        # .env
        if [[ -f "${target}/.hermes/.env" ]]; then
            sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "${target}/.hermes/.env"
            echo "      ✓ .env: Pfade aktualisiert"
        fi

        # config.yaml
        if [[ -f "${target}/.hermes/config.yaml" ]]; then
            sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "${target}/.hermes/config.yaml"
            echo "      ✓ config.yaml: Pfade aktualisiert"
        fi

        # auth.json
        if [[ -f "${target}/.hermes/auth.json" ]]; then
            sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "${target}/.hermes/auth.json"
            echo "      ✓ auth.json: Pfade aktualisiert"
        fi

        # channel_directory.json
        if [[ -f "${target}/.hermes/channel_directory.json" ]]; then
            sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "${target}/.hermes/channel_directory.json"
            echo "      ✓ channel_directory.json: Pfade aktualisiert"
        fi

        # Shell configs
        for f in .bashrc .bash_profile .profile; do
            if [[ -f "${target}/${f}" ]]; then
                sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "${target}/${f}"
                echo "      ✓ ${f}: Pfade aktualisiert"
            fi
        done

        # SSH config
        if [[ -f "${target}/.ssh/config" ]]; then
            sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "${target}/.ssh/config"
            echo "      ✓ .ssh/config: Pfade aktualisiert"
        fi

        # Alle anderen .hermes Files scannen (skills, plugins, cron, memories)
        while IFS= read -r f; do
            if [[ -f "$f" ]] && file "$f" | grep -q "text"; then
                sed -i "s|/home/${old_user}/|/home/${new_user}/|g" "$f"
            fi
        done < <(find "${target}/.hermes" -type f 2>/dev/null)
        echo "      ✓ .hermes/*: restliche Pfade aktualisiert"
    fi

    # ── Permissions setzen ──
    echo ""
    echo "   🔒 Setze Permissions..."
    # SSH-Keys: strenge Permissions
    if [[ -d "${target}/.ssh" ]]; then
        chmod 700 "${target}/.ssh"
        find "${target}/.ssh" -type f -name "id_*" -exec chmod 600 {} \;
        find "${target}/.ssh" -type f -name "authorized_keys" -exec chmod 600 {} \;
        find "${target}/.ssh" -type f -name "config" -exec chmod 600 {} \;
        find "${target}/.ssh" -type f -name "known_hosts" -exec chmod 644 {} \;
        echo "      ✓ SSH-Keys: Permissions korrigiert"
    fi

    # .env niemals world-readable
    if [[ -f "${target}/.hermes/.env" ]]; then
        chmod 600 "${target}/.hermes/.env"
        echo "      ✓ .env: chmod 600"
    fi
    if [[ -f "${target}/.hermes/auth.json" ]]; then
        chmod 600 "${target}/.hermes/auth.json"
        echo "      ✓ auth.json: chmod 600"
    fi

    # Ownership falls mit sudo ausgeführt
    if [[ "$EUID" -eq 0 && -n "$new_user" ]]; then
        local ug
        ug=$(id -un "$new_user" 2>/dev/null || echo "")
        if [[ -n "$ug" ]]; then
            chown -R "${ug}:${ug}" "${target}/.hermes" "${target}/.ssh" "${target}/bin" "${target}/.bashrc" "${target}/.bash_profile" "${target}/.profile" 2>/dev/null || true
            echo "      ✓ Ownership: ${ug}:${ug}"
        fi
    fi

    echo ""
    echo "✅ Restore abgeschlossen in: ${target}"
    echo ""
    echo "🔜 Nächste Schritte:"
    echo "   1. hermes restart        # Hermes-Daemon neustarten"
    echo "   2. playwright install    # Playwright-Browser nachladen (falls nötig)"
    echo "   3. hermes setup          # ggf. neu registrieren"
}

# ──────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────
case "$MODE" in
    backup)  do_backup  ;;
    restore) do_restore ;;
    *)
        echo "❌ Unbekannter Modus: ${MODE}"
        usage
        ;;
esac
