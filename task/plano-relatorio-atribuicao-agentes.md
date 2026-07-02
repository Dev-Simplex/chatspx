# Plano de Implementação — Relatório de Atribuições por Agente (ChatSPX)

> **Tipo:** Planejamento de engenharia (task completa, executável na VM de homologação)
> **Autor:** AIOX Master · **Data:** 2026-07-02
> **Ambiente alvo:** `homologacao` (VM `192.168.8.232`, user `chatwoot`, branch `homologacao`) → depois `producao`
> **Origem:** demanda do supervisor — medir carga de atribuição por pessoa, incluindo **quem atribui para quem**
> **Padrão seguido:** mesma "pegada" dos relatórios existentes (aba nova + CSV, espelhando o relatório **Agentes**). Ver `docs/plano-pdf-relatorios-spx.md` (arquitetura de relatórios) e `docs/plano-download-massa-midias.md` (migration additive segura).

---

## 0. Resumo executivo

Queremos uma **nova subtela na aba Relatórios — "Atribuições"** — que mostre, por agente e num período:

1. **Quanto foi atribuído _para_ a pessoa** (atribuições **recebidas**);
2. **Quanto a pessoa atribuiu _para os outros_** (atribuições **feitas**) — creditando os dois lados: quem atribuiu **e** para quem foi.

A infra de relatórios **já existe e é reaproveitável** (controller de sumário + builders que agrupam por agente + tabela genérica no front + export CSV). O relatório de Atribuições **espelha o relatório "Agentes"**.

**O único bloqueio real:** hoje o sistema **não guarda de forma consultável _quem_ fez a atribuição** — o autor só aparece como **texto livre** na mensagem de atividade ("Atribuído a X **por Y**"). Portanto o núcleo desta task é **adicionar um rastreio estruturado de atribuições** (o ator já está disponível em memória na hora — `Current.user` —, falta só persistir). Felizmente **já existe uma tabela dormente** (`conversation_assignment_histories`) praticamente pronta pra isso: basta **completá-la** (2 colunas + model + writer) em vez de criar do zero.

**Princípio:** rastreio mínimo estruturado → 1 builder novo (espelha `outgoing_messages_count_builder`) → 1 aba nova (espelha `AgentReportsIndex`). Sem tecnologia nova.

---

## 1. Estado atual (o que reaproveitar)

### 1.1. A aba Relatórios tem DUAS gerações (usar a "nova")
- **Nova (sumário/tabela)** — a que vamos espelhar:
  `AgentReportsIndex.vue` → `SummaryReports.vue` (tabela TanStack) → store **namespaced** `summaryReports` → `summary_reports_controller#agent` → `V2::Reports::AgentSummaryBuilder`.
- **Antiga (gráficos/timeseries)** — `AgentReports.vue` → `WootReports.vue` → store `reports` (não-namespaced) → `reports_controller`. Só relevante pra clonar a **rota de CSV**.

### 1.2. Backend — arquivos-espelho (NÃO recriar métrica/infra)
| Papel | Arquivo (espelhar) |
|---|---|
| **Builder "contagem por agente"** (melhor espelho) | `app/builders/v2/reports/outgoing_messages_count_builder.rb` (`build_by_agent`: agrupa por `sender_id`, junta nomes, devolve `[{id,name,count}]`) |
| Builder "agente + range" | `app/builders/v2/reports/agent_summary_builder.rb` (enumera `account.account_users`, filtra por range) |
| Base (SQL agrupado sobre eventos) | `app/builders/v2/reports/base_summary_builder.rb` (`COUNT(CASE WHEN name=…)` agrupado por `group_by_key`) |
| Controller (ação de sumário) | `app/controllers/api/v2/accounts/summary_reports_controller.rb#agent` (`render_report_with(...)`, `prepare_builder_params` = `{since, until, business_hours}`) |
| Rotas | `config/routes.rb` — coleção `summary_reports` (~L551-559) e coleção `reports` (~L560-576) |
| Presenter (segundos→humano p/ CSV) | `app/presenters/reports/time_format_presenter.rb` |
| CSV template | `app/views/api/v2/accounts/reports/agents.csv.erb` |
| Autorização | `app/policies/report_policy.rb` → `view? => administrator?` (**já cobre a ação nova; sem mudança**) |

