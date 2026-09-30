# CONTRIBUTING — Neutron Transfer

## 1. Princípios

- Nativo macOS SwiftUI, Swift 6 strict concurrency. Sem warning novo.
- Endpoints oficiais apenas + header `x-pm-appversion: external-drive-neutron_transfer@0.1.0-alpha`.
- Sem logos Proton, sem claim de suporte oficial. Manter disclaimer third-party.
- Docs antes de código em mudança arquitetural (atualizar `docs/` + ADR se decisão).

## 2. Estilo Swift

- `swiftformat` mental: 2 espaços? Não — padrão Xcode (tabs exibidos como 4, indent real do toolchain). Siga o arquivo vizinho.
- `Sendable`, `actor` onde há estado compartilhado. Nenhum `try!` / `fatalError` em path de produção (só em `precondition` de invariante impossível).
- Nomes: `SessionManager`, `DriveClient`, `UploadEngine`, `DownloadEngine`, `TransferStore`. Protocolos com sufixo `Protocol` para mocks.
- UI: Views magras, lógica em view-models `@Observable`. Nada de rede em `View.body`.

## 3. Workflow Xcode MCP (obrigatório)

- Usar sempre o MCP do Xcode para projetos Swift: `XcodeRead`, `BuildProject`, `RunSomeTests`, `RenderPreview`, etc.
- Descobrir targets/schemes com as tools de listagem antes de compilar.
- Se erro `db lock` / DerivedData: **sempre** apontar para SSD externo:
  `/Volumes/SSD 4TB/DEV/DerivedData`
  Nunca apontar DerivedData para o SSD interno do Mac.
- **Sem builds concorrentes:** se há build rodando em fundo, esperar antes de lançar outra.
- Não deixar processos pendurados (`StopProject` ao terminar verificação em device/sim).
- Não criar projeto via linha de comando se MCP oferecer caminho — preferir MCP.

## 4. Shell — prefixo `rtk`

- Todo comando shell deve ser prefixado com `rtk` (Rust Token Killer proxy).
- Exemplos: `rtk git status`, `rtk swift test`, `rtk ls`.
- Meta: `rtk gain`, `rtk gain --history`.

## 5. CI / Git

- **Desconsidere CI no GitHub.** Sem workflows, sem gates.
- Não commitar sem pedido explícito. Não push sem pedido.
- Nunca commitar segredos, tokens, Keychain exports, `.sqlite`, `DerivedData`, `.build`.

## 6. Issues / PRs

- Abrir issue antes de PR grande. Referenciar fase do `docs/ROADMAP.md` (F1–F6).
- PR pequeno, um tópico, com: o quê, por quê, como testado (build + teste via MCP), docs atualizados.
- Todo PR que toca crypto/rede deve citar vetores ou conta teste usada (sem credenciais).

## 7. Testes

- Suite offline `NeutronTransferTests/CryptoVectorsTests.swift` (Swift Testing):
  vetores RFC (AES-KW §4.1), inteiros vs Python, bcrypt vs implementação C de
  referência, S2K/KDF/ECDH interop sintético, Ed25519 roundtrip, fingerprints.
  Sem rede, sem segredos — seguro rodar sempre.
- O target de testes ainda não está no scheme gerenciado pelo bridge MCP
  (TODO: fiar `NeutronTransferTests` no Test action). Enquanto isso, loop local:
  pacote SPM temporário com symlinks para `Sources/` + `Tests/` e `rtk swift test`.
- Snippets Xcode (`RunCodeSnippet`) têm watchdog de ~5s no host de preview:
  para fluxos longos (SRP ~20s debug) usar o probe CLI com `-O` ou reutilizar
  a sessão do Keychain. Nunca commitar credenciais (só via env em memória).
