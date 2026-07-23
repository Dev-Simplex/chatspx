# Plano — Deploy do eval + nivelamento da frota + espelho de IA da Tozi

**Data:** 2026-07-08
**Máquina de origem:** homologação (.232) — única com credencial GitHub
**Status:** PLANEJAMENTO (aguardando greenlight de execução)

---

## 1. Objetivo

Três frentes, decididas com o Walisson:

| # | Frente | Alvo | Risco |
|---|--------|------|-------|
| A | **Código** — merge `homologacao → producao` (traz o *eval nativo*) | branch `producao` no origin | baixo |
| B | **Deploy do código** — nivelar TODA a frota em `producao`+eval | 6 VMs (via git bundle) | médio/alto |
| C | **Espelho de IA** — agentes da account 3 → account 6 | **só a Tozi** (tozi.chatspx.app) | **alto** (cliente real) |
| D | **Ativar eval** na conta 6 (Tozi) | account 6 | baixo |

---

## 2. Estado atual verificado (08/07, read-only)

### Git
- `origin/producao` = `cf4b73266` — já contém TUDO do full de 07/07 (chat-interno, relatórios, Automações F1/F2, Nicolas, Sinop), gated por flag.
- `origin/homologacao` = `b4aedc2e6` — difere da producao por **apenas 2 commits**: `ae57d3ffd` (eval) + merge `b4aedc2e6`.
- **Único código pendente para produção = "eval nativo LLM-as-a-Judge" (`conversation_eval`)**, do Paulo.
  - Backend-only (jobs/model/service/prompt/rake + `config/schedule.yml`) → **não precisa `assets:precompile`**.
  - **Precisa `db:migrate`** (tabela `captain_conversation_evals`, migration `20260702180000`).
  - Aplica limpo sobre producao (único arquivo modificado não-novo, `get_conversation_analysis_service.rb`, é idêntico à base; resto é novo).
  - Opt-in por conta via `custom_attributes['eval_enabled']` → **inócuo onde não for ativado**.
  - Os 7 arquivos "untracked" na working tree da .232 = esse mesmo commit (já no origin). **Nada a commitar aqui.**

### Frota (branch `producao` em todas)
| VM | IP | HEAD atual | Delta até `producao`+eval | Peso |
|----|----|-----------|---------------------------|------|
| **tozi** (conta 6) | 3.82.215.109 | `cf4b73266` | só o eval | 🟢 leve (backend, 1 migration) |
| **catatau** | 3.85.130.14 | `2fa8d9eb6` | 134 commits + eval (73 arq front, 11 migr.) | 🔴 pesado (OOM) |
| **sentinela** | 54.166.220.138 | `2fa8d9eb6` | idem catatau | 🔴 pesado (OOM) |
| **fabrica** | 3.87.182.184 | `c8f3dc803` ⚠️ | commit **não existe no repo** → divergiu | 🟠 investigar antes |
| **producao** (interna) | 192.168.8.229 | não inspecionada (Proxmox/senha) | ? | ? |
| **alternativo** | 192.168.8.169 | não inspecionada (Proxmox/senha) | ? | ? |
| ~~paulao~~ | 192.168.8.100 | sandbox dev (branch `paulao`) | — | **pular** |

**Fatos que guiam o método:**
- **Nenhuma VM AWS tem credencial GitHub** → o painel de deploy (`git pull`) NÃO serve. **Tudo por git bundle** (chave RSA em `deployment/panel/server.js`; repo dono `chatwoot`; `sudo systemctl restart chatwoot.target`).
- `assets:precompile` padrão (4 GB) **estoura OOM** com o front pesado (chat interno) em VM de 7.6 GB → **swap temporário + `NODE_OPTIONS=--max-old-space-size=6144`**, e checar `manifest mtime` mudou (exit 0 é falso no OOM).
- Erro PRÉ-EXISTENTE na Tozi (não é regressão de deploy): `OrphanRetriageJob` da conta 6 em retry-loop (`blocked?` for nil) — investigar à parte.

---

## 3. Plano de execução

### FRENTE A — Merge do código (na .232, com credencial)
1. `git fetch origin` (feito).
2. Criar branch de deploy a partir de `origin/producao`: `git checkout -b deploy/frota-eval origin/producao`.
3. Trazer o eval: `git merge origin/homologacao` (só adiciona o eval; conflito esperado = nenhum). Alternativa cirúrgica: `git cherry-pick ae57d3ffd`.
4. Sanidade: `bundle exec rubocop` nos arquivos tocados? (opcional) + boot local não é obrigatório (backend puro).
5. Atualizar `producao` e **push `origin producao`** (mantém fonte de verdade). → **Alvo da frota = esse commit** (`producao`+eval).

### FRENTE B — Deploy nas VMs (bundle, 1 por vez, validando cada uma)
Ordem: leve → pesada.

