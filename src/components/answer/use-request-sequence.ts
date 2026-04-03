import { useCallback, useRef } from "react";

export function useRequestSequence() {
  const requestIdRef = useRef(0);

  const beginRequest = useCallback(() => {
    requestIdRef.current += 1;
    return requestIdRef.current;
  }, []);

  const invalidateRequest = useCallback(() => {
    requestIdRef.current += 1;
  }, []);

  const isCurrentRequest = useCallback(
    (requestId: number) => requestIdRef.current === requestId,
    [],
  );

  return {
    beginRequest,
    invalidateRequest,
    isCurrentRequest,
  };
}