### 1.3. Frontend — arquivos-espelho
| Papel | Arquivo (espelhar) |
|---|---|
| Subtela (entry) | `app/javascript/dashboard/routes/dashboard/settings/reports/AgentReportsIndex.vue` |
| Tabela genérica | `.../reports/components/SummaryReports.vue` (colunas, `downloadReports()`, filtros) |
| Filtro data/business-hours | `.../reports/components/OverviewReportFilters.vue` |
| Rotas | `.../reports/reports.routes.js` (bloco `revisedReportRoutes`) |
| **Abas visíveis** | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (`newReportRoutes()` ~L145 **e/ou** grupo "Reports" em `menuItems` ~L496) |
| Store | `app/javascript/dashboard/store/modules/summaryReports.js` (+ registro em `store/index.js`) |
| API | `app/javascript/dashboard/api/summaryReports.js` (`getAgentReports` → `GET /summary_reports/agent`) |
| CSV | `helper/downloadHelper.js` (`downloadCsvFile`) + ações `downloadXReports` em `store/modules/reports.js` |
| i18n | `i18n/locale/en/report.json` (`AGENT_REPORTS`/`SUMMARY_REPORTS`) + `i18n/locale/en/settings.json` (`SIDEBAR.*`) — **replicar em `pt_BR`** |

### 1.4. ⚠️ O GAP crítico — o "quem atribuiu" NÃO é persistido (mapeado 2026-07-02)
| Fonte | Guarda o ator (quem atribuiu)? |
|---|---|
| `reporting_events` | **Não.** Não há evento `conversation_assigned`. Em todo evento, `user_id` = `conversation.assignee_id` (o **receptor**), nunca o autor. |
| Mensagem de atividade | Só **texto livre**: i18n `assigned: 'Assigned to %{assignee_name} by %{user_name}'` (`config/locales/en.yml`). A activity **não tem `sender_id`** (`activity_message_job.rb`) → ator só existe embutido na string, dependente de locale. |
| Gem `audited` | Desligada p/ `assignee_id` (`enterprise/.../audit/conversation.rb`: `audited only: [], on: [:destroy]`). |
| Evento de domínio `assignee.changed` | É disparado (`assignment_handler.rb:64`, `auto_assignment/assignment_service.rb:91`) e consumido por listeners de notificação/cabo, **mas nenhum persiste o par ator→receptor**. |
| Tabela `conversation_assignment_histories` | **Existe no schema** (`db/schema.rb`) com `conversation_id, account_id, assignee_id, team_id, assigned_at, unassigned_at` — **mas sem coluna de autor, sem model e sem nenhum código escrevendo nela** (dormente). |

**Onde o ator ESTÁ disponível (só não é salvo):** no hook central de atribuição `app/models/concerns/assignment_handler.rb` (`after_commit :process_assignment_changes`), via `Current.user` (atribuição manual) e `Current.executed_by` = política/inbox (atribuição automática). **O ponto de escrita já existe; falta só o destino de persistência.**

---

## 2. Objetivo e requisitos

### 2.1. Requisitos funcionais
- **RF1** — Nova subtela **"Atribuições"** na aba Relatórios, com filtro de **período** (igual às outras).
- **RF2** — Tabela **por agente** com, no mínimo:
  - **Recebidas (total)** — atribuições em que a pessoa foi o destino.
  - **↳ Manuais** (atribuídas por outra pessoa) · **↳ Automáticas** (round-robin) · **↳ Auto-assumidas** (a própria pessoa se atribuiu).
  - **Feitas para outros** — atribuições em que a pessoa foi **o autor** e o destino foi **outra** pessoa. *(atende o 2º requisito: "quando uma pessoa atribui aos outros, contar para quem foi")*
- **RF3** — **Export CSV** (mesmo botão/fluxo dos outros relatórios).
- **RF4 (fase 2, opcional)** — **Matriz "Quem atribuiu → Para quem"** (linhas = autor, colunas = destino, célula = contagem), pra visualizar o fluxo de repasse.
- **RF5** — Filtros adicionais coerentes com os outros relatórios: **inbox** e **time** (opcional na v1).

