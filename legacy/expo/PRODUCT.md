# Drillbit Product Context

register: product

## Product Purpose

Drillbit is a local-first, widget-first interview practice app for software engineers. It helps users build stronger verbal reasoning for system design, architecture, distributed systems, scalability, reliability, trade-offs, and senior-level product engineering interviews. Algorithmic prompts are supported, but they are not the default personality of the product.

The home-screen widget is the primary daily touchpoint. The app exists to configure the practice loop, solve the active challenge, and review memory from completed sessions.

## Users

- Software engineers preparing for mid-level through staff interviews.
- Users who want short, recurring reps instead of a large course dashboard.
- Users who value privacy, local history, and controllable model access.
- Advanced users who may bring their own OpenRouter key, remote endpoint, or local model setup.

## Product Principles

- One active challenge at a time. Avoid queue management and feed complexity.
- Widget first, app second. The app should support the daily rep, not become a content library.
- Local by default. Challenge history, memory, model catalog, and settings stay on-device.
- Guidance should be Socratic until the user asks for a reveal.
- Every screen should feel calm, fast, and directly useful.
- Prefer native Expo and React Native patterns before web-shaped fallbacks.

## Tone

Direct, quiet, and practical. Copy should sound like a competent interview coach: specific, brief, and focused on the next useful action. Avoid motivational fluff, cute empty states, and generic AI wording.

## Anti-References

- Course marketplaces with busy catalogs and progress gamification.
- LeetCode-style code-first drilling as the default experience.
- SaaS dashboards with decorative metrics, marketing gradients, and card grids.
- Chat apps where the assistant becomes the whole product.

## Experience Shape

Main surfaces:

- Params: configure focus prompt, difficulty, help mode, model, and challenge cadence.
- Answer: focused solving workspace with one central notes surface and optional coach/reveal assistance.
- Memory: compact review of repeated strengths, repeated gaps, recent sessions, and topic rollups.
- Dev: local debug tools in development builds only.

The product should be dense enough for repeated use, but never visually noisy. The best version feels like a native utility for serious practice.
