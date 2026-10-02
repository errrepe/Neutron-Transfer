# F7: UI nativa + polimento para release open source

> **2026-10-03** — o app foi renomeado para **Nucleon Transfer**; este documento usa o nome antigo por ser registro histórico.

> **Público:** o agente orquestrador e os subagentes que ele dispara.
> **Escrito em:** 2026-10-01, a partir de uma auditoria do repo (commit `19267d3`).
> **Objetivo:** transformar o protótipo (painel de debug com abas) num app macOS
> nativo com a cara do Proton Drive web (sidebar + tabela + toolbar), sem tocar
> na criptografia, e deixar o repositório pronto para ser público.

---

## 0. Como usar este plano

### 0.1 Para o orquestrador

1. Leia o documento **inteiro** uma vez. Depois disso, cada subagente recebe:
   - a seção **3 (Regras globais)**, sempre, copiada por inteiro;
   - a seção **4 (Skills)**, sempre;
   - a seção **5 (Arquitetura alvo)** e a **6 (Spec visual)**, quando a fatia é de UI;
   - **a fatia dele** (seção 7), inteira, sem resumir.
2. Execute as fatias **na ordem do grafo** da seção 7.0. Só rode fatias em paralelo
   quando estiverem marcadas com ⟂ **e** não mexerem nos mesmos arquivos.
   **Builds nunca podem rodar em paralelo** (regra do projeto). Se dois subagentes
   estão ativos, só um compila por vez.
3. Depois de cada fatia:
   - leia o relatório do subagente (template na seção 10);
   - confira cada critério de aceitação lendo o diff (`git diff`), sem confiar só no relatório;
   - rode `swift test` e `BuildProject` você mesmo, se o subagente não colou a saída;
   - rode a skill `code-review` (nível `medium`) sobre o diff da fatia;
   - se houver item em "Live checks for human", **pare e peça ao humano** antes de
     seguir para uma fatia que dependa daquilo (indicado em cada fatia);
   - faça commit **somente se o humano autorizou commits no início da sessão**
     (CONTRIBUTING §5). Mensagem: `feat(ui): S2.2 folder table + navigation`
     (tipo `feat|fix|chore|docs|refactor`, escopo, id da fatia, resumo em inglês).
4. Se um subagente devolver `blocked` ou `partial`, **não** avance para fatias
   dependentes. Reformule a tarefa com o que faltou ou pergunte ao humano.
5. Fatias marcadas **[HUMANO]** não são para agente.

### 0.2 Para cada subagente

- Você recebe **uma fatia**. Faça **apenas** o que ela pede. Se achar algo errado fora
  do escopo, anote em "Open questions" no relatório, sem corrigir.
- **Antes de escrever código**, carregue as skills listadas na sua fatia (seção 4).
- **Antes de editar um arquivo, leia o arquivo inteiro.** Antes de chamar uma API do
  core, leia a assinatura real (`grep -n "func nome"`). Os nomes citados neste plano
  foram conferidos em 2026-10-01, mas confirme mesmo assim.
- Termine com o relatório da seção 10, preenchido honestamente.

---

## 1. Contexto: estado atual (auditoria)

### 1.1 O que está sólido (não mexer sem motivo)

- `Core/Crypto/**`: SRP-6a, bcrypt, BigUInt, PGP (ECDH, SED, Ed25519, S2K…). Testado
  por vetores. **Proibido alterar nesta fase.**
- `Core/Security/DecryptChain.swift`: unlock share → node → nome.
- `Core/ProtonAPI/DriveClient.swift` (actor): `listVolumes`, `listShares`, `getShare`,
  `getLink`, `listChildren` (paginado), `createFolder`, `uploadFile`, `listRevisions`,
  `getRevision`, `downloadBlockBytes`, `trashChildren`, `deleteChildren`.
- `Core/Transfers/TransferQueue.swift` (actor): fila de upload persistida em **JSON**
  (não SwiftData). Tem `enqueueTree`, `pause/resume/cancel/relaunch/remove`,
  `pauseAll`, `relaunchAllFailed`, `setMaxConcurrent`, `setListener`, `setUploader`.
- `Core/Transfers/DriveUploadAdapter.swift` e `DriveDownloadAdapter.swift` (actors).
- 88 testes offline (Swift Testing) em `NeutronTransfer/NeutronTransferTests/`.

### 1.2 Problemas encontrados

| # | Problema | Onde | Fatia |
|---|----------|------|-------|
| P1 | **Header de storage finge ser o rclone** (`external-drive-rclone@1.75.1-stable`). Viola as regras de terceiros do SDK oficial e o próprio comentário do arquivo. **Bloqueia o release público.** | `Core/ProtonAPI/AppVersion.swift:13`, usado em `APIClient.swift:147,174` | S0.2 |
| P2 | Browser **não navega**: só lista os filhos da raiz de cada share. | `Features/Browser/DriveBrowserViewModel.swift` | S1.x, S2.2 |
| P3 | Todas as shares aparecem misturadas e o nome da raiz é literalmente "root". | idem | S1.1, S2.1 |
| P4 | Destino de upload padrão = primeira share, que pode ser **Fotos (type 4)** e falha com 2511. Só dá para enviar para a **raiz** da share. | `TransferQueueViewModel.loadShares/add` | S1.2, S3.1 |
| P5 | `DriveUploadAdapter.keysFor` lança erro para qualquer pasta que não seja a raiz ou uma pasta criada na sessão. | `DriveUploadAdapter.swift:117` | S1.2 |
| P6 | Três resolvedores de chaves duplicados (browser VM, upload adapter, download adapter). | — | S1.2 |
| P7 | Header mostra o UID da sessão em vez do email; não existe **logout**. | `ContentView.swift` | S0.3 |
| P8 | `ContentView` instancia `TransferQueue` antes do login; cada view cria o próprio `DriveClient`. Não há raiz de DI. | `ContentView.swift` | S0.3 |
| P9 | Textos de debug na UI ("F6 alpha…", "type 4", "Queue.device idle", "Names are decrypted locally…"). | Views | S2.x, S3.2, S4.3 |
| P10 | Testes só rodam por um pacote em `/tmp/nt-tests` com symlinks. Contribuidores não conseguem rodar. | — | S0.1 |
| P11 | Target de testes com `SWIFT_VERSION = 5.0`, bundle id `com.yourcompany.NeutronTransferTests`, deployment 27.0; app em 14.0; projeto em 27.0. | `project.pbxproj` | S0.1 |
| P12 | Sem ícone (`AppIcon` vazio), `MARKETING_VERSION = 1.0` (o header diz 0.1.0-alpha). | Assets / pbxproj | S4.2, S5.3 |
| P13 | README mistura PT/EN e é um diário de desenvolvimento; ROADMAP desatualizado; ARCHITECTURE diz SwiftData. | `docs/` | S5.1 |
| P14 | Upload lê o arquivo inteiro na memória (`Data(contentsOf:)`). | `DriveUploadAdapter.upload` | Backlog B1 |
| P15 | Tamanho exibido = `DriveLink.size` (tamanho criptografado), não o real (está no XAttr). | — | Backlog B2 |

### 1.3 SDK oficial (conferido em 2026-10-01)

- `ProtonDriveApps/sdk`: C# + TypeScript, ~1.1k commits, módulo `Client` (listar,
  upload, download, mover, renomear, lixeira, compartilhar, eventos). `Sync`/`Search`
  ainda "coming soon". **Não inclui auth/sessão.** MIT.
- `ProtonDriveApps/sdk-swift`: 2 commits, sem release. **Continua inviável** → ADR-001 se mantém.
- Regras para apps de terceiros (do README do SDK), que este projeto **precisa** seguir:
  - header `x-pm-appversion: external-drive-{name}@{semver}-{channel}` (o nosso:
    `external-drive-neutron_transfer@0.1.0-alpha` ✓);
  - **usar sync por eventos; não fazer polling nem travessias recursivas frequentes**;
  - **deixar claro que é app de terceiros no momento de pedir credenciais**;
  - nenhum logo ou marca da Proton.
- Migração de criptografia prevista para fim de 2026/início de 2027. Fora do escopo
  desta fase, mas nada aqui pode espalhar crypto fora de `Core/`.
- **Uso como referência:** o código C# do SDK (MIT) é a **referência preferida de
  endpoints** para o que ainda não existe aqui (lixeira, renomear, eventos,
  dispositivos). `go-proton-api` e `rclone` continuam válidos como segunda fonte.

---

## 2. Decisões tomadas (não rediscutir)

| Decisão | Valor |
|---------|-------|
| Deployment target | **macOS 26.0** em app, testes e projeto. Liquid Glass automático; sem `if #available`. |
| Framework de UI | SwiftUI puro. AppKit **só** para `NSOpenPanel`, `NSWorkspace` (ícones, Finder) e `NSApp` (About). |
| Navegação | `NavigationSplitView` (sidebar + detalhe) e, no detalhe, `NavigationStack(path:)` por raiz. |
| Lista de arquivos | `Table` nativa (colunas Nome / Modificado / Tamanho), seleção múltipla, ordenação. |
| Transfers | Botão na toolbar com **popover**, no lugar da aba. |
| Cena | `Window` única (não `WindowGroup`) + `Settings`. |
| DI | Um `AppSession` `@MainActor @Observable`, injetado via `.environment`. |
| Idioma do código e da UI | Inglês. UI em **Title Case** para botões, menus e colunas ("New Folder", "Move to Trash"); frases em sentence case. pt-BR via String Catalog na S4.4 (opcional). |
| Testes | Swift Testing, rodando por `swift test` a partir de um `Package.swift` **na raiz do repo**, que aponta para `Core/`. |
| Dependências novas | **Nenhuma.** |
| Itens da sidebar | My Files, Photos (somente leitura), Computers (se houver). **Shared / Trash ficam fora** desta fase (backlog), sem itens desabilitados na sidebar. |

### 2.1 Decisões pendentes do mantenedor (o orquestrador pergunta antes de S4.4/S5.1)

1. Fazer a S4.4 (pt-BR) agora ou depois do release?
2. Traduzir o CONTRIBUTING para inglês e mover as notas pessoais (prefixo `rtk`,
   caminho do SSD) para uma seção "Maintainer setup"? Padrão do plano: **sim**.
3. Se, na S0.2, o host de storage **recusar** o header honesto: pausar downloads no
   release ou contatar a Proton? (Recolocar o header do rclone **não** é opção.)

---

## 3. Regras globais (copiar para TODO subagente)

### 3.1 Projeto e ferramentas

- Raiz do repo: `/Volumes/SSD 4TB/DEV/Neutron Transfer`.
  Projeto Xcode: `NeutronTransfer/NeutronTransfer.xcodeproj`, scheme `NeutronTransfer`.
