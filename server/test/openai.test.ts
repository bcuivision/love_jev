import test from "node:test";
import assert from "node:assert/strict";
import { createReplyGenerator, parseOpenAIAPI, parseCandidates } from "../src/openai.ts";
import { ServiceError } from "../src/contracts.ts";

const config = { openAIKey: "test-key", openAIModel: "gpt-4.1-mini", openAIAPI: "chat_completions" as const };
const context = { strategy: "自然接话", contextIsSufficient: true, untrusted_chat_transcript: "对方：今天很开心。" };
const signal = () => new AbortController().signal;
const errorCode = (code: string) => (error: unknown) => error instanceof ServiceError && error.code === code;

test("compatible string arrays retain duplicate, length, and single-line validation", () => {
  assert.deepEqual(parseCandidates('{"candidates":["你好","今天好吗","辛苦啦"]}'), ["你好", "今天好吗", "辛苦啦"]);
  for (const candidates of [["一样", "一样", "不同"], ["长".repeat(33), "短", "更短"], ["a\nb", "c", "d"], [1, "b", "c"]]) {
    assert.throws(() => parseCandidates(JSON.stringify({ candidates })), ServiceError);
  }
});

test("provider URL and API mode validation fails before sending a credential", () => {
  for (const openAIBaseURL of ["bad-url", "http://example.com/v1", "https://u:p@example.com/v1",
    "https://example.com/v1?key=secret", "https://example.com/v1#fragment"]) {
    assert.throws(() => createReplyGenerator({ ...config, openAIBaseURL }));
  }
  assert.equal(parseOpenAIAPI(undefined), "responses");
  assert.throws(() => parseOpenAIAPI("unsupported"));
});

test("provider requests reject redirects and forward cancellation", async () => {
  const controller = new AbortController();
  const generate = createReplyGenerator(config, async (_url, init) => {
    assert.equal(init?.redirect, "error");
    assert.equal(init?.signal, controller.signal);
    assert.equal(JSON.parse(String(init?.body)).store, false);
    return Response.json({ choices: [{ finish_reason: "stop", message: {
      content: JSON.stringify({ candidates: [{ text: "开心就好！" }, { text: "发生什么好事啦？" }, { text: "听起来很不错呀。" }] })
    } }] });
  });
  assert.equal((await generate(context, controller.signal)).length, 3);
  controller.abort();
  await assert.rejects(generate(context, controller.signal), { name: "AbortError" });
});

test("upstream HTTP failures do not leak provider error bodies", async () => {
  const generate = createReplyGenerator(config, async () => Response.json({ error: "private-provider-detail" }, { status: 401 }));
  await assert.rejects(generate(context, signal()), errorCode("generation_unavailable"));
});

test("truncated, refused, or non-text chat completions never become recommendations", async () => {
  for (const choice of [
    { finish_reason: "length", message: { content: "{}" } },
    { finish_reason: "stop", message: { refusal: "refused", content: "{}" } }
  ]) {
    const generate = createReplyGenerator(config, async () => Response.json({ choices: [choice] }));
    await assert.rejects(generate(context, signal()), errorCode("incomplete_generation"));
  }
  const generate = createReplyGenerator(config, async () => Response.json({ choices: [
    { finish_reason: "stop", message: { content: [{ text: "unexpected shape" }] } }
  ] }));
  await assert.rejects(generate(context, signal()), errorCode("invalid_candidates"));
});
