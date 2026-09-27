import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createApp } from "../src/server.ts";
import { fixtureAnalyzer, fixtureDraftAnalyzer } from "../src/pipeline.ts";
import type { Analyze, AnalyzeDraft } from "../src/contracts.ts";

const token = "local-test-token-at-least-24-characters";
const body = { sessionID: "device-a", revision: 3, context: "我：你好。\n对方：你好！", source: "test" };

async function start(t: TestContext, analyze?: Analyze, timeoutMs?: number, analyzeDraft?: AnalyzeDraft) {
  const server = createApp({ token, analyze, analyzeDraft, demo: analyze === fixtureAnalyzer, timeoutMs });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => { server.closeAllConnections(); server.close(); });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const url = `http://127.0.0.1:${address.port}`;
  return {
    url,
    post: (value: unknown = body, auth = token) => fetch(url + "/v1/assistant/analyze", {
      method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${auth}` }, body: JSON.stringify(value)
    })
  };
}

test("draft endpoint authenticates, validates and echoes draft identity without caching", async t => {
  let calls = 0;
  const app = await start(t, fixtureAnalyzer, undefined, async (input, signal) => {
    calls++; return fixtureDraftAnalyzer(input, signal);
  });
  const draft = { ...body, draft: "今天辛苦了", draftID: "draft-two" };
  const post = (value: unknown, auth = token) => fetch(app.url + "/v1/assistant/draft-impact", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${auth}` }, body: JSON.stringify(value)
  });
  assert.equal((await post(draft, "wrong")).status, 401);
  assert.equal((await post({ ...draft, draft: " " })).status, 400);
  assert.equal(calls, 0);
  const response = await post(draft);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const result = await response.json();
  assert.equal(result.draftID, "draft-two");
  assert.equal(result.delta, null);
  assert.equal(result.isDemo, true);
  assert.equal(calls, 1);
});

test("unconfigured draft analysis never falls back to a reply or fake score", async t => {
  const app = await start(t, fixtureAnalyzer);
  const response = await fetch(app.url + "/v1/assistant/draft-impact", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ ...body, draft: "你好", draftID: "draft" })
  });
  assert.equal(response.status, 503);
});

test("fixture HTTP roundtrip is authenticated, marked, and uncached", async t => {
  const app = await start(t, fixtureAnalyzer);
  assert.equal((await app.post(body, "wrong")).status, 401);
  const response = await app.post();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const value = await response.json();
  assert.equal(value.isDemo, true);
  assert.equal(value.intimacy, null);
  assert.equal(value.sessionID, "device-a");
  assert.equal(value.revision, 3);
});

test("missing provider configuration is explicit", async t => {
  const app = await start(t);
  assert.equal((await app.post()).status, 503);
  assert.equal((await (await fetch(app.url + "/health")).json()).status, "unconfigured");
});

test("malformed requests and oversized transcripts never reach models", async t => {
  let count = 0;
  const app = await start(t, async (input, signal) => { count++; return fixtureAnalyzer(input, signal); });
  assert.equal((await app.post({ ...body, revision: -1 })).status, 400);
  assert.equal((await app.post({ ...body, source: "unknown" })).status, 400);
  assert.equal((await app.post({ ...body, context: "x".repeat(10_001) })).status, 400);
  assert.equal((await app.post({ ...body, context: "x".repeat(50_000) })).status, 413);
  assert.equal(count, 0);
});

test("deadline cancels model work and reports timeout", async t => {
  let cancelled = false;
  const app = await start(t, async (_, signal) => {
    await new Promise<void>((_, reject) => signal.addEventListener("abort", () => { cancelled = true; reject(signal.reason); }, { once: true }));
    throw new Error("unreachable");
  }, 25);
  assert.equal((await app.post()).status, 504);
  assert.ok(cancelled);
});

test("stream publishes the score while recommendation work is still pending", { timeout: 3000 }, async t => {
  let finish!: () => void;
  const pending = new Promise<void>(resolve => { finish = resolve; });
  t.after(() => finish());
  let completed = false;
  const app = await start(t, async (input, signal, onAssessment) => {
    onAssessment?.({ sessionID: input.sessionID, revision: input.revision, intimacy: 72, isDemo: false });
    await pending;
    completed = true;
    return { ...await fixtureAnalyzer(input, signal), intimacy: 72, isDemo: false };
  });
  const response = await fetch(app.url + "/v1/assistant/analyze", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, Accept: "application/x-ndjson" },
    body: JSON.stringify(body)
  });
  assert.match(response.headers.get("content-type")!, /application\/x-ndjson/);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const reader = response.body!.getReader();
  const first = new TextDecoder().decode((await reader.read()).value);
  const event = JSON.parse(first.trim());
  assert.equal(event.type, "intimacy");
  assert.equal(event.assessment.intimacy, 72);
  assert.equal(completed, false);
  finish();
  let rest = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    rest += new TextDecoder().decode(value);
  }
  assert.equal(JSON.parse(rest.trim()).type, "suggestion");
});

test("a reply failure after the score is streamed produces a terminal error event", async t => {
  const app = await start(t, async (input, _signal, onAssessment) => {
    onAssessment?.({ sessionID: input.sessionID, revision: input.revision, intimacy: 72, isDemo: false });
    throw new Error("private provider error");
  });
  const response = await fetch(app.url + "/v1/assistant/analyze", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, Accept: "application/x-ndjson" },
    body: JSON.stringify(body)
  });
  const events = (await response.text()).trim().split("\n").map(line => JSON.parse(line));
  assert.deepEqual(events.map(e => e.type), ["intimacy", "error"]);
  assert.equal(events[1].status, 502);
  assert.equal(events[1].error, "analysis_unavailable");
});