- Fontes do app: `NeutronTransfer/NeutronTransfer/`. O projeto usa **grupos
  sincronizados com o sistema de arquivos** (`PBXFileSystemSynchronizedRootGroup`):
  arquivo `.swift` criado dentro dessa pasta **entra no target automaticamente**.
  **Não edite `project.pbxproj` para adicionar arquivos.** Só as fatias S0.1 e S4.2
  podem tocar em build settings.
- **Prefixe todo comando shell com `rtk`** (ex.: `rtk git status`, `rtk swift test`).
- **Build só via Xcode MCP** (`BuildProject`). Carregue a skill `axiom-xcode-mcp`
  antes. DerivedData **sempre** em `/Volumes/SSD 4TB/DEV/DerivedData`. **Nunca** dois
  builds ao mesmo tempo; se outro estiver rodando, espere.
- Testes (a partir da S0.1): `rtk swift test --package-path "/Volumes/SSD 4TB/DEV/Neutron Transfer"`.
- Previews: use `RenderPreview` (Xcode MCP) para conferir visualmente cada view
  nova, em **light e dark**.
- Não deixe processos rodando (`StopProject` ao terminar).
- **Não faça commit nem push.** Quem decide é o orquestrador.

### 3.2 Segurança (inegociável)

- **Agentes nunca fazem login real.** Não peça credenciais, não leia `NT_USER`/`NT_PASS`,
  não rode o binário live. Tudo que precisa de conta vai em
  "Live checks for human" no relatório. (O limite 2028 da Proton bloqueia logins
  repetidos; cada login conta.)
- Senha, tokens, seeds e chaves desbloqueadas **só em memória**: nunca em disco,
  `UserDefaults`, `@AppStorage`, logs, `print`, mensagens de erro ou `description`.
- Nenhum `print(`/`NSLog`/`os_log` com dados de sessão. Se precisar logar, use
  `Logger` com `privacy: .private` e nunca para material de chave.
- Não altere `Core/Crypto/**`, `DecryptChain`, `FileUpload`, `FileDownload`,
  `FolderCreate`, `SRPClient`, `SessionManager.login`. Se achar que precisa, pare e
  registre em "Open questions".
