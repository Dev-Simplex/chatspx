# Docs do chatspx

O `chatspx` é **um fork único do Chatwoot** que atende vários clientes (contas/tenants) na mesma
base. Para não misturar cliente com cliente (nem cliente com plataforma), os docs seguem:

## Layout

- **`docs/clientes/<cliente>/`** — documentação **específica de um cliente**.
  - `docs/clientes/tozi/` — Tozi Imobiliária (agente Clara e time de IA, disparos, funil, distribuição).
  - `docs/clientes/fabrica-oculos/` — Fábrica / Atacadão dos Óculos (Projeto Elen, MTM).
- **`docs/` (raiz)** — **plataforma SPX / Chatwoot compartilhado**: arquitetura do produto,
  redesigns de UI, Copilot, WhatsApp/WAHA, gestão multi-VM, mapeamentos, ADRs, runbooks, backlog.

> Regra: se o doc só faz sentido para **um** cliente → `clientes/<cliente>/`.
> Se vale para o produto/plataforma (ou mais de um cliente) → raiz.

## Onde estão os ambientes (deploy)

O mapa de "qual VM é de qual cliente/ambiente" **não** fica aqui — fica em
[`scripts/ops/AMBIENTES.md`](../scripts/ops/AMBIENTES.md), junto dos helpers de deploy por cliente.
Leia antes de "subir em homologação": a palavra sozinha é ambígua (cada cliente tem a sua).

## Ambíguos deixados na raiz (revisar se quiser mover)

Alguns docs têm nome de plataforma ("SPX") mas conteúdo puxado pela Tozi. Ficaram na raiz por
serem transversais; mova para `clientes/tozi/` se preferir tratá-los como Tozi:
`MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md` (+ `mapeamento-2026-06-10/`),
`AUDITORIA-SPX-2026-06-04.md`, `RECONCILIACAO-BRANCHES-2026-06-08.md`, `ROADMAP-IA-COMPLETA.md`,
`TESE-META-AGENTE-3-CAMADAS.md`. (`PLANO-GESTAO-IA-MULTIVM.md` é genuinamente multi-cliente → raiz.)
