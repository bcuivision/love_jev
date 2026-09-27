import test from "node:test";
import assert from "node:assert/strict";
import { createModelAnalyzer, createReplyOnlyAnalyzer, parseCandidates } from "../src/pipeline.ts";
import { ServiceError } from "../src/contracts.ts";
import { replyPersona, replyTones } from "../src/reply-persona.ts";

const input = { sessionID: "session-one", revision: 7, context: "我：今天怎么样？\n对方：刚忙完，想出去走走。", source: "test" as const };
const config = { openAIKey: "test-openai", typeSafeKey: "test-jev", openAIModel: "gpt-4.1-mini", jevModel: "jev-latest" };
const candidates = ["忙了一天辛苦啦，想去哪里走走？", "想不想去附近散个步？", "终于可以放松一下啦。"];

test("current intimacy is delivered before any plan or reply generation", async () => {
  const { fetcher, calls } = fakeModels();
  const received: number[] = [];
  await createModelAnalyzer(config, fetcher)(input, new AbortController().signal, value => {
    assert.equal(calls.length, 1);
    assert.equal(value.sessionID, input.sessionID);
    assert.equal(value.revision, input.revision);
    assert.equal(value.isDemo, false);
    received.push(value.intimacy!);
  });
  assert.deepEqual(received, [65]);
});

test("explicit reply-only mode uses only GPT and never fabricates intimacy or demo data", async () => {
  const { fetcher, calls } = fakeModels();
  const result = await createReplyOnlyAnalyzer({ ...config, openAIBaseURL: "https://api.0-0.pro/v1",
    openAIAPI: "chat_completions" }, fetcher)(input, new AbortController().signal);
  assert.equal(calls.length, 1);
  assert.equal(new URL(calls[0].url).hostname, "api.0-0.pro");
  assert.equal(result.recommendation, candidates[0]);
  assert.equal(result.intimacy, null);
  assert.equal(result.reason, null);
  assert.ok(calls[0].body.messages[0].content.includes(replyPersona));
  assert.equal(JSON.parse(calls[0].body.messages[1].content).replyTone, replyTones.adaptive);
  assert.equal(result.isDemo, false);
  assert.match(result.explanation, /未启用 Jev/);
  assert.equal(result.sessionID, input.sessionID);
});

function fakeModels(enough = 0.9, selected = "b", options: {
  stage?: string; signal?: string; action?: string; rawScore?: number;
} = {}) {
  const calls: { url: string; body: any; headers: Headers; redirect?: RequestRedirect }[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    const body = JSON.parse(String(init?.body));
    calls.push({ url: String(url), body, headers: new Headers(init?.headers), redirect: init?.redirect });
    if (!new URL(String(url)).pathname.endsWith("/systemone")) {
      if (new URL(String(url)).pathname.endsWith("/chat/completions")) {
        return Response.json({ choices: [{ finish_reason: "stop", message: {
          content: JSON.stringify({ candidates: candidates.map(text => ({ text })) })
        } }] });
      }
      return Response.json({ status: "completed", output: [{ type: "message", content: [{ type: "output_text",
        text: JSON.stringify({ candidates: candidates.map(text => ({ text })) }) }] }] });
    }
    const answers = body.questions.best ? {
      best: { type: "choice", choice: selected, confidence: 0.8, probabilities: { a: 0.1, b: 0.8, c: 0.1 } }
    } : body.questions.action ? {
      action: { type: "choice", choice: options.action ?? "continue", confidence: 0.8, probabilities: {} }
    } : {
      enough: { type: "noul", noul: enough },
      intimacy: { type: "score", score: options.rawScore ?? 2.6, confidence: 0.7, legend: {}, probabilities: {} },
      stage: { type: "choice", choice: options.stage ?? "familiar", confidence: 0.8, probabilities: {} },
      signal: { type: "choice", choice: options.signal ?? "sharing", confidence: 0.8, probabilities: {} }
    };
    return Response.json({ model: "jev-latest", answers, usage: { input_tokens: 10, output_tokens: 10 } });
  };
  return { fetcher, calls };
}

test("Jev assesses relationship, plans action/result, GPT drafts from that plan, Jev checks alignment", async () => {
  const { fetcher, calls } = fakeModels();
  const result = await createModelAnalyzer(config, fetcher)(input, new AbortController().signal);
  assert.deepEqual(calls.map(c => new URL(c.url).pathname), ["/v1/systemone", "/v1/systemone", "/v1/responses", "/v1/systemone"]);
  assert.equal(result.recommendation, candidates[1]);
  assert.equal(result.intimacy, 65);
  assert.equal(result.sessionID, input.sessionID);
  assert.equal(result.revision, 7);
  assert.equal(result.isDemo, false);
  assert.match(result.explanation, /不代表恋爱成功率/);
  assert.equal(calls[2].body.store, false);
  assert.equal(calls[2].body.text.format.strict, true);
  assert.equal(calls[0].headers.get("authorization"), "Bearer test-jev");
  assert.equal(calls[2].headers.get("authorization"), "Bearer test-openai");
  assert.equal(calls[3].body.state.candidates.b, candidates[1]);
  assert.ok(result.reason);
  assert.equal(calls[1].body.state.relationshipStage, result.reason.relationshipStage);
  assert.deepEqual(JSON.parse(calls[2].body.input).recommendationPlan, result.reason);
  assert.deepEqual(calls[3].body.state.recommendationPlan, result.reason);
  assert.equal(JSON.parse(calls[2].body.input).replyTone, replyTones.playful);
  assert.equal(calls[3].body.state.replyTone, replyTones.playful);
  assert.equal(calls[3].body.state.replyPersona, replyPersona);
  assert.match(result.reason.action, /小问题/);
  assert.match(result.reason.expectedResult, /了解/);
});

