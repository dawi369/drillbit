const DEBUG_PREFIX = "[drillbit-debug]";

export function debugLog(scope: string, message: string, payload?: unknown) {
  if (!__DEV__) {
    return;
  }

  if (payload === undefined) {
    console.log(`${DEBUG_PREFIX} ${scope}: ${message}`);
    return;
  }

  console.log(`${DEBUG_PREFIX} ${scope}: ${message}`, payload);
}
