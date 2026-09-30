# VENDORED — código de terceiros dentro do repo

## Blowfish P/S tables + bcrypt IV (`Sources/Core/Crypto/BCrypt/BcryptTables.swift`)

- Origem: `vapor-community/bcrypt`, arquivo `Sources/BCrypt/Keys.swift` (MIT).
- Commit base: clone `--depth 1` em 2026-09-29 (verificar `git log` upstream para pin exato
  antes de release; conteúdo = tabelas Blowfish padrão + `ctext = "OrpheanBeholderScryDoubt"`).
- Alteração: `struct Key` → `enum BcryptTables` + cabeçalho de atribuição. Zero mudança lógica.
- Licença MIT compatível com a nossa MIT. Texto da licença:
  https://github.com/vapor-community/bcrypt/blob/master/LICENSE

## O que NÃO foi vendored

O restante do `vapor-community/bcrypt` depende dos pacotes `Core`, `Random` e `Debugging`
do ecossistema Vapor. Em vez de vendorar a árvore de dependências, o motor EksBlowfish
(`EksBlowfish.swift`), o base64 bcrypt (`BcryptBase64.swift`) e o hasher Proton
(`ProtonBcrypt.swift`) são implementação própria, com semântica espelhada do fork
`ProtonMail/bcrypt` (primeiros 22 chars do salt, eco no output, NUL-terminated password).

## Verificação

- 3 vetores cruzados com o bcrypt de referência (implementação C via Python):
  custo 6 canônico, custo 10 ASCII, custo 10 UTF-8 — todos exatos.
- Qualquer toque nestes arquivos exige revalidar os vetores (ver `docs/AUTH.md` §2).
