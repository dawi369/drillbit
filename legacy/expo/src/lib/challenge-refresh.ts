type ChallengeRefreshListener = () => void;

const listeners = new Set<ChallengeRefreshListener>();

export function notifyChallengeRefresh() {
  for (const listener of listeners) {
    listener();
  }
}

export function subscribeToChallengeRefresh(listener: ChallengeRefreshListener) {
  listeners.add(listener);

  return () => {
    listeners.delete(listener);
  };
}
