# SDK-STRATEGY — Por que Swift nativo

## 1. Estado do SDK oficial (pesquisado)

- Repo: `ProtonDriveApps/sdk`.
- Módulos: `Client` pronto; `Sync` / `Search` coming soon.
- Linguagens nativas: TypeScript + C#. Swift é **binding incubating** que embrulha o C# (`sdk-swift`, 2 commits, instável).
- O SDK **NÃO** inclui auth / login / session / address provider. Mesmo adotando o SDK, login SRP, unlock de keys e gestão de sessão teriam que ser implementados à parte.

## 2. Por que não usar o binding Swift incubating

1. **Instabilidade:** 2 commits, API churn, sem garantia semântica. Acoplar o MVP a isso é acoplamento a moving target.
2. **Custo FFI:** embrulho C# → Swift via interop adiciona camadas de falha (marshalling de keys, threads, crypto) exatamente onde precisamos de auditabilidade.
3. **Debug opaco:** falha cripto através de binding é quase indepurável sem símbolos das duas pilhas.
4. **Migração quebrante 2026/2027:** se o formato cripto muda, depender de binding atrasa a adaptação (espera upstream). Nativo permite trocar `BlockCrypto` / `KeyHierarchy` isoladamente.

Decisão registrada em `docs/DECISIONS/ADR-001-nativo-swift.md`.

## 3. O que espelhar do SDK para não ser rate-limited / banido

Mesmo nativo, comportamento de rede deve ser indistinguível de um bom cidadão SDK:

- **Endpoints oficiais apenas.** Nenhum host alternativo, nenhum scraping.
- **Header obrigatório:** `x-pm-appversion: external-drive-nucleon_transfer@0.1.0-alpha` em toda chamada.
- **Event-based sync:** usar canal de eventos para invalidar listing; proibido polling curto.
- **Paralelismo limitado:** 4–8 slots globais, backoff exponencial + jitter, respeitar `Retry-After` e `429`.
- **Idempotência:** memoizar `path → nodeID`, commit com hashes, resume por bloco — evita duplicar objetos no retry.
- **User-Agent honesto:** identifica third-party alpha, nunca se passa por app oficial.
- **HV 9001:** ao receber, pausa e surface — nunca tenta bypass automatizado.
- **Sem branding:** sem logos, sem nome Proton no UI além de rótulo factual de interoperabilidade + disclaimer third-party.

## 4. Quando reavaliar

- Se `sdk-swift` estabilizar (tags semânticas, CI, vetores SRP/crypto públicos) **e** `Sync`/`Search` forem lançados, reavaliar adoção parcial (ex.: só `Client` para listing) mantendo SRP + crypto nativos.
- Critério: trocar só se reduzir código sem perder auditabilidade cripto nem controle de fila.
- Reavaliação registrada como novo ADR, nunca troca silenciosa.

## 5. Referências de leitura (não dependências)

- `ProtonDriveApps/sdk` — referência de endpoints `Client`.
- `go-proton-api` — referência SRP + unlock.
- `rclone` protondrive — referência chunking + retry.
