# DESIGN — Enrollment, Conformidade e Analytics/Logs do motor de Automações (Canvas)

> Continuação do dossiê `plano/automacao-macros-pesquisa.md`. Este doc **não re-audita** o que já está lá (herança `ActionService`, paleta de ações/gatilhos/condições, pipeline `send_template`, matriz automação/macro/kanban). Ele projeta as **três camadas transversais** que o mockup `public/mockups/automacoes-canvas.html` já desenha na aba **Fluxo** e nos números dos ramos, mas que ainda não têm modelo de dados: **(1) entrada/reentrada/meta de saída**, **(2) conformidade WhatsApp**, **(3) logs de execução + métricas por ramo**, **(4) observabilidade de falhas**.
>
> **Descoberta que muda o custo do trabalho:** o motor de *enrollment* **já existe no código** — `MessageSequences::*` (migrations `20260625140000..140200`). Ele já modela: instância de contato percorrendo um fluxo, agendamento por `next_run_at` + scheduler de 1 min, enrollment idempotente com índice único parcial, e cancelamento por condição de saída (reply/status). **Não vamos criar isso do zero; vamos generalizar.** Abaixo cito os arquivos reais em cada decisão.

---

## 0. O que já existe (fundação verificada)

| Peça | Arquivo | O que já resolve |
|---|---|---|
| Instância "contato no fluxo" | `app/models/message_sequence_enrollment.rb` | `status {active,completed,cancelled}`, `current_step_position`, `next_run_at`, `enrolled_by_id`, scope `due` |
| Enrollment idempotente | `app/services/message_sequences/enroll_service.rb:20,36-38` | `already_enrolled?` (`enrollments.active.exists?(conversation_id:)`) + `rescue ActiveRecord::RecordNotUnique` contra corrida — **é o dedupe** |
| Scheduler (wait/delay/drip) | `app/jobs/message_sequences/advance_job.rb` + `config/schedule.yml` | roda a cada 1 min, `MessageSequenceEnrollment.due.find_each` → avança 1 passo; `with_lock` re-checa status/`next_run_at` (anti-duplo-envio) — `advance_service.rb:14-16` |
| Meta de saída (exit) | `app/models/message_sequence.rb:33-40` + `app/listeners/message_sequences/exit_listener.rb` | `exit_conditions` jsonb (`on_customer_reply`, `on_status`), cancela enrollment quando o cliente responde ou muda status |
| Envio reaproveitando pipeline | `app/services/message_sequences/advance_service.rb:36-46` | `ScheduledMessages::CreateService` com `template_params` → dispara `SendJob` que já cai no `Whatsapp::SendOnWhatsappService` do dossiê §2.2 |
| Janela 24h | `app/models/conversation.rb:187-189` → `Conversations::MessageWindowService` (`app/services/conversations/message_window_service.rb:9-13,27-28`) | WhatsApp = 24h desde a **última mensagem incoming** (`can_reply?`) |
| Horário comercial | `app/models/concerns/out_of_offisable.rb:13-19` (`Inbox#working_now?`/`out_of_office?`) + `app/models/working_hour.rb:49-65` (`open_now?`, timezone-aware) | teto por dia da semana, por inbox, no fuso da inbox |
| Precedente dedupe/cap/cancel de HSM | `app/services/spx/tozi/reactivation_cadence_service.rb:32-41,72-79` | `cadence_already_scheduled?`, `cancel_pending`, guard `cloud_api_inbox?` — o padrão de suppression que vamos generalizar |

**Leitura:** o canvas do dossiê §5-Opção 3 precisa de um `Flow` autocontido (nós+arestas) com estado entre execuções. Esse "estado entre execuções" é exatamente o `MessageSequenceEnrollment`. A generalização mínima é renomear o conceito para **`flow_run`** (instância de execução) e trocar "step_position linear" por "cursor de nó no grafo". Tudo o mais (scheduler, lock, exit listener, idempotência) é reaproveitado.

