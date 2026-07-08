# Plano de Reestruturação do Banco de Dados do Kanban

> Diagnóstico verificado no banco de **staging (chatwoot_production nesta box) e chatwoot_test** em 2026-07-08.
> Regra de segurança: tudo validado no staging `nicolas`, migrations idempotentes/reversíveis, nunca na frota sem runbook. Ver [[safety-do-no-harm]] / [[runbook-deploy-producao]].

## Situação atual (fatos verificados)

Existem **duas famílias de tabelas** com o mesmo propósito:

- **`funnel_*`** — implementação **VIVA**. Tem models, controllers, services (namespace `Kanban::`), migrations e código. É o "Kanban v2 / Monday-Projeto" real. 9 tabelas.
- **`kanban_*`** — implementação **MORTA/FANTASMA**. 6 tabelas (`kanbans`, `kanban_items`, `kanban_stages`, `kanban_automations`, `kanban_templates`, `kanban_views`). **Sem model, sem controller, sem migration no tree, sem referência em `app/`/`lib/`.**

### Estado físico das tabelas (medido)
| Ambiente | `funnel_*` | `kanban_*` |
|---|---|---|
| chatwoot_production (staging nesta box) | existem, com dados | **NÃO existem (0)** |
| chatwoot_test | existem | **existem (fantasma, via schema:load)** |
| `db/schema.rb` (v2026_07_02_160000) | presentes | **presentes (drift)** |

**Conclusão:** `kanban_*` é *schema drift* — entrou no `schema.rb` num merge (commit `2bee0f724`) sem migration correspondente no tree. O banco real (migrate) nunca as criou; o test DB (schema:load) criou. A ironia: o schema morto é mais robusto que o vivo (tem `position` decimal, `on_delete` explícito, uniques parciais, won/loss, aging).

### Volume de dados hoje (baixo → hora ideal para mexer)
funnels=11 · stages=29 · items=50 (47 c/ conversa, 3 cartão-tarefa) · custom_fields=2 · automations=0 · views=0 · notes=1 · metric_snapshots=141

---

## Problemas estruturais priorizados

| # | Severidade | Problema | Evidência |
|---|---|---|---|
| P0 | Alta | **Schema drift `kanban_*`**: 6 tabelas fantasma no schema.rb + test DB, zero uso. Todo ambiente novo via `db:schema:load` nasce com lixo. | schema.rb 1223-1342; 0 no prod, 6 no test |
| P1 | Alta | **`funnel_items` sem coluna `position`**: sem ordenação persistida de cartões na coluna; sort é só client-side e não sobrevive a reload. | schema.rb 998; [[kanban-wait-priority-feature]] |
| P2 | Média | **`funnel_items.assignee_id` com índice mas SEM FK**: usuário deletado deixa órfão sem nullify no nível do banco (0 órfãos hoje, mas sem garantia). | migration 20260701120000 usa `:bigint` puro |
| P3 | Média | **Valores de custom fields desnormalizados** em `conversations.custom_attributes` (`funnel_<id>_<key>`): sem integridade referencial; ao deletar um field os valores viram órfãos; cartão-tarefa (sem conversa) **não pode ter valores**. | FunnelCustomField#attribute_key |
| P4 | Baixa | **`funnel_templates` sem `account_id`**: catálogo só global; sem templates por conta (o morto `kanban_templates` tinha). | schema.rb 1041 |
| P5 | Baixa | **`moved_at precision: nil`**: usado como chave de resolução de conflito no realtime; baixa precisão pode empatar em movimentos rápidos. | schema.rb 1004 |
| P6 | Info | **Data migrations destrutivas irreversíveis** (`delete_all` sem down; NOT NULL não re-aplicado). Já aplicadas — só registrar. | 20260203180000, 20260701120000 |

---

## Plano por fases (staging-first, cada fase = 1 commit)

