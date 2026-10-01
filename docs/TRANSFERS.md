# TRANSFERS — Upload / Download / Fila

> MVP completo com fila persistente. Concorrência limitada 4–8 via TaskGroup.

## 1. Upload — drag-and-drop

### 1.1 Entrada

- SwiftUI `.onDrop(of: [.fileURL], ...)` → `[NSItemProvider]`.
- Cada provider com `hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)` → `loadItem(forTypeIdentifier:options:)` → `URL` (security-scoped, chamar `startAccessingSecurityScopedResource()`).
- Suporta arquivos + pastas. Preserva estrutura relativa ao ponto de drop.

### 1.2 Enumeração recursiva

- `FileManager.enumerator(at:includingPropertiesForKeys:[.isDirectoryKey,.fileSizeKey,.isSymbolicLinkKey], options:[.skipsHiddenFiles])`.
- Resolve symlinks: segue se dentro da árvore, ignora / registra se apontar para fora (evita loop / leak).
- Coleta: `[(localURL, relativePath, isDirectory, size)]`.
- Ordenação topológica: diretórios por profundidade crescente (pais antes das filhas).

### 1.3 Criação de pastas remotas

- Para cada diretório em ordem topológica: `POST /drive/shares/{shareID}/folders`
  (`ParentLinkID`, `Name`, `Hash`, `NodeKey`, `NodeHashKey`, `NodePassphrase`,
  `NodePassphraseSignature`, `SignatureAddress` — exatamente 8 campos, SEM
  `XAttr`; verificado live 2026-09-30: pasta `NT-F42-*` criada, nome/HMAC
  lidos de volta com nosso código).
  Por pasta: gera keypair novo via `FolderCreate`/`NodeKeyGen` — chave
  TRANSFERÍVEL completa (primária tag 5 + UID `Drive key
  <noreply@protonmail.com>` tag 13 + auto-certificação tag 2 tipo 0x13 +
  subkey tag 7 + binding tag 2 tipo 0x18; blobs nus 5+7 são rejeitados com
  200501); nome cifrado com a Node key do pai + assinatura inline da address
  key (`MessageEncrypt.encryptSigned`); `Hash` = HMAC-SHA256 hex com a
  `NodeHashKey` do pai **decodificada de base64** (`NameHash`); `NodePassphrase`
  cifrada para o pai + assinatura detached da address key (`DetachedSign`).
- Convenções de assinatura live-verificadas (rclone-capturado): hash SHA-256
  (8, não SHA-512), salt `salt@notations.openpgpjs.org` de 16 bytes frescos
  por assinatura, creation-time crítica (0x82), issuer-fingerprint (0x21),
  OPS `nested=0x01` (quirk oficial), literais com data real. Sem o set de
  notation o servidor rejeita (200501).
- `SignatureAddress` = email do criador (validado; ID rejeita com 2501).
  Pastas NÃO carregam `XAttr` (ausente nas pastas oficiais).
  Share tipo Photo rejeita criação (2511) — criar só em shares Drive.
- Memoiza `relativePath → nodeID` em memória + persiste no `TransferJob` para retry idempotente.
- Conflito de nome: sufixo ` (1)`, ` (2)` — nunca sobrescreve silenciosamente.

### 1.4 Chunking + encrypt + upload

- Tamanho de bloco versionado (`BlockFormatVersion`), default 4 MiB
  (`FileUpload.defaultBlockSize`, parâmetro em toda chamada).
- Por arquivo (F4.3, sem fila/UI — capturado do rclone, `FileUpload` +
  `DriveClient.uploadFile`):
  1. `POST .../links/{parent}/checkAvailableHashes {Hashes:[nameHashHex]}`
     (duplicate-name probe; rclone chama 2x idêntico — quirk, chamamos 1x).
  2. `POST .../shares/{id}/files` (draft, 10 campos: envelope pasta SEM
     `NodeHashKey` + `MIMEType` + `ContentKeyPacket`/`ContentKeyPacketSignature`
     no lugar; SEM `XAttr`) → `{File:{ID, RevisionID}}`.
  3. `POST /drive/blocks {AddressID, ShareID, LinkID, RevisionID, BlockList}`
     → `{UploadLinks:[{BareURL, Token, URL, Index}]}` (host de storage vem do
     `BareURL` em runtime, nunca hardcoded).
  4. `POST {BareURL}/storage/blocks` multipart (`Block`/`blob`,
     `application/octet-stream`, header `Pm-Storage-Token`) com os bytes do
     bloco cifrado.
  5. `PUT .../files/{linkID}/revisions/{revID} {ManifestSignature,
     SignatureAddress, XAttr}` → Code 1000.