---

## 1. ENTRADA / REENTRADA / META DE SAÍDA

### 1.1 Modelo de dados — `flow_runs` (generaliza `message_sequence_enrollments`)

```
flow_runs
  id                bigint pk
  flow_id           bigint  fk flows            -- o fluxo/automação (dossiê §5-Op.1/3)
  account_id        bigint  fk accounts         -- denormalizado p/ scoping e agregação
  contact_id        bigint  fk contacts         -- SUPPRESSION/DEDUPE é por CONTATO (ver 1.3)
  conversation_id   bigint  fk conversations    -- conversa que originou/carrega a run (nullable p/ trigger agendado sem conversa)
  status            integer -- {active:0, completed:1, cancelled:2, failed:3}   (herda o enum + 'failed')
  exit_reason       integer -- {goal_met, opted_out, exhausted, manual, error, suppressed}   (nullable)
  current_node_id   string  -- cursor no grafo (era current_step_position); nil quando terminou
  next_run_at       datetime-- reaproveita scope `due` + AdvanceJob
  enrolled_by_id    bigint  -- User que disparou manualmente (macro-mode); nil p/ automático
  entered_at        datetime
  exited_at         datetime
  created_at / updated_at
```

Índices:
```sql
-- 1) DEDUPE de concorrência (o "1 vez ativo por contato"): mesmo papel do índice parcial
--    que o EnrollService já conta como "last line of defense" (enroll_service.rb:5-6)
CREATE UNIQUE INDEX idx_flow_runs_active_per_contact
  ON flow_runs (flow_id, contact_id) WHERE status = 0;   -- 0 = active

-- 2) scope `due` do scheduler (herdado de MessageSequenceEnrollment.due)
CREATE INDEX idx_flow_runs_due ON flow_runs (next_run_at) WHERE status = 0;

-- 3) histórico p/ política 'once' e p/ analytics por contato
CREATE INDEX idx_flow_runs_flow_contact ON flow_runs (flow_id, contact_id, status);
```

### 1.2 Entra 1x vs reentra — política no `Flow`, não na run

Campo no `flow`: `reentry_policy integer` — três valores, cobrindo o que o mockup mostra na aba Fluxo (`automacoes-canvas.html:399-404`, "Cada contato entra 1 vez" vs "Pode reentrar a cada nova conversa"):

| `reentry_policy` | Regra de admissão (no `EnrollService` generalizado) | Onde a decisão lê |
|---|---|---|
| `once` (default seguro p/ marketing) | Rejeita se **existe qualquer** `flow_run` desse `(flow_id, contact_id)` — inclusive `completed`/`cancelled`. "Entrou uma vez na vida, nunca mais." | `flow_runs.where(flow_id:, contact_id:).exists?` (usa índice 3) |
| `re_enroll` | Rejeita só se há run **ativa** (não-concorrente). Ao terminar, pode reentrar em nova conversa. É o comportamento atual do `EnrollService` (`already_enrolled?` só olha `.active`). | `flow_runs.active.where(flow_id:, contact_id:).exists?` |
| `re_enroll_after(cooldown)` | Rejeita se ativa **ou** se a última run terminou há menos de `reentry_cooldown_hours`. Anti-flood de reengajamento. | `max(exited_at)` da última run + cooldown |

> **Por que a chave é `contact_id` e não `conversation_id`:** o `EnrollService` atual deduplica por `conversation_id` (`enroll_service.rb:37`) porque uma sequência vive dentro de uma conversa. Mas reengajamento/marketing precisa impedir que o **mesmo cliente** entre por duas conversas simultâneas (WhatsApp abre conversa nova a cada janela). Suppression correta é **por contato na conta**. A conversa continua registrada em `conversation_id` para roteirizar ações (`send_template` precisa da conversa), mas a **unicidade** é `(flow_id, contact_id)`.