test("Jev and GPT can share one provider without duplicate version paths or redirects", async () => {
  const { fetcher, calls } = fakeModels();
  const result = await createModelAnalyzer({ ...config, typeSafeKey: "test-openai",
    typeSafeBaseURL: "https://api.0-0.pro/v1/", openAIBaseURL: "https://api.0-0.pro/v1/",
    openAIAPI: "chat_completions" }, fetcher)(input, new AbortController().signal);
  assert.deepEqual(calls.map(c => c.url), ["https://api.0-0.pro/v1/systemone", "https://api.0-0.pro/v1/systemone",
    "https://api.0-0.pro/v1/chat/completions", "https://api.0-0.pro/v1/systemone"]);
  assert.ok(calls.every(c => c.headers.get("authorization") === "Bearer test-openai"));
  assert.ok(calls.every(c => c.redirect === "error"));
  assert.equal(calls[0].body.model, "jev-latest");
  assert.equal(calls[3].body.model, "jev-latest");
  assert.equal(result.intimacy, 65);
  assert.equal(result.isDemo, false);
});

test("invalid Jev endpoints and responses from a different model fail closed", async () => {
  for (const typeSafeBaseURL of ["http://example.test/v1", "https://user:password@example.test", "https://example.test?key=test"]) {
    assert.throws(() => createModelAnalyzer({ ...config, typeSafeBaseURL }));
  }
  const { fetcher } = fakeModels();
  const wrongModel: typeof fetch = async (url, init) => {
    const response = await fetcher(url, init);
    const data = await response.json();
    return Response.json({ ...data, model: "gpt-test" });
  };
  await assert.rejects(createModelAnalyzer(config, wrongModel)(input, new AbortController().signal),
    (error: unknown) => error instanceof ServiceError && error.code === "unexpected_decision_model");
});

for (const openAIAPI of ["responses", "chat_completions"] as const) {
  test(`custom provider uses ${openAIAPI} and keeps Jev credentials separate`, async () => {
    const { fetcher, calls } = fakeModels();
    const result = await createModelAnalyzer({ ...config, openAIBaseURL: "https://api.0-0.pro/v1/", openAIAPI }, fetcher)
      (input, new AbortController().signal);
    assert.deepEqual(calls.map(c => new URL(c.url).hostname), ["api.typesafe.ai", "api.typesafe.ai", "api.0-0.pro", "api.typesafe.ai"]);
    assert.equal(new URL(calls[2].url).pathname, openAIAPI === "responses" ? "/v1/responses" : "/v1/chat/completions");
    assert.equal(calls[0].headers.get("authorization"), "Bearer test-jev");
    assert.equal(calls[2].headers.get("authorization"), "Bearer test-openai");
    assert.equal(calls[3].headers.get("authorization"), "Bearer test-jev");
    assert.equal(result.recommendation, candidates[1]);
    const prompt = openAIAPI === "responses" ? calls[2].body.instructions : calls[2].body.messages[0].content;
    const generationInput = JSON.parse(openAIAPI === "responses" ? calls[2].body.input : calls[2].body.messages[1].content);
    assert.ok(prompt.includes(replyPersona));
    assert.equal(generationInput.replyTone, calls[3].body.state.replyTone);
    if (openAIAPI === "chat_completions") {
      assert.equal(calls[2].body.response_format.json_schema.strict, true);
      assert.equal(calls[2].body.messages[0].role, "system");
      assert.equal(JSON.parse(calls[2].body.messages[1].content).untrusted_chat_transcript, input.context);
    }
  });
}

test("insufficient context never produces a numeric intimacy score", async () => {
  const { fetcher } = fakeModels(0.2, "b", { action: "acknowledge" });
  const result = await createModelAnalyzer(config, fetcher)(input, new AbortController().signal);
  assert.equal(result.intimacy, null);
});

test("provider error is surfaced and never silently becomes fixture data", async () => {
  const failed: typeof fetch = async () => Response.json({ error: "unavailable" }, { status: 503 });
  await assert.rejects(createModelAnalyzer(config, failed)(input, new AbortController().signal));
});

