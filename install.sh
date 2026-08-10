#!/usr/bin/env bash
# Install SuperPi for Linux: prompt + wrapper + extension + shell integration.
# Usage:
#   ./install.sh
#   ./install.sh --shell fish|bash|zsh|all
#   ./install.sh --no-system-md
#   PI_HOME=~/.pi ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_HOME="${PI_HOME:-$HOME/.pi}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INSTALL_DIR="$PI_HOME/superpi"
BACKUP_DIR="$PI_HOME/backups/superpi-$TIMESTAMP"
PROMPT_SOURCE="$SCRIPT_DIR/pi-unrestricted.md"
WRAPPER_SOURCE="$SCRIPT_DIR/pi-wrapper.sh"
EXT_SOURCE="$SCRIPT_DIR/extensions/superpi-system-prompt.ts"
PROMPT_DEST="$INSTALL_DIR/pi-unrestricted.md"
WRAPPER_DEST="$INSTALL_DIR/pi-wrapper.sh"
EXT_DEST="$PI_HOME/agent/extensions/superpi-system-prompt.ts"
NATIVE_MARKER="$INSTALL_DIR/native-pi.path"
SYSTEM_MD_DEST="$PI_HOME/agent/SYSTEM.md"
PATH_SHIM="$HOME/.local/bin/pi"
PATH_NATIVE="$HOME/.local/bin/pi.native"

SHELL_TARGET="auto"
INSTALL_SYSTEM_MD=1
INSTALL_EXTENSION=1
INSTALL_PATH_SHIM=1
PI_NATIVE_ARG=""

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --shell fish|bash|zsh|all   Which shell config to update (default: auto)
  --pi-home PATH              Install root (default: $PI_HOME or ~/.pi)
  --pi-native PATH            Record native pi binary path
  --no-system-md              Do not write ~/.pi/agent/SYSTEM.md
  --no-extension              Do not install global before_agent_start extension
  --no-path-shim              Do not install ~/.local/bin/pi wrapper shim
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)
      SHELL_TARGET="${2:-}"
      shift 2
      ;;
    --pi-home)
      PI_HOME="${2:-}"
      INSTALL_DIR="$PI_HOME/superpi"
      BACKUP_DIR="$PI_HOME/backups/superpi-$TIMESTAMP"
      PROMPT_DEST="$INSTALL_DIR/pi-unrestricted.md"
      WRAPPER_DEST="$INSTALL_DIR/pi-wrapper.sh"
      EXT_DEST="$PI_HOME/agent/extensions/superpi-system-prompt.ts"
      NATIVE_MARKER="$INSTALL_DIR/native-pi.path"
      SYSTEM_MD_DEST="$PI_HOME/agent/SYSTEM.md"
      shift 2
      ;;
    --pi-native)
      PI_NATIVE_ARG="${2:-}"
      shift 2
      ;;
    --no-system-md)
      INSTALL_SYSTEM_MD=0
      shift
      ;;
    --no-extension)
      INSTALL_EXTENSION=0
      shift
      ;;
    --no-path-shim)
      INSTALL_PATH_SHIM=0
      shift
      ;;
    --install-system-md)
      # backward compatible alias (now default)
      INSTALL_SYSTEM_MD=1
      shift
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

for path in "$PROMPT_SOURCE" "$WRAPPER_SOURCE" "$EXT_SOURCE"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing source file: $path" >&2
    exit 1
  fi
done

