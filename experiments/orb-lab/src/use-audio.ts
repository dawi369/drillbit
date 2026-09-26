import { useCallback, useEffect, useRef, useState } from "react";
import { AppState } from "react-native";
import {
  AudioContext,
  getAudioDuration,
  type AudioBuffer,
  type AudioBufferSourceNode,
  type AnalyserNode,
  type GainNode,
} from "react-native-audio-api";
import { useSharedValue } from "react-native-reanimated";
import {
  BAND_COUNT,
  FFT_SIZE,
  SILENCE,
  binRanges,
  reduceSpectrum,
} from "./spectrum";

export const clips = [
  {
    id: "voice",
    title: "Interviewer",
    detail: "Speech · natural pauses",
    asset: require("../assets/audio/interviewer.wav") as number,
  },
  {
    id: "bands",
    title: "Band scan",
    detail: "12 tones · one band at a time",
    asset: require("../assets/audio/band-scan.wav") as number,
  },
  {
    id: "sweep",
    title: "Sweep",
    detail: "70 Hz → 9 kHz",
    asset: require("../assets/audio/sweep.wav") as number,
  },
];
export type Clip = {
  id: string;
  title: string;
  detail: string;
  asset: number | string;
};
export type PlayerState = "idle" | "loading" | "playing" | "paused";
export function useAudio() {
  const targets = useSharedValue<number[]>([...SILENCE]);
  const [status, setStatus] = useState<PlayerState>("idle");
  const [error, setError] = useState("");
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [sampleRate, setSampleRate] = useState(48000);
  const [dominant, setDominant] = useState(-1);
  const [loop, setLoop] = useState(true);
  const sensitivity = useRef(1);
  const level = useRef(0.35);
  const generation = useRef(0);
  const alive = useRef(true);
  const ctx = useRef<AudioContext | null>(null);
  const source = useRef<AudioBufferSourceNode | null>(null);
  const analyser = useRef<AnalyserNode | null>(null);
  const gain = useRef<GainNode | null>(null);
  const frame = useRef<number | null>(null);
  const started = useRef(0);
  const buffer = useRef<AudioBuffer | null>(null);
  const cache = useRef(new Map<number | string, AudioBuffer>());
  const desired = useRef<PlayerState>("idle");
  const currentClip = useRef<number | string | null>(null);
  const loopRef = useRef(loop);

  const endPolling = useCallback(() => {
    if (frame.current !== null) cancelAnimationFrame(frame.current);
    frame.current = null;
    targets.set(Array(BAND_COUNT).fill(0));
    if (alive.current) setDominant(-1);
  }, [targets]);
  const stop = useCallback(() => {
    generation.current++;
    desired.current = "idle";
    if (source.current) {
      source.current.onEnded = null;
      try {
        source.current.stop();
      } catch {}
      source.current.disconnect();
    }
    source.current = null;
    buffer.current = null;
    currentClip.current = null;
    endPolling();
    if (alive.current) {
      setStatus("idle");
      setPosition(0);
      setDuration(0);
      setDominant(-1);
    }
  }, [endPolling]);
  const poll = useCallback(() => {
    endPolling();
    const context = ctx.current;
    const node = analyser.current;
    if (!context || !node) return;
    const fft = new Float32Array(node.frequencyBinCount);
    const ranges = binRanges(context.sampleRate);
    let lastRead = 0,
      lastLabel = 0;
    const tick = (now: number) => {
      if (desired.current !== "playing" || !alive.current) return;
      if (now - lastRead >= 1000 / 30) {
        lastRead = now;
        node.getFloatFrequencyData(fft);
        const bands = reduceSpectrum(fft, ranges, sensitivity.current);
        targets.set(bands);
        if (now - lastLabel > 250) {
          lastLabel = now;
          const d = buffer.current?.duration || 1;
          setPosition(Math.max(0, context.currentTime - started.current) % d);
          const peak = Math.max(...bands);
          setDominant(peak > 0.08 ? bands.indexOf(peak) : -1);
        }
      }
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
  }, [endPolling, targets]);
  const pause = useCallback(async () => {
    if (desired.current !== "playing") return;
    const ticket = generation.current;
    desired.current = "paused";
    endPolling();
    try {
      await ctx.current?.suspend();
      if (alive.current && ticket === generation.current) setStatus("paused");
    } catch (e) {
      if (ticket === generation.current) {
        stop();
        setError(String(e));
      }
    }
  }, [endPolling, stop]);
  const play = useCallback(
    async (clip: Clip) => {
      if (desired.current === "loading") return;
      if (
        desired.current === "paused" &&
        currentClip.current === clip.asset &&
        source.current
      ) {
        const ticket = ++generation.current;
        desired.current = "loading";
        setStatus("loading");
        try {
          await ctx.current?.resume();
          if (!alive.current || ticket !== generation.current) return;
          desired.current = "playing";
          setStatus("playing");
          poll();
        } catch (e) {
          if (ticket === generation.current) {
            stop();
            setError(String(e));
          }
        }
        return;
      }
      stop();
      const ticket = generation.current;
      desired.current = "loading";
      setStatus("loading");
      setError("");
      try {
        if (!ctx.current) {
          const context = new AudioContext({ sampleRate: 48000 });
          ctx.current = context;
          const node = context.createAnalyser();
          node.fftSize = FFT_SIZE;
          node.smoothingTimeConstant = 0;
          const volume = context.createGain();
          volume.gain.value = level.current;
          // Analysis is before listening volume: lowering speaker volume must not flatten the orb.
          node.connect(volume);
          volume.connect(context.destination);
          analyser.current = node;
          gain.current = volume;
          setSampleRate(context.sampleRate);
        }
        const context = ctx.current;
        let decoded = cache.current.get(clip.asset);
        if (!decoded) {
          if (typeof clip.asset === "string") {
            const seconds = await getAudioDuration(clip.asset);
            if (!alive.current || ticket !== generation.current) return;
            if (!Number.isFinite(seconds) || seconds <= 0 || seconds > 180)
              throw new Error("Choose an audio clip shorter than 3 minutes.");
          }
          decoded = await context.decodeAudioData(clip.asset);
          if (!alive.current || ticket !== generation.current) return;
          if (decoded.duration > 180)
            throw new Error("Choose a clip shorter than 3 minutes.");
          // Only the three small bundled fixtures are cached. Imported PCM can be large.
          if (typeof clip.asset === "number")
            cache.current.set(clip.asset, decoded);
        }
        await context.resume();
        if (!alive.current || ticket !== generation.current) return;
        buffer.current = decoded;
        currentClip.current = clip.asset;
        const next = context.createBufferSource();
        next.buffer = decoded;
        next.loop = loopRef.current;
        next.connect(analyser.current!);
        next.onEnded = () => {
          if (source.current !== next || !alive.current) return;
          next.disconnect();
          source.current = null;
          desired.current = "idle";
          endPolling();
          setStatus("idle");
          setPosition(decoded.duration);
        };
        source.current = next;
        started.current = context.currentTime;
        next.start();
        desired.current = "playing";
        setStatus("playing");
        setDuration(decoded.duration);
        poll();
      } catch (e) {
        if (alive.current && ticket === generation.current) {
          stop();
          setError(e instanceof Error ? e.message : String(e));
        }
      }
    },
    [endPolling, poll, stop],
  );
  const setVolume = (value: number) => {
    level.current = value;
    if (gain.current) gain.current.gain.value = value;
  };
  const setSensitivity = (value: number) => {
    sensitivity.current = value;
  };
  useEffect(() => {
    loopRef.current = loop;
    if (source.current) source.current.loop = loop;
  }, [loop]);
  useEffect(() => {
    alive.current = true;
    const buffers = cache.current;
    const sub = AppState.addEventListener("change", (value) => {
      if (value !== "active") stop();
    });
    return () => {
      alive.current = false;
      sub.remove();
      stop();
      void ctx.current?.close();
      ctx.current = null;
      buffers.clear();
    };
  }, [stop]);
  return {
    targets,
    status,
    error,
    position,
    duration,
    sampleRate,
    dominant,
    loop,
    setLoop,
    setSensitivity,
    play,
    pause,
    stop,
    setVolume,
  };
}
