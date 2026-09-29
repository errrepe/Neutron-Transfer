# ROADMAP — F0 → F6

> MVP = fila completa de upload + download funcionando contra conta real. Sem sync contínuo.

## F0 — Docs + Repo bootstrap (atual)

- [x] README, LICENSE MIT, .gitignore
- [x] docs/ARCHITECTURE, AUTH, TRANSFERS, SDK-STRATEGY, ROADMAP, DECISIONS
- [x] CONTRIBUTING, SECURITY
- [ ] Criar repo nova (público, MIT), push inicial — manual, sem CI GitHub (ver CONTRIBUTING)
- Critério de saída: docs revisados, repo criado, próxima fase desbloqueada.

## F1 — Scaffold + Build verde

- Criar projeto Xcode macOS SwiftUI Swift 6 (SPM, sem deps nativas ainda salvo BigInt avaliado).
- Alvos: `NeutronTransfer` (app) + `NeutronTransferTests` (unit).
- Build verde no Mac local, DerivedData externo `/Volumes/SSD 4TB/DEV/DerivedData`.
- Sem builds concorrentes. Via Xcode MCP.
- Critério: `BuildProject` passa, app vazio abre.

## F2 — Spike SRP (sem UI)

- `SRPClient` nativo + vetores `go-proton-api`/`rclone` em testes.
- `POST /auth/v4/info` → proof → `POST /auth` contra conta teste.
- 2FA TOTP manual se exigido. Mede NTP skew.
- Nenhum token commitado, nenhum log com segredo.
- Critério: login + refresh + logout funcionam via teste CLI/`RunCodeSnippet`, documentado em AUTH.

## F3 — Listing (browse)

- `SessionManager` + `DriveClient` + `KeyUnlocker` (User→Address→Share).
- Lista vault/folders, navega árvore, event-based invalidation básica.
- UI: BrowserView somente-leitura.
- Critério: navegar conta real, sem crash em unlock, erros HV/429 tratados.

## F4 — Upload

- Drop target + enumerator recursivo + criação topológica de pastas.
- `BlockEncryptor` + chunk upload + commit + retry backoff+jitter.
- Fila SwiftData com progresso/pausa/cancela/retry.
- Critério: arrastar pasta 100 arquivos / 1 GB preserva estrutura e verifica no listing.

## F5 — Download

- `NSOpenPanel` diretório + espelho + fetch paralelo + decrypt + verify.
- Escrita atômica `.neutron-part` → rename.
- Critério: baixar vault parcial para pasta escolhida, hashes OK, resume após kill funciona.

## F6 — Fila completa + Alpha polish

- Unifica Upload/Download em `TransferStore` persistente, limites 4–8 adaptativos.
- HV 9001 UI, estados de erro claros, onboarding + disclaimer third-party.
- Isolamento `BlockFormatVersion` para migração cripto 2026/2027.
- Critério: release `0.1.0-alpha` tagueada, notas + hash, sem segredos no bundle.

## Fora do MVP

Sync contínuo, search index, links de compartilhamento, multi-conta, daemon background, FIDO2 enrollment.