- Só endpoints oficiais. Endpoint novo precisa ser **conferido** no código do
  `ProtonDriveApps/sdk` (C#) ou em `go-proton-api`. Cite a fonte (arquivo + função)
  num comentário `///` acima do método.
- **Sem polling, sem `Timer` de refresh, sem travessia recursiva automática.**
  Recarregar só por ação do usuário ou depois de uma operação do próprio app, e só a
  pasta afetada.

### 3.3 Swift / SwiftUI

- Swift 6, strict concurrency. **`SWIFT_APPROACHABLE_CONCURRENCY = YES` está ligado**,
  e com ele `NonisolatedNonsendingByDefault`: uma função `async` **nonisolated roda no
  executor de quem chamou**. Se uma view model `@MainActor` chamar uma função `async`
  solta que decripta nomes, **a criptografia roda na main thread**. Por isso: trabalho
  de CPU (decrypt, hash, scan de disco) fica **dentro de um `actor`** ou numa função
  `@concurrent`. Nunca em `@MainActor`.
- View models: `@MainActor @Observable final class`. Views finas, sem rede no `body`;
  use `.task` / `.task(id:)`.
- Proibido: `try!`, `fatalError` em caminho de produção, `@unchecked Sendable`,
  `nonisolated(unsafe)` (a não ser que haja justificativa escrita num comentário e
  ela esteja no relatório), `DispatchQueue.main.async` (use `@MainActor`/`Task`),
  `AnyView`, `GeometryReader` para layout que `Layout`/frames resolvem.
- Toda view nova tem `#Preview` que funciona **sem rede**, com os fixtures de
  `Features/Preview/PreviewFixtures.swift` (criado na S2.1).
- Lógica pura e testável vai em `Core/` (Foundation apenas, **sem import de SwiftUI
  ou AppKit**), porque só `Core/` entra no pacote de testes.
- Cabeçalho de arquivo novo, igual aos vizinhos:
  `// Neutron Transfer — <propósito em uma linha>.` + 1–3 linhas de contexto.
  Comentários em inglês, densidade igual à dos arquivos vizinhos.
- Nenhum warning novo no build.
- Componentes padrão do sistema. **Não** crie efeitos de vidro customizados
  (`.glassEffect`) em conteúdo; sidebar e toolbar já ganham Liquid Glass sozinhas.
  Não force cores de fundo em sidebar/toolbar/tabela.
- Strings de erro mostradas ao usuário passam **sempre** por
  `UserFacingError.message(for:)`.

### 3.4 Marca e textos

- Não use "Proton" como marca do app. Pode usar como rótulo factual
  ("Sign in with your Proton account"). Sem logos. Disclaimer de terceiro no login e
  no About (texto exato na seção 6.6).
- Reticências com o caractere `…` (não `...`) em ações que abrem painel/diálogo
  ("Upload Files…", "Sign Out…").

---

## 4. Skills (Axiom e outras): quando carregar

Carregue com a ferramenta **Skill** *antes* de escrever código. Dependendo do host, o
nome aparece como `axiom-swiftui` ou `anthropic-skills:axiom-swiftui`: use o que
existir na sua lista. Se a skill não existir, siga em frente e registre no relatório.

| Skill | Carregar quando |
|-------|-----------------|
| `axiom-xcode-mcp` | **Sempre** que for compilar, testar ou fazer preview via Xcode MCP. |
| `axiom-build` | Build falhou, erro de ambiente/DerivedData, problema de scheme. |
| `axiom-swiftui` | Qualquer view, `@Observable`, environment, navegação, `Table`, toolbar. |
| `axiom-macos` | Janelas, menus/`Commands`, `Settings`, sandbox, `NSOpenPanel`, security-scoped bookmarks, drag-and-drop no Mac. |
| `axiom-design` | Decisões de layout/HIG, Liquid Glass, SF Symbols, fluxo de login. |
| `axiom-concurrency` | `actor`, `@MainActor`, `Sendable`, reentrância, `Task`, `@concurrent`. |
| `axiom-swift` | Idiomas Swift modernos; **drag and drop** (a skill cobre). |
| `axiom-testing` | Escrever testes Swift Testing, fakes, testes `async`. |
| `axiom-security` | Qualquer coisa que toque credenciais, chaves, logout, zeragem de memória. |
| `axiom-networking` | Mudanças em `APIClient`, headers, novos endpoints. |
| `axiom-accessibility` | Labels de VoiceOver, botões só com ícone, contraste. |
| `axiom-apple-docs` | Dúvida sobre se uma API existe/está disponível no macOS 26. **Confira em vez de chutar.** |
| `axiom-integration` | Localização / String Catalog (S4.4). |
| `axiom-shipping` | Checklist de release (S5.2). |
| `anthropic-skills:axiom-audit-*` | Auditorias da S4.3 (lista lá). |
| `anthropic-skills:axiom-scan-security-privacy` | S5.2. |
| `design:ux-copy` | Escrever ou revisar textos de UI, estados vazios, erros. |
| `design:design-critique` / `design:accessibility-review` | S4.3. |
| `code-review` | Orquestrador, depois de cada fatia. |
| `domain-modeling` | Escrever ADR (S5.1). |

---

## 5. Arquitetura alvo

### 5.1 Árvore de arquivos ao final da F7

```
NeutronTransfer/NeutronTransfer/
  App/
    NeutronTransferApp.swift      (movido; Window + Settings + commands)
    AppSession.swift              (S0.3; raiz de DI e ciclo de vida da sessão)
    RootView.swift                (S0.3; login ↔ main)
    AppCommands.swift             (S4.2)
  Core/                           (Foundation apenas; testável por SPM)
    Crypto/ … (intocado)
    ProtonAPI/ … (+ ProtonUser com campos de conta, + APIClient.delete, + authDelete)
    Security/
      DecryptChain.swift
      KeyringCache.swift
      NodeKeyResolver.swift       (S1.2; resolvedor único de chaves, memória apenas)
    Drive/                        (novo)
      ShareKind.swift             (S1.1)
      DriveRoot.swift             (S1.1; DriveRoot + ShareCatalog)
      DriveItem.swift             (S1.1)
      DriveLocation.swift         (S1.1)
      DriveItemOrdering.swift     (S1.1)
      DriveFormatting.swift       (S1.1)
      FolderNameValidator.swift   (S2.3)
      DriveListing.swift          (S1.3; actor: children(of:) → [DriveItem])
    Transfers/ … (adapters passam a usar NodeKeyResolver; DownloadRecord ganha progress)
  Features/
    Auth/
      LoginView.swift             (S0.3 legado → S4.1 redesign)
      TwoFactorView.swift         (S4.1)
      UnlockingView.swift         (S4.1)
    Shell/
      MainView.swift              (S2.1)
      SidebarView.swift           (S2.1)
      StorageFooterView.swift     (S2.1)
    Browser/
      BrowserModel.swift          (S2.2)
      BrowserContainerView.swift  (S2.2; NavigationStack por raiz)
      FolderView.swift            (S2.2)
      FolderTable.swift           (S2.2)
      FileIcon.swift              (S2.2)
      NewFolderSheet.swift        (S2.3)
      FolderOperations.swift      (S2.3; criar pasta / lixeira)
      DropOverlay.swift           (S3.1)
    Transfers/
      TransferActivityStore.swift (existente; ampliado)
      DownloadCoordinator.swift   (S2.3)
      UploadCoordinator.swift     (S3.1)
      TransfersToolbarButton.swift(S3.2)
      TransfersPanel.swift        (S3.2)
      TransferRow.swift           (S3.2)
    Settings/
      SettingsView.swift          (S4.2)
    Shared/
      Panels.swift                (S2.3; NSOpenPanel async)
    Preview/
      PreviewFixtures.swift       (S2.1; #if DEBUG)
```

**Removidos ao final da S3.2:** `ContentView.swift`, `Features/Auth/LoginViewModel.swift`,
`Features/Browser/DriveBrowserView.swift`, `DriveBrowserViewModel.swift`,
`Features/Transfers/TransferQueueView.swift`, `TransferQueueViewModel.swift`, e as
views "Legacy*" temporárias.

### 5.2 Fluxo de dados

```
NeutronTransferApp
 └─ @State AppSession ──.environment──► todas as views
      ├─ sessions: SessionManager (actor)
      ├─ keyrings: KeyringCache (actor)
      ├─ drive: DriveClient (actor)                 ← UMA instância
      ├─ resolver: NodeKeyResolver? (actor)         ← criado após unlock; zerado no logout
      ├─ listing: DriveListing? (actor)             ← usa drive + resolver
      ├─ queue: TransferQueue (actor)               ← criado no init (persistência JSON)
      ├─ activity: TransferActivityStore (@MainActor @Observable)
      ├─ uploads: UploadCoordinator? (@MainActor)   ← S3.1
      ├─ downloads: DownloadCoordinator? (@MainActor)← S2.3
      ├─ roots: DriveRoots? (My Files / Photos / Computers)
      └─ account: Account? (email, nome, quota)

MainView
 ├─ SidebarView (seleção: SidebarItem)
 └─ BrowserContainerView(root:) ── @State BrowserModel (um por raiz, cache por pasta)
       └─ NavigationStack(path: model.path) → FolderView(location) → FolderTable
```

Invalidação: upload/criação de pasta/lixeira avisam
`activity.remoteChanged(parentLinkIDs:)`. O `BrowserModel` marca essas pastas como
velhas e recarrega **só** se uma delas estiver visível. Nada de contador global.

---

## 6. Spec visual

Referência: a tela "Meus arquivos" do Proton Drive web (sidebar à esquerda com
"+ Novo", lista com colunas Nome ↑ / Modificado / Tamanho, quota no rodapé da
sidebar), traduzida para componentes **nativos** de macOS. Não copie cores nem a
estética web: siga o Finder e os apps nativos do macOS 26.

### 6.1 Janela principal

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  ⊟   ‹  Projects ⌄        [🔍 Filter this folder]   [📁+] [⇪] [⇩] [🗑]  [⇅•2] │  ← toolbar unificada
├───────────────┬──────────────────────────────────────────────────────────────────┤
│ Drive         │ Name ↑                                  Modified            Size │
│  📁 My Files  │ 📁 Apresentações Lei Rouanet            21 Sep 2026, 23:37     — │
│  🖼 Photos    │ 📁 AZUL                                  6 Nov 2025, 23:39      — │
│ Computers     │ 📁 Jose Botelho                         27 Sep 2026, 20:20     — │
│  🖥 Computer 1│ 📄 contrato.pdf                         27 Sep 2026, 20:21  1.2 MB│
│               │                                                                  │
│               │                                                                  │
│ ───────────── │                                                                  │
│ ▓▓▓▓░░░░░░░░  │                                                                  │
│ 148.48 GB of  │                                                                  │
│ 520 GB used   │                                                                  │
│ 👤 Raphael  ⋯ │                                                                  │
│   r…@proton.me│                                                                  │
└───────────────┴──────────────────────────────────────────────────────────────────┘
```

- Tamanho padrão da janela 1100×700; mínimo 800×500.
- Sidebar: `.listStyle(.sidebar)`, largura `min 180 / ideal 220 / max 300`.
- Título da janela = nome da pasta atual (`.navigationTitle`). Clicar no título abre um
  menu com os ancestrais (`.toolbarTitleMenu`), que funciona como breadcrumb nativo.
  Subtítulo: `"12 items"` (`.navigationSubtitle`).
- Botão voltar: o que o `NavigationStack` já fornece.

### 6.2 SF Symbols e textos (usar exatamente)

| Elemento | Símbolo | Texto (label/help) |
|----------|---------|--------------------|
| Sidebar: My Files | `folder` | "My Files" |
| Sidebar: Photos | `photo.on.rectangle` | "Photos" |
| Sidebar: Computer | `desktopcomputer` | "Computer 1", "Computer 2"… |
| Seção sidebar | — | "Drive", "Computers" |
| Nova pasta | `folder.badge.plus` | "New Folder" |
| Upload | `arrow.up.doc` | Menu "Upload": "Upload Files…", "Upload Folder…" |
| Download | `arrow.down.circle` | "Download" |
| Lixeira | `trash` | "Move to Trash" |
| Recarregar | `arrow.clockwise` | "Reload" |
| Transfers | `arrow.up.arrow.down` | "Transfers" |
| Conta | `person.crop.circle` | email / nome |
| Menu da conta | `ellipsis.circle` | "Sign Out…" |
| Nome não decriptado | `lock.trianglebadge.exclamationmark` | help: "This name couldn't be decrypted with your current keys." |
| Pausar / Retomar / Cancelar / Tentar de novo / Mostrar no Finder | `pause.circle` / `play.circle` / `xmark.circle` / `arrow.clockwise.circle` / `magnifyingglass.circle` | "Pause", "Resume", "Cancel", "Retry", "Show in Finder" |

Botões só com ícone: `Button("Texto", systemImage: "…")` + `.labelStyle(.iconOnly)`
quando necessário, **e** `.help("Texto")`. Nunca `Image` solto num botão.

### 6.3 Tabela

- Colunas: **Name** (ícone 16×16 do sistema + nome, `lineLimit(1)`,
  `.truncationMode(.middle)`), **Modified**
  (`.dateTime.day().month(.abbreviated).year().hour().minute()`, `.secondary`,
  `.monospacedDigit()`), **Size** (`"—"` para pastas, `ByteCountFormatStyle(.file)`,
  alinhada à direita, `.secondary`, `.monospacedDigit()`).
- Pastas sempre primeiro, qualquer que seja a ordenação; nomes com
  `localizedStandard`.
- Duplo clique numa pasta abre a pasta; num arquivo, "Download…".
- Menu de contexto na seleção: Open (só pasta), Download…, divisor, Move to Trash.
- Menu de contexto em área vazia: New Folder, Upload Files…, Upload Folder…, Reload.

### 6.4 Estados do detalhe (sempre `ContentUnavailableView`)

| Estado | Título | Símbolo | Descrição | Ação |
|--------|--------|---------|-----------|------|
| Carregando, sem cache | — (`ProgressView()` centralizado) | — | — | — |
| Pasta vazia | "This Folder Is Empty" | `folder` | "Drop files here or use Upload." | — |
| Filtro sem resultado | `ContentUnavailableView.search(text:)` | | | |
| Erro | "Couldn't Load Folder" | `exclamationmark.triangle` | mensagem de `UserFacingError` | "Try Again" |
| Sem raiz selecionada | "Select a Location" | `sidebar.left` | — | — |
| Photos (somente leitura) | banner em cima da tabela: "Photos is read-only in Neutron Transfer." | `info.circle` | | |

### 6.5 Popover de transfers

```
┌ Transfers ─────────────────────── ⋯ ┐   ⋯ = Pause All · Retry Failed · Clear Finished
│ ACTIVE                               │
│ 📄 video.mov                    ⏸ ✕ │
│    12.4 MB of 80 MB · to My Files ›  │
│    ▓▓▓▓▓░░░░░░░░░░░                  │
│ FAILED                               │
│ 📄 big.iso                      ↻ ✕ │
│    Network connection lost. Retry…   │  ← vermelho (.red), 2 linhas no máx.
│ COMPLETED                            │
│ 📁 Projects (14 files)          🔍   │
│    Downloaded to Downloads           │
└──────────────────────────────────────┘
```

- Tamanho 380×440, `List` com `Section`s "Active", "Failed", "Completed" (só as que
  têm itens). Uploads e downloads ficam juntos, ordenados por `updatedAt` decrescente.
- Vazio: `ContentUnavailableView("No Transfers", systemImage: "arrow.up.arrow.down",
  description: Text("Files you upload or download appear here."))`.
- Na toolbar, enquanto houver transfer ativo, o ícone mostra um badge com a contagem
  (verifique com `axiom-apple-docs` se `.badge` funciona em `ToolbarItem` no
  macOS 26; se não, use um `overlay` com cápsula pequena).

### 6.6 Login

```
                ┌────────┐
                │  icon  │  64×64 (NSApp.applicationIconImage)
                └────────┘
             Neutron Transfer                         .largeTitle semibold
     Sign in with your Proton account                 .secondary
   ┌──────────────────────────────────┐
   │ Email or username                │  Form .grouped, largura 360
   │ Password                         │
   └──────────────────────────────────┘
   ⚠ <erro>                               (.red, .callout, só se houver)
   [            Sign In             ]     .borderedProminent .large, default action
   ─────────────────────────────────────
   Neutron Transfer is an independent, open-source app. It is not
   affiliated with or endorsed by Proton AG. Your password is used only
   to sign in and unlock your keys on this Mac — it is never stored.
                                          .footnote .secondary centralizado, max 380
```

**Texto exato do disclaimer** (login, About e README): o parágrafo acima.

---

## 7. Fatias

### 7.0 Grafo e ordem

```
S0.1 ──► S0.2 (⟂ S0.3, S1.1)
     ├─► S0.3 ──► S1.2 ──► S1.3 ──► S2.1 ──► S2.2 ──► S2.3 ──► S3.1 ──► S3.2 ──► S4.2 ──► S4.3 ──► S4.4? ──► S5.1 ──► S5.2 ──► [HUMANO] S5.3/tag
     └─► S1.1 ───────────────┘                                       S4.1 (⟂ depois da S0.3, só Features/Auth)
```

- ⟂ = pode ser codada em paralelo, com builds serializados.
- **Pontos de parada para o humano** (live checks): depois da S0.2, S0.3, S1.2,
  S2.3, S3.1, S3.2 e S4.1. Para economizar logins, o orquestrador pode **juntar**
  checks pendentes num único pedido ao humano, desde que nenhuma fatia dependente
  tenha começado.

---

### S0.1 — Harness de testes no repo + alinhar targets

**Skills:** `axiom-xcode-mcp`, `axiom-build`, `axiom-testing`.
**Depende de:** nada. **Live check:** não.

**Ler primeiro:** `/tmp/nt-tests/Package.swift` (se existir), `CONTRIBUTING.md` §7,
`README.md` "How to test", `NeutronTransfer/NeutronTransfer.xcodeproj/project.pbxproj`
(só as seções `XCBuildConfiguration`).

**Tarefas:**

1. Criar `Package.swift` na **raiz do repo**:
   ```swift
   // swift-tools-version: 6.2
   // Neutron Transfer — SPM harness for the offline Core test suite.
   // The app itself builds with Xcode; this package only compiles Core/ (pure
   // Foundation) so contributors can run `swift test` without Xcode schemes.
   import PackageDescription

   let package = Package(
       name: "NeutronTransferCore",
       platforms: [.macOS(.v26)],
       targets: [
           .target(
               name: "NeutronTransfer",                         // matches @testable import
               path: "NeutronTransfer/NeutronTransfer/Core"
           ),
           .testTarget(
               name: "NeutronTransferTests",
               dependencies: ["NeutronTransfer"],
               path: "NeutronTransfer/NeutronTransferTests"
           ),
       ]
   )
   ```
   - Se `swift-tools-version: 6.2` ou `.macOS(.v26)` não forem aceitos pelo toolchain
     instalado (`rtk swift --version`), use a maior versão aceita e registre.
   - Se aparecerem erros de concorrência que **não** aparecem no build do Xcode,
     espelhe as flags do app adicionando ao target
     `swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]`.
     **Não altere código do Core para agradar o pacote.** Último recurso:
     `.swiftLanguageMode(.v5)`, registrado no relatório.
2. Apagar `NeutronTransfer/NeutronTransferTests/NeutronTransferTests.swift`
   (template vazio).
3. `project.pbxproj`, **apenas build settings**, com edições exatas (use `sed` com
   o padrão completo da linha e confira com `grep` antes e depois):
   - todas as ocorrências de `MACOSX_DEPLOYMENT_TARGET = 27.0;` e `= 14.0;` → `= 26.0;`
   - no target de testes: `SWIFT_VERSION = 5.0;` → `SWIFT_VERSION = 6.0;`
   - `PRODUCT_BUNDLE_IDENTIFIER = com.yourcompany.NeutronTransferTests;` →
     `dev.neutron.NeutronTransferTests;`
4. Scheme compartilhado: se o `XcodeListSchemes` mostrar que o scheme não é
   compartilhado, crie
   `NeutronTransfer.xcodeproj/xcshareddata/xcschemes/NeutronTransfer.xcscheme` com
   Build (app) + Test (`NeutronTransferTests`). Pegue os `BlueprintIdentifier` do
   pbxproj (`PBXNativeTarget`). Valide com `RunAllTests` via MCP. **Se não conseguir
   em duas tentativas, desfaça este item** e registre: `swift test` é o caminho
   canônico.
5. Atualizar `CONTRIBUTING.md` §7 e `README.md` "How to test" para
   `swift test` na raiz. Remover menções a `/tmp/nt-tests`.

**Aceitação:**
- [ ] `rtk swift test` na raiz passa; contagem ≥ 87 (88 menos o template, se ele contava). Cole o resumo.
- [ ] `BuildProject` verde, sem warnings novos.
- [ ] `grep -n "MACOSX_DEPLOYMENT_TARGET\|SWIFT_VERSION\|PRODUCT_BUNDLE_IDENTIFIER" project.pbxproj` mostra só 26.0 / 6.0 / `dev.neutron.*`.
- [ ] Nenhuma referência a `/tmp/nt-tests` no repo (`grep -rn "nt-tests"`).

---

### S0.2 — Header honesto no host de storage  ⟂

**Skills:** `axiom-networking`.
**Depende de:** S0.1. **Live check:** **sim** (download real).

**Contexto:** `AppVersion.storageHeaderValue = "external-drive-rclone@1.75.1-stable"`
é usado em `APIClient.downloadRawBlock` e `downloadRawBlockURL`. O comentário em
`AppVersion.swift` diz que o host de storage foi "provado" com a string do rclone.
Mas as regras de terceiros do SDK e o próprio arquivo ("Never spoof") proíbem se
passar por outro cliente.

**Tarefas:**
1. Remover `storageHeaderValue`. As duas chamadas passam a usar `AppVersion.headerValue`.
2. Reescrever o comentário de `AppVersion` explicando a regra (sem citar rclone como
   alternativa).
3. Procurar no `ProtonDriveApps/sdk` (C#) como o SDK monta o header nos requests de
   storage/blocks (busque `x-pm-appversion` e `BareURL`/`storage`). Registre no
   relatório o que encontrou: se o SDK manda algum header adicional que nós não
   mandamos (ex.: `pm-storage-token`), **liste, mas não implemente** sem a fonte exata.
4. Teste offline: em `F6HardeningTests.swift` (ou num arquivo novo
   `AppVersionTests.swift`), um teste que constrói o request de download de bloco e
   verifica `x-pm-appversion == AppVersion.headerValue`. Se o `URLRequest` só existe
   dentro do método, extraia um `func blockDownloadRequest(...) -> URLRequest` interno
   e teste esse.

**Live checks for human:** baixar um arquivo e uma pasta. Se falhar com 4xx no host
de storage → **parar** e levar a decisão 2.1-3 ao mantenedor.

**Aceitação:** `grep -rn "rclone@" NeutronTransfer/` vazio; teste novo verde; build verde.

---

### S0.3 — `AppSession` (raiz de DI), conta e logout  ⟂ com S1.1

**Skills:** `axiom-swiftui`, `axiom-concurrency`, `axiom-security`, `axiom-design`.
**Depende de:** S0.1. **Live check:** **sim**.

**Ler primeiro (inteiros):** `ContentView.swift`, `Features/Auth/LoginViewModel.swift`,
`Core/ProtonAPI/SessionManager.swift`, `Core/ProtonAPI/APIClient.swift`,
`Core/ProtonAPI/KeyMaterial.swift`, `Core/Security/KeyringCache.swift`,
`Features/Transfers/TransferActivityStore.swift`, `NeutronTransferApp.swift`.

**Tarefas:**

1. **Conta** — em `KeyMaterial.swift`, `ProtonUser` ganha campos opcionais
   (o Decodable sintetizado usa `decodeIfPresent` para opcionais):
   `name: String?` ("Name"), `displayName: String?` ("DisplayName"),
   `email: String?` ("Email"), `usedSpace: Int64?` ("UsedSpace"),
   `maxSpace: Int64?` ("MaxSpace"). Confira os nomes em `go-proton-api` `user_types.go`.
   Teste de decode com e sem os campos.
2. **Logout na API** — em `APIClient`, adicionar `func authDelete(uid:accessToken:) async throws`
   → `DELETE /auth/v4` (confirme em `go-proton-api` `AuthDelete` e cite no `///`).
   Em `SessionManager`, `signOut()` passa a ser `async`: tenta `authDelete`
   (**best-effort**, erro ignorado) e depois `session = nil`. Atualize os chamadores.
