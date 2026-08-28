# Métricas separadas por número: Vendas × Locação

**Nível:** pleno · **Risco:** baixo — Fase 1 não tem migration e não muda nada para quem não usar o filtro
**Onde validar:** staging (`nicolas.chatspx.app`) antes da frota
**Estado (28/08/2026):** Fase 1 implementada e no ar no staging — roteiro em
`metricas-por-numero-VALIDACAO.md`. Fases 2 e 3 não começaram.

---

## O pedido

A imobiliária opera dois números de WhatsApp: **Vendas** (o que o Guilherme usa com os
corretores) e **Locação**. Hoje o módulo de Relatórios soma os dois: "conversas no período",
"tempo médio de primeira resposta", "ranking de atendentes" — tudo junto. Cada linha precisa
de números próprios, inclusive **por corretor dentro da linha**.

---

## Resposta curta

Não é preciso separar contas nem duplicar nada. **O corte certo é a caixa de entrada (o
número), e ele já está gravado em cada conversa e em cada evento de relatório.** Falta só
expor:

> um seletor **"Ver métricas de: [Todos os números ▾ | WhatsApp Vendas | WhatsApp Locação]"**
> na barra de filtros dos Relatórios, que atravessa **todas as abas** — e que, na Fase 2, já
> abre pré-selecionado conforme os números que a pessoa atende.

Consequência prática que vale ouro na conversa com o cliente: **o corte é retroativo**. No dia
em que o filtro subir, todo o histórico já se separa — sem backfill, sem migração e sem pedir
para ninguém etiquetar conversa nenhuma.

---

## Por que pelo número, e não pelas outras três saídas

| saída | o que resolveria | por que não |
|---|---|---|
| **Contas separadas** (uma de vendas, outra de locação) | isolamento total | duplica agente, etiqueta, resposta pronta, funil e configuração; o mesmo cliente que aluga hoje e compra amanhã vira dois contatos; o histórico não migra; obriga a trocar de conta o tempo todo. Caro e sem volta. |
| **Times** (Vendas / Locação) | a aba "Times" já existe | só conta conversa que **tem time atribuído** — vira disciplina de processo; e o corretor que atende os dois números continua misturado no próprio ranking |
| **Etiqueta** `vendas` / `locação` | flexível | depende de alguém marcar toda conversa; erra sempre uma fatia; **não vale para o passado** |
| **Filtro por número** ← recomendado | volume, tempos e ranking por linha, e por corretor dentro da linha | o dado já existe em 100% das conversas, é retroativo e não cria nenhum processo novo para quem atende |

O que sustenta a escolha, no banco: `conversations.inbox_id` e **`reporting_events.inbox_id`**
— este último já indexado (`index_reporting_events_on_inbox_id` e o composto
`account_id, name, inbox_id, created_at`) e preenchido em **todo** evento pelo
`app/listeners/reporting_event_listener.rb`. Ou seja, o corte é barato de consultar e não
depende de dado novo.

---

## Onde já corta por número, e onde falta

| aba de Relatórios | corta hoje? | onde |
|---|---|---|
| **Atribuições** | **sim** (time + caixa) | `components/AssignmentReports.vue`, `v2/reports/agent_assignment_builder.rb:47` |
| **CSAT / NPS / SLA** | **sim** (`inbox_id` no filtro) | `Csat/CsatFilters.vue`, `SLA/SLAFilter.vue`, `NetPromoterScoreReports.vue:142` |
| **Caixas** | sim, por definição | `InboxReports*.vue` |
| **Visão geral** (cards + tabela de agentes + tabela de times) | **não** | `summary_reports#agent/#team` → `v2/reports/base_summary_builder.rb` |
| **Conversas** (gráficos e CSV) | **não** | `reports#index` → `v2/reports/timeseries/*` |
| **Ao vivo / Em atendimento** | **não** | `live_reports_controller.rb`, `LiveReports::InServiceQueryService` |
| **Bot** | parcial (quebra por caixa, sem filtro) | `v2/reports/bot_metrics_builder.rb` |
| **PDF** | o resolver já aceita `filters[:inbox_id]` em parte dos relatórios | `services/reports/pdf_data_resolver.rb:154,256,648` |

O buraco maior é justamente a **Visão geral** — a tela que o dono abre primeiro.

---

## Fase 1 — o filtro atravessando o módulo (o essencial)

**Frontend**
- `reports/components/FilterSelector.vue` **já tem** a prop `showInboxFilter` e o componente
  `Filters/Inboxes.vue` — hoje usados só no NPS. Ligar nas demais telas e incluir `inboxId`
  no payload de `filter-change`.
- Telas a ligar: `Index.vue` (Conversas), `components/SummaryReports.vue` (Visão geral),
  `components/WootReports.vue` (agente/time/etiqueta), `LiveInService.vue`, `BotReports.vue`.