### Fase 0 — Baseline e segurança (sem mudança de schema)
- [ ] `pg_dump` das tabelas `funnel_*` do staging (backup lógico) antes de qualquer migration.
- [ ] Confirmar na **frota de produção** (via runbook, read-only) que `kanban_*` também têm 0 linhas / não existem — esperado, mas confirmar antes do P0.
- [ ] Rodar suite de specs do Kanban como baseline verde.

### Fase 1 — P0: Eliminar o schema drift `kanban_*`  ⭐ maior ganho, menor risco
Objetivo: `schema.rb` = realidade; nenhum ambiente novo nasce com tabelas mortas.
- [ ] Migration `drop_orphan_kanban_tables` com **`if_exists: true`** em cada `drop_table` (idempotente: no prod não faz nada, no test/dev limpa). Dropar na ordem de dependência (automations, items, views, stages, templates → kanbans).
- [ ] Guardar o `up` como referência caso alguém queira ressuscitar (as defs estão no git em schema.rb).
- [ ] `down` recria as tabelas a partir das defs do schema.rb (reversível).
- [ ] Rodar `db:migrate` → `schema.rb` regenera **sem** `kanban_*`.
- [ ] Limpar do test DB (`db:test:prepare`).
- **Risco:** baixíssimo — nada referencia essas tabelas. Ganho: fim da confusão e do lixo em envs novos.

### Fase 2 — P1: Ordenação persistida de cartões (`position`)
Objetivo: reordenação manual de cartões dentro da coluna sobrevive a reload; base para drag-and-drop real.
- [ ] `add_column :funnel_items, :position, :decimal, precision: 20, scale: 10` (fractional indexing — mesma escolha do morto `kanban_items`, permite inserir entre dois cartões sem renumerar).
- [ ] Índice `[funnel_stage_id, position]` para leitura ordenada por coluna.
- [ ] Backfill: numerar por `moved_at`/`created_at` dentro de cada stage.
- [ ] Endpoint de reorder no `funnel_items_controller` (ou estender o move) + persistir no drag-and-drop.
- [ ] Casar com o sort client-side de espera ([[kanban-wait-priority-feature]]): decidir precedência (espera vs manual) — provavelmente manual como override opcional.
- **Risco:** médio (toca UX de arrastar). Migration em si é aditiva e segura.

### Fase 3 — P2: FK de `assignee_id`
- [ ] `add_foreign_key :funnel_items, :users, column: :assignee_id, on_delete: :nullify` (concurrently, sem lock longo).
- [ ] Pré-check de órfãos (hoje 0 no staging) antes de aplicar; nullify manual se houver.
- **Risco:** baixo. Aditivo.

### Fase 4 — P3: Normalizar valores de custom fields (opcional/maior)
Só se a demanda de filtro/ordenação por custom field crescer, ou se cartão-tarefa precisar de custom values.
- [ ] Tabela `funnel_item_values` (`funnel_item_id` FK, `funnel_custom_field_id` FK, `value` jsonb, unique `[funnel_item_id, custom_field_id]`).
- [ ] Migração de dados: ler `conversations.custom_attributes['funnel_<id>_<key>']` → linhas.
- [ ] Ajustar controller/serializer para ler/gravar na tabela nova (com fallback de leitura ao jsonb durante transição).
- [ ] `on_delete: cascade` do custom field → valores somem junto (resolve órfãos).
- **Risco:** alto (toca leitura/escrita e migração de dados). Fazer só quando justificar; deixar desenhado aqui.

### Fase 5 — Polimentos P4/P5
- [ ] P4: `add_column :funnel_templates, :account_id` (nullable, FK, `is_official` bool) → templates por conta.
- [ ] P5: `change_column :funnel_items, :moved_at` para `datetime` com precisão (6) — cuidado com o realtime que usa `moved_at` como tiebreak.

---