- Semântica cripto verificada por decodificação dos blobs (detalhes em
  `Core/ProtonAPI/FileUpload.swift`): `ContentKeyPacket` = PKESK nu (96B,
  base64 sem armor) da chave de sessão de 32B para a subkey #18 do próprio
  node, auto-assinado pelo node; bloco = pacote SED tag-18 cru (chave de
  conteúdo, literal `""`), `Size` = tamanho cifrado (26B → 77B), `Hash` =
  base64(SHA-256 do bloco em claro, 44ch); `EncSignature` = literal sem
  assinatura da detached da hash do bloco (address key) cifrada para o node;
  `ManifestSignature` = address key sobre a concatenação das hashes cruas em
  ordem; `XAttr` = JSON `Common.{ModificationTime,Size,MIMEType,BlockSizes}`
  cifrado+assinado pelo node. VARIANT-UNCERTAIN (a confirmar live):
  entrada exata da manifest (raw vs base64-ascii), signatário do EncSignature
  (address vs node), schema exato do XAttr, `Hash` do bloco (claro vs cifrado).
- Arquivo 0 bytes: draft + commit direto (sem sessão de blocos, manifesto vazio).
- Falha de bloco: retry com backoff+jitter (ver §3), não reinicia arquivo inteiro se manifesto parcial existe.

### 1.5 Paralelismo

- `TaskGroup` global com `maxConcurrent = 4...8`.
- Cada arquivo ocupa 1 slot; blocos do mesmo arquivo podem usar sub-paralelismo sem exceder o teto global.
- Reduz para 2 em `429` / `5xx` consecutivos; restaura após janela limpa.

## 2. Download — pasta escolhida

### 2.1 Entrada

- `NSOpenPanel(directoryURL:canChooseFiles:false, canChooseDirectories:true, canCreateDirectories:true, prompt:"Choose destination")`.
- Destino `URL` com security-scoped bookmark persistido no job (para resume após relaunch).

### 2.2 Espelho da árvore

- Lista recursiva remota (`GET /drive/v4/nodes/{id}/children` + eventos) → constrói árvore.
- Cria diretórios locais primeiro (`FileManager.createDirectory(withIntermediateDirectories:true)`).
- Escreve via arquivo temporário `*.neutron-part` → `rename` atômico ao verificar.

### 2.3 Fetch + decrypt + verify

- Por arquivo: fetch session key → `GET` blocos em paralelo limitado → AES-CFB decrypt → SHA256 por bloco + MDC final.
- Mismatch: descarta bloco, retry; após N falhas marca job `failed` com `hashMismatch`.
- Preserva `mtime` se API fornecer.

## 3. Retry — backoff + jitter

```
delay = min(cap, base * 2^attempt) + random(0, jitter)
base = 1s, cap = 60s, jitter = 0..1s
retryable: timeout, 429, 500/502/503/504
non-retryable: 400, 401 (sem refresh), 403, 404, 422 (sem 2FA), HV 9001 (pausa)
maxAttempts por bloco = 5, por job = persistente com contador
```

- 429: respeita `Retry-After` se presente.
- HV 9001: pausa fila inteira, surface UI, resume manual.

## 4. Progresso / Pausa / Cancela / Retry

- `TransferJob`: `bytesTotal`, `bytesDone` atualizados por bloco (throttle UI 100ms).
- Pausa: flag persistida, Task atual termina bloco e suspende (não aborta bytes já enviados).
- Cancela: cancela Tasks, remove `.part`, marca `cancelled`, limpa draft remoto se API permitir.
- Retry manual: reseta `failed` → `queued`, mantém blocos completos (resume).
- Fila observável via SwiftData `@Query` + view-model `@Observable`.

## 5. Persistência

- SwiftData `TransferJob` + `TransferBlock` (ver `ARCHITECTURE.md` §8).
- Bookmark security-scoped do destino (download) e da origem (upload) para sobreviver a relaunch.
- Crash-safe: escreve estado após cada bloco commitado.

## 6. Edge cases

