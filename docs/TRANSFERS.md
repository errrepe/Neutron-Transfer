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
