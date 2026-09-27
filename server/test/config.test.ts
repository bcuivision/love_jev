import test from "node:test";
import assert from "node:assert/strict";
import { readModelConfig } from "../src/config.ts";

test("shared Jev explicitly reuses the configured provider and key", () => {
  const config = readModelConfig({ JEV_PROVIDER: "shared", OPENAI_BASE_URL: "https://api.0-0.pro/v1",
    OPENAI_API_KEY: "shared-test-key", TYPESAFE_API_KEY: "unused-official-key" });
  assert.equal(config.typeSafeKey, "shared-test-key");
  assert.equal(config.typeSafeBaseURL, config.openAIBaseURL);
});

test("official Jev never silently inherits a different provider's credential", () => {
  const config = readModelConfig({ OPENAI_BASE_URL: "https://api.0-0.pro/v1", OPENAI_API_KEY: "shared-test-key" });
  assert.equal(config.typeSafeKey, "");
  assert.equal(config.typeSafeBaseURL, undefined);
});

test("shared Jev requires an explicit endpoint and valid provider selection", () => {
  assert.throws(() => readModelConfig({ JEV_PROVIDER: "shared", OPENAI_API_KEY: "test" }));
  assert.throws(() => readModelConfig({ JEV_PROVIDER: "typo" }));
});