### 1.3 Suppression / dedupe — onde guardar

Duas camadas, ambas com precedente no código:

1. **Concorrência (mesma run duas vezes):** índice único parcial `idx_flow_runs_active_per_contact` + `rescue RecordNotUnique` no create — **cópia literal** de `enroll_service.rb:22-32`. Resolve corrida de dois eventos simultâneos.
2. **Suppression persistente (opt-out, cap atingido, "once" já rodou):** tabela dedicada `contact_flow_suppressions` (ver §2), consultada **antes** de criar a run. Isso separa "não pode reentrar neste fluxo" (histórico de `flow_runs`) de "não pode receber marketing nenhum" (opt-out global do contato).

Fluxo de admissão (pseudo, no `Flows::EnrollService`):
```ruby
return if suppressed?(contact)                      # opt-out global / cap diário (§2)
return unless reentry_allows?(flow, contact)        # política 1.2
return unless within_working_hours?(inbox) if flow.working_hours_only   # §2.4
FlowRun.create!(...)                                # índice único = rede de segurança
rescue ActiveRecord::RecordNotUnique; nil           # idempotente
```

### 1.4 Meta de saída (goal) — "sai quando respondeu / comprou / label"

Generaliza `message_sequence.exit_conditions` (`message_sequence.rb:33-40`) para um array de metas no `flow`:

```json
// flows.goal_conditions (jsonb)
{
  "on_customer_reply": true,
  "on_status": "resolved",
  "on_label": "comprou",
  "on_event": "order.created"
}
```

**Como avaliar — reusar o `ExitListener` que já existe** (`app/listeners/message_sequences/exit_listener.rb`), generalizado para `Flows::GoalListener`, registrado no `AsyncDispatcher` como os outros:

| Meta | Evento de sistema já existente | Handler |
|---|---|---|
| respondeu | `message.created` (incoming, não-activity) | `exit_listener.rb:11-18` — cópia direta: cancela runs ativas do contato com `exit_reason: :goal_met` |
| status (resolved/…) | `conversation.status_changed` | `exit_listener.rb:23-31` |
| label ("comprou") | `conversation.updated` + diff de labels (o listener de automação já observa isso, dossiê §1.3) | novo branch no listener: `conversation.label_list.include?(goal_label)` |
| comprou / evento externo | webhook/`order.created` (não existe ainda — P1 do dossiê §6) | ponto de extensão; MVP usa **label** aplicada pela integração |

Efeito da meta: `flow_run.update!(status: :completed, exit_reason: :goal_met, exited_at: now, next_run_at: nil)` — **idêntico** ao `cancel_matching` de `exit_listener.rb:40`, e cancela qualquer wait/drip pendente (o scheduler ignora runs não-`active`, `advance_service.rb:15`). É o que o mockup chama na aba Fluxo de "Sai quando cliente responder / comprar" (`automacoes-canvas.html:405-408`).

---

## 2. CONFORMIDADE WHATSAPP

Todas as quatro travas do mockup (`automacoes-canvas.html:409-415`) mapeadas para código existente ou tabela nova mínima.

### 2.1 Opt-out por palavra (PARAR / STOP) — remove do fluxo

**Modelo — `contact_flow_suppressions`** (também serve o cap diário, §2.2):
```
contact_flow_suppressions
  id, account_id, contact_id
  kind        integer  -- {marketing_opt_out:0, daily_cap:1, manual:2}
  flow_id     bigint   -- nullable: opt-out global (nil) vs supressão de 1 fluxo
  reason      string   -- 'keyword:PARAR', 'cap_reached', ...
  expires_at  datetime -- nil = permanente (opt-out); fim-do-dia = cap (§2.2)
  created_at
UNIQUE (account_id, contact_id, kind, flow_id)
```

