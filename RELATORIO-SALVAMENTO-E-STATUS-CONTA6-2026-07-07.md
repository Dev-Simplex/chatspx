# Salvamento do trabalho em PROD + status de Prompt-Cache e Eval (Tozi conta 6)

> **Data:** 2026-07-07 · **VM:** Tozi PRODUÇÃO `3.82.215.109` (conta 6) · **HEAD rodando:** `cf4b73266`
> Verificado ao vivo por SSH (helper `scripts/ops/tozi-prod.sh`). Read-only, exceto o salvamento (§1), que só cria tags/arquivos — **não toca no código que roda**.

---

## 0. TL;DR

1. **Nada foi perdido no deploy.** O que você fez direto na PROD estava sem commit → foi pra **stash** (comportamento seguro do `switch-branch.sh`). Blindei tudo agora em **tags permanentes + bundle** (§1).
2. **Prompt-cache (redução de custo LLM): NO AR e funcionando** na conta 6 — Fase 1 (tools) **e** Fase 2 (system). ✅ (§2)
3. **Eval (LLM-as-a-Judge): NÃO está no ar.** O código existe commitado numa branch (`feat/captain-evals`), mas **não foi mergeado** → não há tabela nem job rodando na conta 6. Está **dormente**. (§3)

---

## 1. Salvamento — trabalho em PROD blindado ✅

O deploy de hoje (`cf4b73266`) foi por **fast-forward** (não apaga commit) e suas edições sem commit foram **stasheadas**. Achei **7 stashes** + `.bak` de edições diretas + reflog intacto. Blindei o que estava frágil (stash some com um `git stash clear`):

**Criado no box `/home/chatwoot/`:**

| Artefato | O que protege |
|---|---|
| Tags `salvamento/stash-0` … `salvamento/stash-6` | Os 7 stashes viram refs permanentes (não expiram) |
| Tag `salvamento/linha-83d79e6b4` | A linha-base do stash grande, que ficou fora do deploy |
| `salvamento-prod-conta6-20260707.bundle` (28 KB) | Bundle git com **só o conteúdo único** (verificado OK) |
| `salvamento-bak-codigo-20260707.tgz` (8,2 KB) | Os `.bak` de código (`response_builder_job`, `agent_runner_service`, `humanizer_service`) |

> ⚠️ Os `.env.bak-*` **não** entraram em nenhum artefato — têm segredos, ficam só no box.

**O que está PARADO (preservado, mas não rodando):**

- **`stash@{1}` = 304 arquivos / +11.276 linhas** — corpo grande de customização (reports, gallery, kanban, waha, tools do captain: `handoff_tool` +108, `buscar_imovel` +69, `disparo_lead_job`, `assistant.liquid`…). Baseado em `83d79e6b4`, que **ficou fora da linha do deploy** → não está no código vivo.
- **`stash@{3-6}`** — SSO custom Tozi→AWS (banner Vue+Lottie), ContactHistory, scripts de deploy.
- **`.bak-backstop/order`** (`response_builder_job.rb`) e **`.bak-replay`** (`agent_runner_service.rb`) — divergem do vivo.
- `stash@{0}`, `{2}` e `.bak-split` (`humanizer_service.rb`) — triviais/já aplicados.

**Confirmado que ESTÁ rodando (não se perdeu):** os 3 fixes da Clara (`c3e2df507`), lock de webhooks WhatsApp (`6516d06d5`), as 8 melhorias de comportamento.

> **Recuperar depois:** `git stash apply salvamento/stash-1` (ou `git checkout salvamento/stash-1 -- <arquivo>`). Fora do box: `git clone salvamento-prod-conta6-20260707.bundle`.

**Pendente de decisão:** o `stash@{1}` é trabalho novo que nunca subiu **ou** versão antiga já superada por outro caminho? Só o **conteúdo** diz — é reconciliação (idealmente com quem fez o deploy). Posso gerar o comparativo arquivo-a-arquivo quando quiser.

---

## 2. Prompt-cache (redução de custo LLM) — ✅ NO AR E FUNCIONANDO

**Objetivo:** marcar o prefixo estático das requisições Anthropic com `cache_control` → leituras de cache custam **~10%** do preço de input.

### Está no ar? Sim — verificado ao vivo na conta 6:

| Camada | Estado | Evidência |
|---|---|---|
| **Fase 1 — cache de tools** | ✅ ativa | Log de boot: `[prompt-cache] instalado em RubyLLM::Providers::Anthropic (cache de tools ON)` |
| **Fase 2 — cache do system prompt** | ✅ ligada | `Account(6).custom_attributes['prompt_cache_system'] = true` (lido ao vivo) |

