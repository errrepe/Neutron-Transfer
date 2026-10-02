# ROADMAP — F0 → F7

> 2026-10-03 — app renamed to **Nucleon Transfer**

> MVP = fila completa de upload + download funcionando contra conta real. Sem sync contínuo.
>
> Estado real em 2026-10-02: F0–F6 concluídas, F7 (UI nativa) praticamente
> completa — restam screenshot e publicação. Suite offline 171/171.

## F0 — Docs + Repo bootstrap — ✅ done

- [x] README, LICENSE MIT, .gitignore
- [x] docs/ARCHITECTURE, AUTH, TRANSFERS, SDK-STRATEGY, ROADMAP, DECISIONS
- [x] CONTRIBUTING, SECURITY
- [ ] Publicação do repo (público, MIT) — pendente junto ao release (S5.3, humano)

## F1 — Scaffold + Build verde — ✅ done

- Projeto Xcode macOS SwiftUI Swift 6 criado; alvos `NucleonTransfer` +
  `NucleonTransferTests`. Build verde, DerivedData externo.

## F2 — Spike SRP (sem UI) — ✅ done

- `SRPClient` nativo validado contra vetores `go-proton-api`/`rclone`.
- Login SRP real verificado contra conta de teste; 2FA TOTP e refresh
  implementados. Documentado em `docs/AUTH.md`.

## F3 — Listing (browse) — ✅ done

- `SessionManager` + `DriveClient` + unlock User→Address→Share→Node→Session.
- Navegação de árvore verificada contra conta real; erros HV/429 tratados.
- Na F7 o browser read-only virou o browser completo (ver F7).

## F4 — Upload — ✅ done (com ressalva de servidor)

- Drop target + enumeração recursiva + criação topológica de pastas
  (verificado live 2026-09-30).
- `FileUpload` + chunking + encrypt + commit + retry backoff+jitter.
- Fila persistente (`TransferQueue` — JSON atômico, não SwiftData) com
  progresso/pausa/cancela/retry.
- ⚠️ **Ressalva live (F6):** `POST /drive/blocks` tem allowlist estrita de
  `x-pm-appversion` — nosso header honesto recebe 2000. Uploads diretos ficam
  desabilitados no alpha (sem spoofing). Detalhes em `docs/TRANSFERS.md` §9.

## F5 — Download — ✅ done

- Download de arquivos e pastas para pasta escolhida (`NSOpenPanel`),
  espelho de árvore, blocos em paralelo, SHA-256 por bloco verificado
  contra bytes de storage (live-proven), escrita atômica `.nucleon-part`.

## F6 — Fila completa + Alpha polish — ✅ done

- Aba Transfers unificada (uploads + downloads via `TransferActivityStore`),
  erros acionáveis (`UserFacingError`), refresh pós-operação, modelos
  tolerantes (`ShareMetadata`, `PendingHash`).
- Bateria live de roundtrip + limpeza executada; resultado e achados em
  `docs/TRANSFERS.md` §9.

## F7 — Native UI + open-source prep — 🟡 nearly complete

Plano completo: `docs/plans/F7-NATIVE-UI.md`. Auditoria:
`docs/plans/F7-AUDIT.md`.

- App nativo macOS 26: `Window` + `Settings`, `NavigationSplitView`
  (My Files / Photos read-only / Computers), `Table` com navegação de
  pastas, toolbar (New Folder / Upload / Download / Trash / Reload /
  Transfers popover), comandos de menu, telas de login/2FA/unlocking.
- Arquitetura nova: `AppSession` (raiz DI @MainActor), `NodeKeyResolver`,
  `DriveListing`, coordinators de upload/download — ver
  `docs/ARCHITECTURE.md`.
- Documentação pública em inglês (README/CONTRIBUTING/SECURITY/ADR).
- Pendente: screenshot do README, ícone do app, publicação do repo
  (itens humanos — S5.3).

## Backlog (pós-release)

B1 streaming de upload por bloco · B2 tamanhos/datas reais via XAttr ·
B3 sync por eventos · B4 tela de lixeira · B5 renomear · B6 Shared ·
B7 nomes reais de computadores · B8–B13 (Quick Look, drag-out, drop em
linha, UI HV 9001, fila por conta, grade de miniaturas) — lista completa
no plano F7 §9.

## Fora do MVP

Sync contínuo, search index, links de compartilhamento, multi-conta, daemon background, FIDO2 enrollment.