**Detecção:** um listener em `message.created` incoming — mesmo gancho do `ExitListener` (`exit_listener.rb:11`). Se `message.content` casar (case-insensitive, trim) com a lista de keywords de opt-out da conta (`PARAR`, `STOP`, `SAIR`, `CANCELAR` — configurável), então:
1. Cria `contact_flow_suppressions(kind: :marketing_opt_out, flow_id: nil, expires_at: nil)`.
2. `FlowRun.active.where(contact_id:).update_all(status: :cancelled, exit_reason: :opted_out, next_run_at: nil)` — **remove de todos os fluxos**, reusando o padrão `cancel_pending` de `reactivation_cadence_service.rb:32-41`.

**Bloqueio na entrada:** `suppressed?(contact)` (admissão §1.3) faz `contact_flow_suppressions.where(contact_id:, kind: :marketing_opt_out).exists?`. Contato que deu STOP nunca mais é admitido em fluxo de marketing (mensagens UTILITY/atendimento não usam esta trava — a distinção é a `category` do template, §2.2).

### 2.2 Teto de templates de marketing / dia por contato

O mockup: "Máx. 1 template de marketing por dia / contato" (`automacoes-canvas.html:411`).

**Fonte da verdade da categoria:** o template resolvido carrega `category` (`MARKETING`/`UTILITY`/`AUTHENTICATION`) — vem de `channel.message_templates` e o front já lê isso (`WhatsAppTemplateParser.vue`, dossiê §2.2). O cap **só conta MARKETING**.

**Contagem — duas opções, recomendo a (B):**
- (A) *On-the-fly*: contar mensagens outgoing com `template_params` de categoria marketing nas últimas 24h daquele contato. Barato de implementar (query em `messages`), mas `additional_attributes.template_params` não guarda `category` hoje → exigiria join/reprocesso. Frágil.
- (B) **Contador materializado** reusando `contact_flow_suppressions` com `kind: :daily_cap` e `expires_at = fim do dia (fuso da inbox)`: ao enviar um template marketing pelo nó de envio, incrementa/insere. Na admissão e no nó de envio, `count(kind: :daily_cap, contato, expires_at > now) >= flow.daily_marketing_cap` bloqueia. Determinístico, sem varrer `messages`. Alinhado ao precedente `cadence_already_scheduled?`.

O teto é **por contato**, valor no `flow` (`daily_marketing_cap`, default 1) ou na conta (política global). Ao atingir, a run **não falha**: pausa (`next_run_at = amanhã`) ou pula o nó marcando o step-log como `skipped:cap` (§3), para não estourar quality rating (dossiê §6-P0).

### 2.3 Gestão AUTOMÁTICA da janela 24h no nó de envio — `can_reply?`

Este é o "diferencial de maturidade" do dossiê §3.2/§6-P0 (evitar o erro Twilio 63016). A lógica vive **no nó de envio** (o `send_message`/`send_template` do canvas), decidindo sozinho free-form vs template:

```ruby
# Flows::Nodes::SendService (roda no AdvanceService/ActionService)
if conversation.can_reply?          # app/models/conversation.rb:187 → MessageWindowService
  case node.strategy
  when 'prefer_freeform' then send_freeform(node.text)      # dentro da janela: texto livre (barato, sem custo HSM)
  when 'always_template' then send_template(node.template)  # marketing sempre via HSM aprovado
  end
else
  # FORA da janela de 24h: texto livre seria bloqueado pela Meta → só HSM reabre
  return log_skip(node, :no_template) if node.template.blank?   # observabilidade §4
  send_template(node.template)
end
```

