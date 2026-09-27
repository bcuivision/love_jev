import "../src/proxy.ts";
import { createReplyGenerator, parseOpenAIAPI } from "../src/openai.ts";
import { ServiceError } from "../src/contracts.ts";

// Uses synthetic text only. This verifies reply generation independently of Jev.
try {
  if (!process.env.OPENAI_API_KEY) throw new Error("missing_key");
  const generate = createReplyGenerator({
    openAIKey: process.env.OPENAI_API_KEY,
    openAIModel: process.env.OPENAI_MODEL || "gpt-4.1-mini",
    openAIBaseURL: process.env.OPENAI_BASE_URL,
    openAIReasoningEffort: process.env.OPENAI_REASONING_EFFORT || undefined,
    openAIAPI: parseOpenAIAPI(process.env.OPENAI_API)
  });
  const candidates = await generate({ strategy: "沿当前话题自然接话，可问一个容易回答的问题。",
    contextIsSufficient: true,
    untrusted_chat_transcript: "我：周末准备做什么？\n对方：想去公园散步，最近天气挺好。"
  }, AbortSignal.timeout(20_000));
  console.log(`Reply provider verified: ${candidates.length} valid candidates. Jev was not called.`);
} catch (error) {
  const cause = error instanceof Error ? error.cause as { code?: unknown } | undefined : undefined;
  const code = error instanceof ServiceError ? error.code
    : typeof cause?.code === "string" && /^[A-Z_]+$/.test(cause.code) ? cause.code
    : error instanceof Error && error.name === "TimeoutError" ? "connection_timeout"
    : !process.env.OPENAI_API_KEY ? "missing_key" : "configuration_or_connection_error";
  console.error(`Reply provider check failed: ${code}. No Jev request was made.`);
  process.exitCode = 1;
}
