import "../src/proxy.ts";
import { createDraftAnalyzer } from "../src/pipeline.ts";
import { readModelConfig } from "../src/config.ts";

// Two bounded real Jev requests using fictional text. Never print credentials or provider errors.
const config = readModelConfig(process.env);
if (!config.typeSafeKey) throw new Error("Jev is not configured");
const analyze = createDraftAnalyzer(config);
const context = "我：你说的那家咖啡店，后来去了吗？\n对方：还没呢，最近一直加班。\n我：那等你忙完，有空去坐坐。\n对方：好呀，忙完再说～\n对方：终于忙完了，想出去走走。";
for (const [label, draft] of [["warm", "忙了一天辛苦啦，要不要一起喝杯咖啡？不想出门也可以好好休息。"],
  ["cold", "随便你，别烦我。"]]) {
  const started = Date.now();
  try {
    const result = await analyze({ sessionID: "synthetic-draft-check", revision: 1, source: "test",
      context, draft, draftID: label }, AbortSignal.timeout(15_000));
    console.log(JSON.stringify({ label, before: result.before, after: result.after, delta: result.delta,
      isDemo: result.isDemo, durationMs: Date.now() - started }));
  } catch {
    console.error(JSON.stringify({ label, error: "draft_check_failed" }));
    process.exitCode = 1;
  }
}
