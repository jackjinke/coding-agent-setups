// Runs Impeccable's design hook, the same `impeccable hook` its Claude Code and
// Codex manifests call, on OMP file edits and at session stop. The engine owns
// detection, per-session dedupe, and the deferred Stop pass; this file only
// translates OMP events into the engine's Claude-shaped stdin and hands the
// returned context back to the agent.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"
import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

// Installed by `impeccable install --providers=codex --scope=global`.
const launcher = join(homedir(), ".agents", "skills", "impeccable", "scripts", "impeccable")
const hookTimeoutMs = 60_000

type HookEvent = Record<string, unknown>
type HookContext = {
  cwd: string
  hasUI: boolean
  ui: { notify(message: string, type?: string): void }
}

function additionalContext(stdout: string): string | undefined {
  const text = stdout.trim()
  if (!text) return undefined
  const context = JSON.parse(text)?.hookSpecificOutput?.additionalContext
  return typeof context === "string" && context.trim() ? context : undefined
}

function runHook(event: HookEvent, cwd: string): Promise<string | undefined> {
  const { promise, resolve, reject } = Promise.withResolvers<string | undefined>()
  const child = spawn(launcher, ["hook"], {
    cwd,
    env: {
      ...process.env,
      // The engine's default contract and the one its other harnesses are modeled on.
      IMPECCABLE_HOOK_HARNESS: "claude",
      // Upstream installs the hook per project; this one is global, so keep the
      // engine's session cache out of every project tree it touches.
      IMPECCABLE_CACHE_ROOT: process.env.IMPECCABLE_CACHE_ROOT || join(homedir(), ".impeccable", "hook-state"),
    },
    stdio: ["pipe", "pipe", "pipe"],
  })
  let stdout = ""
  let stderr = ""
  let timedOut = false
  const timer = setTimeout(() => {
    timedOut = true
    try {
      child.kill("SIGKILL")
    } catch {}
  }, hookTimeoutMs)
  child.stdout.setEncoding("utf8").on("data", chunk => (stdout += chunk))
  child.stderr.setEncoding("utf8").on("data", chunk => (stderr += chunk))
  child.stdin.on("error", () => {})
  child.on("error", error => {
    clearTimeout(timer)
    reject(error)
  })
  child.on("close", code => {
    clearTimeout(timer)
    if (timedOut) return reject(new Error(`timed out after ${hookTimeoutMs / 1000}s`))
    if (code !== 0) return reject(new Error(`exited ${code}: ${stderr.trim()}`))
    try {
      resolve(additionalContext(stdout))
    } catch {
      reject(new Error(`unexpected output: ${stdout.trim().slice(0, 200)}`))
    }
  })
  child.stdin.end(JSON.stringify(event))
  return promise
}

// The engine rewrites one per-project cache file per call; overlapping calls
// from parallel tool results would race on it.
let queue: Promise<unknown> = Promise.resolve()

function runSerialized(event: HookEvent, ctx: HookContext): Promise<string | undefined> {
  const run = queue.then(() => runHook(event, ctx.cwd))
  queue = run.catch(() => {})
  return run.catch(error => {
    const reason = error instanceof Error ? error.message : String(error)
    if (ctx.hasUI) ctx.ui.notify(`Impeccable design hook failed: ${reason}`, "warning")
    return undefined
  })
}

// Paths come from result details, which OMP resolves to absolute paths for
// every edit mode, so edit syntax never has to be parsed here.
function editedPaths(event: { toolName: string; isError?: boolean; details?: unknown }): string[] {
  if (event.isError || !event.details || typeof event.details !== "object") return []
  const details = event.details as Record<string, unknown>
  if (event.toolName === "write") {
    return typeof details.resolvedPath === "string" ? [details.resolvedPath] : []
  }
  if (event.toolName !== "edit") return []
  const entries: unknown[] = Array.isArray(details.perFileResults) ? details.perFileResults : [details]
  const paths: string[] = []
  for (const entry of entries) {
    if (!entry || typeof entry !== "object") continue
    const { path, op } = entry as Record<string, unknown>
    if (typeof path === "string" && op !== "delete") paths.push(path)
  }
  return paths
}

export default function impeccableDesignHook(pi: ExtensionAPI): void {
  pi.on("tool_result", async (event, ctx) => {
    const paths = editedPaths(event)
    if (paths.length === 0 || !existsSync(launcher)) return
    const notes: string[] = []
    for (const path of paths) {
      const note = await runSerialized(
        {
          session_id: ctx.sessionManager.getSessionId(),
          cwd: ctx.cwd,
          hook_event_name: "PostToolUse",
          tool_name: event.toolName === "write" ? "Write" : "Edit",
          tool_input: { file_path: path },
        },
        ctx,
      )
      if (note) notes.push(note)
    }
    if (notes.length === 0) return
    return { content: [...event.content, { type: "text", text: notes.join("\n\n") }] }
  })

  pi.on("session_stop", async (event, ctx) => {
    if (!existsSync(launcher)) return
    const note = await runSerialized(
      {
        session_id: ctx.sessionManager.getSessionId(),
        cwd: ctx.cwd,
        hook_event_name: "Stop",
        stop_hook_active: event.stop_hook_active === true,
      },
      ctx,
    )
    if (note) return { continue: true, additionalContext: note }
  })
}