discover_native_pi() {
  if [[ -n "$PI_NATIVE_ARG" && -x "$PI_NATIVE_ARG" ]]; then
    printf '%s\n' "$PI_NATIVE_ARG"
    return 0
  fi
  if [[ -n "${PI_NATIVE:-}" && -x "${PI_NATIVE}" ]]; then
    printf '%s\n' "$PI_NATIVE"
    return 0
  fi
  # Prefer real native over an old SuperPi shim.
  if [[ -x "$PATH_NATIVE" ]]; then
    printf '%s\n' "$PATH_NATIVE"
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/ForMe/bin/pi" \
    "$HOME/.local/bin/pi" \
    "$PI_HOME/bin/pi" \
    "/usr/local/bin/pi"; do
    if [[ -x "$candidate" ]]; then
      # Skip if candidate is already our wrapper.
      if grep -q 'SuperPi launcher' "$candidate" 2>/dev/null; then
        continue
      fi
      if [[ "$(readlink -f "$candidate" 2>/dev/null || true)" == *"/superpi/pi-wrapper.sh" ]]; then
        continue
      fi
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  local resolved
  if resolved="$(type -P pi 2>/dev/null)" && [[ -n "$resolved" && -x "$resolved" ]]; then
    if ! grep -q 'SuperPi launcher' "$resolved" 2>/dev/null; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi
  return 1
}

mkdir -p "$INSTALL_DIR" "$BACKUP_DIR" "$PI_HOME/agent/extensions"

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    local base
    base="$(basename "$path")"
    # Avoid collisions for nested names
    local stamp
    stamp="$(echo "$path" | tr '/' '_' | sed 's/^_//')"
    cp -a "$path" "$BACKUP_DIR/$base"
  fi
}

backup_if_exists "$PROMPT_DEST"
backup_if_exists "$WRAPPER_DEST"
backup_if_exists "$NATIVE_MARKER"
backup_if_exists "$EXT_DEST"

cp -f "$PROMPT_SOURCE" "$PROMPT_DEST"
cp -f "$WRAPPER_SOURCE" "$WRAPPER_DEST"
chmod +x "$WRAPPER_DEST"

if native_path="$(discover_native_pi)"; then
  printf '%s\n' "$native_path" >"$NATIVE_MARKER"
  echo "Recorded native pi: $native_path"
else
  echo "Warning: native pi not found. Set PI_NATIVE or re-run with --pi-native PATH." >&2
  rm -f "$NATIVE_MARKER"
  native_path=""
fi

if [[ $INSTALL_SYSTEM_MD -eq 1 ]]; then
  backup_if_exists "$SYSTEM_MD_DEST"
  cp -f "$PROMPT_SOURCE" "$SYSTEM_MD_DEST"
  echo "Installed SYSTEM.md: $SYSTEM_MD_DEST"
fi

if [[ $INSTALL_EXTENSION -eq 1 ]]; then
  cp -f "$EXT_SOURCE" "$EXT_DEST"
  echo "Installed extension: $EXT_DEST"
fi

if [[ $INSTALL_PATH_SHIM -eq 1 ]]; then
  mkdir -p "$HOME/.local/bin"
  if [[ -n "${native_path:-}" && -x "$native_path" ]]; then
    # Preserve a direct native entrypoint for stock/debugging.
    if [[ "$(readlink -f "$native_path")" != "$(readlink -f "$PATH_NATIVE" 2>/dev/null || true)" ]]; then
      if [[ ! -e "$PATH_NATIVE" ]]; then
        ln -sfn "$native_path" "$PATH_NATIVE"
        echo "Linked native: $PATH_NATIVE -> $native_path"
      fi
    fi
  fi
  ln -sfn "$WRAPPER_DEST" "$PATH_SHIM"
  ln -sfn "$WRAPPER_DEST" "$HOME/.local/bin/pi-stock"
  echo "PATH shim: $PATH_SHIM -> $WRAPPER_DEST"
  echo "PATH shim: $HOME/.local/bin/pi-stock"
fi

BASH_BLOCK=$(cat <<EOF

# >>> SUPERPI >>>
pi() {
  "$WRAPPER_DEST" "\$@"
}
pi-stock() {
  "$WRAPPER_DEST" --stock-prompt "\$@"
}
# <<< SUPERPI <<<
EOF
)

FISH_BLOCK=$(cat <<EOF

# >>> SUPERPI >>>
function pi
    "$WRAPPER_DEST" \$argv
end
function pi-stock
    "$WRAPPER_DEST" --stock-prompt \$argv
end
# <<< SUPERPI <<<
EOF
)