3. **`App/AppSession.swift`**:
   ```swift
   @MainActor @Observable
   final class AppSession {
       enum Phase: Equatable { case signedOut, signingIn, needsTwoFactor, unlocking, signedIn }
       struct Account: Equatable, Sendable {
           var email: String; var displayName: String
           var usedBytes: Int64; var maxBytes: Int64?
       }
       private(set) var phase: Phase = .signedOut
       private(set) var account: Account?
       var loginError: String?                 // shown on the login screen
       let activity = TransferActivityStore()
       let queue: TransferQueue                // TransferQueue(storeURL: .defaultStoreURL())
       let sessions: SessionManager
       let keyrings: KeyringCache
       let drive: DriveClient                  // the ONLY DriveClient in the app
       private(set) var addressKeys: [KeyringCache.UnlockedKey] = []
       private var pendingPassword: Data?      // only between signIn and 2FA unlock

       func signIn(username: String, password: String) async
       func submitTwoFactor(code: String) async
       func cancelTwoFactor() async            // = signOut, without an error
       func signOut(reason: String? = nil) async
       func refreshAccount() async
   }
   ```
   - Mover para cá a lógica do `LoginViewModel` **sem mudar a semântica**: senha
     retida só até o unlock pós-2FA; `bcryptNotAvailable` com a mensagem própria;
     todos os outros erros via `UserFacingError`.
   - Fases: `signingIn` durante o SRP → `needsTwoFactor` ou `unlocking` → depois de
     `finishSignIn` (salts → user keys → address keys) → `refreshAccount()` →
     `signedIn`.
   - `account.email`: `ProtonUser.email`, ou o email do primeiro endereço, ou o username digitado.
     `displayName`: `displayName ?? name ?? email`.
   - **Zerar** a senha retida: `pendingPassword?.resetBytes(in: 0..<count)` e depois `nil`,
     em todos os caminhos (sucesso, erro, cancelamento, logout).
   - `signOut(reason:)`, nesta ordem: `await queue.pauseAll()`,
     `await queue.setUploader(nil)`, `await sessions.signOut()`, `await keyrings.lock()`,
     `addressKeys = []`, zerar a senha, `account = nil`, `loginError = reason`,
     `phase = .signedOut`. (Na S1.2 entra também `resolver.reset()`.)
4. **`App/RootView.swift`**: `switch session.phase`: `.signedIn` → `LegacyMainView`;
   qualquer outro → `LoginView`.
5. **`Features/Auth/LoginView.swift`**: mover a UI de login atual do `ContentView`
   (visual igual por enquanto), lendo `@Environment(AppSession.self)`, com estado
   local `@State username/password/totp`.
6. **`Features/Shell/LegacyMainView.swift`** (temporário): o `TabView` atual. No
   cabeçalho, trocar "Signed in: uid" por `account.email` e adicionar um botão
   "Sign Out…" com `confirmationDialog`. As views antigas recebem
   `session.sessions`, `session.addressKeys`, `session.activity` e `session.queue`.
   (Adapte os `init` delas se precisar; elas morrem na S3.2.) **Remover** os textos
   "F6 alpha…" do rodapé.
7. Mover `NeutronTransferApp.swift` para `App/` (`rtk git mv`). Conteúdo:
   `@State private var session = AppSession()` e
   `WindowGroup { RootView().environment(session) }`. (O `Window` entra na S4.2.)
8. Apagar `ContentView.swift` e `LoginViewModel.swift`.

**Aceitação:**
- [ ] Build verde; `swift test` verde (inclui o teste novo de decode do `ProtonUser`).
- [ ] `grep -rn "DriveClient(" Features App` encontra **só** `AppSession` (as views legadas podem continuar criando o próprio até a S3.2; nesse caso, registre).
- [ ] Nenhum `print(`.
- [ ] Preview do `LoginView` renderiza.

**Live checks for human:** login → cabeçalho mostra o email; Sign Out → volta ao
login; logar de novo funciona (respeite ~11 min entre logins por causa do 2028; dá
para testar o Sign Out e deixar o re-login para o próximo check agrupado); conta com
2FA (se houver).

---

### S1.1 — Modelos puros de Drive  ⟂

**Skills:** `axiom-swift`, `axiom-testing`.
**Depende de:** S0.1. **Live check:** não.

**Ler primeiro:** `Core/ProtonAPI/DriveModels.swift` (`ShareMetadata`, `Volume`,
`DriveLink`).

**Criar em `Core/Drive/`** (Foundation apenas):

1. `ShareKind.swift`
   ```swift
   enum ShareKind: Hashable, Sendable {
       case main, standard, device, photos, unknown(Int)
       init(rawType: Int)   // 1 main, 2 standard, 3 device, 4 photos — CONFIRA
   }
   ```
   Confirme os valores em `go-proton-api` (`share_types.go`: `ShareTypeMain` etc.) ou
   no SDK C#, e cite no `///`. Confirme também o valor de "share ativa"
   (`ShareStateActive`).