### 2.2. Requisitos não-funcionais
- **RNF1** — **Zero impacto** no fluxo de atribuição existente: o writer roda em `after_commit`, idempotente, e **nunca** pode quebrar/atrasar a atribuição (rescue defensivo, best-effort).
- **RNF2** — **Migration additive e segura pro painel Deploy** (roda `db:migrate` na frota — additiva, sem lock pesado, sem destruir dados). Ver `docs/plano-download-massa-midias.md §5.2`.
- **RNF3** — Consultas do relatório **indexadas** (por `account_id + assigned_at`, `assignee_id`, `assigned_by_id`).
- **RNF4** — Autorização: **admin-only** (herda de `report_policy` sem mudança).
- **RNF5** — i18n completo **en + pt_BR**.

### 2.3. Fora de escopo (decisões de produto — NÃO incluir na v1)
- **Backfill histórico** de atribuições anteriores ao deploy (o histórico é **forward-only**). *(Opcional posterior: backfill best-effort parseando mensagens de atividade — frágil/locale-dependente; tratar como fase 3 se pedido.)*
- Métricas de **tempo até primeira resposta após atribuição** (já existe no relatório Agentes: `first_response_after_assignment`).
- Alterar a lógica de **round-robin** em si.
- PDF brandeado desta aba (encaixa depois no pipeline de `docs/plano-pdf-relatorios-spx.md`, como +1 relatório).

---

## 3. Decisão de arquitetura — fonte de dados

O requisito tem **dois lados**: *recebidas* (existe hoje) e *feitas por quem* (**não existe** — precisa de rastreio novo). Opções avaliadas para o rastreio do **autor**:

| Opção | Como | Prós | Contras | Veredito |
|---|---|---|---|---|
| **A. Ativar `conversation_assignment_histories`** (recomendada) | Add colunas `assigned_by_id` + `source`; criar model + writer no `assignment_handler`; builder agrupa por `assignee_id` (recebidas) e `assigned_by_id` (feitas) | Estruturado e consultável; dá o par autor→destino e a **matriz**; reusa tabela já existente (migration mínima); guarda intervalos (`assigned_at`/`unassigned_at`) | Forward-only (sem histórico pré-deploy) | ✅ **Escolhida** |
| B. Novo `reporting_event 'conversation_assigned'` | `ReportingEventListener#assignee_changed` grava evento | Reusa pipeline de eventos | `reporting_events.user_id` já significa "receptor/atribuído" — sobrecarregar pra "autor" quebra a convenção do `base_summary_builder`; contagem (não-tempo) destoa do shape `value:float` | ❌ |
| C. `reporting_event` só com receptor | grava `user_id = assignee` | Simples | **Não captura o autor** → não atende RF2/"feitas para outros" | ❌ insuficiente |

### 3.1. Tratamento do round-robin / automação (decisão importante)
Na atribuição **automática** não há autor humano (`Current.user` é `nil`; `Current.executed_by` = política/inbox). Decisão:
- `assigned_by_id = NULL` e `source = :auto_round_robin` (ou `:automation`/`:bot` conforme o executor).
- **"Feitas para outros"** conta **apenas atribuições manuais com autor humano** (`source ∈ {manual}` e `assigned_by_id` presente e ≠ destino).
- Auto-assign conta como **recebida automática** do destino, **sem creditar autoria** a ninguém.

### 3.2. Enum `source`
`{ manual: 0, self_assigned: 1, auto_round_robin: 2, automation: 3, bot: 4, api: 5, unknown: 6 }`
Derivado no writer a partir de `Current.user` / `Current.executed_by` (ver §4.3).

---

## 4. Modelo de dados

> Esqueletos de referência (scaffolding — **não é o código final**), no mesmo estilo de `docs/plano-download-massa-midias.md §5`.

