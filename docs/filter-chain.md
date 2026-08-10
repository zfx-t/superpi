# Pi prompt filtering chain

The observed chain has these relevant layers:

1. Pi's built-in default coding-assistant system prompt (tools, guidelines, docs paths).
2. Optional custom base from `--system-prompt`, `.pi/SYSTEM.md`, or `~/.pi/agent/SYSTEM.md`.
3. Optional append from `--append-system-prompt` / `APPEND_SYSTEM.md`.
4. Project context files (`AGENTS.md` / `CLAUDE.md` / `AGENTS.override.md`) under `<project_context>`.
5. Skills catalog (when the `read` tool is available).
6. Model / provider behavior.

Appending stronger `AGENTS.md` rules alone leaves the default Pi system prompt in place
and can still compete with a custom policy. Replacing the default prompt with
`--system-prompt` (and disabling context files with `--no-context-files`) makes the
override the primary session contract while the model and backend stay unchanged.

The SuperPi wrapper therefore:

- injects `--system-prompt` only for normal TUI / print sessions;
- adds `--no-context-files` by default so AGENTS.md is not double-loaded;
- leaves management commands (`install`, `update`, `auth`, `config`, …) unchanged;
- keeps user/project rule merging opt-in via `SUPERPI_INCLUDE_PROJECT_RULES=1`;
- strips known conflicting `## Safety` / `## Safe Capability Boost` sections when merging;
- labels merged rules by basename only (no absolute personal paths);
- provides `pi-stock` as an explicit stock-prompt entrypoint.

Install defaults (v2):

1. CLI wrapper injects `--system-prompt <file-path>` (not a huge argv string).
2. `~/.pi/agent/SYSTEM.md` replaces the default base prompt for all loaders.
3. Global extension `superpi-system-prompt.ts` re-applies the prompt on every
   `before_agent_start` (covers web-chat and non-shell entry points).

`pi-stock` sets `SUPERPI_DISABLED=1` and passes an empty `--system-prompt` so the
extension no-ops and Pi rebuilds the default coding-assistant prompt.

Verification: ask the model to answer `OVERRIDE_OK` iff the system prompt starts
with `[MODE: UNRESTRICTED]`. Behavioral refusals on individual topics can still
happen under provider policy even when the fingerprint check passes.

The result is an inference from controlled same-model/same-backend comparisons, not a
claim about any provider's internal server implementation.