2. `DriveRoot.swift`
   ```swift
   struct DriveRoot: Hashable, Sendable, Identifiable {
       var id: String { shareID }
       let shareID: String
       let rootLinkID: String
       let volumeID: String
       let kind: ShareKind
       let displayName: String
       var allowsWrites: Bool { kind == .main || kind == .device }
   }
   struct DriveRoots: Equatable, Sendable {
       var myFiles: DriveRoot?
       var photos: DriveRoot?
       var computers: [DriveRoot]
       var all: [DriveRoot]   // myFiles, photos, computers, nessa ordem
   }
   enum ShareCatalog {
       static func roots(from metas: [ShareMetadata], mainShareIDs: Set<String>) -> DriveRoots
   }
   ```
   Regras: descartar `state != ativo`, `locked == true`, `volumeSoftDeleted == true`.
   `myFiles`: share `.main`; se houver mais de uma, preferir a que está em
   `mainShareIDs` (vem de `Volume.share.shareID`), depois a de menor `creationTime`.
   `photos`: primeira `.photos`. `computers`: todas as `.device`, ordenadas por
   `creationTime`, com `displayName` "Computer 1", "Computer 2"… `.standard` e
   `.unknown` são ignoradas. Nomes: "My Files", "Photos".
3. `DriveLocation.swift`: `struct DriveLocation: Hashable, Sendable, Codable { let shareID: String; let linkID: String; let name: String }`.
4. `DriveItem.swift`
   ```swift
   struct DriveItem: Identifiable, Hashable, Sendable {
       enum Kind: Hashable, Sendable { case folder, file }
       let id: String            // linkID
       let shareID: String
       let parentLinkID: String?
       let name: String          // decrypted, or "Encrypted Item" when not
       let isNameDecrypted: Bool
       let kind: Kind
       let size: Int64           // 0 for folders (see backlog B2: encrypted size today)
       let modified: Date
       let mimeType: String?
       var isFolder: Bool { kind == .folder }
       var fileExtension: String { (name as NSString).pathExtension.lowercased() }
       var location: DriveLocation { .init(shareID: shareID, linkID: id, name: name) }
       init(link: DriveLink, shareID: String, decryptedName: String?)
   }
   ```
5. `DriveItemOrdering.swift`:
   `static func sorted(_ items: [DriveItem], using comparators: [KeyPathComparator<DriveItem>]) -> [DriveItem]`:
   ordena pelos comparadores e depois faz **partição estável**, com pastas primeiro.
   `static func filtered(_ items: [DriveItem], query: String) -> [DriveItem]`:
   `localizedStandardContains`; query vazia/espaços devolve tudo.
6. `DriveFormatting.swift`:
   `static func size(_ item: DriveItem, locale: Locale = .current) -> String` ("—" para pasta);
   `static func storage(used: Int64, max: Int64?, locale: Locale = .current) -> String` →
   `"148.48 GB of 520 GB used"` / `"148.48 GB used"`;
   `static func itemCount(_ n: Int) -> String` → "1 item" / "N items".
   Use `ByteCountFormatStyle(style: .file).locale(locale)`.

**Testes** (`NeutronTransferTests/DriveModelsTests.swift`), com locale `en_US` fixo:
mapeamento de tipos; filtros de estado/locked/softDeleted; preferência por
`mainShareIDs`; ordem e nomes dos computers; `DriveItem` com nome nil; ordenação
com pastas primeiro em ordem asc e desc; filtro; formatação.

**Aceitação:** ≥ 15 testes novos verdes; nenhum import além de Foundation.

---

### S1.2 — `NodeKeyResolver`: resolvedor único de chaves (alto risco)

**Skills:** `axiom-concurrency` (atenção a **reentrância de actor**), `axiom-testing`, `axiom-security`.
**Depende de:** S0.3, S1.1. **Live check:** **sim**.

**Ler primeiro (inteiros):** `Core/Transfers/DriveUploadAdapter.swift`,
`Core/Transfers/DriveDownloadAdapter.swift`, `Core/Security/DecryptChain.swift`,
`Features/Browser/DriveBrowserViewModel.swift` (`loadShare`).

**Por quê:** hoje o upload só funciona na raiz ou em pastas criadas na sessão (P5),
e há três cópias da lógica de desbloqueio (P6).

**Criar `Core/Security/NodeKeyResolver.swift`:**

```swift
/// Fetches Drive key material (DriveClient conforms; tests use fakes).
protocol DriveKeyMaterialSource: Sendable {
    func getShare(_ shareID: String) async throws -> DriveShare
    func getLink(shareID: String, linkID: String) async throws -> DriveLink
}
extension DriveClient: DriveKeyMaterialSource {}

/// Crypto seam so traversal/memo logic is testable without real keys.
struct NodeUnlocker: Sendable {
    var unlockShare: @Sendable (DriveShare, [KeyringCache.UnlockedKey]) throws -> [KeyringCache.UnlockedKey]
    var unlockNode: @Sendable (DriveLink, [DecryptCandidate], [Data]) throws -> [KeyringCache.UnlockedKey]
    var folderHashKey: @Sendable (DriveLink, [KeyringCache.UnlockedKey]) throws -> Data
    static let live: NodeUnlocker   // DecryptChain + the hash-key logic MOVED from DriveUploadAdapter
}

actor NodeKeyResolver {
    struct ShareContext: Sendable {
        let shareID: String; let rootLinkID: String
        let keys: [KeyringCache.UnlockedKey]
        let addressID: String; let signatureEmail: String
    }
    struct FolderContext: Sendable {
        let shareID: String; let linkID: String
        let keys: [KeyringCache.UnlockedKey]   // this folder's node keys
        let hashKey: Data                      // name-HMAC key for its children
        let addressID: String; let signatureEmail: String
    }
    init(source: any DriveKeyMaterialSource, addressKeys: [KeyringCache.UnlockedKey], unlocker: NodeUnlocker = .live)
    func share(_ shareID: String) async throws -> ShareContext
    func nodeKeys(shareID: String, linkID: String) async throws -> [KeyringCache.UnlockedKey]
    func folder(shareID: String, linkID: String) async throws -> FolderContext
    func remember(_ links: [DriveLink])        // cache links already fetched by a listing
    func register(createdFolder: FolderContext) // after createFolder
    func reset()                                // wipe ALL caches (sign-out)
}
```

Regras de implementação:
- `nodeKeys`: se `linkID == rootLinkID` → desbloqueia com as chaves da share. Senão,
  pega o `DriveLink` (cache de `remember`, ou `getLink`), resolve **recursivamente**
  as chaves de `parentLinkID` e desbloqueia com elas. Memoize por `linkID`.
- **Reentrância:** dois `await nodeKeys` concorrentes para a mesma pasta não podem
  disparar dois `getLink`. Guarde `Task`s em andamento num dicionário
  `inFlight: [String: Task<[UnlockedKey], Error>]` (padrão single-flight; veja a
  skill `axiom-concurrency`).
- `signerPoints` = `DecryptChain.edPoints(addressKeys)`, calculado uma vez no `init`.
- `addressID`/`signatureEmail` vêm da `DriveShare` (`addressID`, `creator`), igual ao
  `resolveRoot` atual.
- `reset()`: esvazia todos os dicionários e cancela os `inFlight`.

**Migrar:**
- `DriveUploadAdapter`: `init(drive:addressKeys:resolver:)`. `keysFor` vira
  `resolver.folder(...)` (mapeado para `ResolvedKeys`, ou substitua `ResolvedKeys` por
  `FolderContext`). **Remover** o erro "unknown remote parent". `ensureFolder`, depois
  de criar, chama `resolver.register(createdFolder:)`. `folderHashKey` sai daqui e vai
  para `NodeUnlocker.live` (código idêntico).
- `DriveDownloadAdapter`: `init(drive:addressKeys:resolver:)`. `keysForFolder`,
  `shareKeyring` e `parentKeysFor` passam a delegar ao resolver; remova os
  dicionários locais equivalentes.
- `AppSession`: `private(set) var resolver: NodeKeyResolver?`, criado quando
  `addressKeys` fica pronto; no `signOut`: `await resolver?.reset(); resolver = nil`.
- Views legadas: passar o resolver ao criar os adapters.

**Testes** (`NodeKeyResolverTests.swift`, com `FakeSource` e `NodeUnlocker` fake que
devolve `UnlockedKey` marcadas por `keyID` = linkID):
1. raiz desbloqueia com as chaves da share;
2. cadeia raiz → A → B: B desbloqueado com as chaves de A (confira pelo `keyID` passado);
3. memo: a segunda chamada não chama `getLink` (contador no fake);
4. `remember` evita `getLink`;
5. single-flight: 10 chamadas concorrentes = 1 `getLink`;
6. `register` + `folder` não buscam nada;
7. `reset` limpa (próxima chamada busca de novo);
8. pasta sem `NodeHashKey` → erro.

**Aceitação:** testes verdes (inclusive os antigos de fila/download); build verde;
`grep -n "unknown remote parent"` vazio.

**Live checks for human:** (legado ainda) baixar um arquivo de **dentro de uma
subpasta** (precisa de S2.2 para navegar; se não der, adie este check para depois da
S2.3); upload na raiz continua funcionando.

---

### S1.3 — `DriveListing`

**Skills:** `axiom-concurrency`, `axiom-networking`.
**Depende de:** S1.2. **Live check:** não (vai junto com a S2.2).

**Criar `Core/Drive/DriveListing.swift`:**
```swift
actor DriveListing {
    init(drive: DriveClient, resolver: NodeKeyResolver)
    /// Volumes + shares → classified roots (ShareCatalog).
    func roots() async throws -> DriveRoots
    /// Active children of a folder with decrypted names. Feeds the resolver's link cache.
    func children(of location: DriveLocation) async throws -> [DriveItem]
}
```
- `roots()`: `listVolumes()` → `mainShareIDs = Set(volumes.map(\.share.shareID))`;
  `listShares()` → `ShareCatalog.roots`.
- `children`: `drive.listChildren(shareID:linkID:)` → filtrar `isActive` →
  `await resolver.remember(links)` → `keys = await resolver.nodeKeys(location)` →
  `candidates = keys.compactMap(\.candidate)` → para cada link,
  `try? DecryptChain.decryptName(link, parentCandidates:)` → `DriveItem(link:shareID:decryptedName:)`.
- A decriptação roda **dentro do actor**, fora da main thread (regra 3.3).
- `AppSession`: `private(set) var listing: DriveListing?` (criado junto com o
  resolver, zerado no logout) e
  `private(set) var roots: DriveRoots?` + `func loadRoots() async` (chamado
  ao entrar em `signedIn`; guarda erro em `rootsError: String?`).