### 4.1. Migration (additive, defensiva — segura pro painel Deploy)
```rb
# db/migrate/XXXXXXXXXXXXXX_complete_conversation_assignment_histories.rb
class CompleteConversationAssignmentHistories < ActiveRecord::Migration[7.1]
  def change
    # A tabela existe no schema.rb mas pode não existir em DBs antigos (nunca teve create_table).
    # Defensivo: cria se faltar, depois adiciona colunas se faltarem.
    unless table_exists?(:conversation_assignment_histories)
      create_table :conversation_assignment_histories do |t|
        t.bigint  :conversation_id, null: false
        t.bigint  :account_id,      null: false
        t.bigint  :assignee_id
        t.bigint  :team_id
        t.datetime :assigned_at
        t.datetime :unassigned_at
        t.timestamps
      end
    end

    add_column :conversation_assignment_histories, :assigned_by_id, :bigint      unless column_exists?(:conversation_assignment_histories, :assigned_by_id)
    add_column :conversation_assignment_histories, :source,         :integer, default: 6, null: false unless column_exists?(:conversation_assignment_histories, :source)

    add_index :conversation_assignment_histories, [:account_id, :assigned_at],   name: 'idx_cah_account_assigned_at'   unless index_exists?(:conversation_assignment_histories, [:account_id, :assigned_at])
    add_index :conversation_assignment_histories, :assignee_id                                                             unless index_exists?(:conversation_assignment_histories, :assignee_id)
    add_index :conversation_assignment_histories, :assigned_by_id                                                          unless index_exists?(:conversation_assignment_histories, :assigned_by_id)
  end
end
```
> ⚠️ **Gotcha de frota** (§14): confirmar se a tabela já existe em cada DB antes; a migration acima é idempotente/defensiva justamente por isso.

### 4.2. Model
```rb
# app/models/conversation_assignment_history.rb
class ConversationAssignmentHistory < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :assignee,   class_name: 'User', optional: true
  belongs_to :assigned_by, class_name: 'User', optional: true
  belongs_to :team, optional: true

  enum source: { manual: 0, self_assigned: 1, auto_round_robin: 2, automation: 3, bot: 4, api: 5, unknown: 6 }

  scope :in_range, ->(range) { where(assigned_at: range) }
end
```

### 4.3. Writer (o único ponto novo no fluxo de atribuição)
Chamado do hook central **já existente** `app/models/concerns/assignment_handler.rb` (`after_commit`, onde o ator está em mãos). Best-effort (RNF1).
```rb
# app/services/conversations/assignment_history_service.rb
class Conversations::AssignmentHistoryService
  def initialize(conversation); @conversation = conversation; end

  def record_change!
    now = Time.current
    # fecha o intervalo aberto anterior (se houver)
    ConversationAssignmentHistory
      .where(conversation_id: @conversation.id, unassigned_at: nil)
      .update_all(unassigned_at: now)

    assignee_id = @conversation.assignee_id
    return if assignee_id.nil? # unassign: só fechou o intervalo

    ConversationAssignmentHistory.create!(
      account_id:     @conversation.account_id,
      conversation_id: @conversation.id,
      assignee_id:    assignee_id,
      team_id:        @conversation.team_id,
      assigned_by_id: actor_id(assignee_id),
      source:         derive_source(assignee_id),
      assigned_at:    now
    )
  rescue StandardError => e
    Rails.logger.error("[assignment_history] #{e.message}") # nunca quebra a atribuição
  end

  private

  def actor_id(assignee_id)
    Current.user&.id # nil em auto-assign
  end

  def derive_source(assignee_id)
    return :self_assigned if Current.user && Current.user.id == assignee_id
    return :manual        if Current.user
    case Current.executed_by
    when AssignmentPolicy, Inbox then :auto_round_robin
    when AutomationRule          then :automation
    else :unknown
    end
  end
end
```
Ganho no `assignment_handler.rb` (dentro do `after_commit` que já detecta mudança de `assignee_id`):
```rb
Conversations::AssignmentHistoryService.new(self).record_change! if saved_change_to_assignee_id?
```

---

## 5. Especificação backend (relatório)