- `can_reply?` já retorna `false` quando a janela WhatsApp (24h desde o último **incoming**) expirou (`message_window_service.rb:34-37,27-28`). **Não precisamos recalcular nada** — o nó só consulta.
- É exatamente o comportamento que o painel do mockup descreve: *"Template entrega dentro e fora da janela de 24h. Janela aberta? dá pra mandar como mensagem normal."* (`automacoes-canvas.html:357`).
- Reaproveita o pipeline de envio inteiro do dossiê §2.2 (o `send_on_whatsapp_service.rb:8` já faz `should_send_template = template_params.present? || !can_reply?`). Ou seja: o nó só precisa **preencher `template_params`** quando escolher template; o serviço de envio já respeita a janela por conta própria. A "gestão automática" é: **decidir qual conteúdo montar** e **avisar na UI** (badge "janela fechada → usando template").

### 2.4 Horário comercial (working hours da inbox)

Mockup: "Só disparar em horário comercial" (`automacoes-canvas.html:413-414`) e no nó Esperar "Respeitar horário comercial" (`:378`).

**Já existe pronto:** `Inbox#working_now?` (`out_of_offisable.rb:17-19`) → `working_hours.today.closed_now?` → `WorkingHour#open_now?` (`working_hour.rb:58-65`), **timezone-aware pela inbox** (`working_hour.rb:59`). Uso em dois pontos:

- **Admissão / trigger** (`flow.working_hours_only`): `return unless inbox.working_hours_enabled? && inbox.working_now?` no `EnrollService`. Fora do horário → não cria run (ou cria com `next_run_at` = próxima abertura, se quisermos enfileirar em vez de descartar).
- **Nó de envio / Esperar** (`node.respect_working_hours`): antes de enviar, se `inbox.working_now?` for falso, o `AdvanceService` re-agenda `next_run_at` para o próximo horário de abertura em vez de enviar — reusa o mecanismo `next_run_at` que o scheduler já drena (`advance_service.rb:48-56`). Zero infra nova; só um cálculo "próximo slot aberto" a partir do `weekly_schedule` (`out_of_offisable.rb:21-23`).

---

## 3. LOGS DE EXECUÇÃO + MÉTRICAS POR RAMO

### 3.1 Tabela `flow_step_logs` (exatamente o pedido)

```
flow_step_logs
  id            bigint pk
  flow_run_id   bigint  fk flow_runs      -- a instância (contato) — liga log→contato/conversa
  flow_id       bigint  fk flows          -- denormalizado: agregação por fluxo sem join
  account_id    bigint                    -- scoping/particionamento
  node_id       string                    -- id do nó no grafo (bate com data-node do canvas)
  node_type     string                    -- 'send_template','router','wait','ai_classify',... (facilita agregação por tipo)
  branch_key    string                    -- p/ router/AI: qual saída/ramo foi tomado ('comprar','suporte','sem_resposta')
  status        integer                   -- {ok:0, skipped:1, failed:2, waiting:3, entered:4}
  input         jsonb                     -- params resolvidos do nó (template name, vars, condição avaliada)
  output        jsonb                     -- resultado (message_id enviado, branch escolhido, valor extraído pela IA)
  error_code    string                    -- 'template_not_approved','empty_variable','outside_window_no_template','cap_reached'
  error_message text
  duration_ms   integer                   -- latência do nó (útil p/ nós de IA/webhook)
  created_at    datetime                  -- o timestamp pedido
```

Índices para as agregações da §3.3:
```sql
CREATE INDEX idx_fsl_flow_node_status ON flow_step_logs (flow_id, node_id, status);
CREATE INDEX idx_fsl_flow_branch      ON flow_step_logs (flow_id, node_id, branch_key);
CREATE INDEX idx_fsl_run              ON flow_step_logs (flow_run_id, created_at);
CREATE INDEX idx_fsl_errors           ON flow_step_logs (flow_id, error_code) WHERE status = 2;
```

**Quem grava:** cada nó, ao executar dentro do `Flows::AdvanceService`/`ActionService`, emite um `flow_step_logs` — um por passagem. O `entered` (status 4) marca "a run chegou neste nó"; `ok/skipped/failed` marca o desfecho. Isso dá o funil por nó (quantos entraram vs saíram por cada ramo). Volume: alto → ver retenção §3.4.