## Ordem recomendada de execução
**Fase 0 → Fase 1 (P0)** já entrega o maior valor (schema limpo e confiável) com risco mínimo. Fases 2 e 3 são aditivas e seguras, entregam valor de produto (ordenação + integridade). Fase 4 é o item pesado — só sob demanda. Fase 5 é cosmético.

## Fora de escopo (decisões conscientes já tomadas, não são bugs)
- Namespace `Kanban::` em services/jobs operando sobre `funnel_*` — ok, é só naming.
- `moved_at` como fonte de "tempo em stage" — ok para a feature atual.

---

## LOG DE EXECUÇÃO — 2026-07-08 (staging `nicolas`, NÃO commitado)

**Fase 0 ✅** backup lógico `pg_dump` das 9 tabelas `funnel_*` (scratchpad); baseline de specs verde.

**Fase 1 (P0) ✅ — APLICADA no staging**
- Migration `20260708120000_drop_orphan_kanban_tables` — `up` idempotente (`if_exists`, ordem topológica: automations→items→views→stages→kanbans→templates, pois `kanbans`→`kanban_templates`); `down` recria as 6 tabelas + 14 FKs fiéis ao schema.rb (reversível, provado no test DB: up 6→0, down 0→6).
- `schema.rb` regenerado do test DB (dump desligado em prod/staging): diff = só bump de versão + −138 linhas `kanban_*`. Aplicada no staging (drop no-op, versão registrada). test DB limpo.

**Fase 3 (P2) ✅ — APLICADA no staging**
- Migration `20260708130000` FK `funnel_items.assignee_id → users on_delete: :nullify`, padrão baixo-lock (`validate: false` + `validate_foreign_key`). Pré-check: 0 órfãos.

**Fase 2 (P1) ✅ — APLICADA + DEPLOYADA no staging**
- Migration `20260708140000` add `position` decimal(20,10) + índice `[funnel_stage_id, position]` + backfill por recência DESC (`last_activity_at`→`moved_at`→`created_at`) ⇒ position ASC == ordem antiga (virada invisível). Backfill no staging: 56 itens, 0 em position 0, sem colisão por stage.
- Backend: `position` no serializer + `push_event_data`; policy `reorder?`; rota `POST .../funnel_items/reorder`; `FunnelItems::ReorderService` (renumera 1-based via `update_all`, não bumpa `moved_at`); controller action. Spec dedicado 5/5 verde; e2e no staging (transação com rollback) inverteu e restaurou.
- Front: ordem base por `position` no `KanbanColumn` (wait-priority sobreposto, position vira tiebreak); `moved` (reorder na mesma coluna) persiste via `reorderItems` (action otimista + rollback, mutation `SET_FUNNEL_ITEM_POSITIONS`, API `reorderItems`). vitest 13/13; eslint 0 erro.
- Build assets (NODE_OPTIONS 8GB) + `systemctl restart chatwoot.target`: app up (health 200, rota reorder 401).

**Decisões conscientes**
- Ordenação do backend (dedup/cursor/legacy) **intacta** → zero risco à paginação; a virada para `position` é só client-side. Caveat de escala: em colunas grandes o bastante para paginar (>~30/stage) as páginas são buscadas por recência mas exibidas por position — aceitável no volume atual (<2/stage), follow-up se crescer.
- **Drop cross-stage NÃO persiste a posição no destino** (evita corrida com a troca de stage); só reorder na mesma coluna persiste. Fine-tune manual no destino persiste. Follow-up se necessário.

**DEFERIDO** (conforme plano): Fase 4 (normalizar custom field values — pesado, só sob demanda) e Fase 5 (P4 `funnel_templates.account_id`; P5 precisão de `moved_at` — este mexe no tiebreak do realtime, risco > ganho cosmético).

**Pendente:** validação visual do usuário no board; commit (working tree, não commitado — [[commit-at-end-of-each-phase]]); promoção à frota só via [[runbook-deploy-producao]] (atenção: nova migration de drop + coluna).
