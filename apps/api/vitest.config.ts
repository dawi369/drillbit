import { readFileSync, writeFileSync } from "node:fs";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
// The test pool's bundled wrangler predates targeted placement, which only matters once deployed. Tests start
// ungated with daily free reps and opt into the gate and the lifetime count themselves, so the development Worker's
// settings for both are reset here.
writeFileSync("./wrangler.vitest.jsonc", readFileSync("./wrangler.jsonc", "utf8")
  .replace(/^\s*"placement":.*\n/m, "").replace(/^\s*"FREE_REPS_LIFETIME":.*\n/m, "")
  .replace(/^(\s*)"PRACTICE_GATE": "true",/m, '$1"PRACTICE_GATE": "false",'));
export default defineWorkersConfig({
  test: {
    // The Sentry SDK is hundreds of small modules; loaded one by one per test file they overwhelm the pool's module
    // server. Pre-bundled, each file loads it once.
    deps: { optimizer: { ssr: { enabled: true, include: ["@sentry/cloudflare"] } } },
    poolOptions: {
      workers: {
        isolatedStorage: false,
        wrangler: { configPath: "./wrangler.vitest.jsonc" },
      },
    },
  },
});
