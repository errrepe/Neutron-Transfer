# F7 S4.3 — Auditoria de polimento (HIG, acessibilidade, concorrência)

Escopo: `NeutronTransfer/NeutronTransfer/App/` + `Features/` (todo o código,
~3.250 linhas) com spot-check de concorrência em `Core/`. Preview fixtures são
DEBUG-only — achados nelas são cosméticos por definição.

Método: os agentes `anthropic-skills:axiom-audit-*` e `design:*` nomeados no
plano **não existem** nesta máquina. O equivalente foi executado inline seguindo
os procedimentos dos skills `axiom-*` instalados
(`~/.agents/skills/`):
`axiom-accessibility/skills/accessibility-auditor.md`,
`axiom-concurrency/skills/concurrency-auditor.md`,
`axiom-swiftui/skills/{swiftui-architecture-auditor,swiftui-layout-auditor,ux-flow-auditor}.md`,
`axiom-design/skills/liquid-glass-auditor.md`,
`axiom-performance/skills/memory-auditor.md` — leitura de cada fase + greps
prescritos, verificados com leitura de contexto.

**Build:** verde via `BuildProject` (0 erros, 0 warnings novos — os 3 warnings
do log são pré-existentes em `Core/`: CC_MD5 deprecated, resultado de
`commitRevision` não usado, `try` sem throwing call).
**Testes:** `rtk swift test` → 171/171 (baseline 171).

---

## Checklist manual — resultado

| Item | Resultado |
|---|---|
| Botão só-ícone tem `.help` + label de acessibilidade | ✅ Todos cobertos — toolbar (`FolderView`), menus `⋯` (TransfersPanel, StorageFooterView), `TransferRow.rowButton`, `TransfersToolbarButton` (label dinâmico com contagem). Exceção corrigida: badge de nome não-decodificado (F-A2). |
| Texto com cor fixa que quebre no dark mode | ✅ Nenhum. Tudo semântico (`.secondary`, `.red`, `.tint`, `.orange`, `.accentColor`, `.regularMaterial`). `.white` sobre `.red` no badge de contagem é convenção de badge e funciona nos dois modos. |
| `.monospacedDigit()` em números que mudam | ✅ Após fix F-A5. Cobertos: Modified/Size (FolderTable), subtítulo de progresso (TransferRow), badge de contagem, quota do footer, campo TOTP. |
| `.frame(width:)` fixo que corte texto (pt-BR +30%) | ✅ Nenhum. Larguras fixas são de containers/ícones (LoginView 360, NewFolderSheet 340, TransfersPanel 380, TwoFactor 180 p/ 6 dígitos) ou previews DEBUG. Nenhum `Text` com largura fixa truncável. |
| Estados vazios/erro em todas as telas | ✅ FolderView (loading/vazio/filtrado/erro com Try Again), MainView (roots erro + sem drives + sem seleção), TransfersPanel (vazio + strip de erro), LoginView/NewFolderSheet (erro inline). |
| `Task {}` sem cancelamento em view que some | ✅ Justificado — ver "Notas". Todos os `Task {}` em views chamam objetos que sobrevivem à view (`session`, `model`, `uploads`); `.task` cancelaria trabalho que deve continuar (ex.: signIn troca a fase e desmonta a própria LoginView). |

## Regras globais — verificação

- `try!` / `fatalError` / `@unchecked Sendable` / `nonisolated(unsafe)` /
  `DispatchQueue.main.async` / `AnyView` / `GeometryReader` / `print(` /
  `NSLog` / `Timer(`: **zero ocorrências** em todo o alvo.
- `DecryptChain`/`MessageDecrypt`/`Data(contentsOf`: somente em `Core/` —
  nada em views. `Core/Crypto`, `DecryptChain`, `FileUpload`, `FileDownload`,
  `FolderCreate`, `SRPClient`, `SessionManager.login`: **intocados**.
- Concorrência: todo o trabalho de CPU/rede mora em actors (`DriveListing`,
  `NodeKeyResolver`, `KeyringCache`, `SessionManager`, `DriveClient`,
  `TransferQueue`, `Drive{Up,Down}loadAdapter`). Nenhum `@MainActor` em
  `Core/`. `LocalTreeScan` roda em `Task.detached`. Single-flight tasks do
  resolver limpas via `defer` + `reset()`; `TransferQueue.tasks` removidas em
  `defer`. Erros passam por `UserFacingError`. Title Case e `…` único OK
  (1 exceção corrigida: F-H2).

---

## Achados corrigidos (severidade alta/média, ≤30 linhas cada)

### F-H1 · Upload menu — tooltip errado em raízes graváveis (HIG/UX copy)
`Features/Browser/FolderView.swift:60` — `.help("Uploading to Photos isn't
supported yet.")` era incondicional: pairar sobre o menu Upload em "My Files"
mostrava a explicação do estado desabilitado. **Fix:** help condicional —
"Upload files or a folder into this folder." em raízes graváveis.

### F-H2 · Menu "Download" sem reticências (HIG)
`App/AppCommands.swift:104` — o comando abre um painel de destino (pede input
adicional) e a contraparte no context menu já é "Download…". **Fix:**
renomeado para "Download…".

### F-M1 · Badge de nome não-decodificado sem label de VoiceOver
`Features/Browser/FolderTable.swift:28` — `Image(systemName:)` com `.help`
mas sem `accessibilityLabel`: VoiceOver podia ler o nome do símbolo.
**Fix:** `.accessibilityLabel("Name couldn't be decrypted")`.

