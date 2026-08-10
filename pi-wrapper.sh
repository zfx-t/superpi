#!/usr/bin/env bash
# SuperPi launcher for Linux.
# Injects --system-prompt <file> (+ --no-context-files by default) for normal pi sessions.
# Management subcommands and --stock-prompt keep the stock prompt.
# Prefer file-path injection (Pi resolvePromptInput reads files) over huge argv strings.

set -euo pipefail

SUPERPI_ROOT="${SUPERPI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

log_debug() {
  if [[ "${SUPERPI_DEBUG:-}" == "1" ]]; then
    printf 'superpi: %s\n' "$*" >&2
  fi
}

find_native_pi() {
  if [[ -n "${PI_NATIVE:-}" ]]; then
    printf '%s\n' "$PI_NATIVE"
    return 0
  fi

  local pi_home="${PI_HOME:-$HOME/.pi}"
  local marker="$pi_home/superpi/native-pi.path"
  if [[ -f "$marker" ]]; then
    local recorded
    recorded="$(tr -d '\r\n' <"$marker")"
    if [[ -n "$recorded" && -x "$recorded" ]]; then
      local real_self real_recorded
      real_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
      real_recorded="$(readlink -f "$recorded" 2>/dev/null || printf '%s' "$recorded")"
      if [[ "$real_self" != "$real_recorded" ]]; then
        printf '%s\n' "$recorded"
        return 0
      fi
    fi
  fi

  local candidate
  for candidate in \
    "$pi_home/bin/pi" \
    "$HOME/.local/bin/pi.native" \
    "$HOME/ForMe/bin/pi" \
    "/usr/local/bin/pi"; do
    if [[ -x "$candidate" ]]; then
      local real_self real_cand
      real_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
      real_cand="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      if [[ "$real_self" != "$real_cand" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done

  local resolved
  if resolved="$(type -P pi 2>/dev/null)" && [[ -n "$resolved" && -x "$resolved" ]]; then
    local real_self real_resolved
    real_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    real_resolved="$(readlink -f "$resolved" 2>/dev/null || printf '%s' "$resolved")"
    if [[ "$real_self" != "$real_resolved" ]]; then
      # Skip PATH shims that point back at this wrapper.
      if [[ "$real_resolved" == *"/superpi/pi-wrapper.sh" ]]; then
        :
      else
        printf '%s\n' "$resolved"
        return 0
      fi
    fi
  fi

  return 1
}

is_management_command() {
  local arg lower
  local -a management=(
    install remove uninstall update list config auth
    help version
  )
  for arg in "$@"; do
    [[ "$arg" == -* ]] && continue
    lower="${arg,,}"
    local cmd
    for cmd in "${management[@]}"; do
      if [[ "$lower" == "$cmd" ]]; then
        return 0
      fi
    done
    return 1
  done
  return 1
}

is_meta_flag_only() {
  local arg
  local -a meta=(--help -h --version -v --list-models --export)
  for arg in "$@"; do
    local m
    for m in "${meta[@]}"; do
      if [[ "$arg" == "$m" || "$arg" == "$m"=* ]]; then
        return 0
      fi
    done
  done
  return 1
}

has_explicit_system_prompt() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --system-prompt|--system-prompt=*|--append-system-prompt|--append-system-prompt=*)
        return 0
        ;;
    esac
  done
  return 1
}

has_no_context_files_flag() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --no-context-files|-nc) return 0 ;;
    esac
  done
  return 1
}

resolve_prompt_file() {
  local prompt_path="${SUPERPI_PROMPT_FILE:-}"
  if [[ -n "$prompt_path" && -f "$prompt_path" ]]; then
    printf '%s\n' "$prompt_path"
    return 0
  fi
  if [[ -f "$SUPERPI_ROOT/pi-unrestricted.md" ]]; then
    printf '%s\n' "$SUPERPI_ROOT/pi-unrestricted.md"
    return 0
  fi
  local pi_home="${PI_HOME:-$HOME/.pi}"
  if [[ -f "$pi_home/superpi/pi-unrestricted.md" ]]; then
    printf '%s\n' "$pi_home/superpi/pi-unrestricted.md"
    return 0
  fi
  if [[ -f "$pi_home/agent/SYSTEM.md" ]]; then
    printf '%s\n' "$pi_home/agent/SYSTEM.md"
    return 0
  fi
  return 1
}

strip_conflicting_rule_sections() {
  awk '
    BEGIN { skip = 0 }
    /^## Safety[[:space:]]*$/ { skip = 1; next }
    /^## Safe Capability Boost[[:space:]]*$/ { skip = 1; next }
    /^## / {
      if (skip) skip = 0
    }
    !skip { print }
  '
}

