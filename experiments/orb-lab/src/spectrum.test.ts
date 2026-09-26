import { describe, expect, test } from "bun:test";
import {
  BAND_COUNT,
  BAND_EDGES,
  FFT_SIZE,
  binRanges,
  envelope,
  reduceSpectrum,
} from "./spectrum";

describe("frequency-to-contour mapping", () => {
  for (const rate of [44100, 48000, 96000]) {
    test(`${rate} Hz maps every band without overlap`, () => {
      const ranges = binRanges(rate);
      expect(ranges).toHaveLength(BAND_COUNT);
      ranges.forEach((range, i) => {
        expect(range.high).toBeGreaterThan(range.low);
        expect(range.high).toBeLessThanOrEqual(FFT_SIZE / 2);
        if (i) expect(range.low).toBe(ranges[i - 1].high);
        const spectrum = new Float32Array(FFT_SIZE / 2).fill(-Infinity);
        const toneHz = Math.sqrt(BAND_EDGES[i] * BAND_EDGES[i + 1]);
        spectrum[Math.round((toneHz * FFT_SIZE) / rate)] = -25;
        const levels = reduceSpectrum(spectrum, ranges, 1);
        expect(levels[i]).toBeGreaterThan(0.5);
        expect(levels.filter((level) => level > 0)).toHaveLength(1);
      });
    });
  }
  test("silence and invalid samples remain finite and quiet", () => {
    const spectrum = new Float32Array(FFT_SIZE / 2).fill(-Infinity);
    spectrum[9] = NaN;
    spectrum[10] = Infinity;
    expect(reduceSpectrum(spectrum, binRanges(48000), 1)).toEqual(
      Array(BAND_COUNT).fill(0),
    );
  });
  test("power addition is logarithmic and output stays bounded", () => {
    const spectrum = new Float32Array(FFT_SIZE / 2).fill(-Infinity);
    const ranges = binRanges(48000);
    spectrum[ranges[4].low] = -40;
    const one = reduceSpectrum(spectrum, ranges, 1)[4];
    spectrum[ranges[4].low + 1] = -40;
    const two = reduceSpectrum(spectrum, ranges, 1)[4];
    expect(two - one).toBeCloseTo((10 * Math.log10(2)) / 55, 6);
    expect(
      reduceSpectrum(new Float32Array(FFT_SIZE / 2).fill(0), ranges, 2),
    ).toEqual(Array(BAND_COUNT).fill(1));
  });
});
describe("motion envelope", () => {
  test("60 and 120 Hz converge to the same response", () => {
    const integrate = (fps: number, start: number, target: number) => {
      let current = start;
      for (let i = 0; i < fps; i++)
        current = envelope(current, target, 1 / fps, 45, 260);
      return current;
    };
    expect(integrate(60, 0, 1)).toBeCloseTo(integrate(120, 0, 1), 10);
    expect(integrate(60, 1, 0)).toBeCloseTo(integrate(120, 1, 0), 10);
  });
  test("fast attack, soft release, no jump after a long suspension", () => {
    expect(envelope(0, 1, 1 / 60, 45, 260)).toBeGreaterThan(
      1 - envelope(1, 0, 1 / 60, 45, 260),
    );
    expect(envelope(0, 1, 60, 45, 260)).toEqual(envelope(0, 1, 0.1, 45, 260));
    expect(envelope(0.4, 1, -1, 45, 260)).toBe(0.4);
  });
});