test("invalid final selection is rejected", async () => {
  const { fetcher } = fakeModels(0.9, "d");
  await assert.rejects(createModelAnalyzer(config, fetcher)(input, new AbortController().signal));
});

test("candidate parser rejects duplicates, empty and excessive responses", () => {
  assert.throws(() => parseCandidates('{"candidates":[{"text":"a"},{"text":"a"},{"text":"b"}]}'), ServiceError);
  assert.throws(() => parseCandidates('{"candidates":[{"text":""}]}'), ServiceError);
  assert.throws(() => parseCandidates(JSON.stringify({ candidates: [{ text: "长".repeat(81) }, { text: "b" }, { text: "c" }] })), ServiceError);
});

for (const scenario of [
  { name: "limited context", enough: 0.2, stage: "mutual_interest", signal: "open_to_meeting", action: "acknowledge", score: null },
  { name: "unknown stage even with confident scoring", enough: 0.9, stage: "unknown", signal: "routine", action: "acknowledge", score: null },
  { name: "explicit boundary at a close stage", enough: 0.9, stage: "established", signal: "boundary", action: "give_space", score: 65 },
  { name: "boundary in a short transcript", enough: 0.1, stage: "unknown", signal: "boundary", action: "give_space", score: null },
  { name: "emotional support", enough: 0.9, stage: "familiar", signal: "distress", action: "support", score: 65 },
  { name: "repair a misunderstanding", enough: 0.9, stage: "established", signal: "tension", action: "repair", score: 65 },
  { name: "mutual meeting intent", enough: 0.9, stage: "mutual_interest", signal: "open_to_meeting", action: "invite", score: 65 }
]) {
  test(`plan stays grounded for ${scenario.name}`, async () => {
    const { fetcher, calls } = fakeModels(scenario.enough, "a", scenario);
    const result = await createModelAnalyzer(config, fetcher)(input, new AbortController().signal);
    assert.equal(result.intimacy, scenario.score);
    assert.ok(result.reason?.action && result.reason.expectedResult && result.reason.observation);
    assert.deepEqual(JSON.parse(calls[2].body.input).recommendationPlan, result.reason);
    if (scenario.score === null) assert.match(result.reason.relationshipStage, /信息不足/);
    if (scenario.signal === "boundary") assert.match(result.reason.action, /不再追问或邀请/);
    const expectedTone = ["boundary", "distress", "tension"].includes(scenario.signal) ? replyTones.gentle
      : scenario.score === null ? replyTones.natural : replyTones.playful;
    assert.equal(JSON.parse(calls[2].body.input).replyTone, expectedTone);
    assert.equal(calls[3].body.state.replyTone, expectedTone);
  });
}

test("early-stage or unclear conversations do not inherit a familiar teasing voice", async () => {
  for (const options of [{ stage: "getting_to_know", signal: "sharing", action: "continue" },
    { stage: "familiar", signal: "unclear", action: "acknowledge" }]) {
    const { fetcher, calls } = fakeModels(0.9, "a", options);
    await createModelAnalyzer(config, fetcher)(input, new AbortController().signal);
    assert.equal(JSON.parse(calls[2].body.input).replyTone, replyTones.natural);
    assert.equal(calls[3].body.state.replyTone, replyTones.natural);
  }
});

for (const options of [
  { signal: "boundary", action: "invite" },
  { signal: "sharing", action: "invite" },
  { signal: "distress", action: "invite" },
  { stage: "unknown", signal: "open_to_meeting", action: "invite" },
  { action: "toString" }
]) {
  test(`unsupported plan stops before generation: ${JSON.stringify(options)}`, async () => {
    const { fetcher, calls } = fakeModels(0.9, "a", options);
    await assert.rejects(createModelAnalyzer(config, fetcher)(input, new AbortController().signal),
      (error: unknown) => error instanceof ServiceError && error.code === "invalid_plan");
    assert.equal(calls.length, 2);
  });
}

test("invalid assessment stops before planning", async () => {
  for (const options of [{ stage: "toString" }, { signal: "invented" }, { rawScore: 9 }]) {
    const { fetcher, calls } = fakeModels(0.9, "a", options);
    await assert.rejects(createModelAnalyzer(config, fetcher)(input, new AbortController().signal));
    assert.equal(calls.length, 1);
  }
});

test("Jev can reject all candidates that do not carry out the plan", async () => {
  const { fetcher } = fakeModels(0.9, "none");
  await assert.rejects(createModelAnalyzer(config, fetcher)(input, new AbortController().signal),
    (error: unknown) => error instanceof ServiceError && error.code === "invalid_selection");
});

test("cancellation after planning prevents generation", async () => {
  const controller = new AbortController();
  const fake = fakeModels();
  const fetcher: typeof fetch = async (url, init) => {
    const response = await fake.fetcher(url, init);
    if (fake.calls.length === 2) controller.abort();
    return response;
  };
  await assert.rejects(createModelAnalyzer(config, fetcher)(input, controller.signal));
  assert.equal(fake.calls.length, 2);
});