collect_runtime_rules() {
  local effective_cwd="$1"
  local pi_home="${PI_HOME:-$HOME/.pi}"
  local agent_dir="${PI_AGENT_DIR:-$pi_home/agent}"
  local -a recognized=(Agents.md Claude.md AGENT.md AGENTS.md AGENTS.override.md CLAUDE.md)
  local -a rule_files=()
  local name candidate resolved dir

  for name in "${recognized[@]}"; do
    candidate="$agent_dir/$name"
    if [[ -f "$candidate" ]]; then
      resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      rule_files+=("$resolved")
    fi
  done

  local git_root=""
  if git_root="$(git -C "$effective_cwd" rev-parse --show-toplevel 2>/dev/null)"; then
    git_root="$(readlink -f "$git_root" 2>/dev/null || printf '%s' "$git_root")"
  else
    git_root=""
  fi

  local -a rule_dirs=()
  if [[ -n "$git_root" ]]; then
    local cursor="$effective_cwd"
    local -a reverse=()
    while true; do
      reverse+=("$cursor")
      if [[ "$cursor" == "$git_root" ]]; then
        break
      fi
      local parent
      parent="$(dirname "$cursor")"
      if [[ -z "$parent" || "$parent" == "$cursor" ]]; then
        break
      fi
      case "$parent" in
        "$git_root"|"$git_root"/*) cursor="$parent" ;;
        *) break ;;
      esac
    done
    local i
    for ((i = ${#reverse[@]} - 1; i >= 0; i--)); do
      rule_dirs+=("${reverse[i]}")
    done
  else
    rule_dirs=("$effective_cwd")
  fi

  for dir in "${rule_dirs[@]}"; do
    for name in "${recognized[@]}"; do
      candidate="$dir/$name"
      if [[ -f "$candidate" ]]; then
        resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
        local seen=0 existing
        for existing in "${rule_files[@]+"${rule_files[@]}"}"; do
          if [[ "$existing" == "$resolved" ]]; then
            seen=1
            break
          fi
        done
        if [[ $seen -eq 0 ]]; then
          rule_files+=("$resolved")
        fi
      fi
    done
  done

  local runtime="" rule_index=0 rule_text label remaining
  local max_total=16000
  for resolved in "${rule_files[@]+"${rule_files[@]}"}"; do
    if ((${#runtime} >= max_total)); then
      break
    fi
    rule_index=$((rule_index + 1))
    rule_text="$(strip_conflicting_rule_sections <"$resolved")"
    remaining=$((max_total - ${#runtime}))
    if ((${#rule_text} > remaining)); then
      rule_text="${rule_text:0:remaining}"
    fi
    label="$(basename "$resolved")"
    runtime+="===== rule ${rule_index}: ${label} ====="$'\n'
    runtime+="${rule_text}"$'\n'
  done

  printf '%s' "$runtime"
}

build_merged_prompt_file() {
  local base_path="$1"
  local runtime_rules="$2"
  local out_dir="${TMPDIR:-/tmp}"
  local out
  out="$(mktemp "$out_dir/superpi-prompt.XXXXXX.md")"
  {
    if [[ -n "$runtime_rules" ]]; then
      printf '<runtime_rules>\n%s</runtime_rules>\n\n' "$runtime_rules"
    fi
    cat "$base_path"
  } >"$out"
  printf '%s\n' "$out"
}

print_status() {
  local native prompt_path
  native="$(find_native_pi 2>/dev/null || true)"
  prompt_path="$(resolve_prompt_file 2>/dev/null || true)"
  cat <<EOF
SuperPi status
  wrapper:     ${BASH_SOURCE[0]}
  root:        $SUPERPI_ROOT
  native pi:   ${native:-NOT FOUND}
  prompt file: ${prompt_path:-NOT FOUND}
  extension:   ${PI_HOME:-$HOME/.pi}/agent/extensions/superpi-system-prompt.ts
  SYSTEM.md:   ${PI_HOME:-$HOME/.pi}/agent/SYSTEM.md
  stock env:   PI_STOCK_PROMPT=${PI_STOCK_PROMPT:-} SUPERPI_DISABLED=${SUPERPI_DISABLED:-}

Verify override (print mode):
  pi -p --no-session --no-tools --thinking off \\
    'Reply OVERRIDE_OK if system prompt starts with [MODE: UNRESTRICTED], else OVERRIDE_FAIL.'
EOF
}

main() {
  # Built-in superpi meta commands (do not require model).
  if [[ "${1:-}" == "--superpi-status" || "${1:-}" == "superpi-status" ]]; then
    print_status
    exit 0
  fi

  local native
  if ! native="$(find_native_pi)"; then
    echo "Set PI_NATIVE or install pi on PATH (e.g. npm i -g @earendil-works/pi-coding-agent)." >&2
    exit 1
  fi
  if [[ ! -x "$native" ]]; then
    echo "Pi binary not executable: $native" >&2
    exit 1
  fi

  local stock_prompt=0
  local self_base
  self_base="$(basename "$0")"
  if [[ "$self_base" == "pi-stock" ]]; then
    stock_prompt=1
  fi

  local -a filtered_args=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--stock-prompt" ]]; then
      stock_prompt=1
      continue
    fi
    filtered_args+=("$arg")
  done

  if [[ "${PI_STOCK_PROMPT:-}" == "1" || "${SUPERPI_STOCK_PROMPT:-}" == "1" ]]; then
    stock_prompt=1
  fi

  local -a effective_args=()
  local cleanup_prompt=""

  if [[ $stock_prompt -eq 1 ]]; then
    # Disable extension + force empty custom prompt so SYSTEM.md is not used.
    export SUPERPI_DISABLED=1
    export PI_STOCK_PROMPT=1
    # Empty CLI system prompt: resource-loader keeps "" source, resolvePromptInput
    # returns undefined → Pi builds default coding assistant prompt.
    effective_args+=(--system-prompt "")
    log_debug "stock mode: SUPERPI_DISABLED=1, empty --system-prompt"
  elif ! has_explicit_system_prompt "${filtered_args[@]+"${filtered_args[@]}"}" \
    && ! is_management_command "${filtered_args[@]+"${filtered_args[@]}"}" \
    && ! is_meta_flag_only "${filtered_args[@]+"${filtered_args[@]}"}"; then

    local prompt_path
    if ! prompt_path="$(resolve_prompt_file)"; then
      echo "SuperPi prompt not found. Re-run install.sh or set SUPERPI_PROMPT_FILE." >&2
      exit 1
    fi

    local effective_cwd
    if [[ -n "${SUPERPI_CWD:-}" && -d "${SUPERPI_CWD}" ]]; then
      effective_cwd="$(cd "$SUPERPI_CWD" && pwd)"
    else
      effective_cwd="$(pwd)"
    fi

    local runtime_rules=""
    if [[ "${SUPERPI_INCLUDE_PROJECT_RULES:-}" == "1" ]]; then
      runtime_rules="$(collect_runtime_rules "$effective_cwd")"
    fi

    local inject_path="$prompt_path"
    if [[ -n "$runtime_rules" ]]; then
      inject_path="$(build_merged_prompt_file "$prompt_path" "$runtime_rules")"
      cleanup_prompt="$inject_path"
    fi

    # Pass as file path — Pi resolvePromptInput reads existing paths as files.
    effective_args+=(--system-prompt "$inject_path")
    log_debug "inject --system-prompt $inject_path"

    if [[ "${SUPERPI_KEEP_CONTEXT_FILES:-}" != "1" ]] \
      && ! has_no_context_files_flag "${filtered_args[@]+"${filtered_args[@]}"}"; then
      effective_args+=(--no-context-files)
      log_debug "inject --no-context-files"
    fi

    # Signal extension (also active by default when installed).
    export SUPERPI_PROMPT_FILE="${SUPERPI_PROMPT_FILE:-$prompt_path}"
    unset SUPERPI_DISABLED 2>/dev/null || true
  fi

  if ((${#filtered_args[@]} > 0)); then
    effective_args+=("${filtered_args[@]}")
  fi

  if [[ -n "${SUPERPI_PROXY:-}" ]]; then
    export HTTP_PROXY="$SUPERPI_PROXY"
    export HTTPS_PROXY="$SUPERPI_PROXY"
    export ALL_PROXY="$SUPERPI_PROXY"
    if [[ -n "${SUPERPI_NO_PROXY:-}" ]]; then
      if [[ -n "${NO_PROXY:-}" ]]; then
        export NO_PROXY="${NO_PROXY},${SUPERPI_NO_PROXY}"
      else
        export NO_PROXY="$SUPERPI_NO_PROXY"
      fi
    fi
  fi

  if [[ -n "$cleanup_prompt" ]]; then
    # Remove temp merged prompt after pi exits.
    # shellcheck disable=SC2064
    trap 'rm -f "$cleanup_prompt"' EXIT
  fi

  log_debug "exec $native ${effective_args[*]:0:6}..."
  exec "$native" "${effective_args[@]+"${effective_args[@]}"}"
}

main "$@"
