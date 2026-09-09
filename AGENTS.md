# Drillbit

Native iOS client and independent Cloudflare backend. Product and architectural decisions live in `docs/architecture.md`; consult it when changing navigation, persistence, API contracts, scheduling, credentials or account lifecycle. `docs/operations.md` covers local setup, deployment and recovery.

- Preserve user work. `legacy/expo` is archived reference, excluded from active builds.
- Domain operations are independent of HTTP, Cloudflare bindings and SwiftUI views.
- Every account-owned read/write is scoped by the authenticated account. Credentials and private practice content stay out of logs.
- Test lifecycle concurrency and failure recovery against D1; mocked happy paths are insufficient.
- API changes update OpenAPI and fixtures; native DTOs remain compatible with the contract.
- Native UI uses system fonts, semantic colors, SF Symbols and system controls. Custom spacing uses 4-point increments; custom surfaces use a 12-point radius. System component geometry takes precedence over legacy web rules.
- Preserve Dynamic Type, VoiceOver, reduced motion and native keyboard behavior.
- Reports distinguish compiled/tested, live-service verified and physical-device verified outcomes.
