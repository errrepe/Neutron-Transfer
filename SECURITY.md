# SECURITY — Neutron Transfer

## Reportar vulnerabilidade

- Abra issue privada / contato do mantenedor (a definir no repo). Não abra issue pública com PoC explorável antes de correção.
- Inclua: versão (`0.1.0-alpha` + commit), macOS, passos mínimos, impacto, logs redatados.
- SLA best-effort alpha: triagem em até 7 dias. Sem bug bounty nesta fase.

## O que nunca fazer

- Nunca commitar credenciais, tokens, `otp_secret`, chaves privadas, exports Keychain.
- Nunca colar `AccessToken` / `RefreshToken` / `clientProof` / session keys em issues, logs, screenshots.
- Nunca logar password, SRP secrets (`S`, `K`, `M1`), chaves desembrulhadas. Logs só com IDs e prefixos truncados.

## Como guardamos segredos

- Keychain (`kSecClassGenericPassword`, `kSecAccessibleAfterFirstUnlockThisDeviceOnly`) para refresh tokens e keys. Nada em UserDefaults / SwiftData / plist.
- `AccessToken` só em memória (`SessionManager` actor), refresh single-flight com expiração `expiresIn - 60s`.
- Bookmark security-scoped para pastas de upload/download — sem paths absolutos sensíveis em logs.

## Telemetria

- Nenhuma telemetria. Zero analytics, zero crash reporter third-party no MVP.
- Sem envio de dados para fora além das chamadas oficiais à API Proton Drive com header `x-pm-appversion: external-drive-neutron_transfer@0.1.0-alpha`.

## Superfície relevante

- SRP-6a nativo, unlock User→Address→Share→Node→Session, AES-CFB + SHA256 + MDC por bloco.
- Migração cripto quebrante fim 2026 / início 2027: entradas Keychain versionadas (`v1.`), `BlockFormatVersion` isolado para rotação limpa.
- HV 9001: pausa fila, nunca bypass automatizado.
