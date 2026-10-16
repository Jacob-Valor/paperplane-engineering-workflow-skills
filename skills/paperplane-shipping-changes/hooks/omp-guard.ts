// omp adapter for the paperplane guard: omp doesn't run Claude Code's settings.json hooks, so this
// hook factory feeds each bash tool call to the same claude-guard.sh and blocks on exit 2.
// Installed by `install-claude-hook.sh --commit` (as .omp/hooks/pre/paperplane-guard.ts, using
// .claude/hooks/paperplane-guard.sh) or `--omp` (as ~/.omp/agent/hooks/pre/, with the guard beside it).
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

function findGuard(cwd: string): string | undefined {
  const beside = join(here, "paperplane-guard.sh");
  if (existsSync(beside)) return beside;
  const top = spawnSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  const root = top.status === 0 ? top.stdout.trim() : cwd;
  const committed = join(root, ".claude", "hooks", "paperplane-guard.sh");
  return existsSync(committed) ? committed : undefined;
}

interface ToolCallEvent {
  toolName: string;
  input?: Record<string, unknown>;
}
interface HookApi {
  on(event: "tool_call", handler: (event: ToolCallEvent, ctx: { cwd?: string }) => Promise<{ block: true; reason: string } | undefined>): void;
}

export default function paperplaneGuard(pi: HookApi): void {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;
    const command = typeof event.input?.command === "string" ? event.input.command : "";
    if (!command) return;
    const cwd = typeof event.input?.cwd === "string" ? event.input.cwd : (ctx?.cwd ?? process.cwd());
    const guard = findGuard(cwd);
    if (!guard) return;
    const input = JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd });
    const run = spawnSync("bash", [guard], { input, encoding: "utf8", cwd });
    if (run.status === 2) {
      return { block: true, reason: (run.stderr || "blocked by the paperplane guard").trim() };
    }
  });
}