### 5.1. Builder — espelha `outgoing_messages_count_builder.rb`
```rb
# app/builders/v2/reports/agent_assignment_builder.rb
class V2::Reports::AgentAssignmentBuilder
  def initialize(account:, params:)
    @account = account
    @range   = params[:since]..params[:until] # unix → Time (igual aos outros)
  end

  def build
    rows = ConversationAssignmentHistory.where(account_id: @account.id).in_range(@range)
    received      = rows.group(:assignee_id).count
    received_auto = rows.where(source: :auto_round_robin).group(:assignee_id).count
    received_self = rows.where(source: :self_assigned).group(:assignee_id).count
    made_to_others = rows.where(source: :manual).where.not('assigned_by_id = assignee_id')
                         .group(:assigned_by_id).count

    @account.account_users.includes(:user).map do |au|
      uid = au.user_id
      total = received[uid].to_i
      {
        id:   uid,
        name: au.user.name,
        received_total:     total,
        received_auto:      received_auto[uid].to_i,
        self_assigned:      received_self[uid].to_i,
        received_manual:    total - received_auto[uid].to_i - received_self[uid].to_i,
        assigned_to_others: made_to_others[uid].to_i
      }
    end
  end
end
```

### 5.2. Controller — nova ação em `summary_reports_controller.rb` (espelha `#agent`)
```rb
# app/controllers/api/v2/accounts/summary_reports_controller.rb
def agent_assignment
  render json: V2::Reports::AgentAssignmentBuilder.new(account: Current.account, params: prepare_builder_params).build
end
```

### 5.3. Rota — dentro da coleção `summary_reports` (config/routes.rb ~L551)
```rb
resources :summary_reports, only: [] do
  collection do
    # ...agent, team, inbox, label, channel...
    get :agent_assignment
  end
end
```

### 5.4. CSV (opcional na v1 — mesmo padrão do relatório Agentes)
- Ação `agent_assignments` no `reports_controller.rb` (padrão CSV antigo) **ou** gerar o CSV no front a partir do JSON (mais simples). Se backend: `app/views/api/v2/accounts/reports/agent_assignments.csv.erb` (espelha `agents.csv.erb`) + helper em `reports_helper.rb`.

### 5.5. Autorização
Nenhuma mudança: `report_policy.rb#view? => administrator?` já cobre a ação nova.

---

## 6. Especificação frontend

### 6.1. Rota + subtela
- **Criar** `.../reports/AgentAssignmentReports.vue` (espelha `AgentReportsIndex.vue`): `ReportHeader` + tabela, ligada a `action-key="summaryReports/fetchAgentAssignmentReports"`, `summary-key="summaryReports/getAgentAssignmentReports"`.
- **Editar** `reports.routes.js` (`revisedReportRoutes`): child `path: 'assignment'`, `name: 'agent_assignment_reports'`, `component: AgentAssignmentReports`.

### 6.2. Tabela
- **Reusar** `components/SummaryReports.vue` com um `type="assignment"` novo **ou** criar `components/AssignmentReports.vue` (espelho enxuto) com as colunas de RF2. Preferir **reuso** se as colunas couberem no schema de colunas atual.

### 6.3. Store + API (namespaced `summaryReports`)
- **`api/summaryReports.js`**: `getAgentAssignmentReports({since,until})` → `GET /summary_reports/agent_assignment` (espelha `getAgentReports`).
- **`store/modules/summaryReports.js`**: entrada no `typeMap` + `fetchAgentAssignmentReports` (action) + `getAgentAssignmentReports` (getter) + mutation (espelha o wiring de `agent`). Sem novo módulo → **sem mexer no `store/index.js`**.

### 6.4. Aba visível (Sidebar)
- **Editar** `components-next/sidebar/Sidebar.vue`: adicionar o link em `newReportRoutes()` (~L145) **ou** nos filhos do grupo "Reports" em `menuItems` (~L496), apontando pra `accountScopedRoute('agent_assignment_reports')`.

### 6.5. CSV
- Botão "Exportar CSV" já vem do componente de tabela; ligar `downloadReports()` → `downloadCsvFile` (`helper/downloadHelper.js`). Se seguir o backend CSV, adicionar ação `downloadAgentAssignmentReports` em `store/modules/reports.js` (espelha `downloadAgentReports`).

