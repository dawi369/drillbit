# Drillbit

A native iPhone practice space for software engineering interviews: one question, room to think, a coach when useful, and a short reflection worth keeping.

- **iOS 26+ / SwiftUI** — Today, Memory, full-screen practice, keyboard dictation, WidgetKit and local reminders.
- **Independent backend** — Cloudflare Workers, D1 and Workflows; Clerk authentication; managed or encrypted OpenRouter BYOK.
- **Recoverable work** — SwiftData drafts and outbox, revision-checked cloud writes, durable completion and explicit conflicts.
- **Android-ready boundary** — versioned HTTP/OpenAPI; future Kotlin UI consumes the same service.

## Development

```sh
bun install --frozen-lockfile
bun run typecheck
bun run test
bun run contracts
bun run ios:generate
swift test --package-path apps/ios -j 2
open apps/ios/Drillbit.xcodeproj
```

Configure Clerk, Apple capabilities and server secrets using [operations](docs/operations.md). Local configuration files are ignored. Never put provider secrets in an iOS build. `--fixtures` is a Debug-only simulator launch argument for an isolated sample practice session.

[Product vision](docs/product-vision.md) · [Architecture](docs/architecture.md) · [Operations and deployment](docs/operations.md) · [Verification and release gates](docs/acceptance.md) · [HTTP contract](packages/contracts/openapi.json)

The former Expo application is preserved under `legacy/expo`, outside all new build targets. This checkout is a native rebuild under verification, not a signed TestFlight release.
