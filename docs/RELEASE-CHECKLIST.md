# Release checklist — Nucleon Transfer v0.1.0-alpha

Direct distribution (Developer ID + notarization). **No App Store** — the app
is sandboxed with hardened runtime; there is no App Store Connect step.

Target artifact: `NucleonTransfer-0.1.0-alpha.zip` containing
`NucleonTransfer.app` (arm64, macOS 26+, `dev.nucleon.NucleonTransfer`).

## Pre-flight (automated, already verified — S5.2)

- [x] `swift test` — 171/171 green.
- [x] Security grep sweep clean: no `print(`/`NSLog`/`Logger`, no
      UserDefaults outside `maxConcurrentUploads`, no password/accessToken in
      interpolated user-facing strings, no `rclone@`, no `yourcompany` bundle
      IDs, no `http://` endpoints (only the plist DOCTYPE + docs).
- [x] Entitlements minimal: `app-sandbox`, `network.client`,
      `files.user-selected.read-write`.
- [x] `ENABLE_HARDENED_RUNTIME = YES` in the Release configuration.
- [x] Release build green (`xcodebuild -configuration Release`); bundle
      contents minimal (`MacOS/NucleonTransfer`, `Info.plist`, `PkgInfo`,
      `Resources/Assets.car` + `AppIcon.icns`).
- [x] Tokens/password/key seeds are memory-only (SessionManager/KeyringCache
      actors); only `transfer-queue.json` persists — paths + IDs, no secrets.
- [x] Decode-error bodies redact credential-shaped JSON fields
      (`APIClient.redactedBodyPrefix`).

## Outstanding human items — must resolve before tagging

- [x] **App icon:** `AppIcon.appiconset` now holds all 10 macOS slots
      generated from `assets/app-icon.png` (the catalog is picked up via the
      synchronized root group — the earlier "not a member of the Resources
      phase" finding was actually the catalog being empty). Verified:
      `Resources/Assets.car` + `AppIcon.icns` in the built `.app`.
      `AccentColor` filled with the icon's blue. Optional polish: rebuild the
      icon in Icon Composer for Liquid Glass layering.
- [ ] **Screenshot:** README references `docs/images/main-window.png`
      (`TODO(maintainer)` line 15) — capture it on a clean session.
- [ ] **Repo URL in README:** no link to
      `https://github.com/errrepe/Neutron-Transfer` anywhere in
      README/CONTRIBUTING/SECURITY (in-app About link is already correct).
- [ ] **Contact channel in SECURITY.md:** "contact the maintainer (channel
      to be defined)" — pick one (GitHub private vulnerability reporting or
      email) and write it in.
- [ ] **Upload allowlist:** direct-API block uploads return Proton 2000 —
      uploads stay disabled in this alpha (documented in README "Known
      limitations"). Confirm the wording is still accurate at release time.

## Build

```sh
cd "NucleonTransfer"   # the .xcodeproj dir
xcodebuild -project NucleonTransfer.xcodeproj \
  -scheme NucleonTransfer -configuration Release \
  -derivedDataPath "/Volumes/SSD 4TB/DEV/DerivedData" \
  archive -archivePath "/tmp/NucleonTransfer-0.1.0-alpha.xcarchive"
```

(Or: Xcode › Product › Archive with the Release configuration.)

## Sign — Developer ID (human step, do NOT automate)

```sh
# Verify identities: need "Developer ID Application: <name> (<TEAMID>)"
security find-identity -v -p codesigning

codesign --deep --force --options runtime \
  --sign "Developer ID Application: <name> (<TEAMID>)" \
  --entitlements NucleonTransfer/NucleonTransfer/NucleonTransfer.entitlements \
  --timestamp \
  "/tmp/NucleonTransfer-0.1.0-alpha.xcarchive/Products/Applications/NucleonTransfer.app"

# Verify: hardened runtime flag + entitlements + sandbox
codesign -dv --verbose=4 NucleonTransfer.app
codesign -d --entitlements :- NucleonTransfer.app
spctl -a -vvv -t execute NucleonTransfer.app   # expect: "rejected" until notarized
```

## Notarize — `notarytool` (human step)

```sh
# Zip the .app first (ditto preserves signatures; do NOT use Finder compress)
ditto -c -k --sequesterRsrc --keepParent NucleonTransfer.app \
  NucleonTransfer-0.1.0-alpha.zip

xcrun notarytool submit NucleonTransfer-0.1.0-alpha.zip \
  --keychain-profile "AC_PASSWORD" --wait

xcrun stapler staple NucleonTransfer.app
spctl -a -vvv -t execute NucleonTransfer.app   # expect: "accepted, source=Notarized Developer ID"
# Re-zip AFTER stapling so the ticket ships inside the archive:
ditto -c -k --sequesterRsrc --keepParent NucleonTransfer.app \
  NucleonTransfer-0.1.0-alpha.zip
```

## Checksum + tag + publish (human step)

```sh
shasum -a 256 NucleonTransfer-0.1.0-alpha.zip
# paste the digest into the release notes

git tag -a v0.1.0-alpha -m "Nucleon Transfer 0.1.0-alpha — first public alpha"
git push origin v0.1.0-alpha

# GitHub release
gh release create v0.1.0-alpha \
  NucleonTransfer-0.1.0-alpha.zip \
  --title "v0.1.0-alpha" --notes-file docs/release-notes-v0.1.0-alpha.md \
  --prerelease
```

## Release notes template (`docs/release-notes-v0.1.0-alpha.md`)

```markdown
# Nucleon Transfer 0.1.0-alpha

First public alpha of a native macOS client for Proton Drive (unofficial —
not affiliated with or endorsed by Proton AG).

**Requires:** macOS 26 or later, Apple Silicon.

## What works
- SRP-6a sign-in with TOTP 2FA; session refresh; memory-only credentials.
- Browse My Files / Photos (read-only) / Computers; sort, filter, multi-select.
- New Folder, Move to Trash.
- Download files/folders to a chosen folder — SHA-256 verified per block.
- Resumable transfer queue (pause/cancel/retry), Transfers popover.

## Known limitations
- **Uploads are disabled**: Proton's block-upload endpoint allowlist rejects
  our honest app-version string (2000). The upload pipeline is implemented
  and validated against the rclone reference but the roundtrip is refused
  server-side. Downloads work.
- No Keychain persistence: you sign in again on every launch (same model as
  the official app's security posture; secrets never touch disk).
- Alpha: expect rough edges. Report issues at the repo's issue tracker.

## Integrity
SHA-256 of `NucleonTransfer-0.1.0-alpha.zip`: `<shasum -a 256 output>`

Signed with Developer ID, notarized by Apple, sandboxed, hardened runtime.
Source: https://github.com/errrepe/Neutron-Transfer (MIT).
```

## Post-release

- [ ] Confirm `spctl`/`stapler validate` passes on the *downloaded* zip on a
      second machine (Gatekeeper quarantine path).
- [ ] Close/label the milestone; bump `MARKETING_VERSION` for the next cycle.
