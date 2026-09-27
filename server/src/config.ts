import { parseOpenAIAPI } from "./openai.ts";
import type { ModelConfig } from "./pipeline.ts";

export function readModelConfig(env: NodeJS.ProcessEnv): ModelConfig {
  const provider = env.JEV_PROVIDER || "typesafe";
  if (provider !== "typesafe" && provider !== "shared") throw new Error("JEV_PROVIDER must be typesafe or shared");
  if (provider === "shared" && !env.OPENAI_BASE_URL) throw new Error("Shared Jev provider requires OPENAI_BASE_URL");
  return {
    openAIKey: env.OPENAI_API_KEY ?? "",
    openAIBaseURL: env.OPENAI_BASE_URL,
    openAIAPI: parseOpenAIAPI(env.OPENAI_API),
    openAIReasoningEffort: env.OPENAI_REASONING_EFFORT || undefined,
    openAIModel: env.OPENAI_MODEL || "gpt-4.1-mini",
    jevModel: env.JEV_MODEL || "jev-latest",
    typeSafeKey: provider === "shared" ? env.OPENAI_API_KEY ?? "" : env.TYPESAFE_API_KEY ?? "",
    typeSafeBaseURL: provider === "shared" ? env.OPENAI_BASE_URL : env.TYPESAFE_BASE_URL
  };
}
