import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { readFileSync, writeFileSync } from "node:fs";
// The test pool's bundled wrangler predates targeted placement, which only matters once deployed. Tests start
// ungated with daily free reps and opt into the gate and the lifetime count themselves, so the development Worker's
// settings for both are reset here.
writeFileSync("./wrangler.vitest.jsonc", readFileSync("./wrangler.jsonc", "utf8")
  .replace(/^\s*"placement":.*\n/m, "").replace(/^\s*"ratelimits":.*\n/gm, "").replace(/^\s*"FREE_REPS_LIFETIME":.*\n/m, "")
  .replace(/^(\s*)"PRACTICE_GATE": "true",/m, '$1"PRACTICE_GATE": "false",'));
export default defineWorkersConfig({
  test: {
    // CI runners are several times slower than a laptop; the simulated Pro week makes hundreds of requests per test.
    testTimeout: 30_000,
    // Files share one D1, and the cron sweeps in jobs/daily tests requeue any job left running for two minutes of
    // wall time. A simulated week dated before today looks stale to them, so files run one at a time.
    poolOptions: {
      workers: {
        singleWorker: true,
        isolatedStorage: false,
        wrangler: { configPath: "./wrangler.vitest.jsonc" },
      },
    },
    // The Sentry SDK is hundreds of small modules; loaded one by one per test file they overwhelm the pool's module
    // server. Pre-bundled, each file loads it once.
    deps: { optimizer: { ssr: { enabled: true, include: ["@sentry/cloudflare"] } } },
  },
});
