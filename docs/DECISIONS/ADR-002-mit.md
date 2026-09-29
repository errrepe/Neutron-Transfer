# ADR-002 — Licença MIT

- Status: Accepted
- Data: 2026-09-29
- Contexto: Projeto open source desde o dia zero. Precisa maximizar contribuição e reuso, incluindo eventual interoperabilidade com SDKs e ferramentas (rclone, go-proton-api). Sem modelo comercial definido no MVP.

## Decisão

Licenciar Neutron Transfer sob MIT (2026, `Neutron Transfer contributors`). Arquivo `LICENSE` na raiz.

## Alternativas consideradas

1. **GPL / AGPL:** descartado — copyleft restringiria reuso em integrações e afastaria contribuidores do ecossistema Apple.
2. **Apache-2.0:** viável, mas MIT é mais simples e suficiente para MVP sem patenteamento explícito em jogo.
3. **Proprietário / source-available:** descartado — conflita com objetivo open source e auditoria cripto.

## Consequências

- Positivas: reuso máximo, contribuição frictionless, compatível com SPM e auditoria third-party.
- Negativas: sem proteção copyleft; forks fechados permitidos (aceito conscientemente).
- Obrigações: manter header `LICENSE`, `Copyright (c) 2026 Neutron Transfer contributors`, sem branding Proton no código ou UI.
