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

Optional: `./install.sh --install-system-md` also writes `~/.pi/agent/SYSTEM.md` so bare
`pi` without the wrapper still loads the SuperPi prompt. Prefer the wrapper if you need
a reliable `pi-stock` path (SYSTEM.md would still load in stock mode).

The result is an inference from controlled same-model/same-backend comparisons, not a
claim about any provider's internal server implementation.