### 6.6. i18n (en + pt_BR)
- `i18n/locale/en/report.json`: bloco novo `ASSIGNMENT_REPORTS` (header/description) + labels de coluna (ou estender `SUMMARY_REPORTS`).
- `i18n/locale/en/settings.json`: `SIDEBAR.REPORTS_AGENT_ASSIGNMENT` (⚠️ **não** reusar `AGENT_ASSIGNMENT` de L564 — esse é da *política* de atribuição, outra feature).
- **Replicar as mesmas chaves em `pt_BR`.**

---

## 7. Colunas do relatório (definição final)

| Coluna | Definição (no período, por `assigned_at`) |
|---|---|
| **Agente** | nome do `account_user` |
| **Recebidas (total)** | linhas com `assignee_id = agente` |
| ↳ **Manuais** | recebidas com `source = manual` (atribuídas por outra pessoa) |
| ↳ **Automáticas** | recebidas com `source = auto_round_robin` |
| ↳ **Auto-assumidas** | recebidas com `source = self_assigned` |
| **Feitas para outros** | linhas com `assigned_by_id = agente` e `assignee_id ≠ agente` (só `source = manual`) |
| *(fase 2)* **Matriz autor→destino** | contagem por par `(assigned_by_id, assignee_id)` |

Totais/rodapé: soma por coluna. Ordenação default: **Recebidas (total)** desc.

---

## 8. Limites e configuração (defaults propostos)
- Período máximo consultável: **igual aos outros relatórios** (sem novo limite).
- Retenção do histórico de atribuições: **indefinida** (linhas leves; reavaliar se a tabela crescer — candidata a rollup futuro como `reporting_events_rollup`).
- Sem feature flag por padrão (relatório é admin-only e aditivo). *(Opcional: gate por conta se quiser rollout gradual.)*

---

## 9. Edge cases (tratamento obrigatório)
1. **Round-robin/auto** → `assigned_by_id = NULL`, `source = auto_round_robin`; não credita autoria.
2. **Auto-atribuição** (pega pra si) → `source = self_assigned`; entra em "Auto-assumidas", **não** em "Feitas para outros".
3. **Desatribuir** (assignee → nil) → só fecha o intervalo (`unassigned_at`), não cria linha nova; não conta como recebida.
4. **Reatribuição** (A→B) → fecha intervalo de A, abre de B; conta 1 recebida pra B e 1 "feita" pro autor.
5. **Atribuição em massa / bulk_actions** → o autor é `Current.user`; garantir que `Current.user` esteja setado no fluxo de bulk (verificar `bulk_actions`).
6. **Automação/Macro** → `source = automation`; `assigned_by_id = NULL` (ou o user que disparou a macro, se disponível — decidir na implementação).
7. **Handoff do bot / Captain** → `source = bot`.
8. **Agente removido** (`account_user` deletado) → linhas históricas permanecem; o builder itera `account_users` atuais → agentes removidos **não aparecem** (documentar; opcional: incluir "ex-agentes" via `assignee_id` órfão).
9. **Mesma conversa atribuída várias vezes no período** → cada mudança é 1 linha (contagem por **eventos**, não por conversa distinta). *(Se o produto quiser "conversas distintas", usar `COUNT(DISTINCT conversation_id)` — decisão em aberto §Anexo.)*
10. **Fuso/limite de dia** → usar o mesmo `getUnixStartOfDay/EndOfDay` + `timezone_offset` dos outros relatórios.

---

## 10. Auditoria e segurança
- Admin-only (herdado). Escopo sempre por `Current.account` (multi-tenant).
- Writer é **best-effort** com `rescue` — falha de log **nunca** afeta a atribuição (RNF1).
- Nenhum dado sensível novo exposto (só contagens + nomes de agentes já visíveis ao admin).

---

## 11. Plano de testes

### 11.1. Specs (RSpec)
- `spec/services/conversations/assignment_history_service_spec.rb` — grava linha em atribuição manual (autor correto), self-assign (`self_assigned`), auto (`assigned_by_id nil`, `auto_round_robin`), desatribuir (fecha intervalo, sem linha), reatribuir (fecha+abre).
- `spec/builders/v2/reports/agent_assignment_builder_spec.rb` — recebidas/manuais/auto/self/feitas-para-outros com dados semeados no range; exclui fora do range; ignora self em "feitas".
- `spec/models/concerns/assignment_handler_spec.rb` — `after_commit` chama o service só quando `assignee_id` muda; não quebra se o service levantar.
- `spec/controllers/.../summary_reports_controller_spec.rb` — `GET agent_assignment` admin 200 / agente comum 403.

