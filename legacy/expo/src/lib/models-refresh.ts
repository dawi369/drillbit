type ModelsRefreshListener = () => void;

const listeners = new Set<ModelsRefreshListener>();

export function notifyModelsRefresh() {
  for (const listener of listeners) {
    listener();
  }
}

export function subscribeToModelsRefresh(listener: ModelsRefreshListener) {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
}