**B1. Tozi** (`cf4b73266` → +eval) — LEVE:
- `git bundle create eval.bundle deploy/frota-eval --not cf4b73266` → scp `/tmp` (.109) → `git fetch /tmp/eval.bundle` → `git checkout -- public/version.json` → `git merge --ff-only FETCH_HEAD`.
- **`RAILS_ENV=production bundle exec rails db:migrate`** (tabela nova).
- `sudo systemctl restart chatwoot.target`.
- Validar: `curl localhost:3000` 200, boot limpo, tabela `captain_conversation_evals` existe, HEAD == alvo.

**B2. catatau + B3. sentinela** (`2fa8d9eb6` → alvo) — PESADO:
- Backup do banco antes (aditivas, mas produção real).
- Bundle `--not 2fa8d9eb6` → scp → fetch → `merge --ff-only`.
- Swap temporário 4 G → `assets:precompile` com 6144 → checar manifest mtime → `db:migrate` (11) → restart → validar (health, front novo, migrations up) → swapoff/rm.

**B4. fabrica** (`c8f3dc803` divergiu) — INVESTIGAR PRIMEIRO:
- SSH read-only: `git log/status` da VM, descobrir o que é `c8f3dc803` (customização local? branch própria?).
- Decidir: reconciliar (se descartável, alinhar ao alvo) ou preservar delta. **Não deployar às cegas.**

**B5. producao interna (.229) + B6. alternativo (.169)** — Proxmox:
- Precisam de acesso (senha `simplexia`). Inspecionar branch/HEAD/credencial primeiro.
- Se tiverem credencial GitHub, o painel de deploy funciona (mas cuidado com OOM). Senão, bundle.

### FRENTE C — Espelho de IA da Tozi (account 3 .232 → account 6 .109)
Escopo aprovado: **prompts/instruções + FAQs + tools armadas + credenciais + behavior + elegibilidade.**
Mecanismo: receptor `spx/ai_config` (control plane Almirante) — change-sets HTTPS com snapshot/rollback/auditoria.
⚠️ **Não cobre `captain_scenarios` nem knowledge base/documents** — se necessário, caminho à parte (a confirmar).

1. **Comparar os 2 lados ANTES** (decisão: mostrar o diff antes de aplicar):
   - Ler baseline dos assistants da account 3 (local, `ConfigReader`) e da account 6 (.109, `GET /spx/ai_config/accounts/6/assistants/:id/baseline`, header `api_access_token` de PlatformApp).
   - Mapear assistants por **nome** (id account 3 ≠ id account 6).
   - Diff por assistant: instructions, faqs, tools, credenciais (mascaradas), behavior, elegibilidade.
2. **Apresentar o diff ao Walisson** (produção pode estar mais rica — regra de ouro).
3. Montar change-set(s) (`update_instructions`, `add_faq`, `arm_tool`/`disarm_tool`, `set_credential`, `update_behavior`, `set_eligibility`).
4. `POST /spx/ai_config/change_sets/dry_run` → revisar.
5. Backup manual dos prompts da conta 6 (como em 07/07: `/tmp/prompts_backup_conta6.json`) + snapshot automático do applier.
6. `POST /spx/ai_config/change_sets` (apply) — com aprovação.
7. Validar IA respondendo (receptor/HTTPS). Rollback disponível: `POST /spx/ai_config/change_sets/:id/revert`.

### FRENTE D — Ativar eval na conta 6 (após B1)
- `account(6).custom_attributes['eval_enabled'] = true` + save.
- `rake spx:eval:enable` (conforme `lib/tasks/spx_eval.rake`) e/ou `spx:eval:run` para primeiro batch.
- Validar: registros em `captain_conversation_evals`, `spx:eval:report`.

---

## 4. Riscos e mitigações
- **OOM** (catatau/sentinela/prod interna) → swap + 6144 + checar manifest mtime.
- **Migrations em produção real** → backup de banco antes; migrations do delta são aditivas (chat-interno/relatórios forward-only).
- **fabrica divergida** → investigar `c8f3dc803` antes de tocar.
- **Espelho de IA em cliente real** → comparar + dry-run + backup + revisão humana; horário de menor movimento.
- **Downtime** → serviço fica no ar durante build; só o restart derruba por segundos.
- **Push `origin producao`** → só adiciona o eval (resto já está lá). Seguro.

## 5. Pendências para destravar execução
- [ ] Acesso às Proxmox internas (.229 producao, .169 alternativo) — senha `simplexia`.
- [ ] `api_access_token` (PlatformApp) da .109 para o receptor de IA. Descobrir/gerar.
- [ ] Espelho inclui **cenários / base de conhecimento**? (receptor não cobre)
- [ ] Janela de deploy (horário de menor movimento) e ordem entre A→D.
- [ ] Backup de banco antes das migrations pesadas — confirmar.
