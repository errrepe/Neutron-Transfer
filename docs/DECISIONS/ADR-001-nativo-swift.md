# ADR-001 — Swift nativo com SRP próprio (sem binding SDK incubating)

> **2026-10-03** — o app foi renomeado para **Nucleon Transfer**; este documento usa o nome antigo por ser registro histórico.

- Status: Accepted
- Data: 2026-09-29
- Contexto: SDK oficial `ProtonDriveApps/sdk` tem `Client` pronto, `Sync`/`Search` coming soon. Swift é binding incubating que embrulha C# (`sdk-swift`, 2 commits, instável). SDK não inclui auth/login/session/address provider. Migração cripto quebrante prevista fim 2026 / início 2027.

## Decisão

Implementar cliente macOS em Swift 6 nativo, incluindo SRP-6a próprio, `KeyHierarchy` e `BlockCrypto` isolados por protocolo. Não adotar `sdk-swift` no MVP.

## Alternativas consideradas

1. **Binding incubating (`sdk-swift`):** descartado — instável, FFI opaco para crypto, atrasa adaptação à migração 2026/2027.
2. **Portar SDK C#/TS para Swift:** descartado — custo alto, diverge do upstream sem ganho.
3. **WebView / Electron:** descartado — viola requisito nativo macOS.

## Consequências

- Positivas: auditabilidade cripto, controle de fila/paralelismo, troca isolada na migração, sem dependência instável.
- Negativas: reimplementar SRP + unlock (mitigado com vetores `go-proton-api`/`rclone` + spike F2).
- Obrigações: endpoints oficiais apenas, header `x-pm-appversion: external-drive-neutron_transfer@0.1.0-alpha`, event-based sync, sem logos, disclaimer third-party.

## Reavaliação

Se `sdk-swift` estabilizar com tags + `Sync`/`Search` lançados, reavaliar adoção parcial via novo ADR.