**Relação com o log que já existe:** hoje as ações de automação/macro têm apenas `rescue` silencioso por ação (dossiê §1.1) e não deixam rastro. `flow_step_logs` é o rastro que falta e é o que alimenta os números `142 · 38%` que o mockup já pinta nos ramos (`automacoes-canvas.html:284,290,297`).

### 3.2 Métricas por ramo — o que agregar

O mockup mostra em cada ramo do roteador `<entraram> · <%>` e o painel de IA lista as saídas que viram ramificações (`automacoes-canvas.html:362-365`). Definições:

| Métrica | Derivação de `flow_step_logs` / `flow_runs` |
|---|---|
| **Entraram no ramo** | `count(DISTINCT flow_run_id)` em `flow_step_logs WHERE node_id = <router> AND branch_key = <ramo> AND status = ok` |
| **% do ramo** | entraram_no_ramo / entraram_no_router |
| **Enviados** (nó send) | `count WHERE node_type='send_template' AND status=ok` |
| **Converteram** | `flow_runs count WHERE exit_reason = goal_met` atribuídos ao ramo (via `branch_key` do primeiro log da run) |
| **Erro** | `count WHERE status=failed` por `node_id`/`error_code` |
| **Opt-out** | `flow_runs count WHERE exit_reason = opted_out` |

### 3.3 Como agregar para mostrar no canvas — rollup, não COUNT ao vivo

Contar `flow_step_logs` a cada abertura do canvas não escala. Padrão: **tabela de rollup incremental** `flow_node_stats`, atualizada por job periódico (reusa a infra de scheduler que o `AdvanceJob` já usa) ou por trigger de contadores:

```
flow_node_stats            -- 1 linha por (flow, node, branch, dia)
  flow_id, node_id, branch_key, date
  entered_count, ok_count, skipped_count, failed_count, converted_count, opted_out_count
  updated_at
UNIQUE (flow_id, node_id, branch_key, date)
```

- **Escrita:** job `Flows::StatsRollupJob` a cada N min varre `flow_step_logs` novos (cursor por `id`/`created_at`) e faz `UPSERT ... ON CONFLICT DO UPDATE SET *_count = *_count + excluded.*` — agregação incremental barata.
- **Leitura do canvas:** o endpoint que serve os números dos ramos faz `SUM(...) GROUP BY node_id, branch_key` sobre `flow_node_stats` filtrando o range de datas do seletor. Instantâneo, pré-agregado. Um "número no ramo" = `SUM(ok_count)` daquele `(node_id, branch_key)`; o "%" = razão contra o total do nó-pai.
- **Realtime opcional:** para o mockup "ao vivo", contadores em Redis (incr por `flow:node:branch`) drenados para `flow_node_stats`. Não obrigatório no MVP.

### 3.4 Retenção

`flow_step_logs` cresce rápido (1 linha × nó × contato). Particionar por mês (`created_at`) ou purga via `Internal::RemoveStaleRedisSetJob`-style: manter logs detalhados 30-90 dias, manter `flow_node_stats` (pré-agregado, leve) indefinidamente para os gráficos históricos.

---

## 4. OBSERVABILIDADE DE FALHAS

O dossiê §2.4 lista os riscos exatos; aqui viram **eventos de log tipados + sinalização no canvas**. Regra herdada do código: falhas **não derrubam o fluxo** — são best-effort com `rescue` (`advance_service.rb:27-30`, `action_service` dispatch por-ação). A diferença é que agora **deixam rastro** (§3.1) em vez de sumir.

