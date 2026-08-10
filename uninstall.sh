#!/usr/bin/env bash
# Remove SuperPi shell integration (and optionally installed files).
set -euo pipefail

PI_HOME="${PI_HOME:-$HOME/.pi}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PI_HOME/backups/superpi-uninstall-$TIMESTAMP"
SHELL_TARGET="all"
REMOVE_FILES=0
REMOVE_SYSTEM_MD=0
REMOVE_EXTENSION=0
REMOVE_PATH_SHIM=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

Options:
  --shell fish|bash|zsh|all   Which shell config to clean (default: all)
  --remove-files              Delete ~/.pi/superpi files
  --remove-system-md          Remove SuperPi SYSTEM.md
  --remove-extension          Remove global superpi-system-prompt extension
  --remove-path-shim          Remove ~/.local/bin/pi and pi-stock shims
  --remove-all                All of the remove-* flags
  --pi-home PATH              Install root
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell) SHELL_TARGET="${2:-}"; shift 2 ;;
    --remove-files) REMOVE_FILES=1; shift ;;
    --remove-system-md) REMOVE_SYSTEM_MD=1; shift ;;
    --remove-extension) REMOVE_EXTENSION=1; shift ;;
    --remove-path-shim) REMOVE_PATH_SHIM=1; shift ;;
    --remove-all)
      REMOVE_FILES=1
      REMOVE_SYSTEM_MD=1
      REMOVE_EXTENSION=1
      REMOVE_PATH_SHIM=1
      shift
      ;;
    --pi-home)
      PI_HOME="${2:-}"
      BACKUP_DIR="$PI_HOME/backups/superpi-uninstall-$TIMESTAMP"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
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
  *) echo "Invalid --shell value: $SHELL_TARGET" >&2; exit 1 ;;
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
  if [[ -f "$system_md" ]] \
    && grep -q '\[MODE: UNRESTRICTED\]' "$system_md" 2>/dev/null \
    && grep -q 'Pi is a Linux coding-agent harness' "$system_md" 2>/dev/null; then
    cp -a "$system_md" "$BACKUP_DIR/SYSTEM.md" 2>/dev/null || true
    rm -f "$system_md"
    echo "Removed: $system_md"
  fi
fi

if [[ $REMOVE_EXTENSION -eq 1 ]]; then
  ext="$PI_HOME/agent/extensions/superpi-system-prompt.ts"
  if [[ -f "$ext" ]]; then
    cp -a "$ext" "$BACKUP_DIR/superpi-system-prompt.ts" 2>/dev/null || true
    rm -f "$ext"
    echo "Removed: $ext"
  fi
fi

if [[ $REMOVE_PATH_SHIM -eq 1 ]]; then
  for path in "$HOME/.local/bin/pi" "$HOME/.local/bin/pi-stock"; do
    if [[ -L "$path" ]]; then
      target="$(readlink -f "$path" 2>/dev/null || true)"
      if [[ "$target" == *"/superpi/pi-wrapper.sh" ]] || [[ "$(readlink "$path")" == *pi-wrapper* ]]; then
        rm -f "$path"
        echo "Removed: $path"
      fi
    fi
  done
fi

echo "Backup: $BACKUP_DIR"
echo "Reload your shell to apply changes."