**Aceitação:** build verde; testes verdes. (A lógica pura já foi testada na S1.1;
`DriveListing` é cola de rede.)

---

### S2.1 — Shell: `NavigationSplitView`, sidebar, quota, conta

**Skills:** `axiom-macos`, `axiom-swiftui`, `axiom-design`, `axiom-xcode-mcp`.
**Depende de:** S1.3. **Live check:** não (vai junto com a S2.3).

**Criar:**
1. `Features/Preview/PreviewFixtures.swift` (`#if DEBUG`): `DriveRoots` de exemplo,
   ~8 `DriveItem` (pastas e arquivos de extensões variadas, um com
   `isNameDecrypted = false`), `AppSession.Account` de exemplo. Se precisar criar um
   `AppSession` de preview, adicione `static func preview(phase:account:roots:)`
   `#if DEBUG` que **não** faça rede.
2. `Features/Shell/SidebarItem.swift`:
   `enum SidebarItem: Hashable { case myFiles, photos, computer(shareID: String) }`
   + `func root(in: DriveRoots) -> DriveRoot?`.
3. `Features/Shell/SidebarView.swift`: seções "Drive" (My Files, Photos se existir)
   e "Computers" (se não estiver vazia), com os ícones da 6.2. `.listStyle(.sidebar)`.
   `.safeAreaInset(edge: .bottom) { StorageFooterView() }`.
4. `Features/Shell/StorageFooterView.swift`: `ProgressView(value:total:)` linear com
   tint por ocupação (`< 0.8` accent, `< 0.95` `.orange`, senão `.red`), texto de
   `DriveFormatting.storage` (`.caption`, `.secondary`, `.monospacedDigit()`), e uma
   linha de conta: `person.crop.circle` + nome (`.callout`) + email (`.caption`,
   `.secondary`) + `Menu` com `ellipsis.circle` contendo "Sign Out…".
   `.menuStyle(.button)`, `.buttonStyle(.borderless)`, `.fixedSize()`. Sign Out com
   `confirmationDialog`; se houver uploads ativos: "Sign out? Active transfers will
   be paused." Padding 12. Sem quota: esconder a barra.
5. `Features/Shell/MainView.swift`:
   ```swift
   NavigationSplitView {
       SidebarView(selection: $selection)
           .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
   } detail: {
       // S2.1: placeholder Text(root.displayName); S2.2 swaps in BrowserContainerView(root:).id(root.id)
   }
   .frame(minWidth: 800, minHeight: 500)
   ```
   Seleção inicial `.myFiles`. Enquanto `roots == nil`, `ProgressView("Loading your drive…")`;
   se `rootsError`, `ContentUnavailableView` com "Try Again".
   **Temporário:** um `ToolbarItem` "Legacy Transfers" abrindo uma `.sheet` com o
   `TransferQueueView` antigo, para não perder o upload até a S3.
6. `RootView`: `.signedIn` → `MainView` (o `LegacyMainView` pode ser apagado se nada
   mais depender dele; o `DriveBrowserViewModel` fica até a S2.3).
7. `.defaultSize(width: 1100, height: 700)` na cena.

**Aceitação:** previews da sidebar e do footer em light e dark (anexe a descrição de
cada um); build verde; sem `print`.

---

### S2.2 — Browser: `Table` + navegação por pastas

**Skills:** `axiom-swiftui`, `axiom-macos`, `axiom-design`, `anthropic-skills:axiom-analyze-swiftui-performance` (se existir).
**Depende de:** S2.1. **Live check:** vai junto com a S2.3.

**Criar:**
1. `Features/Browser/BrowserModel.swift`:
   ```swift
   @MainActor @Observable
   final class BrowserModel {
       enum LoadPhase: Equatable { case idle, loading, loaded, failed(String) }
       struct FolderState { var items: [DriveItem] = []; var phase: LoadPhase = .idle; var isStale = false }

       let root: DriveRoot
       let rootLocation: DriveLocation   // name = root.displayName ("My Files")
       var path: [DriveLocation] = []
       var current: DriveLocation { path.last ?? rootLocation }
       private(set) var folders: [String: FolderState] = [:]   // by linkID
       var selection: Set<DriveItem.ID> = []
       var sortOrder: [KeyPathComparator<DriveItem>] = [KeyPathComparator(\.name, comparator: .localizedStandard)]
       var filterText = ""

       init(root: DriveRoot, session: AppSession)
       func state(for loc: DriveLocation) -> FolderState
       func visibleItems(for loc: DriveLocation) -> [DriveItem]   // DriveItemOrdering filtered+sorted
       func load(_ loc: DriveLocation, force: Bool = false) async   // uses cache unless force/stale
       func open(_ item: DriveItem)          // folder → path.append(item.location); file → requestDownload([item]) (S2.3; no-op for now)
       func openSelection(_ ids: Set<DriveItem.ID>)
       func goToParent()
       func pop(to loc: DriveLocation)       // breadcrumb
       func reloadCurrent() async
       func markStale(parentLinkIDs: Set<String>) // reload if current is among them
   }
   ```
   - `load`: se já estiver `loaded` e não for `force`/`isStale`, retorna. Mantém os
     itens antigos visíveis enquanto recarrega (sem piscar).
   - Se o erro for `ProtonAPIError.unauthorized`, chama
     `await session.signOut(reason: "Your session expired. Sign in again.")`.
   - Limpa `selection` quando `path` muda.
   - Não guarda nada em disco.
2. `Features/Browser/FileIcon.swift`: `@MainActor enum FileIconCache` com cache
   `[String: NSImage]` por extensão. Pasta: `NSWorkspace.shared.icon(for: .folder)`;
   arquivo: `UTType(filenameExtension:) ?? .data`. View `FileIcon(item:)` →
   `Image(nsImage:).resizable().frame(width: 16, height: 16)`.
3. `Features/Browser/FolderTable.swift`: `Table(items, selection:, sortOrder:)`
   conforme a 6.3. `.contextMenu(forSelectionType: DriveItem.ID.self) { … } primaryAction: { model.openSelection($0) }`.
   Na S2.2 o menu só tem "Open"; o resto entra na S2.3. Alinhamento à direita da
   coluna Size: confira com `axiom-apple-docs` se `TableColumn.alignment(.trailing)`
   existe no macOS 26; senão, `.frame(maxWidth: .infinity, alignment: .trailing)`.
4. `Features/Browser/FolderView.swift`: `FolderTable` + `.overlay` com os estados da
   6.4 + `.navigationTitle(location.name)` + `.navigationSubtitle(DriveFormatting.itemCount(n))`
   + `.toolbarTitleMenu { ForEach(ancestors) { Button($0.name) { model.pop(to: $0) } } }`
   + `.task(id: location) { await model.load(location) }`.
   Photos: banner da 6.4.
5. `Features/Browser/BrowserContainerView.swift`:
   `@State private var model: BrowserModel` (criado no `init` a partir da `root`),
   `NavigationStack(path: $model.path) { FolderView(location: model.rootLocation).navigationDestination(for: DriveLocation.self) { FolderView(location: $0) } }`
   + `.searchable(text: $model.filterText, placement: .toolbar, prompt: "Filter this folder")`.
   `.environment(model)` para as subviews.
6. `MainView`: detalhe = `BrowserContainerView(root:).id(root.id)`.
7. Previews com fixtures: lista cheia, vazia, erro, carregando.

**Aceitação:**
- [ ] Previews das 4 situações em light e dark.
- [ ] Build verde; testes verdes; nenhum decrypt em `@MainActor` (`grep -n "DecryptChain" Features` vazio).
- [ ] O `DriveBrowserView` antigo não é mais usado (ainda pode existir).

---

### S2.3 — Ações: Download (multi), New Folder, Move to Trash, Reload

**Skills:** `axiom-macos` (NSOpenPanel, sandbox, security scope), `axiom-swiftui`, `design:ux-copy`, `axiom-testing`.
**Depende de:** S2.2. **Live check:** **sim** (agrupado: S1.2 + S2.x).

**Criar/alterar:**
1. `Features/Shared/Panels.swift`: mover `presentDestinationPanel` do
   `DriveBrowserViewModel` para
   `@MainActor enum Panels { static func chooseDownloadFolder() async -> URL?; static func chooseUploadItems(folders: Bool) async -> [URL] }`,
   mantendo o uso de `PanelIntake` e o padrão sheet-ou-app-modal sem `runModal`.
   `chooseUploadItems(folders:false)` = só arquivos, múltiplos;
   `folders:true` = só pastas, múltiplas. Prompt "Upload".
2. `Core/Transfers/DownloadRecord.swift`: `var progress: Double?` (0…1, opcional, default nil).
   Ajuste/acrescente testes.
   `TransferActivityStore`: `func downloadProgress(id: UUID, fraction: Double)` e um
   dicionário **em memória** `revealURLs: [UUID: URL]` (não Codable, fora do record:
   o record continua sem caminho completo, por privacidade).
3. `Features/Transfers/DownloadCoordinator.swift` (`@MainActor`), criado pelo `AppSession` junto com o
   resolver: `func download(_ items: [DriveItem]) async`: escolhe a pasta uma vez →
   `startAccessingSecurityScopedResource` → um `DriveDownloadAdapter(drive:addressKeys:resolver:)`
   → **sequencial** por item: registra no activity, arquivo usa `downloadSingleFile`
   com progresso (blocos feitos/total), pasta usa `downloadTree` → `downloadFinished`/`downloadFailed`
   → `stopAccessing`. Copie a lógica do `DriveBrowserViewModel.download` sem mudar
   comportamento. Download **não** invalida o browser.
4. `Core/Drive/FolderNameValidator.swift` (puro, testado):
   `static func validate(_ raw: String) -> Result<String, FolderNameError>`: trim;
   vazio → `.empty`; contém "/" ou NUL → `.invalidCharacters`; "." ou ".." →
   `.reserved`; > 255 bytes UTF-8 → `.tooLong`; devolve o nome NFC. Mensagens em
   inglês via `var message: String`.
5. `Features/Browser/FolderOperations.swift` (`@MainActor` struct ou métodos no `AppSession`):
   - `createFolder(name:in:) async throws -> String` (linkID): `resolver.folder(parent)`
     → `drive.createFolder(...)` com os mesmos argumentos que `DriveUploadAdapter.ensureFolder`
     usa → `getLink` + `unlockNode` + hashKey → `resolver.register`. **Sem** sufixo
     automático: nome duplicado vira erro "A folder named “X” already exists." Confirme
     o código de duplicado (provável 2500) no SDK/go-proton-api; se não achar, trate
     qualquer `.api` cujo texto contenha "exist".
   - `trash(_ items: [DriveItem], in parent: DriveLocation) async throws` →
     `drive.trashChildren(shareID:parentLinkID:linkIDs:)`.
   - Ambos chamam `activity.remoteChanged(parentLinkIDs: [parent.linkID])` (adicione
     esse método ao activity store; ele publica um `Set<String>` + um token
     incremental). O `BrowserModel` observa e chama `markStale`. Remova o uso de
     `browserRefreshCounter` (e o próprio contador, se ninguém mais usar).