- Arquivo 0 bytes: cria node vazio, sem blocos.
- Nome com emoji / NFD vs NFC: normaliza NFC antes de comparar.
- Drop com 10k+ arquivos: paginação da coleta, sem bloquear main thread (`Task.detached` + progressivo).
- Disco cheio: pré-checa espaço (`URLResourceValues.volumeAvailableCapacity`), falha elegante antes de baixar.
- Rede cai: jobs `running` → `queued` no relaunch, resume de blocos.

## 7. F4.4 — fila de upload + UI drag-drop (implementado 2026-10-01, offline)

Arquivos: `Core/Transfers/TransferQueue.swift` (ator + `TransferFailure` +
`TransferRetryPolicy` + protocolos `TransferUploader`/`RemoteFolderCreator`),
`Core/Transfers/LocalTreeScan.swift` (coleta recursiva),
`Core/Transfers/DriveUploadAdapter.swift` (ponte live),
`Features/Transfers/TransferQueueView{,Model}.swift` (aba Uploads),
`NeutronTransferTests/TransferQueueTests.swift` (18 testes; suite 59/59 via
`/tmp/nt-tests` + `swift test`; build Xcode verde, scheme `NeutronTransfer`,
DerivedData externo).

- Job: arquivo local → share/parent, estados
  queued/uploading/paused/done/failed/cancelled, `bytesTotal/Done`,
  `attempt` persistente, `maxAttempts` (default 5), `remoteLinkID` no sucesso.
- Persistência = snapshot JSON atômico em
  `Application Support/NeutronTransfer/transfer-queue.json` (NÃO SwiftData:
  um ator dono de um snapshot `Codable` tem menos modos de falha que um grafo
  `@Model` + `ModelContext`; só paths/IDs/progresso, NUNCA segredos —
  verificado por teste `snapshotHoldsNoSecrets`). `uploading` → `queued` no load.
- Concorrência: 3 uploads simultâneos, sequencial por job (caminho verificado
  `DriveClient.uploadFile`; blocos paralelos por job ficam diferidos, §1.5).
  Backoff em-slot: `min(60s, 1s·2^(n-1)) + jitter 0..1s`, `sleeper` injetável.
  Classificação: 429/5xx + `URLError` transitório → retry; resto permanente;
  desconhecido = permanente (retry é opt-in); HV 9001 → `pauseAll()`.
- Recursivo: `LocalTreeScan.collect` (relativos NFC estruturais — nunca strip
  de prefixo absoluto: FileManager canoniza `/tmp` → `/private/tmp`;
  symlinks seguidos só dentro da árvore, fora ignora+conta, loops por visited
  set, hidden skip) → `enqueueTree` cria pastas pai→filho via `ensureFolder`
  (memo por path relativo) e enfileira arquivos com `parentLinkID` resolvido.
- Adapter live: resolve keyrings por share raiz (`unlockShare`/`unlockNode` +
  `NodeHashKey` base64→32B, cache em memória), carrega bytes do disco,
  `uploadFile` + `progress(total)` no fim (granularidade por arquivo em F4.4;
  progresso por bloco é refactor futuro). `ensureFolder` tenta
  `nome`, `nome (1)`, `nome (2)` em erro `.api` (código exato de duplicata
  ainda VARIANT — confirma live em F4.5). Memo de pastas por sessão:
  jobs com parent de sessão anterior falham permanente com "re-add"
  (persistir `relativePath → nodeID` no job é F4.5, cf. §1.3).
- UI: aba Uploads (Browse | Uploads) com Picker de share destino (raiz do
  share), `NSOpenPanel` (arquivos+pastas, multi) + `.onDrop(of: [.fileURL])`,
  bookmarks security-scoped best-effort por arquivo, linhas com
  progresso/estado/pausar/retomar/cancelar/relaçar/remover + "Retry all failed".
- Retry F4.4 recomeça o ARQUIVO inteiro (sem resume de manifesto parcial —
  difere do aspirado em §1.4; resume de blocos é follow-up).

## 8. F5 — download de arquivos/pastas (implementado 2026-10-01, offline + rclone-capturado)

