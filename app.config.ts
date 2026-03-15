import type { ConfigContext, ExpoConfig } from "expo/config";

import appJson from "./app.json";

export default ({ config }: ConfigContext): ExpoConfig => {
  const baseConfig = appJson.expo as ExpoConfig;

  return {
    ...baseConfig,
    ...config,
    extra: {
      ...baseConfig.extra,
      ...config.extra,
      openRouterApiKey: process.env.OPENROUTER_API_KEY ?? null,
    },
  };
};