- **Código mergeado em `producao`:** `e785949ce` (prompt caching) + `c8453e999` (flag Fase 2 por conta), presentes em `cf4b73266`.
- **Como funciona:** `enterprise/app/models/concerns/agentable.rb` divide o system em **bloco estável** (com `cache_control`) + **bloco volátil** (data/hora). A flag é lida **por chamada** → ligar/desligar **não precisa de restart**.
- **Prova de funcionamento (registrada 07/07):** bloco estável de 27.714 chars; 1ª chamada `cache_creation=8472` → 2ª chamada `cache_read=8472` → system caindo pra ~10% do custo nas repetições.

### O que falta / observações
- **Nada bloqueia na conta 6** — está completo e provado.
- **Reverter** (se precisar): `Account(6).custom_attributes['prompt_cache_system'] = false` (sem restart).
- **Fábrica (contas 1/2):** cache de system **desligado** — ligar por conta quando fizer sentido.

---

## 3. Eval (LLM-as-a-Judge) — ❌ NÃO ESTÁ NO AR (dormente)

**Objetivo:** avaliar automaticamente a qualidade das conversas (nota + findings) via um LLM juiz.

### Está no ar? Não — verificado ao vivo na conta 6:

| Checagem | Resultado |
|---|---|
| Arquivos no box (`conversation_eval*.rb`, `spx_eval.rake`, jobs) | ❌ **FALTAM todos** |
| Tabela `captain_conversation_evals` | ❌ **não existe** |
| Constante `Captain::ConversationEval` | ❌ **ausente** |
| Job de eval no scheduler (sidekiq-cron) | ❌ **nenhum** |

### Por quê
- O código **existe commitado** na branch `feat/captain-evals` (`ae57d3ffd`, já no GitHub), **mas nunca foi mergeado** em `homologacao`/`producao`. Logo, **não desceu pra nenhuma VM** de produção.
- Na **conta 3 (HML)** ele rodou **uma vez** (E2E de 02/07: 5 evals daquele dia, 0 desde) via **arquivos soltos off-git** — e o **scheduler nunca foi registrado** (o `schedule.yml` do box não tem o cron). Ou seja: **o mecanismo funciona** (nota média ~7,2, findings corretos), mas **não roda sozinho**.
- No seu clone local, os arquivos do eval estão **não-commitados** (untracked) — mais um motivo de não terem subido.

### Para virar real (produção, conta 6)
1. Mergear `feat/captain-evals` → `homologacao` + **restart do worker** (valida na `.232`).
2. Mergear → `producao`, aplicar a **migration aditiva** `20260702180000_create_captain_conversation_evals` (rodar `db:migrate:status` **antes** do restart) + `spx:eval:enable[6]` + restart.
3. Registrar o **cron do eval** no `schedule.yml` (senão nunca dispara sozinho).
4. Reconciliar `enterprise/app/services/captain/tools/copilot/get_conversation_analysis_service.rb` (está modificado local vs. o commit).
5. Fase 2 do eval (alertas de nota ruim + painel) segue **pendente**.

> ⚠️ Só com **OK explícito** — é produção, cliente real, e envolve restart.

---

## 4. Ações recomendadas

| Prioridade | Ação | Risco |
|---|---|---|
| ✅ Feito | Salvamento dos stashes/`.bak` (tags + bundle + tgz) | nenhum |
| 🟡 Quando quiser | Comparar `stash@{1}` (304 arq) vs. vivo → decidir o que reintegrar | leitura |
| 🟡 Decisão sua | Mergear+deployar o **eval** na conta 6 (passos §3) | restart em prod |
| 🟢 Opcional | Ligar cache de system na **Fábrica** (contas 1/2) | flag, sem restart |
| 🔵 Higiene | Copiar o `.bundle`/`.tgz` pra fora do box (backup externo real) | — |

---

## Anexo — como foi verificado

```bash
# Salvamento
scripts/ops/tozi-prod.sh run 'for i in 0..6; do git tag -f salvamento/stash-$i stash@{$i}; done'
scripts/ops/tozi-prod.sh run 'git bundle create /home/chatwoot/salvamento-prod-conta6-20260707.bundle ^cf4b73266 refs/tags/salvamento/*'

# Cache + Eval (rails runner na conta 6)
#   custom_attributes['prompt_cache_system'] => true
#   table captain_conversation_evals         => false
#   Captain::ConversationEval                => AUSENTE
#   sidekiq-cron: nenhum job de eval
```