Arquivos: `Core/Transfers/FileDownload.swift` (núcleo puro: verify hash +
reassemble + destino + escrita atômica), `Core/Transfers/DriveDownloadAdapter.swift`
(ponte live: keyrings em memória, blocos paralelos, recursivo),
`Core/ProtonAPI/DriveClient.swift` (`listRevisions`/`getRevision`/`downloadBlockBytes`),
`Core/ProtonAPI/APIClient.swift` (`downloadRawBlock{,URL}` — octet-stream, sem envelope),
`Core/ProtonAPI/DriveModels.swift` (`RevisionBlock/Detail/Summary`),
`Core/ProtonAPI/AppVersion.swift` (`storageHeaderValue`),
`Features/Browser/DriveBrowserView{,Model}.swift` (botão Download por linha + progresso),
`NeutronTransferTests/FileDownloadTests.swift` (9 testes; suite 68/68 via
`/tmp/nt-tests` + `swift test` — 59 anteriores intactos; build Xcode verde,
scheme `NeutronTransfer`, DerivedData externo).

- Descoberta (0 logins SRP frescos — token em cache de 23:55 reutilizado):
  `rclone --config /tmp/rclone-nt.conf cat "nt:NT-F43-FIXTURE.txt" --dump bodies`
  (`/tmp/f5ref/rclone-download.log` + redacted). Fluxo: `GET .../links/{fileID}`
  → `FileProperties.ContentKeyPacket` (b64 sem armor) + `ActiveRevision.ID` →
  `GET .../files/{id}/revisions` → `GET .../revisions/{revID}` →
  `Revision.Blocks[]={Index, Hash (b64 SHA-256 dos bytes CIFRADOS), Token (JWT
  curto), URL (token em-path), BareURL (host storage runtime), EncSignature}` →
  `GET {BareURL}` no host storage (`Pm-Storage-Token: Token`, Bearer + X-Pm-Uid,
  `x-pm-appversion: external-drive-rclone@1.75.1-stable`) → octet-stream do
  pacote SED tag-18 (77B p/ fixture 26B). Hash PROVADO = sha256(storage bytes),
  não plaintext (fixture Hash f854… ≠ sha256(plaintext) 0532…) — corrige o
  aspirado em §1.4/§2.3 que dizia "SHA-256 por bloco" ambíguo/claro.
- Download por arquivo: `unlockNode` (parent + address signers) →
  `FileUpload.openContentKey` (node candidates; cipher 7/8/9 aceito) →
  revision (activeRevision.ID, fallback última de `listRevisions`) → blocos em
  paralelo limitado (default 4, TaskGroup com janela deslizante) →
  `FileDownload.reassemble` (ordena por Index, checa contiguidade 1-based,
  verifica SHA-256 de CADA bloco antes de decriptar — fail-closed
  `hashMismatch`, `decryptBlock` SED/SEIPDv1 existente) → bytes idênticos.
  Arquivo 0 bytes: sem blocos, retorna `Data()` (paridade upload §1.4).
- Recursivo: `downloadTree` (arquivo → download direto; pasta →
  `listChildren` + `decryptName` com candidates da pasta, cria dirs locais
  primeiro, subpastas antes dos bytes, arquivos da pasta com paralelismo
  limitado default 4). Destino = pasta via `NSOpenPanel` (só diretórios,
  pode criar; `startAccessingSecurityScopedResource` best-effort na sessão,
  sem bookmark persistente — fila de downloads persistente é F6).
  Sobrescrita: `uniqueDestination` (`nome`, `nome (1).ext`, … — paridade
  upload) + escrita atômica `*.neutron-part` → rename (§2.2).
- Decisão de escopo: downloader DEDICADO com progresso próprio (não extensão
  do `TransferQueue` — `TransferJob` é upload-específico: localPath/parentLinkID/
  uploader; adaptar para download balloonaria o ator + persistência; F6 unifica).
- UI (browser): botão "Download" por linha (arquivo e pasta) + `NSOpenPanel`
  destino; progresso por blocos no arquivo (`0/total` + barra) e status por
  arquivo na pasta; estado `downloading`/`downloadProgress`/`downloadStatus`
  no view-model (sem fila persistente em F5).
- Testes offline (9, sem rede): roundtrip single/multi-bloco (incl. ordem
  reversa), vazio, `hashMismatch` fail-closed + base64 ruim, gap de índice,
  chave errada rejeitada, sufixo ` (1)` ext-aware, escrita atômica, regra
  26B→77B + `Hash == sha256(ciphertext)` (paridade fixture live).
