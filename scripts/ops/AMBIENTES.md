# Ambientes SPX — mapa de deploy por cliente

> **Leia isto ANTES de "subir em homologação" / "deployar" qualquer coisa.**
> O `chatspx` é **um fork único do Chatwoot** que serve vários clientes como contas (tenants)
> diferentes na mesma base de código. "Homologação" e "produção" são **por cliente** — cada um
> tem sua própria VM. A palavra "homologação" sozinha é ambígua: sempre diga **de qual cliente**.

## Tabela-mestre

| Cliente | Ambiente | Host / VM | App (URL) | Conta(s) | Helper |
|---|---|---|---|---|---|
| **Tozi** | Homologação (sandbox) | `192.168.8.232` (LAN, `simplexia@`) | chatspx.app | conta **3** | `scripts/ops/tozi-hml.sh` |
| **Tozi** | 🔴 Produção (cliente real) | `3.82.215.109` (`ubuntu@`, PEM) | tozi.chatspx.app | conta **6** | `scripts/ops/tozi-prod.sh` |
| **Fábrica / Atacadão** | Box único (build/teste) | `3.87.182.184` (`chatwoot@`) | fabrica.chatspx.app | **1** Fábrica · **2** Atacadão | `scripts/ops/fabrica.sh` |

Observações:
- **Tozi** tem dois ambientes separados (HML `.232` × PROD AWS). Não confundir: `.232` também
  hospeda o SaaS `chatspx.app` com outros clientes — tratar como produção leve.
- **Fábrica/Atacadão** ainda é **greenfield**: há **um** box (`3.87.182.184`), que hoje serve de
  build/teste. Não existe HML×PROD separado ainda. `fbchml.simplexsolucoes.com.br` é o **MTM**
  (CRM da Simplex), **não** um ambiente chatspx.
- Os 3 números WhatsApp reais da Fábrica ainda estão no BSP **WTS Chat** (migração p/ chatspx pendente).

## Como o código separa os clientes

Não é por pasta — é por **namespace + conta**:
- Código específico de cliente vive em `Spx::Tozi::*` / `Spx::FabricaOculos::*`
  (`app/{services,jobs,listeners}/spx/<cliente>/`). Hoje só `Spx::Tozi` está reconciliado no repo;
  o código da Fábrica ainda vive off-git no box `3.87.182.184` (a reconciliar).
- Config viva (prompts, behavior, tools, elegibilidade) vive **no banco de cada conta**, não no git.
- O app Chatwoot em si é **compartilhado** — não pode virar pasta por cliente.

## Credenciais

Nenhuma senha/chave fica nestes scripts. Cada helper lê a credencial do **vault Obsidian** em
tempo de execução (via `SSH_ASKPASS`, nunca ecoada):
- Tozi HML: `Obsidian/credenciais/infraestrutura.md` (seção Cortex LAN)
- Tozi PROD: PEM em `Downloads/handoff-tozi/simplex.linux.pem`
- Fábrica: `Obsidian/clientes/fabrica-atacadao-oculos.md` (linha "Servidor (SSH)")

## Regra de ouro antes de deployar

1. Confirme **cliente + ambiente** (não só "homologação").
2. Rode o helper certo — ele imprime um **banner** com CLIENTE · AMBIENTE · HOST. Confira o banner.
3. Em produção (Tozi conta 6): só com **OK explícito** do Paulo. Antes de `restart`,
   sempre `rails db:migrate:status` (migration pendente + restart = 500 em cadeia).
