# Scripts de operação — Fábrica / Atacadão dos Óculos (Projeto Elen)

IA de atendimento WhatsApp ("Elen") no SPX. Box único: `3.87.182.184` (fabrica.chatspx.app),
Account 1 = Fábrica · Account 2 = Atacadão. Rodam via `rails runner` **no box** (não localmente).

**Acesso ao box:** `scripts/ops/fabrica.sh run "<cmd>"` (ver `scripts/ops/AMBIENTES.md`).
**Guia do dev:** `docs/clientes/fabrica-oculos/FABRICA-OCULOS-GUIA-DEV-IA.md`.

## Setup (Ruby — idempotentes)
- `setup_mtm_tools.rb` — cria as custom tools do CRM **MTM** (`mtm_buscar_cliente`,
  `mtm_registrar_cliente`, `mtm_loja_por_cidade`, `mtm_listar_clinicas`). **A `MTM_API_KEY`
  entra por ENV, nunca no arquivo** (transferir por base64 pra não corromper acento).
- `setup_elen_brain.rb` — cérebro v1 da Elen (persona do formulário + attach das tools + behavior).
- `setup_elen_agents.rb` — segrega a Elen em 3 agentes (Elen triagem · Bia sol/relógios · Carol grau+broker),
  estilo Tozi (transferência invisível). Idempotente (acha por nome novo ou antigo).
- `elen_ligar.rb` — cutover: liga `CaptainInbox(2,1)` + regra `conversation_created → assign_ai_agent`.
- `harden_mtm_tools_20260807.rb` — endurece contratos e atribuições das tools do atendimento
  MTM da conta 1. O modo padrão `plan` não escreve; `SPX_ACTION=apply` cria snapshot 0600
  sem credenciais antes da transação; `SPX_ACTION=rollback SPX_BACKUP_PATH=...` restaura
  somente os campos tocados. Em rollback completo, reverta a configuração antes do código.

## Segredos
Nenhuma chave/senha vive nestes scripts. `MTM_API_KEY` e senha SSH ficam no vault
(`Obsidian/clientes/fabrica-atacadao-oculos.md`) e no `.env` do box.

## Pendências conhecidas (dados, lado MTM)
- Clínicas sem `contato_whatsapp_e164`/lat-lng → broker de consulta bloqueado.
- Só 1 seller (Ana Carla #8) → `agendar` precisa de estratégia de `seller_id`.
- Origem de agendamento "WhatsApp - Bot Elen" (#42) inativa — reativar.
