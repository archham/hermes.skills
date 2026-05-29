#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/install-skill.sh [--profile PROFILE] <category/skill-name>

Examples:
  scripts/install-skill.sh devops/hermes-log-watchdog
  scripts/install-skill.sh --profile myprofile devops/hermes-log-watchdog
USAGE
}

profile=""
if [[ "${1:-}" == "--profile" ]]; then
  profile="${2:-}"
  shift 2 || true
fi

skill_path="${1:-}"
if [[ -z "$skill_path" || "$skill_path" == "-h" || "$skill_path" == "--help" ]]; then
  usage
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo_root/skills/$skill_path"

if [[ ! -d "$src" ]]; then
  echo "ERROR: skill not found: $src" >&2
  exit 1
fi

if [[ ! -f "$src/SKILL.md" ]]; then
  echo "ERROR: missing SKILL.md in $src" >&2
  exit 1
fi

if [[ -n "$profile" ]]; then
  hermes_home="$HOME/.hermes/profiles/$profile"
else
  hermes_home="${HERMES_HOME:-$HOME/.hermes}"
fi

dest="$hermes_home/skills/$skill_path"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -a "$src" "$dest"

echo "Installed skill: $skill_path"
echo "Destination: $dest"
echo "Tip: start a new Hermes session or run /reload-skills where supported."
