# ADR-003 — SDK status as of 2026-10: stay native Swift

- Status: Accepted
- Date: 2026-10-02 (SDK state checked 2026-10-01)
- Context: pre-release check of `ProtonDriveApps/sdk`, which Proton presents
  as the supported path for third-party Drive clients.

## Decision

Keep the native Swift implementation (ADR-001 stands). The SDK is a
reference for endpoints, not a dependency.

## SDK state (checked 2026-10-01)

- `ProtonDriveApps/sdk`: C# + TypeScript, MIT, ~1.1k commits. The `Client`
  module covers listing, upload, download, move, rename, trash, sharing and
  events. `Sync`/`Search` are still "coming soon". **No auth/session** —
  SRP login, key unlock and session management would remain ours regardless.
- `ProtonDriveApps/sdk-swift`: 2 commits, no release. Still not usable.
- The SDK README sets the rules for third-party apps this project must
  follow: an honest `x-pm-appversion: external-drive-{name}@{semver}-{channel}`
  header, event-based sync instead of polling or frequent recursive
  traversals, clear third-party disclosure where credentials are requested,
  and no Proton branding.

## Why native remains correct

There is no Swift SDK to adopt. Binding to the C# core means opaque FFI on
exactly the paths we need to audit (keys, crypto), and it turns the crypto
migration expected end of 2026 / early 2027 into a dependency on upstream
timing. Native keeps `Core/Crypto` swappable in isolation.

## Mitigations for going off-SDK

- Honest `x-pm-appversion` on every call (API + storage host) — never
  impersonating another client, even where the server would allow it.
  Consequence already observed: `POST /drive/blocks` rejects our string
  (allowlist, error 2000); uploads stay disabled rather than spoofed.
- Event-based sync is on the backlog (B3); until it lands we rely on
  manual refresh plus targeted invalidation after local writes — no fixed
  polling, no frequent full-tree traversals.
- Third-party disclaimer on the login screen, the About panel and the README.

## Re-evaluation trigger

Revisit if either lands: (a) a usable `sdk-swift` release (semver tags,
CI, published crypto vectors), or (b) the announced crypto migration —
whichever forces a rewrite of `Core/Crypto` anyway. Any switch goes through
a new ADR; no silent adoption.
