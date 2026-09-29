# Neutron Transfer

Nativo macOS client for Proton Drive focused on what the official app does not allow: arbitrary upload via drag-and-drop preserving folder structure, and download to a user-chosen folder.

> **Disclaimer:** Neutron Transfer is an independent third-party client. It is not officially supported by, affiliated with, or endorsed by Proton. No Proton logos or branding are used in this project.

## Status

`0.1.0-alpha` — documentation + repo bootstrap phase. No usable build yet. See `docs/ROADMAP.md`.

## The Gap

The native Proton Drive app for macOS does not support:

1. Arbitrary file/folder upload via drag-and-drop with structure preservation.
2. Download to an arbitrary user-chosen destination folder.

Neutron Transfer exists to close exactly that gap, nothing more for MVP.

## MVP Features

- **Auth:** username + password with SRP-6a, TOTP 2FA support, session refresh, Keychain storage.
- **Browse:** list vault / folders, navigate tree.
- **Upload:**
  - Drag-and-drop files and folders onto the app.
  - Recursive folder creation preserving hierarchy.
  - Encrypted block upload with progress, pause, cancel, retry.
- **Download:**
  - Choose destination via system folder picker.
  - Mirror remote tree locally.
  - Parallel decrypt + SHA256 verify.
- **Transfer queue:** persistent queue (SwiftData), bounded concurrency (4–8), backoff + jitter, Human Verification handling (HV 9001).

Non-goals for MVP: full sync engine, search index, sharing links, multi-account, background daemon.

## Stack

- macOS native, SwiftUI
- Swift 6 (strict concurrency, `Sendable`, `actor` isolation where needed)
- Swift Package Manager, no CocoaPods / Carthage
- Crypto: native Swift implementation (SRP-6a, AES-CFB block crypto + SHA256 + MDC) — no binding to incubating SDK
- Persistence: Keychain (secrets) + SwiftData (transfer queue)
- Concurrency: Swift `TaskGroup` with limited parallelism

## Rules (non-negotiable)

- Official API endpoints only. No scraping, no undocumented endpoints.
- HTTP header on every call: `x-pm-appversion: external-drive-neutron_transfer@0.1.0-alpha`
- Event-based sync where applicable. No polling loops.
- No Proton logos, names in UI beyond factual interoperability labels, or any implication of official status.
- Crypto migration breaking change expected end of 2026 / early 2027 — architecture must isolate crypto for swap.

## Docs

- `docs/ARCHITECTURE.md` — layers, engines, concurrency
- `docs/AUTH.md` — SRP flow, 2FA, refresh, Keychain, errors
- `docs/TRANSFERS.md` — upload / download engines in detail
- `docs/SDK-STRATEGY.md` — why native Swift instead of SDK binding
- `docs/ROADMAP.md` — F0–F6 phases
- `docs/DECISIONS/` — ADRs
- `CONTRIBUTING.md` — workflow, Xcode MCP, DerivedData rules
- `SECURITY.md` — reporting, secret handling

## Contributing

Open source under MIT. See `CONTRIBUTING.md` and `LICENSE`.

1. Read `docs/ARCHITECTURE.md`, `docs/AUTH.md`, `docs/TRANSFERS.md`.
2. Check `docs/ROADMAP.md` for the current phase.
3. Open an issue before large PRs.

## License

MIT — see `LICENSE`. Copyright 2026 Neutron Transfer contributors.
