# Plano — Sistema de Gestão de Comportamento das IAs (multi-VM) com aprovação

> **v2 — decisões travadas (2026-06-29).** A v1 deste doc levantava opções; esta versão decide.
> Contexto: sessão Claude Code que operava os agentes Captain da Tozi/SPX.

---

## 1. Objetivo

Permitir **alterar/criar o comportamento das IAs (agentes Captain)** em **cada VM do SPX** (cada cliente roda sua própria VM com um fork do Chatwoot), com um **fluxo de aprovação antes de ir pra produção**.

**Fluxo-alvo (palavras do Paulo):**
1. Cliente acha uma falha de comportamento na IA → reporta à equipe.
2. **Dev júnior + Claude** diagnosticam: muitas vezes é um ajuste pequeno no system prompt.
3. Júnior edita o prompt e abre uma **"PR"** (proposta de mudança).
4. O **diff** sobe pro portal — **Almirante**.
5. Um **dev pleno aprova** dentro do portal.
6. A mudança desce pra **aquela IA específica, na VM daquele cliente**.

Governança de dois: júnior propõe, pleno aprova, nada toca a VM do cliente sem o aval.

---

## 2. Decisões travadas (locked)

| # | Decisão | Por quê |
|---|---|---|
| **D1** | **Control plane = Almirante** (portal próprio). A proposta + diff + aprovação vivem no store do Almirante; o **diff é calculado ao vivo** contra a config lida da VM. **Não** é git+PR literal. | A config da IA vive no **banco da VM**, não no git. Forçar git exigiria espelhar todo prompt no repo. O "PR" é uma metáfora — review de diff dentro do Almirante. |
| **D2** | **Transporte = o canal SSH que o Almirante já tem** pras VMs. O receptor é **código versionado no repo** (service + rake), então **toda VM já o tem no próximo deploy**. Almirante faz `scp` do change-set + roda o applier. **Sem endpoint HTTP novo em VM de cliente.** | Reusa a confiança SSH existente. Zero superfície de ataque nova em produção. Distribui sozinho via git. |
| **D3** | **Auth v1 = a própria confiança SSH.** O change-set carrega `author`/`approved_by` pra auditoria, mas **sem HMAC ainda** (só chega na VM via SSH autenticado do Almirante). HMAC/JWT entram só quando existir transporte não-SSH. | Não pagar complexidade de crypto + gestão de chave por VM antes de precisar. Simplicidade primeiro. |
| **D4** | **Linha dura: este sistema gerencia só config-no-banco que é LIVE por request** — `instructions`, `FAQ`, `behavior`, `eligibility`, toggle de `tools` já existentes. **Código** (template `assistant.liquid`, tool nova, service) = deploy git/Almirante com restart + `migrate:status`. **Não se misturam.** | Rollback/idempotência de config são baratos; de código são deploy. Misturar é erro de categoria. |
| **D5** | **Sequência:** reader (export, read-only) → applier (`update_instructions` + `add_faq`) → rollback → E2E Paulao. Almirante por cima depois. | O reader dá a baseline pro diff. As 2 ops são as mais comuns e seguras. |
| **D6** | **Código no layer SPX em OSS** (`app/services/spx/ai_config/`, `lib/tasks/spx_ai_config.rake`, `app/models/ai_config_change.rb`) — espelhando o precedente `Spx::Tozi`. | Consistência com o que já existe (`app/services/spx/tozi/` + `spx_tozi.rake`) pesa mais que a nota genérica "enterprise/". Additivo, autoload cobre. |

---

## 3. Contexto do SPX (onde mora o "comportamento")

- **Stack:** fork do Chatwoot (Rails 7.1 + Vue). IA = **Captain v2** (`captain_integration_v2`).
- **Config por conta/VM, no BANCO (não git):**
  - `Captain::Assistant` (`enterprise/app/models/captain/assistant.rb`):
    - `config` (JSONB): **`instructions`** (prompt), **`tools`** (ids habilitados), `model`, `team_id`, `triage`, `knowledge_mode`, `temperature`…
    - `behavior` (JSONB, `store_accessor`): `debounce_seconds`, `router_config`, `business_hours_config`, `humanizer_config`, `dedup_config`, `copilot_trigger_config`, `media_pipeline_config`.
  - **FAQ** = `Captain::AssistantResponse` (`question`, `answer`, `status` enum pending/approved, `embedding` vector(1536) gerado async no `after_commit`). `account` auto-setado do assistant.
  - **Elegibilidade:** `CaptainInbox(inbox_id, captain_assistant_id)`.
  - **Espelho atribuível:** `AgentBot` com `bot_type: captain` (sincronizado por `after_commit` no assistant).
- **Código compartilhado (git, vale pra TODA a instância):** template `enterprise/lib/captain/prompts/assistant.liquid` (`Captain::PromptRenderer`, `File.read` por request → live sem restart) e tools em `enterprise/lib/captain/tools/`.

### O problema que isto resolve
Hoje as mudanças são feitas **na mão, por sessão sênior, via `rails runner` direto no banco da VM (SSH)** — sem aprovação formal, sem auditoria padronizada, sem rollback estruturado, sem caminho seguro pro júnior.

> ⚠️ **Importante:** config-no-banco (instructions/FAQ/behavior) **sobrevive a `reset --hard`** (o deploy só mexe em código). O que se perde no deploy é **código off-git** (template, tools) — e isso **não** é escopo deste sistema (é deploy git). Logo o reader/export aqui é **feature de diff do portal**, não emergência de "estancar sangria".

---

## 4. Arquitetura (alvo)