### F-M2 · Botão Sign In perde o label durante o spinner
`Features/Auth/LoginView.swift:82` — com `isSigningIn`, o conteúdo do botão é
um `ProgressView` puro; o label de acessibilidade degradava. **Fix:**
`.accessibilityLabel(isSigningIn ? "Signing In" : "Sign In")`.

### F-M3 · 2FA falho retorna ao login com campos vazios
`App/AppSession.swift:69` + `Features/Auth/LoginView.swift:97` — a LoginView
desmonta durante `.needsTwoFactor`/`.unlocking`, destruindo o `@State`; uma
falha de TOTP devolvia a tela de login com usuário **e** senha apagados.
**Fix:** `loginUsername` virou `private(set)` e a `.task` da LoginView
repopula o campo quando vazio. (Cancelamento de 2FA limpa via `signOut` —
comportamento mantido: voltar por escolha = campos limpos.)

### F-M4 · Stepper de uploads simultâneos sem `.monospacedDigit()`
`Features/Settings/SettingsView.swift:41` — número que muda sem dígitos
monoespaçados (item explícito do checklist). **Fix:** `.monospacedDigit()`.

### F-M5 · Ícones `NSImage` decorativos não ocultos do VoiceOver
`Features/Browser/FileIcon.swift:44` e `Features/Transfers/TransferRow.swift:30`
— `Image(nsImage:)` sem descrição podia ser anunciado como "image" em cada
linha da tabela/popover. **Fix:** `.accessibilityHidden(true)` (o texto
adjacente já carrega o conteúdo).

---

## Backlog (não corrigido nesta slice)

| # | Sev. | Arquivo:linha | Achado / correção proposta |
|---|------|---------------|-----------------------------|
| B-1 | média | `Features/Browser/FileIcon.swift:11-34` | `FileIconCache` resolve `NSWorkspace.icon(for:)` sincronamente no `@MainActor` durante a renderização de linhas — cada UTI nova é uma chamada XPC. Proposta: cache nonisolated com `Mutex`/`NSLock` (NSImage precisa de ponte Sendable segura) ou pre-aquecer ícones fora do body. |
| B-2 | baixa | `Features/Shell/StorageFooterView.swift:22` | `ProgressView` de quota sem label próprio — VoiceOver anuncia só a %. Proposta: `.accessibilityLabel("Storage used")` (o texto "X of Y used" já segue abaixo). |
| B-3 | baixa | `Features/Auth/TwoFactorView.swift:42` | Botão "Back" sem `.keyboardShortcut(.cancelAction)` — Esc não cancela. Proposta: adicionar o atalho. |
| B-4 | baixa | `App/RootView.swift:27` | Crossfade `.easeInOut(0.2)` não consulta `accessibilityReduceMotion`. Animations value-driven já respeitam parcialmente a setting; opcionalmente envolver em `withAnimation` condicionado. |
| B-5 | baixa | `Features/Browser/FolderView.swift:39` | `navigationSubtitle` recebe `String` ("N items") — não aceita `.monospacedDigit()`; a contagem pula largura ao mudar de ordem de grandeza. Cosmético. |
| B-6 | baixa | `Features/Browser/FolderView.swift:163-187` | Falha de **refresh** com linhas em cache não mostra nenhum erro (design intencional — "degrada mantendo dados velhos"). Se desejado, um strip não-bloqueante no topo. |
| B-7 | baixa | `Features/Browser/NewFolderSheet.swift:80`, `Features/Shell/StorageFooterView.swift:95` | `Task {}` que escreve `@State` após `await` — inofensivo se a view sumiu, mas o padrão pode mascarar bugs futuros. Alternativa: capturar em `Task` e checar `isPresented`/binding. |
| B-8 | baixa | `Features/Browser/BrowserModel.swift:93-98` | `visibleItems` filtra+ordena no MainActor a cada avaliação de body — pastas gigantes (10⁴+ itens) podem custar. Proposta: memoizar por (folderID, filterText, sortOrder). |
| B-9 | baixa | `Features/Transfers/UploadCoordinator.swift:28` | `lastError` persiste no rodapé do popover até o próximo intake; considerar limpar ao fechar o popover ou após N segundos. |
| B-10 | info | — | Liquid Glass (macOS 26): nenhuma adoção explícita (`glassEffect`, `ToolbarSpacer`). O app usa `.regularMaterial`/toolbar padrão, que já renderizam o novo visual — não é bug, é oportunidade de adoção futura. |

## Não-achados verificados (falsos positivos descartados)

- `TwoFactorView.swift:15` — `.font(.system(size: 40))` num símbolo SF
  decorativo (`accessibilityHidden`): ícone, não texto; fora do escopo de
  Dynamic Type.
- `TransfersToolbarButton` badge `.white`/`.red` — convenção de badge,
  contraste mantido nos dois esquemas.
- `DropOverlay` — `.accessibilityHidden(true)` correto: overlay decorativo e
  a ação tem equivalente de teclado/menus (Upload no toolbar/menubar) —
  nenhum caminho gesture-only.
- `.onDrop` — única interação por gesto do app; possui equivalente total via
  menu/botão (acessível por teclado e VoiceOver).
- `remoteChangedParents` acumula sem consumir — union intencional; pastas
  não-tocadas degradam a refresh lazy na visita. Sem leak mensurável.
