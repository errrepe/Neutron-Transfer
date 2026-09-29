# ARCHITECTURE — Neutron Transfer

> Status: alpha design. Stack: macOS SwiftUI native, Swift 6 strict concurrency.

## 1. Goals

- Upload arbitrário com drag-and-drop preservando estrutura.
- Download para pasta escolhida via seletor do sistema.
- Fila de transfers persistente com progresso / pausa / cancela / retry.
- Interop com Proton Drive via endpoints oficiais apenas.
- Isolamento cripto para sobreviver à migração quebrante fim 2026 / início 2027.

## 2. Layering

```
App/
  NeutronTransferApp.swift      — entry, DI root
  ContentView / Navigation      — shell only, no logic

Features/
  Auth/                         — LoginView, TwoFAView, SessionViewModel
  Browser/                      — Vault/Folder list, navigation
  Transfers/                    — QueueView, TransferRow, pickers, drop target

Core/
  Session/  → SessionManager
  Network/  → DriveClient
  Crypto/   → SRP + KeyHierarchy + BlockCrypto (protocols isolados)
  Upload/   → UploadEngine
  Download/ → DownloadEngine
  Store/    → TransferStore (SwiftData) + KeychainStore
```

Regras:

- `Features` nunca importam `URLSession` diretamente. Só via `DriveClient` / Engines.
- `Core/Crypto` não conhece UI nem rede. Interfaces puras, injetáveis para troca na migração cripto.
- `TransferStore` é a única fonte de verdade da fila.

## 3. SessionManager (actor)

Responsabilidades:

- Guarda `AccessToken`, `RefreshToken`, `UID`, expiração em memória.
- Refresh automático com single-flight (evita N refreshes concorrentes).
- Detecta `401` / token expirado → refresh → retry uma vez.
- Detecta HV `9001` → surface para UI (captcha / verificação humana), pausa fila.
- Corrige clock skew via NTP (comparar `Date` servidor vs local, tolerância configurável).
- Expõe `actor SessionManager: Sendable` com `func validAccessToken() async throws -> String`.

Segredos long-lived (refresh token, address keys, share keys) ficam em Keychain, nunca em SwiftData / UserDefaults / logs.

## 4. DriveClient

- Wrapper fino sobre `URLSession`, `Sendable`, `async/await`.
- Base URL oficial apenas. Sem endpoint custom / scraping.
- Header obrigatório em toda chamada:
  `x-pm-appversion: external-drive-neutron_transfer@0.1.0-alpha`
- Serializa `Codable` requests/responses. Mapeia erros API (`Code`, `Error`, HV) para `DriveError` tipado.
- Recebe `SessionManager` por injeção para auth header.
- Retry de rede (timeout, 5xx, 429) com backoff exponencial + jitter — ver `TRANSFERS.md`.
- Event-based sync: usa endpoint de eventos quando disponível; proibido polling fixo curto.

## 5. Crypto — três blocos isolados

### 5.1 SRP (`SRPClient`)

- SRP-6a puro Swift (BigInt + SHA256 + HMAC).
- Entrada: username, password, `info` de `POST /auth/v4/info` (version, modulus, serverEphemeral, salt).
- Saída: `clientEphemeral`, `clientProof`. Sem atalho, sem lib externa opaca.
- Testável com vetores de `go-proton-api` / `rclone`.

### 5.2 KeyHierarchy (`KeyUnlocker`)

Ordem de unlock:

```
User key (key password / passphrase)
  → Address keys
    → Share keys (vault root)
      → Node keys (file/folder)
        → Session keys (per-block / per-file content key)
```

- Cada nível descriptografa o próximo. Falha em qualquer nível = erro tipado, nunca crash, nunca log de chave.
- Chaves desembrulhadas vivem em memória o mínimo necessário, `SecureBytes` com `memset` no `deinit` onde viável.

### 5.3 BlockCrypto (`BlockEncryptor` / `BlockDecryptor`)

- Upload: split em blocos → AES-CFB encrypt por bloco → SHA256 por bloco + MDC final → upload.
- Download: fetch blocos → decrypt → verify SHA256/MDC → escreve.
- Tamanho de bloco e formato versionados em `struct BlockFormatVersion` para suportar migração 2026/2027 sem reescrever engines.

## 6. UploadEngine

Ver detalhe em `TRANSFERS.md`. Resumo:

- Input: `NSItemProvider` de `onDrop` + `FileManager.enumerator` recursivo.
- Fase 1: coleta + ordenação topológica (pastas-pai antes de filhas).
- Fase 2: cria pastas remotas, memoiza `localPath → nodeID`.
- Fase 3: arquivos em `TaskGroup` limitado (4–8), cada arquivo = chunking + encrypt + upload + commit.
- Reporta progresso por bytes via `AsyncStream` / observation.

## 7. DownloadEngine

- Input: lista de nodes + destino `URL` de `NSOpenPanel` (directory mode).
- Espelha árvore localmente antes de baixar bytes (cria diretórios).
- Blocos em paralelo limitado, decrypt + verify, escrita atômica (`.part` → rename).
- Resume via manifesto de blocos completos se retomado.

## 8. TransferStore (SwiftData + Keychain)

- `TransferJob`: id, type (upload/download), remotePath, localPath, state (queued/running/paused/failed/done), bytesTotal/bytesDone, errorCode, retryCount.
- `TransferBlock`: jobID, index, hash, size, state — permite resume e verify.
- Persistência imediata a cada transição de estado (crash-safe).
- Secrets (tokens, keys) em `KeychainStore`, nunca em SwiftData.

Modelo Swift 6: `@Model actor`-safe, `Sendable` DTOs para UI.

## 9. Concorrência

- `TaskGroup` com `maxConcurrent = 4...8` (adaptativo: reduz em 429/5xx, aumenta em rede idle).
- Cancelamento cooperativo: `Task.checkCancellation()` por bloco.
- Pausa: token por job, não cancela Task — suspende emissão de próximos blocos.
- UI observa via `@Observable` view-models, nunca `Task` em `View.body`.

## 10. Testabilidade

- `DriveClientProtocol`, `SRPClientProtocol`, `KeyUnlockerProtocol`, `BlockCryptoProtocol`, `TransferStoreProtocol` — mocks em testes.
- Spike SRP validado contra vetores reais antes de qualquer UI (ver `ROADMAP.md` F2).
- Nenhum teste integra rede real por padrão; gravações (cassette) se necessário.