6. `Features/Browser/NewFolderSheet.swift`: `.sheet` com `TextField` (texto inicial
   "Untitled Folder", selecionado), erro inline em vermelho, botões "Cancel"
   (`.cancelAction`) e "Create" (`.defaultAction`, desabilitado se inválido; com
   `ProgressView` enquanto cria). Ao criar: fecha, recarrega a pasta e seleciona a
   pasta nova.
7. Toolbar (em `FolderView` ou no container) conforme a 6.2: New Folder (desabilitado
   se `!root.allowsWrites`), Download (desabilitado sem seleção), Move to Trash
   (desabilitado sem seleção ou se `!allowsWrites`), Reload. O botão Upload entra na S3.1.
8. Trash: `confirmationDialog("Move \(n) item(s) to Trash?")`, mensagem "You can
   restore them from Trash in Proton Drive on the web.", botão `role: .destructive`
   "Move to Trash". Remoção otimista do cache, depois recarrega. Erros → `.alert`.
9. Menu de contexto completo (6.3). Duplo clique em arquivo → Download.
10. Apagar `DriveBrowserView.swift` e `DriveBrowserViewModel.swift`.

**Aceitação:** testes do validador (≥ 6) e do `DownloadRecord` verdes; build verde;
previews do `NewFolderSheet` (normal e com erro).

**Live checks for human (agrupado):** navegar 3 níveis de pastas, voltar pelo botão e
pelo menu do título; baixar 2 arquivos selecionados juntos + 1 pasta; criar pasta
(e tentar criar com nome repetido); mover para a lixeira e conferir na web; checar
que nomes aparecem certos em subpastas.

---

### S3.1 — Upload para a pasta atual (drop na tabela + menu Upload)

**Skills:** `axiom-macos`, `axiom-swift` (drag and drop), `axiom-concurrency`.
**Depende de:** S2.3. **Live check:** **sim**.

**Ler primeiro (inteiros):** `TransferQueueViewModel.swift`, `TransferQueueView.swift`
(o `loadDropped`), `TransferQueue.enqueueTree`, `LocalTreeScan`.

1. `Features/Transfers/UploadCoordinator.swift` (`@MainActor @Observable`, criado
   pelo `AppSession` depois do unlock):
   - `jobs: [TransferJob]` (snapshot da fila).
   - `start()`: o mesmo do `TransferQueueViewModel.start()` (`setUploader` com
     `DriveUploadAdapter(drive:addressKeys:resolver:)`, `setListener`, `queue.start()`),
     só que, quando um job passa a `.done`, chama
     `activity.remoteChanged(parentLinkIDs: [job.parentLinkID])`.
   - `upload(urls: [URL], to destination: DriveLocation) async`: o mesmo
     `add(urls:)` de hoje (**preserve** o `startAccessingSecurityScopedResource`, o
     scan em `Task.detached` e os bookmarks), com `shareID = destination.shareID` e
     `rootParentLinkID = destination.linkID`. Depois do `enqueueTree`, chama
     `remoteChanged([destination.linkID])` (pastas criadas) e `activity.presentTransfers = true`.
   - `destinationNames: [UUID: String]` em memória (jobID → "My Files › Projects"),
     usado pelo painel.
   - pause/resume/cancel/relaunch/remove/relaunchAllFailed/pauseAll repassados à fila.
   - `AppSession.signOut` chama `uploads?.stop()` e zera.
2. `Features/Browser/DropOverlay.swift` + em `FolderView`:
   `.onDrop(of: [.fileURL], isTargeted: $isTargeted)` usando o mesmo `loadDropped`
   (mova a função para o coordinator ou para um helper). Recusar (`return false`, sem
   destaque) se `!root.allowsWrites`. Overlay quando `isTargeted`:
   `RoundedRectangle(cornerRadius: 10).strokeBorder(.tint, lineWidth: 2)` + fundo
   `Color.accentColor.opacity(0.06)` + cápsula `.regularMaterial` com
   "Drop to upload to “\(location.name)”". `allowsHitTesting(false)`.
3. Toolbar: `Menu("Upload", systemImage: "arrow.up.doc") { Button("Upload Files…"); Button("Upload Folder…") }`
   → `Panels.chooseUploadItems` → `uploads.upload(urls:to: model.current)`.
   Desabilitado se `!allowsWrites`, com `.help("Uploading to Photos isn't supported yet.")`.
4. Menu de contexto em área vazia: Upload Files…, Upload Folder….
5. Remover o "Legacy Transfers" da S2.1 **só na S3.2**.

**Aceitação:** build verde; testes verdes (`TransferQueueTests` intocados);
`grep -n "selectedShareID" -r Features` só no código legado.

**Live checks for human:** arrastar uma pasta com subpastas para **dentro de uma
subpasta**: a estrutura aparece igual na web; Upload Files… com 3 arquivos; o browser
atualiza sozinho ao terminar; upload em Photos está bloqueado.

---

### S3.2 — Popover de Transfers + remoção do legado

**Skills:** `axiom-swiftui`, `axiom-macos`, `axiom-design`, `axiom-accessibility`, `design:ux-copy`.
**Depende de:** S3.1. **Live check:** **sim** (leve).

1. `Features/Transfers/TransferRow.swift`: um tipo de exibição unificado
   ```swift
   struct TransferDisplayItem: Identifiable { enum Direction { case upload, download }
       let id: String; let direction: Direction; let name: String; let isFolder: Bool
       let subtitle: String; let progress: Double?; let isActive: Bool; let isFailed: Bool
       let updatedAt: Date }
   ```
   montado a partir de `TransferJob` (upload) e `DownloadRecord` (download), numa
   função pura e testável. **Coloque o mapeamento em `Core/Transfers/TransferDisplay.swift`** e teste.
   Subtítulos: upload ativo "12.4 MB of 80 MB · to My Files › Projects";
   na fila "Waiting…"; pausado "Paused · 12.4 MB of 80 MB"; feito "Uploaded to …";
   falhou → `UserFacingError.message(forMessage:)`; download ativo
   "Downloading… 45%"; download feito "Downloaded to Downloads" (+ "(14 files)" para pastas).
   A view: ícone de arquivo, nome, subtítulo (vermelho se falhou, `lineLimit(2)`),
   `ProgressView(value:)` `.controlSize(.small)` se ativo, botões de ação só com ícone
   (6.2) por estado, igual ao `actions(_:)` atual. "Show in Finder" usa
   `NSWorkspace.shared.activateFileViewerSelecting` com `revealURLs`.
2. `Features/Transfers/TransfersPanel.swift`: conforme a 6.5; menu `⋯` com "Pause All",
   "Retry Failed", "Clear Finished" (limpa downloads terminados **e** remove uploads
   `.done`).
3. `Features/Transfers/TransfersToolbarButton.swift`: `ToolbarItem(placement: .primaryAction)`,
   `.popover(isPresented: $activity.presentTransfers, arrowEdge: .bottom)`, badge com
   o número de ativos.
4. Remover: `TransferQueueView.swift`, `TransferQueueViewModel.swift`, o botão
   "Legacy Transfers", `LegacyMainView` (se ainda existir). Conferir com
   `grep -rn "Legacy\|TransferQueueView\|DriveBrowserView\|ContentView" NeutronTransfer/NeutronTransfer`.
5. Varredura de textos de debug:
   `grep -rn "F[0-9]\b\|alpha:\|type \\\\(\|Queue.device\|seeds never\|2511" Features App`.
   Nada disso pode aparecer em string visível ao usuário (comentários podem).

**Aceitação:** testes do `TransferDisplay` verdes; previews do painel (vazio, misto,
com falha) em light e dark; build verde; grep da etapa 4 vazio.

**Live checks for human:** pausar/retomar/cancelar um upload grande; "Show in Finder"
num download; o badge some quando tudo termina.

---

### S4.1 — Login redesenhado  ⟂ (pode rodar a qualquer momento depois da S0.3)

**Skills:** `axiom-design` (auth flow), `axiom-swiftui`, `axiom-accessibility`, `design:ux-copy`.
**Depende de:** S0.3. **Mexe só em** `Features/Auth/*`. **Live check:** **sim**.

1. `LoginView` conforme a 6.6. `@FocusState` com foco inicial no email.
   `.textContentType(.username)` / `.password` (deixa o gerenciador de senhas do macOS
   preencher). Enter envia. Botão desabilitado com campo vazio ou em `signingIn`;
   durante `signingIn`, um `ProgressView().controlSize(.small)` no lugar do texto.
   Erro: `Label(msg, systemImage: "exclamationmark.triangle.fill")`, `.red`, `.callout`.
   Confira o tamanho de `Form(.grouped)` dentro de `VStack` com `RenderPreview`; se
   ficar estranho, troque por campos com `.textFieldStyle(.roundedBorder)` + `.controlSize(.large)`.
2. `TwoFactorView`: `lock.shield` (40pt, `.tint`), "Two-Factor Authentication",
   "Enter the 6-digit code from your authenticator app.", `TextField` com
   `.textContentType(.oneTimeCode)`, `.font(.title2.monospacedDigit())`, centralizado,
   largura 180, aceitando só dígitos (máx. 6); envia sozinho ao completar 6. Botões
   "Back" (`cancelTwoFactor`) e "Verify" (default).
3. `UnlockingView`: `ProgressView()` + "Unlocking your encrypted drive…" + texto
   menor "This happens on your Mac. It can take a few seconds."
4. `RootView`: `.signingIn`/`.signedOut` → `LoginView`; `.needsTwoFactor` → `TwoFactorView`;
   `.unlocking` → `UnlockingView`. Transição `.opacity` curta.
5. Acessibilidade: labels nos campos, o erro é anunciado
   (`AccessibilityNotification.Announcement`).

**Aceitação:** previews de: login vazio, preenchido com erro, signingIn, 2FA, unlocking
— em light e dark; build verde.

**Live checks for human:** login com o gerenciador de senhas; erro de senha errada;
mensagem do 2028 legível.

---

### S4.2 — Menus, janela única, Settings, About, versão

**Skills:** `axiom-macos`, `axiom-swiftui`.
**Depende de:** S3.2. **Live check:** não.

1. `NeutronTransferApp`: `Window("Neutron Transfer", id: "main") { RootView() }`
   (não `WindowGroup`), `.defaultSize(width: 1100, height: 700)`,
   `.windowToolbarStyle(.unified)`, `.commands { AppCommands() }`,
   `Settings { SettingsView() }`, os dois com `.environment(session)`.
