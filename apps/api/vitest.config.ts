import { readFileSync, writeFileSync } from "node:fs";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
// The test pool's bundled wrangler predates targeted placement, which only matters once deployed.
writeFileSync("./wrangler.vitest.jsonc", readFileSync("./wrangler.jsonc", "utf8").replace(/^\s*"placement":.*\n/m, ""));
export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        isolatedStorage: false,
        wrangler: { configPath: "./wrangler.vitest.jsonc" },
      },
    },
  },
});