1. **Control plane = Almirante** (D1) — onde o júnior submete e o pleno aprova. Guarda proposta, diff, estado (rascunho → em revisão → aprovado → aplicado → revertido), autor, aprovador, timestamps.
2. **Receptor por VM** (D2) — aplica um change-set **aprovado** no banco da VM: **transacional, idempotente, auditável, reversível**. ⟵ **foco da 1ª sessão.**
3. **MCP (opcional, depois)** — embrulha o receptor/portal em tools pra dev/Claude. **MCP é cliente do receptor, não o receptor.**

---

## 5. O receptor — change-set

### Unidade de mudança
Pacote versionado e aprovado com 1+ operações. **Escopo v1:** `update_instructions`, `add_faq`. **Ampliar depois:** `update_behavior`, `update_tools` (toggle), `set_eligibility`, `add/remove_knowledge`, `create/delete_assistant`.

### Formato (JSON)
```json
{
  "change_set_id": "uuid-do-almirante",
  "account_id": 1,
  "author": "junior@spx",
  "approved_by": "pleno@spx",
  "operations": [
    { "type": "update_instructions", "assistant_id": 7, "instructions": "novo prompt…" },
    { "type": "add_faq", "assistant_id": 7, "question": "…", "answer": "…" }
  ]
}
```

### Propriedades obrigatórias
- **Idempotente:** reaplicar o mesmo `change_set_id` é no-op (short-circuit no registro `applied`).
- **Transacional:** tudo ou nada (`ActiveRecord::Base.transaction`).
- **Snapshot + rollback:** antes de aplicar, salva o estado anterior (config JSONB = snapshot barato; FAQ = guarda o id criado pra deletar no revert).
- **Dry-run + diff:** mostra o que MUDARIA sem aplicar (pro Almirante renderizar o diff pro pleno).
- **Auditoria:** tabela `ai_config_changes` (change_set_id, account_id, assistant_id, operations, snapshot_before, result, status, author, approved_by, applied_at, reverted_at).
- **Multi-tenant:** toda op valida que o `assistant` pertence ao `account_id` do change-set; **nunca cruza conta**.
- **Sem segredos no payload:** keys (Vista/Google/LLM) ficam em `Account.custom_attributes`/ENV.

### Reversibilidade — honestidade de escopo
- `update_instructions` / `add_faq` (v1): **reversível barato e limpo** (snapshot do config / delete do id criado).
- `delete_assistant` / `add_knowledge` (futuro): **irregular** — ids não voltam iguais, re-embedding custa $/tempo. Não prometer "reversível sempre"; prometer **pro escopo v1**.

---

## 6. Entregável da 1ª sessão (na VM Paulao)

1. **Tabela** `ai_config_changes` (migration additiva, `if_not_exists`).
2. **`Spx::AiConfig::ConfigReader`** — exporta a config viva de um assistant (instructions, behavior, tools, model, FAQ, eligibility) → Hash/JSON. Read-only. Baseline do diff.
3. **`Spx::AiConfig::ChangeSetApplier`** — `dry_run` (diff) + `apply!` (transacional, idempotente, snapshot, audit) + `revert!(change_set_id)`. Ops v1: `update_instructions`, `add_faq`.
4. **Rake** `spx:ai_config:{export,dry_run,apply,revert}` — entrypoints chamáveis por SSH (o que o Almirante invoca).
5. **E2E Paulao:** export → editar o prompt no JSON → `dry_run` mostra o diff → `apply` → conferir no banco → `revert` → conferir que voltou.

> **Sucesso =** "de fora da VM, aplico uma mudança de prompt aprovada — com diff, transacional, auditada e reversível — sem `rails runner` na mão."

---

## 7. Decisões adiadas (fase 2, conscientemente)
- **HMAC/assinatura** do change-set (só quando houver transporte não-SSH).
- **Onde o Almirante guarda** propostas/aprovações (store dele — schema da fase 2).
- **Ampliar ops** pra behavior/tools/eligibility/knowledge/agentes.
- **MCP** por cima do receptor.
- **Registro de VMs** no Almirante (como chegar em cada uma: SSH/PEM/host).

---

## 8. Riscos / gotchas (da experiência operando na mão)
- Config é **por conta no banco** — operar na VM certa, com `account_id` certo.
- **Restart:** instructions/behavior/FAQ = **live por request** (sem restart). Tools/template/service = código → **restart do worker** + **SEMPRE `rails db:migrate:status` antes** (regra crítica do projeto). O v1 só toca config live → seguro.
- **Migration landmine:** `20260330120000_add_foreign_key_constraints` é DESTRUTIVA e está `down` de propósito. Aplicar a migration nova com `db:migrate:up VERSION=<ts>` específico — **nunca `db:migrate` puro** em VM com a landmine pendente.
- Template de prompt é **compartilhado pela instância** — distinguir "config por-agente" (este sistema) de "código compartilhado" (deploy).
- **Elegibilidade (`CaptainInbox`)** é o interruptor mestre de quem responde — fora do v1, mexer com cuidado.
- Multi-VM: cada VM tem acesso próprio (SSH/PEM) — o Almirante precisa de um registro seguro de "como chegar".

---

## 9. Referências de código
- `enterprise/app/models/captain/assistant.rb` — `config` (instructions/tools/model/team_id/triage) + `behavior` (`store_accessor`).
- `enterprise/app/models/captain/assistant_response.rb` — FAQ (question/answer/status/embedding async).
- `CaptainInbox`, `AgentBot(bot_type: captain)` — elegibilidade + espelho.
- `app/services/spx/tozi/*` + `lib/tasks/spx_tozi.rake` — **precedente** do layer SPX (estilo a espelhar).
- `enterprise/lib/captain/prompts/assistant.liquid` + `Captain::PromptRenderer` — template compartilhado (fora do escopo; é código).