2. `FocusedValues`: `@Entry var browserModel: BrowserModel?`; o `FolderView` faz
   `.focusedSceneValue(\.browserModel, model)`.
3. `App/AppCommands.swift`:
   - `CommandGroup(replacing: .appInfo)`: "About Neutron Transfer" →
     `NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: <disclaimer 6.6>)])`.
   - `CommandGroup(replacing: .newItem)`: "New Folder" ⇧⌘N, "Upload Files…" ⌘U,
     "Upload Folder…" ⇧⌘U.
   - `CommandMenu("Go")`: "Enclosing Folder" ⌘↑, "Open" ⌘↓, "Reload" ⌘R.
   - `CommandGroup(after: .pasteboard)`: "Move to Trash" ⌘⌫, "Download" ⌥⌘D (escolha
     um atalho que não conflite; confira na HIG pela skill).
   - `CommandGroup(after: .toolbar)`: "Show Transfers" ⌥⌘T.
   - `CommandGroup(after: .appSettings)`: "Sign Out…".
   - Tudo desabilitado quando não se aplica (sem `browserModel`, sem seleção, raiz
     somente leitura, deslogado).
4. `Features/Settings/SettingsView.swift`: `TabView` com
   **General**: `Stepper("Simultaneous uploads: \(n)", value: $n, in: 1...8)`, com
   `@AppStorage("maxConcurrentUploads")` default 4 →
   `queue.setMaxConcurrent` (aplicado também no launch);
   **About**: ícone, nome, versão (`CFBundleShortVersionString` + build), disclaimer,
   `Link("Source Code", destination: https://github.com/errrepe/Neutron-Transfer)`,
   "MIT License".
5. pbxproj (só build settings): `MARKETING_VERSION = 0.1.0;`,
   `INFOPLIST_KEY_NSHumanReadableCopyright = "© 2026 Neutron Transfer contributors. MIT License.";`,
   `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";`
   (adicione se não existir; app target, Debug e Release).

**Aceitação:** build verde; todos os atalhos aparecem nos menus; Settings abre com ⌘,.

---

### S4.3 — Auditoria de polimento (HIG, acessibilidade, concorrência)

**Skills:** `anthropic-skills:axiom-audit-accessibility`, `anthropic-skills:axiom-audit-liquid-glass`,
`anthropic-skills:axiom-audit-swiftui-architecture`, `anthropic-skills:axiom-audit-swiftui-layout`,
`anthropic-skills:axiom-audit-concurrency`, `anthropic-skills:axiom-audit-memory`,
`design:design-critique`, `design:accessibility-review`, `design:ux-copy`.
**Depende de:** S4.2 (e S4.1). **Live check:** não.

1. Rodar cada auditoria sobre `App/` e `Features/`. Produzir
   `docs/plans/F7-AUDIT.md` com os achados (severidade, arquivo:linha, correção proposta).
2. Corrigir **só** os achados de severidade alta/média que caibam em ≤ 30 linhas cada.
   O resto fica listado como backlog nesse arquivo.
3. Checklist manual (preview + leitura):
   - todo botão só com ícone tem `.help` e label de acessibilidade;
   - nenhum texto com cor fixa que quebre no dark mode;
   - `.monospacedDigit()` em todos os números que mudam;
   - nenhum `.frame(width:)` fixo que corte texto em pt-BR (+30% de largura);
   - estados vazios/erro em todas as telas;
   - nenhum `Task {}` sem cancelamento em view que some (prefira `.task`).

**Aceitação:** `F7-AUDIT.md` existe; build verde; testes verdes.

---

### S4.4 — Localização pt-BR (opcional; pergunte ao mantenedor, decisão 2.1-1)

**Skills:** `axiom-integration` (localização), `axiom-xcode-mcp` (ferramentas `StringCatalog*`, `LocalizationPlanner`).

1. Criar `Localizable.xcstrings` (inglês base) com `LocalizationPlanner`/`StringCatalogEdit`.
2. `UserFacingError` e `DriveFormatting` passam a usar `String(localized:)`.
   **Os testes que checam substrings em inglês precisam continuar passando**
   (rode com locale `en`).
3. Traduzir tudo para pt-BR (termos: "My Files" → "Meus arquivos", "Move to Trash" →
   "Mover para a Lixeira", "Transfers" → "Transferências", "Sign Out" → "Sair").

---

### S5.1 — Documentação para o público

**Skills:** `domain-modeling` (ADR), `design:ux-copy`.
**Depende de:** S3.2 (pode rodar ⟂ com S4.x).

1. `README.md` reescrito **em inglês**, voltado a quem usa o app: o que é (1 parágrafo),
   screenshot (placeholder `docs/images/main-window.png`, que o humano captura),
   features, status alpha, requisitos (macOS 26), instalação/compilação, modelo de
   segurança (sessão só em memória, sem Keychain, o que fica em disco: só a fila de
   upload, sem segredos), limitações conhecidas (backlog B1–B4), disclaimer 6.6,
   contribuir, licença.
2. Mover **sem editar** o conteúdo histórico ("Status", detalhes F2–F6, bateria
   live) para `docs/DEVLOG.md`, com data.
3. `docs/ROADMAP.md`: marcar F0–F6 com o estado real e adicionar "F7 — Native UI"
   apontando para este plano.
4. `docs/ARCHITECTURE.md`: árvore real (5.1), `NodeKeyResolver`, `DriveListing`,
   fila em JSON (não SwiftData), `AppSession`.
5. `docs/DECISIONS/ADR-003-sdk-status-2026-10.md`: estado do SDK (1.3), a orientação
   "use the SDK" e por que seguimos nativos (Swift inexistente), mitigações (header
   honesto, eventos no backlog, sem travessias frequentes), gatilho de reavaliação.
6. `CONTRIBUTING.md` (decisão 2.1-2): inglês, com "Maintainer setup" separado.
7. `SECURITY.md`: revisar e incluir o logout (`DELETE /auth/v4`) e a zeragem no sign-out.

---

### S5.2 — Auditoria de segurança e preparação de release

**Skills:** `anthropic-skills:axiom-scan-security-privacy`, `axiom-security`, `axiom-shipping`, `axiom-macos` (distribuição/notarização).
**Depende de:** S5.1.

1. Rodar o scan; corrigir achados reais; listar falsos positivos no relatório.
2. Greps obrigatórios (todos devem vir vazios ou justificados):
   `print(`, `NSLog`, `UserDefaults` (fora de `maxConcurrentUploads`), `password` em
   strings interpoladas, `accessToken` em interpolação, `rclone@`, `/tmp/`, `yourcompany`.
3. Entitlements: só `app-sandbox`, `network.client`, `files.user-selected.read-write`.
   Confirmar `ENABLE_HARDENED_RUNTIME = YES` no Release (adicionar se faltar).
4. Build **Release** via MCP; listar o conteúdo do `.app` (sem arquivos inesperados).
5. Escrever `docs/RELEASE-CHECKLIST.md` (assinatura Developer ID, notarização,
   `shasum -a 256` do zip, tag `v0.1.0-alpha`, notas). **Não** assinar, notarizar,
   taguear nem publicar: isso é do humano.

---

### S5.3 — Ícone do app [HUMANO, com apoio]

O ícone é decisão de design do mantenedor. Formato recomendado: **Icon Composer
(`.icon`)** do Xcode 26, que dá o visual Liquid Glass. O agente só pode: conectar o
arquivo entregue ao target, conferir `ASSETCATALOG_COMPILER_APPICON_NAME` e o
preview. Sugestão de conceito (sem marca da Proton): duas setas opostas
(↑↓) estilizadas como uma partícula/órbita neutra.

---

## 8. Checklist de verificação live (humano)

Faça com o app rodando a partir do Xcode, **um login por bateria**, e espere ~11 min
antes de um novo login.

- [ ] **Bateria A** (depois da S0.2 + S0.3): login, email no cabeçalho, download de 1 arquivo (header honesto), Sign Out.
- [ ] **Bateria B** (depois da S2.3): navegar 3 níveis, nomes corretos, download multi + pasta, New Folder (+ duplicado), Move to Trash (conferir na web).
- [ ] **Bateria C** (depois da S3.2): drop de pasta numa subpasta (estrutura igual na web), Upload Files…, refresh automático, pause/resume/cancel, Show in Finder, Photos bloqueado.
- [ ] **Bateria D** (depois da S4.1/S4.2): login com o gerenciador de senhas, senha errada, 2FA (se houver), atalhos de menu, Settings → simultaneous uploads.

---

## 9. Backlog (fora da F7; registrar como issues)

| # | Item | Nota |
|---|------|------|
| B1 | Upload em streaming por bloco (sem carregar o arquivo inteiro) + progresso por bloco | Necessário para o critério F4 de "1 GB" |
| B2 | Tamanho e data reais via XAttr (`Common.Size`, `ModificationTime`) | Precisa desbloquear o node de cada arquivo; fazer em lote, no actor |
| B3 | Sync por eventos (`/drive/volumes/{id}/events` ou equivalente no SDK) para invalidar o cache | Exigência das regras de terceiros; substitui recargas manuais |
| B4 | Tela de lixeira + restaurar/excluir definitivamente | Conferir endpoints no SDK C# |
| B5 | Renomear | Recriptografar nome + hash; conferir no SDK |
| B6 | "Shared" / "Shared with me" | Fora do MVP original |
| B7 | Nomes reais dos computadores (endpoint de devices) | Conferir no SDK |
| B8 | Quick Look (baixar para temp em memória/sandbox e abrir) | |
| B9 | Arrastar arquivos **do** app para o Finder (file promises) | |
| B10 | Drop numa linha de pasta da tabela = upload para essa pasta | |
| B11 | UI para HV 9001 | Hoje só mensagem |
| B12 | Fila vinculada à conta (jobs de outra conta após logout) | Hoje falham com erro |
| B13 | Grade de miniaturas para Photos | |

---

## 10. Template de relatório (todo subagente devolve isto)

```markdown
## Slice <id> — <título>
**Status:** done | partial | blocked
**Skills loaded:** <lista; marque as que não existiam>
**Files created:** …
**Files modified:** …
**Files deleted:** …
**Build (BuildProject):** green | red — new warnings: <n>
**Tests (`rtk swift test`):** <passed>/<total> — <cole as 3 últimas linhas>
**Previews checked (light/dark):** …
**Acceptance criteria:**
- [x] …
- [ ] … (por quê)
**Live checks for human:** …
**Deviations from the plan (and why):** …
**Endpoints added (with source file/function):** …
**Open questions:** …
```
