/** Renderer-independent FFT reduction. One logarithmic band per contour, low inside. */
export const BAND_COUNT = 12;
export const FFT_SIZE = 4096;
export const BAND_EDGES = Array.from(
  { length: BAND_COUNT + 1 },
  (_, i) => 70 * (9000 / 70) ** (i / BAND_COUNT),
);
export const SILENCE = Array<number>(BAND_COUNT).fill(0);
export function binRanges(sampleRate: number, fftSize = FFT_SIZE) {
  const hzPerBin = sampleRate / fftSize;
  return BAND_EDGES.slice(0, -1).map((low, i) => ({
    low: Math.max(1, Math.ceil(low / hzPerBin)),
    high: Math.min(fftSize / 2, Math.ceil(BAND_EDGES[i + 1] / hzPerBin)),
  }));
}
/** Aggregate linear power, then convert to a bounded dB-derived visual target. */
export function reduceSpectrum(
  db: Float32Array,
  ranges: ReturnType<typeof binRanges>,
  sensitivity: number,
) {
  return ranges.map(({ low, high }) => {
    let sum = 0;
    for (let i = low; i < high; i++)
      sum += Number.isFinite(db[i]) ? 10 ** (db[i] / 10) : 0;
    // Sum captures energy in the band; normalization uses the same dB scale for each band.
    const powerDb = 10 * Math.log10(Math.max(1e-12, sum));
    return Math.max(0, Math.min(1, ((powerDb + 70) / 55) * sensitivity));
  });
}
export function envelope(
  current: number,
  target: number,
  dt: number,
  attackMs: number,
  releaseMs: number,
) {
  "worklet";
  const tau = Math.max(1, target > current ? attackMs : releaseMs) / 1000;
  return (
    current +
    (target - current) * (1 - Math.exp(-Math.max(0, Math.min(dt, 0.1)) / tau))
  );
}
export function frequencyLabel(hz: number) {
  return hz >= 1000 ? `${(hz / 1000).toFixed(1)}k` : `${Math.round(hz)}`;
}
