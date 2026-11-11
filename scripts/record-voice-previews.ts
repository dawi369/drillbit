/**
 * Records the Settings voice previews from GPT-Live itself, so a preview sounds exactly like a mock.
 * Each voice opens one short WebSocket session (billed like any voice session, about 15 seconds minimum).
 *
 *   OPENAI_API_KEY=… bun scripts/record-voice-previews.ts [voice…]
 *
 * Writes apps/ios/Drillbit/Resources/VoicePreviews/voice-<name>.m4a. Never logs the key.
 */
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { liveVoices } from "../apps/api/src/domain";

const key = process.env.OPENAI_API_KEY;
if (!key) throw new Error("OPENAI_API_KEY missing");
const line = "Hey, I'm your interviewer today. Let's design a URL shortener. Talk me through how you'd start, and think out loud.";
const out = new URL("../apps/ios/Drillbit/Resources/VoicePreviews/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });
const rate = 24000;
const voices = process.argv.slice(2).length ? process.argv.slice(2) : [...liveVoices];

function record(voice: string): Promise<{ pcm: Buffer; said: string }> {
  return new Promise((resolve, reject) => {
    let said = "";
    // Bun's WebSocket accepts request headers.
    const ws = new WebSocket("wss://api.openai.com/v1/live/sessions", { headers: { Authorization: `Bearer ${key}` } } as any);
    const chunks: Buffer[] = [];
    let silence: ReturnType<typeof setInterval> | undefined, quiet: ReturnType<typeof setTimeout> | undefined, closing = false;
    const finish = () => {
      if (closing) return;
      closing = true;
      ws.send(JSON.stringify({ type: "session.close" }));
      setTimeout(() => ws.close(), 8000);
    };
    const deadline = setTimeout(finish, 30000);
    ws.onopen = () => ws.send(JSON.stringify({
      type: "session.start",
      session: {
        model: "gpt-live-1",
        store: false,
        instructions: "You record a short voice sample for a practice app. Say the developer's line once, word for word, in a warm, relaxed interviewer tone. Then stop and stay silent.",
        input: [{ type: "message", role: "developer", content: [{ type: "input_text", text: `Say this now, exactly: "${line}"` }] }],
        audio: { format: { type: "audio/pcm", rate }, output: { voice } },
      },
    }));
    ws.onmessage = (message) => {
      const event = JSON.parse(String(message.data));
      if (event.type === "session.started") {
        // GPT-Live expects a live input stream; 100 ms of silence at a time keeps it running.
        const frame = Buffer.alloc(rate / 10 * 2).toString("base64");
        silence = setInterval(() => !closing && ws.send(JSON.stringify({ type: "session.input_audio.append", audio: frame })), 100);
      } else if (event.type === "session.output_audio.delta") {
        chunks.push(Buffer.from(event.delta, "base64"));
      } else if (event.type === "session.output_transcript.delta") {
        // Output audio keeps streaming silence, so the transcript marks the end of speech.
        said += event.delta;
        clearTimeout(quiet);
        quiet = setTimeout(finish, 2500);
      } else if (event.type === "error") {
        console.error(voice, JSON.stringify(event.error ?? event).slice(0, 300));
      }
    };
    ws.onclose = () => {
      clearInterval(silence); clearTimeout(quiet); clearTimeout(deadline);
      chunks.length ? resolve({ pcm: Buffer.concat(chunks), said }) : reject(new Error(`${voice}: no audio`));
    };
    ws.onerror = () => reject(new Error(`${voice}: connection failed`));
  });
}

/** Keeps the spoken part: 150 ms before the first loud sample, 400 ms after the last. */
function trim(pcm: Buffer) {
  const samples = pcm.length / 2, loud = (i: number) => Math.abs(pcm.readInt16LE(i * 2)) > 600;
  let first = 0, last = samples - 1;
  while (first < samples && !loud(first)) first++;
  while (last > first && !loud(last)) last--;
  return pcm.subarray(Math.max(0, first - Math.round(rate * 0.15)) * 2, Math.min(samples, last + Math.round(rate * 0.4)) * 2);
}

function wav(pcm: Buffer) {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0); header.writeUInt32LE(36 + pcm.length, 4); header.write("WAVE", 8);
  header.write("fmt ", 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28); header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write("data", 36); header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

for (const voice of voices) {
  try {
    const recorded = await record(voice), pcm = trim(recorded.pcm);
    const temp = `/tmp/voice-${voice}.wav`;
    writeFileSync(temp, wav(pcm));
    execFileSync("afconvert", ["-f", "m4af", "-d", "aac", "-b", "64000", temp, `${out}voice-${voice}.m4a`]);
    rmSync(temp);
    console.log(`${voice}: ${(pcm.length / 2 / rate).toFixed(1)} s · ${recorded.said.trim()}`);
  } catch (error) {
    console.error(String(error));
  }
}