strip_existing_block() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk '
    /^# >>> SUPERPI >>>/ { skip=1; next }
    /^# <<< SUPERPI <<</ { skip=0; next }
    !skip { print }
  ' "$file" >"$tmp"
  if command -v sed >/dev/null 2>&1; then
    sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" >"${tmp}.2" 2>/dev/null || cp "$tmp" "${tmp}.2"
    mv "${tmp}.2" "$tmp"
  fi
  mv "$tmp" "$file"
}

install_to_profile() {
  local profile_path="$1"
  local block="$2"
  local profile_dir
  profile_dir="$(dirname "$profile_path")"
  mkdir -p "$profile_dir"

  if [[ -f "$profile_path" ]]; then
    backup_if_exists "$profile_path"
    strip_existing_block "$profile_path"
  else
    touch "$profile_path"
  fi

  if [[ -s "$profile_path" ]] && [[ -n "$(tail -c 1 "$profile_path" 2>/dev/null || true)" ]]; then
    printf '\n' >>"$profile_path"
  fi
  printf '%s\n' "$block" >>"$profile_path"
  echo "Updated profile: $profile_path"
}

detect_shells() {
  local shell_name
  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    fish) echo fish ;;
    zsh) echo zsh ;;
    bash|sh) echo bash ;;
    *) echo bash ;;
  esac
}

SHELLS_TO_INSTALL=()
case "$SHELL_TARGET" in
  auto)
    mapfile -t SHELLS_TO_INSTALL < <(detect_shells)
    if [[ "${SHELLS_TO_INSTALL[0]}" != "fish" && -f "$HOME/.config/fish/config.fish" ]]; then
      SHELLS_TO_INSTALL+=(fish)
    fi
    if [[ "${SHELLS_TO_INSTALL[0]}" != "bash" && -f "$HOME/.bashrc" ]]; then
      SHELLS_TO_INSTALL+=(bash)
    fi
    ;;
  all)
    SHELLS_TO_INSTALL=(bash zsh fish)
    ;;
  fish|bash|zsh)
    SHELLS_TO_INSTALL=("$SHELL_TARGET")
    ;;
  *)
    echo "Invalid --shell value: $SHELL_TARGET" >&2
    exit 1
    ;;
esac

declare -A seen_shells=()
unique_shells=()
for s in "${SHELLS_TO_INSTALL[@]}"; do
  if [[ -z "${seen_shells[$s]:-}" ]]; then
    seen_shells[$s]=1
    unique_shells+=("$s")
  fi
done
SHELLS_TO_INSTALL=("${unique_shells[@]}")

for s in "${SHELLS_TO_INSTALL[@]}"; do
  case "$s" in
    bash) install_to_profile "$HOME/.bashrc" "$BASH_BLOCK" ;;
    zsh) install_to_profile "$HOME/.zshrc" "$BASH_BLOCK" ;;
    fish) install_to_profile "$HOME/.config/fish/config.fish" "$FISH_BLOCK" ;;
  esac
done

cat <<EOF
Installed prompt:    $PROMPT_DEST
Installed wrapper:   $WRAPPER_DEST
Installed extension: $EXT_DEST (before_agent_start force)
Installed SYSTEM.md: $SYSTEM_MD_DEST (default on)
Backup:              $BACKUP_DIR

Reload your shell, then:

  pi                 # SuperPi prompt (wrapper + extension + SYSTEM.md)
  pi-stock           # stock Pi default prompt
  pi --superpi-status

Verify:

  pi -p --no-session --no-tools --thinking off \\
    'Reply OVERRIDE_OK if system prompt starts with [MODE: UNRESTRICTED], else OVERRIDE_FAIL.'

Notes:
  - Shell wrapper alone does NOT cover web-chat / non-shell entrypoints.
  - Global extension + SYSTEM.md cover those paths.
  - New session required; old sessions keep prior behavior.
  - Model/provider hard refusals can still fire even when OVERRIDE_OK.
EOF
