# SuperPi vs SuppperGrok

| Item | SuppperGrok (Grok CLI) | SuperPi (Pi coding-agent) |
|------|------------------------|---------------------------|
| Override flag | `--system-prompt-override` | `--system-prompt` |
| Append | wrapper-merge only | `--append-system-prompt` / `APPEND_SYSTEM.md` |
| Built-in file override | (none official) | `SYSTEM.md` global/project |
| Context files | AGENTS via Grok rules | `AGENTS.md` / `CLAUDE.md` auto-append |
| Primary-contract default | override replaces stock | override + `--no-context-files` |
| Wrapper stock entry | `grok-stock` | `pi-stock` |
| Management skip | login/models/update/… | install/update/auth/config/list/… |
| Prompt-bank | `run_prompt_bank.py` + grok | same runner adapted for `pi -p` |

## Semantic alignment

SuperPi aims to mirror SuppperGrok's **launcher behavior**:

1. Normal interactive/print sessions get the unrestricted prompt as the **primary** system prompt.
2. Project rules are **opt-in** (`SUPERPI_INCLUDE_PROJECT_RULES=1`).
3. Management / meta flags skip injection.
4. Explicit `--system-prompt` on the CLI wins (no double inject).
5. Prompt-bank scores refusal / fallback markers, not open-ended semantic correctness.

## Pi-specific note

Even with `--system-prompt`, Pi still appends skills and `Current working directory`
when tools/skills are enabled. SuperPi's prompt text is rewritten for Pi tools
(`read` / `bash` / `edit` / `write` / …) rather than Grok Build tool names.
