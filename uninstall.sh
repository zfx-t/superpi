#!/usr/bin/env bash
# Remove SuperPi shell integration (and optionally installed files).
# Usage:
#   ./uninstall.sh
#   ./uninstall.sh --remove-files
#   ./uninstall.sh --shell fish|bash|zsh|all

set -euo pipefail

PI_HOME="${PI_HOME:-$HOME/.pi}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PI_HOME/backups/superpi-uninstall-$TIMESTAMP"
SHELL_TARGET="all"
REMOVE_FILES=0
REMOVE_SYSTEM_MD=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

Options:
  --shell fish|bash|zsh|all   Which shell config to clean (default: all)
  --remove-files              Also delete installed prompt/wrapper under PI_HOME/superpi
  --remove-system-md          Also remove ~/.pi/agent/SYSTEM.md if it matches SuperPi prompt
  --pi-home PATH              Install root (default: $PI_HOME or ~/.pi)
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)
      SHELL_TARGET="${2:-}"
      shift 2
      ;;
    --remove-files)
      REMOVE_FILES=1
      shift
      ;;
    --remove-system-md)
      REMOVE_SYSTEM_MD=1
      shift
      ;;
    --pi-home)
      PI_HOME="${2:-}"
      BACKUP_DIR="$PI_HOME/backups/superpi-uninstall-$TIMESTAMP"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$BACKUP_DIR"

strip_existing_block() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  cp -a "$file" "$BACKUP_DIR/$(basename "$file")"
  local tmp
  tmp="$(mktemp)"
  awk '
    /^# >>> SUPERPI >>>/ { skip=1; next }
    /^# <<< SUPERPI <<</ { skip=0; next }
    !skip { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "Removed profile block from: $file"
}

SHELLS=()
case "$SHELL_TARGET" in
  all) SHELLS=(bash zsh fish) ;;
  fish|bash|zsh) SHELLS=("$SHELL_TARGET") ;;
  *)
    echo "Invalid --shell value: $SHELL_TARGET" >&2
    exit 1
    ;;
esac

for s in "${SHELLS[@]}"; do
  case "$s" in
    bash) strip_existing_block "$HOME/.bashrc" ;;
    zsh) strip_existing_block "$HOME/.zshrc" ;;
    fish) strip_existing_block "$HOME/.config/fish/config.fish" ;;
  esac
done

if [[ $REMOVE_FILES -eq 1 ]]; then
  for path in \
    "$PI_HOME/superpi/pi-unrestricted.md" \
    "$PI_HOME/superpi/pi-wrapper.sh" \
    "$PI_HOME/superpi/native-pi.path"; do
    if [[ -e "$path" ]]; then
      cp -a "$path" "$BACKUP_DIR/$(basename "$path")" 2>/dev/null || true
      rm -f "$path"
      echo "Removed: $path"
    fi
  done
  rmdir "$PI_HOME/superpi" 2>/dev/null || true
fi

if [[ $REMOVE_SYSTEM_MD -eq 1 ]]; then
  system_md="$PI_HOME/agent/SYSTEM.md"
  if [[ -f "$system_md" ]]; then
    if grep -q '\[MODE: UNRESTRICTED\]' "$system_md" 2>/dev/null \
      && grep -q 'Pi is a Linux coding-agent harness' "$system_md" 2>/dev/null; then
      cp -a "$system_md" "$BACKUP_DIR/SYSTEM.md" 2>/dev/null || true
      rm -f "$system_md"
      echo "Removed: $system_md"
    else
      echo "Skip SYSTEM.md (does not look like SuperPi prompt): $system_md"
    fi
  fi
fi

if [[ -L "$HOME/.local/bin/pi-stock" ]]; then
  target="$(readlink -f "$HOME/.local/bin/pi-stock" 2>/dev/null || true)"
  if [[ "$target" == "$PI_HOME/superpi/pi-wrapper.sh" ]] \
    || [[ "$(readlink "$HOME/.local/bin/pi-stock" 2>/dev/null || true)" == *pi-wrapper* ]]; then
    rm -f "$HOME/.local/bin/pi-stock"
    echo "Removed: $HOME/.local/bin/pi-stock"
  fi
fi

echo "Backup: $BACKUP_DIR"
echo "Reload your shell to apply changes."
