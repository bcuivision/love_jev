import { createServer } from "node:http";
import type { IncomingMessage, ServerResponse } from "node:http";
import { timingSafeEqual, createHash } from "node:crypto";
import type { Analyze, AnalyzeDraft } from "./contracts.ts";
import { parseRequest, parseDraftRequest, ServiceError } from "./contracts.ts";

interface Options { token: string; analyze?: Analyze; analyzeDraft?: AnalyzeDraft; demo: boolean; timeoutMs?: number; analysisMode?: string }

export function createApp(options: Options) {
  if (options.token.length < 24) throw new Error("APP_ACCESS_TOKEN must contain at least 24 characters.");
  const expected = digest(`Bearer ${options.token}`);
  let inFlight = 0, windowStart = Date.now(), requests = 0;
  const server = createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (req.method === "GET" && req.url === "/health") {
      return send(res, 200, { status: options.analyze ? "ready" : "unconfigured", mode: options.demo ? "fixture" : "live",
        analysisMode: options.demo ? "fixture" : options.analysisMode || "jev", draftImpact: Boolean(options.analyzeDraft) });
    }
    const isDraft = req.url === "/v1/assistant/draft-impact";
    const stream = !isDraft && req.headers.accept === "application/x-ndjson";
    if (req.method !== "POST" || (!isDraft && req.url !== "/v1/assistant/analyze")) return send(res, 404, { error: "not_found" });
    if (!timingSafeEqual(expected, digest(req.headers.authorization ?? ""))) return send(res, 401, { error: "unauthorized" });
    if (isDraft ? !options.analyzeDraft : !options.analyze) return send(res, 503, { error: "models_unconfigured" });
    if (!req.headers["content-type"]?.startsWith("application/json")) return send(res, 415, { error: "json_required" });
    // Team demo uses one bearer token. Bounded global quotas, with no stored transcripts or IP history.
    if (Date.now() - windowStart > 60_000) { windowStart = Date.now(); requests = 0; }
    if (inFlight >= 4 || requests >= 30) { res.setHeader("Retry-After", "5"); return send(res, 429, { error: "busy" }); }
    requests += 1; inFlight += 1;
    const cancellation = new AbortController();
    const timer = setTimeout(() => cancellation.abort(new Error("deadline")), options.timeoutMs ?? 32_000);
    const onClose = () => { if (!res.writableEnded) cancellation.abort(new Error("disconnected")); };
    res.on("close", onClose);
    try {
      const body = await readJSON(req);
      cancellation.signal.throwIfAborted();
      const result = isDraft
        ? await options.analyzeDraft!(parseDraftRequest(body), cancellation.signal)
        : await options.analyze!(parseRequest(body), cancellation.signal, stream ? assessment => {
            cancellation.signal.throwIfAborted();
            sendEvent(res, { type: "intimacy", assessment });
          } : undefined);
      cancellation.signal.throwIfAborted();
      if (stream) { sendEvent(res, { type: "suggestion", result }); res.end(); }
      else send(res, 200, result);
    } catch (error) {
      if (!res.destroyed) {
        const status = cancellation.signal.aborted ? 504 : error instanceof ServiceError ? error.status : 502;
        const code = cancellation.signal.aborted ? "analysis_timeout" : error instanceof ServiceError ? error.code : "analysis_unavailable";
        // Do not log provider errors, credentials, request bodies, or chat text.
        if (res.headersSent) { sendEvent(res, { type: "error", status, error: code }); res.end(); }
        else send(res, status, { error: code });
      }
    } finally {
      clearTimeout(timer); res.off("close", onClose); inFlight -= 1;
    }
  });
  server.requestTimeout = 25_000;
  server.headersTimeout = 10_000;
  return server;
}

function digest(value: string) { return createHash("sha256").update(value).digest(); }
function sendEvent(res: ServerResponse, event: unknown) {
  if (res.destroyed || res.writableEnded) return;
  if (!res.headersSent) {
    res.writeHead(200, { "Content-Type": "application/x-ndjson; charset=utf-8", "X-Accel-Buffering": "no" });
    res.flushHeaders();
  }
  res.write(JSON.stringify(event) + "\n");
}
function send(res: ServerResponse, status: number, body: unknown) {
  if (res.destroyed || res.writableEnded) return;
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}
async function readJSON(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  if (Number(req.headers["content-length"]) > 48_000) throw new ServiceError(413, "body_too_large");
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 48_000) throw new ServiceError(413, "body_too_large");
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new ServiceError(400, "invalid_json"); }
}
