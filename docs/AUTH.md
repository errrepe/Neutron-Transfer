# AUTH — SRP, 2FA, Session, Keychain

> Endpoints oficiais apenas. Header obrigatório: `x-pm-appversion: external-drive-neutron_transfer@0.1.0-alpha`.

## 1. Fluxo completo

```
1. POST /auth/v4/info { Username }
   → { Version, Modulus (hex), ServerEphemeral (hex), Salt, SRPSession }

2. SRP-6a local:
   clientEphemeral (A), clientProof (M1) = H(A, B, S)
   usando password + salt + modulus

3. POST /auth { Username, ClientEphemeral, ClientProof, SRPSession }
   → 200 { AccessToken, RefreshToken, UID, ExpiresIn, Scope }
   → 422 com 2FA required → passo 4
   → 400/401 → erro auth (ver §5)
   → 9001 → Human Verification exigida

4. (se 2FA) POST /auth/v4/2fa { TwoFactorCode, SRPSession }
   → 200 tokens como acima
   Suporta TOTP (6 dígitos). `otp_secret` para setup não é usado no MVP
   além de exibir instrução se conta exigir enrollment (fora de escopo).

5. Unlock hierarchy (F3b-1 implementado para user keys):
   a. `GET /core/v4/keys/salts` (só com escopo de password, logo após login)
      → salt da primary user key.
   b. `saltedKeyPass = bcrypt(keyPass, dotSlash(keySalt))[-31:]`
      (semântica rclone `SaltForKey`; NUNCA a senha crua — validado: pgpy
      independente também rejeita a senha crua). Persiste em Keychain junto
      à sessão (password-equivalent); seeds destravadas ficam SÓ em memória
      (`KeyringCache` actor, `lock()` limpa).
   c. `GET /core/v4/users` → user keys armored → parse pacotes → S2K iterado
      + AES-CFB puro a partir do IV (SEM prefixo random nessas chaves Proton:
      secretData é exatamente MPI + SHA-1 — verificado por hexdump) →
      seed verificada contra a pública (Ed25519 direto; X25519 com bytes
      reversos BE→LE). `GET /core/v4/addresses` → address keys (Token, F3b-2).
   d. Pendente (F3b-2/3): Token→address, Passphrase→share, NodePassphrase→node,
      decrypt de nomes (PKESK ECDH + SED) e detached-sig verify.
   e. Rate limit: logins repetidos retornam `2028 Too many recent logins`.
      Nunca retry em loop no `/auth/v4`; backoff + reutilizar sessão Keychain.

6. Persist:
   Keychain: refreshToken, addressKeys, shareKeys (kSecClassGenericPassword,
   accessGroup app, `kSecAccessibleAfterFirstUnlock`, biometric se disponível)
   Memória (actor): accessToken + expiry.

7. Refresh:
   POST /auth/v4/refresh { RefreshToken, UID }
   → novos Access+Refresh (rotativo). Single-flight no SessionManager.
   Agenda refresh em `expiresIn - 60s`.

8. Logout / revoke:
   POST /auth/v4/logout. Apaga Keychain + SwiftData session + memória.
```

## 2. SRP-6a detalhe

- Implementação nativa Swift, sem binding incubating.
- BigInt: `Core/Crypto/BigUInt.swift` próprio, limbs de 32-bit (toda intermediação
  cabe em `UInt64`, sem carry/borrow wrap). Wire little-endian igual a go-srp.
  Verificado contra Python: mul exato, `pow(a,3,2^256-1)` exato, consistência `q·m+r==d`.
- Hash: `expandHash = SHA512(d||0)||SHA512(d||1)||SHA512(d||2)||SHA512(d||3)` (256 bytes),
  `M1 = expand(A||B||S)`, `M2 = expand(A||M1||S)` verificado do servidor, gerador sempre 2, 2048-bit.
