# Drillbit design directions · app-wide comparison

[Figma comparison](https://www.figma.com/design/ATjVdRblnJ1wlMcxWF33lM)

The first page compares two directions side by side. Each has the same nine product moments: Welcome, Focus, Home, Session brief, Voice room, Feedback, Recall, Library, and Settings. A tenth paired screen shows the voice-to-type handoff. The particle direction also has a visual-system board with eight sampled color roles and six agent states. A second page, **Signal · yellow particle**, studies a third direction with a tighter voice-first flow.

## Particle direction

The supplied screenshot sets the palette and hierarchy. The upper field uses `#414141` and `#373737`, the lower field `#262626` and `#181818`. Fine silver particles use `#D4D4D4` and `#8C8C8C`; `#A2A2A2` carries secondary information. `#F0817B` is reserved for the active voice/action cue. The voice room remains full-bleed with a central cloud, narrow waveform, timer, and one transport control. Other screens use open space, restrained typography, and small particle references without repeating a central card.

The agent's six proposed states are ready, listening, thinking, speaking, muted, and reconnecting. The native experiment in `experiments/orb-lab` drives a particle field from 12 frequency bands of local playback. The Figma states are static design studies, not recorded or live audio.

## Mirage direction

The orange comparison uses the existing editor-inspired graphite/amber language: `#202530` background, `#292F3A` surface, `#EDEFF2` primary ink, and `#E8C17D` action. Its amber contour is the agent identity. It is included to compare the same flows against the particle concept; the previous interactive browser study and original Figma draft remain untouched.

## Signal direction

[Open the Signal page in Figma](https://www.figma.com/design/ATjVdRblnJ1wlMcxWF33lM?node-id=3-4551)

Signal combines the silver voice-reactive particle field with the original yellow (`#FFCC65`) over graphite `#1F2430` and raised `#232834` surfaces. Yellow is concentrated in the field's core, waveform, live state, and primary actions. The six frames cover Welcome, Home, Session brief, Voice room, Reflection, and the design rules. The interview question sits above the field so motion never competes with it; explicit voice controls sit below. Home presents a single upcoming question and an open event timeline, while Reflection turns answer evidence into one Recall item. The Figma field shows a still listening state; frequency-driven motion remains in the native Orb Lab experiment.

## Product rules to retain

- Start, stop, mute, finish, and text handoff must be explicit. Voice and type share one conversation context.
- Feedback should point to the learner's actual answer, and Recall should carry an idea forward from it. All copy here is illustrative.
- Motion must have a readable state label, a still reduced-motion presentation, and a distinct reconnecting state.
- Auth, access, audio transport, transcript persistence, interruptions, and lock-screen behavior are implementation work. These Figma screens are visual concepts, not native or service verification.

The SVGs are editable in Figma as frames, vectors, and text. Regenerate the first page with `python3 generate_boards.py` and Signal with `python3 generate_signal.py`; the saved Figma canvas is a snapshot, so regenerate and reimport for broad changes. Visual inspection in Figma desktop confirmed both pages and the supplemental studies.
