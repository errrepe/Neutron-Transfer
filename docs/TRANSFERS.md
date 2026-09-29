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

- Para cada diretório em ordem topológica: `POST /drive/v4/nodes (parentID, name, type=folder)` criptografando nome com Node key do pai.
- Memoiza `relativePath → nodeID` em memória + persiste no `TransferJob` para retry idempotente.
- Conflito de nome: sufixo ` (1)`, ` (2)` — nunca sobrescreve silenciosamente.

### 1.4 Chunking + encrypt + upload

- Tamanho de bloco versionado (`BlockFormatVersion`), default a definir no spike F4 (ex.: 4 MiB).
- Por arquivo:
  1. `GET upload session` / `POST draft` para obter `uploadURL` + session key.
  2. Split → AES-CFB encrypt por bloco → SHA256 por bloco + MDC final.
  3. `PUT` blocos em ordem ou paralelo limitado (dentro do limite global 4–8).
  4. `POST commit` com lista de hashes. Servidor verifica.
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
