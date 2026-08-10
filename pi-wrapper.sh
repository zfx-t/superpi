#!/usr/bin/env bash
# SuperPi launcher for Linux.
# Injects --system-prompt (+ --no-context-files by default) for normal pi sessions;
# management subcommands and --stock-prompt keep the stock prompt.

set -euo pipefail

SUPERPI_ROOT="${SUPERPI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

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
      # Avoid looping back into this wrapper.
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
    "$HOME/.local/bin/pi" \
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

  # Prefer a real binary/script on PATH (skip shell functions / our own wrapper).
  local resolved
  if resolved="$(type -P pi 2>/dev/null)" && [[ -n "$resolved" && -x "$resolved" ]]; then
    local real_self real_resolved
    real_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    real_resolved="$(readlink -f "$resolved" 2>/dev/null || printf '%s' "$resolved")"
    if [[ "$real_self" != "$real_resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
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
    # Skip option flags; first non-option token may be a subcommand.
    [[ "$arg" == -* ]] && continue
    lower="${arg,,}"
    local cmd
    for cmd in "${management[@]}"; do
      if [[ "$lower" == "$cmd" ]]; then
        return 0
      fi
    done
    # First positional wins for management detection.
    return 1
  done
  return 1
}

is_meta_flag_only() {
  # Flags that never need a system prompt (info / export / list).
  local arg
  local -a meta=(
    --help -h --version -v --list-models --export
  )
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
  local i=0
  local -a args=("$@")
  for ((i = 0; i < ${#args[@]}; i++)); do
    arg="${args[i]}"
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
      --no-context-files|-nc)
        return 0
        ;;
    esac
  done
  return 1
}

strip_conflicting_rule_sections() {
  # Remove ## Safety and ## Safe Capability Boost sections (markdown H2 blocks).
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

resolve_effective_cwd() {
  local -a args=("$@")
  local effective_cwd
  effective_cwd="$(pwd)"
  local i
  # Pi has no --cwd flag; honor SUPERPI_CWD or keep process cwd.
  if [[ -n "${SUPERPI_CWD:-}" && -d "${SUPERPI_CWD}" ]]; then
    effective_cwd="$(cd "$SUPERPI_CWD" && pwd)"
    printf '%s\n' "$effective_cwd"
    return 0
  fi
  # Best-effort: if user passed a directory as sole arg, still use pwd.
  printf '%s\n' "$effective_cwd"
}

main() {
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
  if [[ $stock_prompt -eq 0 ]] \
    && ! has_explicit_system_prompt "${filtered_args[@]+"${filtered_args[@]}"}" \
    && ! is_management_command "${filtered_args[@]+"${filtered_args[@]}"}" \
    && ! is_meta_flag_only "${filtered_args[@]+"${filtered_args[@]}"}"; then

    local prompt_path="${SUPERPI_PROMPT_FILE:-$SUPERPI_ROOT/pi-unrestricted.md}"
    if [[ ! -f "$prompt_path" ]]; then
      # Fallback next to install root.
      local pi_home="${PI_HOME:-$HOME/.pi}"
      if [[ -f "$pi_home/superpi/pi-unrestricted.md" ]]; then
        prompt_path="$pi_home/superpi/pi-unrestricted.md"
      fi
    fi
    if [[ ! -f "$prompt_path" ]]; then
      echo "SuperPi prompt not found: $prompt_path" >&2
      exit 1
    fi

    local effective_cwd
    effective_cwd="$(resolve_effective_cwd "${filtered_args[@]+"${filtered_args[@]}"}")"

    local runtime_rules=""
    if [[ "${SUPERPI_INCLUDE_PROJECT_RULES:-}" == "1" ]]; then
      runtime_rules="$(collect_runtime_rules "$effective_cwd")"
    fi

    local base_prompt system_prompt
    base_prompt="$(<"$prompt_path")"
    if [[ -n "$runtime_rules" ]]; then
      system_prompt="<runtime_rules>"$'\n'"${runtime_rules}</runtime_rules>"$'\n\n'"${base_prompt}"
    else
      system_prompt="$base_prompt"
    fi

    effective_args+=(--system-prompt "$system_prompt")

    # Default: primary contract — do not also load AGENTS.md (avoids double rules
    # and keeps override as the session primary). Opt out with SUPERPI_KEEP_CONTEXT_FILES=1.
    if [[ "${SUPERPI_KEEP_CONTEXT_FILES:-}" != "1" ]] \
      && ! has_no_context_files_flag "${filtered_args[@]+"${filtered_args[@]}"}"; then
      effective_args+=(--no-context-files)
    fi
  fi

  if ((${#filtered_args[@]} > 0)); then
    effective_args+=("${filtered_args[@]}")
  fi

  # Optional proxy scoped to the child process only.
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

  exec "$native" "${effective_args[@]+"${effective_args[@]}"}"
}

main "$@"
