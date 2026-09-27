import test from "node:test";
import assert from "node:assert/strict";
import { createDraftAnalyzer, fixtureDraftAnalyzer } from "../src/pipeline.ts";
import { parseDraftRequest } from "../src/contracts.ts";

const config = { openAIKey: "unused", typeSafeKey: "test-jev", openAIModel: "unused", jevModel: "jev-latest" };
const input = { sessionID: "one", revision: 3, draftID: "draft-one", source: "test" as const,
  context: "我：忙完了吗\n对方：忙完了，想出去走走", draft: "要一起散步吗？" };

function models(impact: number, baseline = 2.56, enough = 0.9, model = "jev-latest") {
  const calls: any[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    calls.push({ url: String(url), body: JSON.parse(String(init?.body)), init });
    return Response.json({ model, usage: { input_tokens: 10, output_tokens: 10 }, answers: {
      enough: { type: "noul", noul: enough },
      before: { type: "score", score: baseline, confidence: 0.9, legend: {}, probabilities: {} },
      impact: { type: "score", score: impact, confidence: 0.9, legend: {}, probabilities: {} },
      reason: { type: "choice", choice: impact > 2 ? "attentive" : impact < 2 ? "pressure" : "neutral",
        confidence: 0.9, probabilities: {} }
    } });
  };
  return { fetcher, calls };
}

for (const [score, expected] of [[4, 12], [0, -12], [2, 0], [3, 6]]) {
  test(`Jev draft impact ${expected} is one call with consistent before/after scores`, async () => {
    const { fetcher, calls } = models(score);
    const result = await createDraftAnalyzer(config, fetcher)(input, new AbortController().signal);
    assert.equal(calls.length, 1);
    assert.equal(new URL(calls[0].url).pathname, "/v1/systemone");
    assert.equal(calls[0].body.state.untrusted_unsent_draft, input.draft);
    assert.equal(calls[0].body.state.untrusted_chat_transcript, input.context);
    assert.equal(calls[0].init.redirect, "error");
    assert.equal(result.before, 64);
    assert.equal(result.delta, expected);
    assert.equal(result.after, 64 + expected);
    assert.equal(result.draftID, input.draftID);
    assert.equal(result.sessionID, input.sessionID);
    assert.equal(result.revision, input.revision);
    assert.equal(result.isDemo, false);
  });
}

test("clamping reports the actual bounded change", async () => {
  for (const [score, baseline, before, after] of [[4, 3.92, 98, 100], [0, 0.08, 2, 0]]) {
    const { fetcher } = models(score, baseline);
    const result = await createDraftAnalyzer(config, fetcher)(input, new AbortController().signal);
    assert.equal(result.before, before);
    assert.equal(result.after, after);
    assert.equal(result.delta, after - before);
  }
});

test("insufficient evidence and explicit fixture mode have no numeric prediction", async () => {
  const { fetcher } = models(4, 3, 0.2);
  for (const analyze of [createDraftAnalyzer(config, fetcher), fixtureDraftAnalyzer]) {
    const result = await analyze(input, new AbortController().signal);
    assert.equal(result.before, null);
    assert.equal(result.after, null);
    assert.equal(result.delta, null);
  }
});

test("invalid model identity, score and provider failure never produce a score", async () => {
  for (const args of [[5, 2, 0.9, "jev-latest"], [3, 8, 0.9, "jev-latest"], [3, 2, 2, "jev-latest"],
    [3, 2, 0.9, "gpt-test"]] as const) {
    const { fetcher } = models(args[0], args[1], args[2], args[3]);
    await assert.rejects(createDraftAnalyzer(config, fetcher)(input, new AbortController().signal));
  }
  const failed: typeof fetch = async () => Response.json({}, { status: 503 });
  await assert.rejects(createDraftAnalyzer(config, failed)(input, new AbortController().signal));
});

test("draft contract rejects blank, oversized, missing identity and invalid context", () => {
  assert.equal(parseDraftRequest({ ...input, draft: "  你好  " }).draft, "你好");
  for (const patch of [{ draft: " " }, { draft: "x".repeat(2001) }, { draftID: "" }, { draftID: 3 },
    { revision: -1 }, { context: "" }, { source: "unknown" }]) {
    assert.throws(() => parseDraftRequest({ ...input, ...patch }));
  }
});
