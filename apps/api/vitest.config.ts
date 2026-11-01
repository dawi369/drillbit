import { readFileSync, writeFileSync } from "node:fs";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
// The test pool's bundled wrangler predates targeted placement, which only matters once deployed. Tests start from
// daily free reps and opt into the lifetime count themselves, so the development Worker's lifetime setting is dropped.
writeFileSync("./wrangler.vitest.jsonc", readFileSync("./wrangler.jsonc", "utf8")
  .replace(/^\s*"placement":.*\n/m, "").replace(/^\s*"FREE_REPS_LIFETIME":.*\n/m, ""));
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
