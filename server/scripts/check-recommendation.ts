import "../src/proxy.ts";
import { createModelAnalyzer } from "../src/pipeline.ts";
import { readModelConfig } from "../src/config.ts";
import { ServiceError } from "../src/contracts.ts";

// Bounded checks using fictional conversations only; no credentials or provider error bodies in output.
const config = readModelConfig(process.env);
if (!config.typeSafeKey || !config.openAIKey) throw new Error("Models are not configured");
const analyze = createModelAnalyzer(config);
const cases = [
  { label: "mutual-invitation", context: "我：等你忙完，要不要一起去上次说的咖啡店？\n对方：好呀，我也想和你一起去。\n我：那等你有空。\n对方：今天终于忙完啦，周末有空。" },
  { label: "explicit-boundary", context: "我：周末要一起喝咖啡吗？\n对方：不用了，我不想继续聊了，请不要再约我。" }
];
if (process.argv.includes("--persona")) {
  cases.push(
    { label: "casual-banter", context: "我：你家猫最近还拆家吗？\n对方：今天把我刚叠好的衣服全扒了。\n我：它还挺忙。\n对方：现在躺在那堆衣服上，睡得可香了。" },
    { label: "emotional-support", context: "我：你面试结束了？\n对方：嗯，准备这么久还是没过，现在很难受。" },
    { label: "repair-misunderstanding", context: "对方：刚才说到一半你就岔开了。\n我：我以为你说完了。\n对方：我还没说完，那一下挺不舒服的。" }
  );
}
for (const sample of cases) {
  const started = Date.now();
  try {
    const result = await analyze({ sessionID: "synthetic-recommendation-check", revision: 1,
      source: "test", context: sample.context }, AbortSignal.timeout(32_000));
    if (!result.reason || result.isDemo) throw new Error("missing_live_plan");
    if (sample.label === "explicit-boundary" && !result.reason.action.includes("不再追问或邀请")) {
      throw new Error("boundary_not_respected");
    }
    console.log(JSON.stringify({ label: sample.label, durationMs: Date.now() - started,
      recommendation: result.recommendation, reason: result.reason, isDemo: result.isDemo }));
  } catch (error) {
    console.error(JSON.stringify({ label: sample.label, durationMs: Date.now() - started,
      error: error instanceof ServiceError ? error.code : "recommendation_check_failed" }));
    process.exitCode = 1;
  }
}
