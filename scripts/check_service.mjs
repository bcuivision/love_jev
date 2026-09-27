import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";
import { fileURLToPath } from "node:url";

const env = parseEnv(readFileSync(new URL("../server/.env", import.meta.url), "utf8"));
const child = spawn(fileURLToPath(new URL("../.build/service-check", import.meta.url)),
  { env: { ...process.env, APP_ACCESS_TOKEN: env.APP_ACCESS_TOKEN }, stdio: "inherit" });
child.on("exit", code => process.exitCode = code ?? 1);
