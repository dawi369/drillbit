type MemoryRefreshListener = () => void;

const listeners = new Set<MemoryRefreshListener>();

export function notifyMemoryRefresh() {
  for (const listener of listeners) {
    listener();
  }
}

export function subscribeToMemoryRefresh(listener: MemoryRefreshListener) {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
}
