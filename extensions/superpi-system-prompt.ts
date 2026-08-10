/**
 * SuperPi extension: force primary system prompt every agent turn.
 *
 * Works for CLI, web-chat, and any entry that loads global extensions —
 * unlike shell wrappers, which only wrap interactive `pi` invocations.
 *
 * Disable for one process: SUPERPI_DISABLED=1
 * Custom prompt file:     SUPERPI_PROMPT_FILE=/path/to.md
 * Skip if already present: SUPERPI_EXTENSION_SOFT=1 (only inject when missing fingerprint)
 */

import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const FINGERPRINT = "[MODE: UNRESTRICTED]";

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

function shouldApply(current: string): boolean {
	if (process.env.SUPERPI_DISABLED === "1" || process.env.PI_STOCK_PROMPT === "1") {
		return false;
	}
	if (process.env.SUPERPI_EXTENSION_SOFT === "1" && current.includes(FINGERPRINT)) {
		return false;
	}
	return true;
}

export default function (pi: ExtensionAPI) {
	pi.on("before_agent_start", async (event) => {
		if (!shouldApply(event.systemPrompt ?? "")) {
			return;
		}
		const base = loadPrompt();
		if (!base?.trim()) {
			return;
		}

		const cwd =
			(event.systemPromptOptions as { cwd?: string } | undefined)?.cwd ??
			process.cwd();
		let systemPrompt = base.trimEnd();

		// Keep Pi-appended project context / skills if already present in the
		// chained prompt and user opted into keep-context mode.
		if (process.env.SUPERPI_KEEP_CONTEXT_FILES === "1" && event.systemPrompt) {
			const ctxStart = event.systemPrompt.indexOf("<project_context>");
			const skillsStart = event.systemPrompt.indexOf("<available_skills>");
			const markers = [ctxStart, skillsStart].filter((i) => i >= 0);
			if (markers.length > 0) {
				const cut = Math.min(...markers);
				systemPrompt += "\n\n" + event.systemPrompt.slice(cut);
			}
		}

		if (!systemPrompt.includes("Current working directory:")) {
			systemPrompt += `\n\nCurrent working directory: ${cwd.replace(/\\/g, "/")}`;
		}

		return { systemPrompt };
	});
}
