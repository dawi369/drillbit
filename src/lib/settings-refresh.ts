type SettingsRefreshListener = () => void;

const listeners = new Set<SettingsRefreshListener>();

export function notifySettingsRefresh() {
  for (const listener of listeners) {
    listener();
  }
}

export function subscribeToSettingsRefresh(listener: SettingsRefreshListener) {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
}
