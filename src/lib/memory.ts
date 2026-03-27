export function completionScoreToPercent(score?: number) {
  if (typeof score !== "number" || Number.isNaN(score)) {
    return null;
  }

  return Math.max(0, Math.min(100, Math.round(score * 100)));
}

export function formatCompletionScore(score?: number) {
  const percent = completionScoreToPercent(score);
  return percent == null ? "-" : `${percent}%`;
}

export function getCompletionScoreBarPercent(score?: number) {
  const percent = completionScoreToPercent(score);
  return percent == null ? 32 : Math.max(20, Math.min(100, percent));
}