### 11.2. Manual (homologação — VM 8.232, depois 8.100/paulao antes de prod)
- Atribuir manual A→B, auto (round-robin), pegar pra si, reatribuir, desatribuir → conferir a tabela e os números na aba.
- Trocar o período e conferir recorte por data.
- Exportar CSV e conferir colunas/linhas.
- Verificar i18n pt_BR.

---

## 12. Fases, entregáveis e estimativa

| Fase | Entregável | Esforço | Risco |
|---|---|---|---|
| **F1 — Rastreio** | Migration defensiva + model + `AssignmentHistoryService` + gancho no `assignment_handler` + specs | ~0,5-1 dia | Baixo (aditivo, best-effort) |
| **F2 — Backend relatório** | `AgentAssignmentBuilder` + ação `agent_assignment` + rota + specs | ~0,5 dia | Baixo |
| **F3 — Frontend** | Subtela + rota + sidebar + store/api + i18n en/pt_BR + CSV | ~1-1,5 dia | Médio (reuso de `SummaryReports`) |
| **F4 (opcional)** | Matriz autor→destino + PDF brandeado | ~1 dia | Médio |

**Total v1 (F1-F3):** ~2-3 dias. Ordem obrigatória: **F1 antes de F2/F3** (sem dados, o relatório fica vazio — comportamento esperado forward-only).

---

## 13. Critérios de aceite
- [ ] Toda mudança de `assignee_id` grava 1 linha em `conversation_assignment_histories` com `assigned_by_id`/`source` corretos; falha do writer **não** afeta a atribuição.
- [ ] Aba **"Atribuições"** aparece na barra de Relatórios (admin), com filtro de período.
- [ ] Tabela por agente mostra **Recebidas (total/manuais/auto/auto-assumidas)** e **Feitas para outros** corretos.
- [ ] Round-robin conta como recebida automática e **não** credita autoria a ninguém.
- [ ] Export CSV funciona; números batem com a tela.
- [ ] i18n en + pt_BR; admin-only (agente comum recebe 403).
- [ ] Migration additive roda limpo (idempotente) — validada em homolog e no painel Deploy.

---

## 14. Rollout ⚠️
- **Migration é aditiva e defensiva** (create-if-missing + add-column-if-missing) → segura pro botão **Deploy** do painel (que roda `db:migrate` na frota). Ainda assim: **conferir antes** se `conversation_assignment_histories` já existe em cada DB (schema.rb tem a tabela, mas DBs antigos podem não ter — a migration cobre, mas validar em homolog primeiro). Ver `feedback_prod_restart_migration` (checar `db:migrate:status` antes de restart).
- **Ordem:** homologação (8.232) → validação humana → paulao/8.100 → producao (frota) → Tozi por último. `git push`/deploy = **@devops** (não empurrar por conta própria).
- **Sem downtime:** aditivo, sem lock pesado; o writer só passa a gravar após o deploy do código (forward-only).
- **Reversível:** desligar = remover o gancho no `assignment_handler` (as colunas/tabela ficam, inertes).

---

## Anexo — Perguntas em aberto (confirmar com o supervisor)
1. **Contagem por evento ou por conversa distinta?** Default proposto: **por evento** (cada atribuição conta). Se for "conversas distintas atribuídas", troca pra `COUNT(DISTINCT conversation_id)`.
2. **Automação/Macro credita o usuário que disparou** como autor, ou fica `automation` sem autor? Default: `automation` sem autor.
3. **Incluir ex-agentes** (removidos da conta) que ainda têm histórico? Default: **não** (só agentes atuais).
4. **Matriz autor→destino (RF4)** entra na v1 ou fica pra fase 2? Default: **fase 2**.
5. **CSV** gerado no backend (`.csv.erb`) ou no front (a partir do JSON)? Default: **front** (mais simples), a menos que queira paridade total com o relatório Agentes.