- **Persistir**: refletir na URL (`?inbox_id=`) e lembrar a última escolha. Sem isso o
  supervisor volta para o "tudo misturado" a cada visita.

**Backend** — o `inbox_id` entra como **filtro ortogonal**, não substitui o `type`:
- `V2::Reports::BaseSummaryBuilder` → `reporting_events` ganha `.where(inbox_id:)`; e o
  `fetch_conversations_count` de cada builder filho, idem.
- `V2::Reports::Timeseries::*` → nos `scope_for_*` (conversations, messages, reporting_events).
- `summary_reports_controller#prepare_builder_params` e `reports_controller#common_params`
  passam a permitir `inbox_id`.
- `live_reports_controller` + `LiveReports::InServiceQueryService`.
- CSV e PDF: repassar o recorte **e carimbar no título** ("Relatórios — WhatsApp Vendas").

Molde pronto para copiar: o `agent_assignment_builder.rb` já faz exatamente isso
(`scope.joins(:conversation).where(conversations: { inbox_id: ... })`).

---

## Fase 2 — cada um abre já no seu número

Hoje o Relatórios mostra a conta inteira para qualquer um que tenha permissão de ver
relatório. Com a Fase 2, quem não é administrador abre **pré-filtrado nas caixas de que é
membro** (`inbox_members`): o supervisor de locação não vê o número de vendas, e o Guilherme
entra direto no dele. Encaixa no trabalho de isolamento que já existe no fork.

> Esta fase **muda o que as pessoas enxergam** — precisa do "ok" do cliente antes.

---

## Fase 3 — grupos nomeados de números (só se precisar)

Se um dia houver mais de um número por linha (ex.: dois de vendas), o multi-seleção resolve
na unha, mas o certo é um grupo nomeado "Vendas" / "Locação". O modelo `Unit`
(`app/models/unit.rb:19`) **já agrupa caixas por filial** — o grupo por linha de negócio seria
o segundo eixo. **Não fazer agora**: com dois números, o seletor basta.

---

## Metas próprias por linha — isso já dá hoje

- **Horário comercial é por caixa** (e agora por unidade). O toggle "horário comercial" dos
  relatórios já mede cada número pela agenda dele — locação com um expediente, vendas com outro.
- **SLA** pode ter política diferente por número, então "responder em 15 min" na locação e
  "em 5 min" em vendas já é configurável.

---

## Armadilhas

1. **Dimensão única.** `V2::Reports::Timeseries::BaseTimeseriesBuilder#scope` trata `type` +
   `id` como *a* dimensão (conta OU caixa OU agente OU time OU etiqueta). Se o `inbox_id`
   entrar como mais um `type`, fica impossível pedir "o agente X, só no número de vendas" —
   que é o coração do pedido. Ele tem que ser **filtro**, aplicado por cima do `scope`.
2. **Números que não fecham.** Na Visão geral, a contagem de conversas vem de
   `conversations` e as médias vêm de `reporting_events`. Se o filtro entrar só em um dos
   dois, o card mostra "40 conversas" com um TMR da conta inteira. Filtrar **os dois**.
3. **Mensagens têm caixa própria.** `scope_for_incoming/outgoing_messages_count` usa
   `scope.messages` — o filtro vai em `messages.inbox_id`, não via conversa.
4. **`type: :inbox` + filtro de caixa** é redundante e pode se contradizer: na aba "Caixas",
   ignorar o filtro (ou esconder o seletor).
5. **O filtro precisa sobreviver ao reload** — ver Fase 1.
6. **Exportação sem recorte** é pior que não exportar: gera um PDF intitulado "Vendas" com o
   número da conta inteira.
7. **Limite honesto do corte:** se o corretor atender um cliente de vendas pelo número de
   locação, a conversa conta na linha errada. O corte é pelo **número**, não pela intenção. Se
   isso for frequente, aí sim entra etiqueta ou time como segundo eixo — não antes.

---

## Como provar (staging, conta do cliente)

```bash
cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner '
a = Account.find(ID_DA_CONTA)
r = 30.days.ago..Time.current
a.inboxes.each do |i|
  convs = a.conversations.where(inbox_id: i.id, created_at: r).count
  frt   = a.reporting_events.where(inbox_id: i.id, name: "first_response", created_at: r).average(:value)
  puts format("%-28s conversas=%-6d TMPR=%s", i.name, convs, frt&.round(0))
end
puts "sem caixa nos eventos: #{a.reporting_events.where(inbox_id: nil, created_at: r).count}"'
```

A soma por caixa tem que bater com o total da tela sem filtro, e a última linha tem que ser
**0** — se não for, existe evento sem caixa e o corte perde essa fatia.
