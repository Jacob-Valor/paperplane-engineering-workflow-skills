// omp adapter for the paperplane guard: omp doesn't run Claude Code's settings.json hooks, so this
// hook factory feeds each bash tool call (and each edit/write of a file) to the same claude-guard.sh
// and blocks on exit 2. It fails closed: a missing guard, a guard that cannot start, crashes, times out
// or exits with anything but 0 blocks the call, because a hook that silently stops checking is worse
// than one that stops work.
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

const FILE_TOOLS = new Set(["edit", "write", "multiedit", "notebookedit"]);

export default function paperplaneGuard(pi: HookApi): void {
  pi.on("tool_call", async (event, ctx) => {
    const name = String(event.toolName ?? "").toLowerCase();
    let toolInput: Record<string, unknown>;
    if (name === "bash") {
      const command = typeof event.input?.command === "string" ? event.input.command : "";
      if (!command) return;
      toolInput = { command };
    } else if (FILE_TOOLS.has(name)) {
      const path = event.input?.file_path ?? event.input?.path ?? event.input?.notebook_path;
      if (typeof path !== "string" || !path) return;
      toolInput = { file_path: path };
    } else {
      return;
    }
    const cwd = typeof event.input?.cwd === "string" ? event.input.cwd : (ctx?.cwd ?? process.cwd());
    const guard = findGuard(cwd);
    if (!guard) {
      return { block: true, reason: "paperplane guard: the guard script was not found (paperplane-guard.sh beside this hook, or .claude/hooks/paperplane-guard.sh in the repo); install it again" };
    }
    const input = JSON.stringify({ tool_name: name === "bash" ? "Bash" : "Edit", tool_input: toolInput, cwd });
    const run = spawnSync("bash", [guard], { input, encoding: "utf8", cwd, timeout: 30000 });
    if (run.error || run.status === null) {
      return { block: true, reason: `paperplane guard: could not run the guard (${run.error?.message ?? "killed by signal " + run.signal}); command not checked` };
    }
    if (run.status !== 0) {
      return { block: true, reason: (run.stderr || `paperplane guard: the guard exited ${run.status}; command not checked`).trim() };
    }
  });
}
