import "./proxy.ts";
import { createApp } from "./server.ts";
import { createModelAnalyzer, createReplyOnlyAnalyzer, createDraftAnalyzer, fixtureAnalyzer, fixtureDraftAnalyzer } from "./pipeline.ts";
import { readModelConfig } from "./config.ts";

const demo = process.env.DEMO_MODE === "1";
const token = process.env.APP_ACCESS_TOKEN ?? "";
const analysisMode = process.env.ANALYSIS_MODE || "jev";
if (!["jev", "reply_only"].includes(analysisMode)) throw new Error("ANALYSIS_MODE must be jev or reply_only");
const config = readModelConfig(process.env);
const analyze = demo ? fixtureAnalyzer : !config.openAIKey ? undefined
  : analysisMode === "reply_only" ? createReplyOnlyAnalyzer(config)
  : config.typeSafeKey ? createModelAnalyzer(config) : undefined;
const analyzeDraft = demo ? fixtureDraftAnalyzer
  : analysisMode === "jev" && config.typeSafeKey ? createDraftAnalyzer(config) : undefined;
const server = createApp({ token, analyze, analyzeDraft, demo, analysisMode });
const port = Number(process.env.PORT || 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid PORT");
const host = process.env.HOST || "127.0.0.1";
server.listen(port, host, () => console.log(`恋爱吧 service: http://${host}:${port} (${demo ? "fixture" : analyze ? analysisMode : "model keys missing"})`));
for (const event of ["SIGINT", "SIGTERM"] as const) process.on(event, () => {
  server.close(); server.closeAllConnections();
});
