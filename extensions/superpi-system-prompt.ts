/**
 * SuperPi extension: HARD-REPLACE system prompt every agent turn.
 *
 * Pi's default `--system-prompt` still appends context/skills/cwd in
 * buildSystemPrompt(). This extension forces the wire-level system prompt to be
 * exactly the SuperPi file contents (same contract as Grok
 * --system-prompt-override).
 *
 * Disable: SUPERPI_DISABLED=1 or PI_STOCK_PROMPT=1
 * Prompt:  SUPERPI_PROMPT_FILE or ~/.pi/superpi/pi-unrestricted.md
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function resolvePromptPath(): string | undefined {
	const fromEnv = process.env.SUPERPI_PROMPT_FILE?.trim();
	if (fromEnv && existsSync(fromEnv)) {
		return fromEnv;
	}
	const piHome = process.env.PI_HOME?.trim() || join(homedir(), ".pi");
	const candidates = [
		join(piHome, "superpi", "pi-unrestricted.md"),
		join(piHome, "agent", "SYSTEM.md"),
	];
	for (const path of candidates) {
		if (existsSync(path)) {
			return path;
		}
	}
	return undefined;
}

function loadPrompt(): string | undefined {
	const path = resolvePromptPath();
	if (!path) {
		return undefined;
	}
	try {
		return readFileSync(path, "utf-8");
	} catch {
		return undefined;
	}
}

export default function (pi: ExtensionAPI) {
	// Force hard-replace for this process when SuperPi extension is active
	// (unless stock mode). Works even if caller only set --system-prompt (soft).
	if (process.env.SUPERPI_DISABLED !== "1" && process.env.PI_STOCK_PROMPT !== "1") {
		process.env.PI_SYSTEM_PROMPT_HARD = process.env.PI_SYSTEM_PROMPT_HARD || "1";
		process.env.SUPERPI_HARD_REPLACE = process.env.SUPERPI_HARD_REPLACE || "1";
	}

	pi.on("before_agent_start", async (_event) => {
		if (process.env.SUPERPI_DISABLED === "1" || process.env.PI_STOCK_PROMPT === "1") {
			return;
		}
		const exact = loadPrompt();
		if (!exact?.trim()) {
			return;
		}
		// Exact file bytes only — no cwd, skills, project_context, APPEND_SYSTEM.
		return { systemPrompt: exact };
	});
}
