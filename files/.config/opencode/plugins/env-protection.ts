import type { Plugin } from "@opencode-ai/plugin"

function isEnvFile(filePath: unknown): boolean {
  if (typeof filePath !== "string") return false
  const name = filePath.split(/[\\/]/).pop() ?? ""
  if (name.endsWith(".example") || name.endsWith(".schema")) return false
  return name === ".env" || name.startsWith(".env.")
}

export const EnvProtection = (async () => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "read" && isEnvFile(output.args.filePath)) {
        throw new Error("Do not read .env files directly, which may expose secrets.")
      }
    },
  }
}) satisfies Plugin