- Password v3/v4: `bcrypt($2y$10$, dotSlashBase64(salt+"proton"))` + expand. Bcrypt vendored
  (`Core/Crypto/BCrypt/`, motor EksBlowfish próprio + tabelas Blowfish MIT de
  vapor-community/bcrypt, ver `docs/VENDORED.md`). Semântica idêntica ao fork
  ProtonMail/bcrypt (primeiros 22 chars do salt, eco no output). Validado contra
  bcrypt de referência (Python): 3 vetores incluindo senha UTF-8.
- Modulus PGP-clearsign: envelope parseado (`ModulusDecoder`); verificação da assinatura
  GATADA para F2c (GopenPGP bridge). Transporte é TLS.
- **Login real verificado em 2026-09-29** contra `neutrontransfertest@proton.me`:
  info → hash → proofs → `/auth/v4` → serverProof OK → UID recebido. Credenciais
  usadas só em memória, nunca commitadas.
- Perf conhecido: ~6s por modPow 2048-bit em debug (≈20s por login). Release é
  ~5-10x mais rápido. Otimizar (Montgomery/janela deslizante) só se virar gargalo real.
- Nunca logar `password`, `S`, `K`, `M1`, salt raw. Logs só com prefixos truncados para debug local opt-in.
- Vetores de referência: `go-proton-api` (SRP), `rclone` backend protondrive.

## 3. 2FA

- `POST /auth/v4/2fa` com `{ TwoFactorCode: "123456" }`.
- TOTP de 30s — validar skew de relógio via NTP antes de acusar código inválido.
- Erros comuns: `8002` (código inválido/expirado), `8101` (muitas tentativas → backoff).
- Fora de escopo MVP: FIDO2 / hardware key enrollment. Mensagem clara se conta exigir.

## 4. Keychain

- Serviço implementado: `dev.neutron.transfer.session`, conta `proton-session`
  (`Core/Security/KeychainStore.swift`, JSON `ProtonSession{uid,accessToken,refreshToken}`).
  (Doc original previa `com.neutron.transfer.session` + contas por chave — convergir em F3.)
- Nunca em UserDefaults, SwiftData, plist, logs, crash reports.
- Acesso: `kSecAccessibleAfterFirstUnlockThisDeviceOnly` por padrão.
- Migração cripto 2026/2027: versionar entradas (`v1.` prefix) para re-unlock limpo.

## 5. Erros comuns

| Código / HTTP | Significado | Ação |
|---|---|---|
| 400 Bad Request | payload SRP inválido | re-gerar A/M1, checar hex padding |
| 401 Unauthorized | proof errado / senha errada | não retry cego, pedir senha |
| 422 2FA required | falta TOTP | pedir código, POST /auth/v4/2fa |
| 8002 | TOTP inválido | checar NTP skew, pedir novo código |
| 9001 HV required | Human Verification | pausar fila, abrir fluxo HV, retry após |
| 429 | rate limit | backoff exponencial + jitter, reduzir paralelismo |
| 500/502/503 | transitório servidor | retry limitado, surface após N tentativas |

## 6. NTP / Clock skew

- Antes de SRP e TOTP, faz `HEAD` ou lê `Date` header da resposta `/auth/v4/info`.
- Se `abs(serverDate - localDate) > 60s`, avisa usuário e ajusta cálculo TOTP / expiração.
- Não altera relógio do sistema, só corrige lógica de expiração local.

## 7. Referências de implementação

- `go-proton-api` — fluxo SRP + unlock hierarchy (Go, leitura obrigatória).
- `rclone` backend `protondrive` — chunking + retry + mapeamento de erros.
- SDK oficial `ProtonDriveApps/sdk` — apenas `Client` como referência de endpoints; auth/session/address provider NÃO vêm do SDK e devem ser implementados aqui.
- `sdk-swift` (binding C# → Swift, 2 commits, instável) — explicitamente NÃO usado (ver `SDK-STRATEGY.md`).

## 8. Segurança

- Zero telemetria de credenciais. Nenhum log com tokens/keys.
- `AccessToken` só em memória (`SessionManager` actor).
- `RefreshToken` só em Keychain.
- Veja `SECURITY.md`.
