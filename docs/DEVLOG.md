# DEVLOG — Neutron Transfer

> **2026-10-03** — o app foi renomeado para **Nucleon Transfer**; este documento usa o nome antigo por ser registro histórico.

> Registro histórico do desenvolvimento. Conteúdo movido verbatim do README
> em 2026-10-02 (S5.1), quando o README virou documentação voltada ao usuário.
> O estado atual do projeto está no README e em `docs/ROADMAP.md`.

## 2026-10-01 — Status (snapshot de F0–F6, movido do README)

`0.1.0-alpha` — F0 docs+repo, F1 scaffold e F2 AuthCore concluídos (build verde).
**Login SRP real verificado** contra conta de teste. **F3a DriveClient** (volumes/shares/
links/children + browser read-only) implementado e verificado contra a API.
**F3b-1 user-key unlock verificado live** (saltedKeyPass + seed bate com a pública).
**F3b-2/3 (PKESK/SED/Ed25519/fingerprints) implementado e verificado offline**
(vetores RFC + interop Python + pgpy); validação live pendente do cooldown do
rate-limit de login. Cofre provisionado (usuário abriu drive.proton.me).
**Suite `NeutronTransferTests` (Swift Testing, 13 vetores offline) verde.**
**F4.4 fila de upload + UI drag-drop** (offline 18 testes + build verde).
**F5 download de arquivos/pastas** para pasta escolhida (offline 9 testes +
rclone-capturado; suite 68/68; build verde).
**F6 hardening alpha** (offline 20 testes novos, suite 88/88; Transfers
unificada uploads+downloads, erros acionáveis com espera 2028, refresh
pós-operação, `ShareMetadata` Bool-tolerante, build verde): bateria live de
roundtrip + limpeza pronta em `/private/tmp/nt-f6live` (1 login SRP, resto
reusa sessão; credenciais SÓ via env `NT_USER`/`NT_PASS`).
See `docs/ROADMAP.md`.

## 2026-10-01 — How to test (movido do README; instruções de mantenedor)

- Offline (sem rede, sem segredos): `swift test` na raiz do repo
  (esperado 100/100). O `Package.swift` da raiz compila
  `NeutronTransfer/NeutronTransfer/Core/` direto — sem symlinks, sem Xcode.
- Build: via Xcode MCP, scheme `NeutronTransfer`, DerivedData externo
  `/Volumes/SSD 4TB/DEV/DerivedData` (sem builds concorrentes, sem commit).
- Live (1 login SRP; espaçar ~11min entre SRPs frescos; nunca em disco):
  `NT_USER=… NT_PASS=… /private/tmp/nt-f6live/.build/release/nt-f6live`
  (build: `swift build -c release --package-path /private/tmp/nt-f6live`).
  Faz unlock → auditoria bruta de shares → lista decriptada (nunca toca no
  fixture `NT-F43-FIXTURE.txt`) → trash de resíduos ativos → upload
  `NT-F6-*` via fila/adapter → download via adapter → cmp + SHAs → trash
  de limpeza. Sem env sai 3 (sem login); em 2028 sai 4 sem retry.

## Notas de continuidade

- A bateria live F6 (resultados completos, incluindo a allowlist estrita de
  `POST /drive/blocks` — erro 2000 — que mantém uploads diretos desabilitados
  no alpha) está documentada em `docs/TRANSFERS.md` §9.
- A auditoria de polimento da UI nativa (HIG/acessibilidade/concorrência,
  achados F-H/F-M e backlog B-1…B-10) está em `docs/plans/F7-AUDIT.md`.
- O plano completo da fase de UI nativa está em `docs/plans/F7-NATIVE-UI.md`.
