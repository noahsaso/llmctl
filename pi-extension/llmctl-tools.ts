/**
 * llmctl-tools — per-model tool policy for pi.
 *
 * pi's --tools allowlist binds at launch, so switching model with /model (or
 * Ctrl+P, or restoring a session) leaves the previous model's tools active.
 * This applies the policy on every model change instead.
 *
 * It uses pi.setActiveTools(), which changes the *active tool set* — excluded
 * tools are absent from the prompt entirely, not blocked at call time, so they
 * cost no tokens.
 *
 * Policy is written by `llmctl pi-setup` to ~/.config/llmctl/tool-policy.json,
 * keyed by "<provider>/<model id>". llmctl stays the single source of truth.
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const POLICY_FILE =
	process.env.LLMCTL_TOOL_POLICY ?? join(homedir(), ".config", "llmctl", "tool-policy.json");

type Entry = { deny?: string[]; tools?: string[]; model?: string };
type Policy = Record<string, Entry>;

function loadPolicy(): Policy {
	try {
		return JSON.parse(readFileSync(POLICY_FILE, "utf8")) as Policy;
	} catch {
		return {}; // absent or malformed -> no restrictions
	}
}

export default function llmctlTools(pi: ExtensionAPI) {
	// Every tool pi knows about, captured before we ever narrow the set.
	// getAllTools() is the full inventory, so this stays correct even after
	// setActiveTools() has already restricted things.
	const allNames = () => pi.getAllTools().map((t) => t.name);

	const apply = (model: { provider?: string; id?: string } | undefined, notify: boolean, ctx?: any) => {
		if (!model?.provider || !model?.id) return;

		const all = allNames();
		const entry = loadPolicy()[`${model.provider}/${model.id}`];

		let allowed: string[];
		let missing: string[] = [];

		if (entry?.deny?.length) {
			// Preferred form. Denylists fail safe: a tool pi registers at runtime
			// (several subagent tools do) stays active instead of being dropped
			// because a static inventory never listed it.
			allowed = all.filter((n) => !entry.deny!.includes(n));
			missing = entry.deny.filter((n) => !all.includes(n));
		} else if (entry?.tools?.length) {
			allowed = entry.tools.filter((n) => all.includes(n));
			missing = entry.tools.filter((n) => !all.includes(n));
		} else {
			// No policy: clear any restriction left over from a previous model.
			pi.setActiveTools(all);
			return;
		}

		const removed = all.filter((n) => !allowed.includes(n));

		pi.setActiveTools(allowed);

		if (notify && ctx?.ui?.notify) {
			const parts = [`llmctl: ${allowed.length}/${all.length} tools active`];
			if (removed.length) parts.push(`hidden: ${removed.join(", ")}`);
			if (missing.length) parts.push(`in policy but not registered: ${missing.join(", ")}`);
			ctx.ui.notify(parts.join(" · "), missing.length ? "warning" : "info");
		}
	};

	pi.on("session_start", async (_event, ctx: any) => apply(ctx?.model, false, ctx));
	pi.on("model_select", async (event: any, ctx: any) => apply(event?.model, true, ctx));
}