| Falha | Onde é detectada | `error_code` gravado | Como o nó reage | Sinal no canvas |
|---|---|---|---|---|
| **Template desaprovado/excluído** | `Whatsapp::TemplateProcessorService#find_template` casa `status=='approved'`; nil se ausente (dossiê §2.2, `template_processor_service.rb:21-27`) | `template_not_approved` | `status: failed`, **não envia** (hoje falha silenciosa em `send_on_whatsapp_service.rb:26`) | badge vermelho no nó + card "Template X reprovado — 12 execuções bloqueadas" no painel Fluxo |
| **Variável vazia** (`{{contact.name}}` → `""`) | validação **pré-envio** ao resolver `processed_params`: se alguma var obrigatória do template resolver p/ `""`/nil, a Graph API rejeita (dossiê §2.4 risco 2) | `empty_variable` (+ qual var no `input`) | `status: failed` **antes** de chamar a Graph (fail-fast, não queima quota) | destaque da variável faltante no preview do nó |
| **Fora da janela sem template** | nó de envio §2.3, `can_reply? == false && node.template.blank?` | `outside_window_no_template` | `status: skipped`, run continua/pausa | aviso "janela fechada, sem template — cliente não recebeu" |
| **Cap de marketing atingido** | §2.2 | `cap_reached` | `status: skipped`, re-agenda p/ amanhã | contador "N adiados pelo teto diário" |
| **Opt-out** | §2.1 | — (vira `exit_reason: opted_out` na run) | run cancelada | métrica de opt-out por fluxo |
| **Inbox não-WhatsApp / não-Cloud** | guard `cloud_api_inbox?` (`reactivation_cadence_service.rb:67-70`) | `unsupported_channel` | `status: skipped` no-op limpo | nó marcado "indisponível nesta inbox" (espelha guard de `assign_ai_agent`, dossiê §1.7) |

**Painel de saúde do fluxo (aba Fluxo):** agregação de `flow_step_logs WHERE status = failed GROUP BY error_code` no range selecionado → lista priorizada de "o que está quebrando", com deep-link para o nó. É o mesmo dado da §3.3, filtrado por `status=failed`. Um alerta proativo (Slack/e-mail admin) quando `failed_count` de um `error_code` cruza limiar em janela curta fecha o loop de observabilidade — reusa o padrão de logging `Rails.logger.error` que os services já emitem (`advance_service.rb:28`, `exit_listener.rb:20`).

---

## 5. RESUMO DE ENTREGÁVEIS (o que construir, em ordem)

| Item | Novo? | Reaproveita |
|---|---|---|
| `flow_runs` (+ índice único parcial por contato) | tabela nova (generaliza `message_sequence_enrollments`) | `EnrollService`, scope `due`, `AdvanceJob`, `with_lock` |
| `reentry_policy` + goal (`goal_conditions`) no `flow` | colunas novas | `MessageSequence#exit_conditions`, `ExitListener` → `Flows::GoalListener` |
| `contact_flow_suppressions` (opt-out + cap diário) | tabela nova | padrão `cadence_already_scheduled?`/`cancel_pending` |
| Detecção keyword STOP | listener novo (branch em `message.created`) | `ExitListener` gancho |
| Nó de envio com gestão 24h + working hours | lógica no `AdvanceService`/nó | `Conversation#can_reply?`, `Inbox#working_now?`, `next_run_at` re-schedule |
| `flow_step_logs` | tabela nova | — (é o rastro que hoje falta) |
| `flow_node_stats` + `StatsRollupJob` | tabela + job novos | infra de scheduler do `AdvanceJob` |
| Observabilidade de falhas | `error_code` tipado + painel | `find_template` nil, `rescue` best-effort existentes |

**Princípio-guia:** nenhuma das quatro camadas exige um motor novo. O *enrollment engine* (`MessageSequences::*`), a janela 24h (`can_reply?`), o horário comercial (`working_now?`) e o pipeline de envio de template (dossiê §2.2) **já existem**. O trabalho é **generalizar** de "sequência linear" para "grafo de nós" e **acrescentar as tabelas de compliance e de log** que dão as travas de conformidade e os números que o canvas já desenha.
