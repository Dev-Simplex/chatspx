# Kanban Chat SPX — Projeto "padrão monday" (clonar no bom sentido)

> Documento de projeto (produto + engenharia) para evoluir o Kanban de **conversas/atendimento** do Chat SPX (fork do Chatwoot) inspirado nas ferramentas úteis e inovadoras do monday.com. Base técnica: modelo `Funnel` / `FunnelStage` / `FunnelItem` + `ScheduledMessage` já existentes na branch `nicolas`.

---

## 1. Visão & princípios

### Onde queremos chegar
Transformar o Kanban de conversas num **centro de operação de atendimento** com a flexibilidade do monday.com — campos customizáveis, automações declarativas, dashboards ao vivo, IA de triagem e formulários que viram conversa — **sem perder a alma**: cada card é uma **conversa real de WhatsApp/Instagram/e-mail**, viva, respondível e com SLA. O monday gerencia tarefas abstratas; nós gerenciamos **gente conversando com gente**. Essa é a vantagem injusta: tudo que clonarmos deve servir ao atendente que precisa responder o cliente **agora**.

### Princípios
1. **Conversa em primeiro lugar.** Todo recurso novo deve facilitar responder/encerrar/escalar uma conversa, não virar um CRM genérico.
2. **Progressivo e atrás de flag.** Cada fase entra por `feature_flag`, validada em `nicolas.chatspx.app` antes da frota (regra dura do usuário).
3. **Preservar o que existe.** Cursor loading, dedupe por telefone BR, aging, WIP soft, automação open/resolved, policies team-aware — nada disso regride.
4. **Reaproveitar a casa.** ActionCable, Webhook, custom_attributes de Conversation, Pundit, Sidekiq já existem; estendemos antes de criar do zero.
5. **Esforço honesto.** Quick-wins de alto valor primeiro (campos custom, WIP persistido, card customizável, views salvas); o ambicioso (rule engine, dashboards, IA, Gantt) depois.

### O que **NÃO** copiar (fora de escopo)
- **Connect Boards / Mirror / Dependency entre boards** como mecânica central de planejamento de projeto — somos atendimento, não gestão de portfólio de tarefas. (Uma versão enxuta "vincular conversa ↔ registro de cliente" entra em diferenciais, mas não o motor de dependências em cascata.)
- **WorkDocs colaborativos multi-cursor em tempo real** — alto custo, baixo retorno para uma fila de atendimento; nota interna no card resolve 90%.
- **Timeline/Gantt como visão primária** — atendimento é fila/funil, não cronograma. Entra só como visão secundária opcional para negociações longas.
- **Map View / World Clock / Country / Vote / Color Picker manual** — nicho demais para o ROI agora.
- **Marketplace de apps de terceiros / GraphQL público** — complexidade de plataforma que não justifica para um fork.
- **Auto Number/Item ID como protocolo** — Chatwoot já tem `display_id` de conversa; não duplicar.
- **Agent Factory (workforce de agentes de IA autônomos)** — visão de longuíssimo prazo; começamos com blocos de IA pontuais e auditáveis.

---

## 2. Estado atual (resumo do inventário)

- **3 views**: Kanban (drag-drop entre stages), List (tabular) e Calendar (timeline de mensagens agendadas) — `KanbanBoard.vue`, `ListView.vue`, `CalendarView.vue`.
- **Automação por status**: stages com `automation_type` `'open'`/`'resolved'` movem a conversa automaticamente (`FunnelItems::MoveService#update_conversation_status` + callbacks `move_to_automated_stage` em `conversation.rb`).
- **Automação por team**: atribuir team move a conversa para o funil do team (`Kanban::MoveConversationToTeamFunnelService`).
- **Performance madura**: cursor-based pagination (`kanban_cursor_loading`), lazy load por stage com IntersectionObserver, bulk fetch de last_message via `DISTINCT ON` (`Kanban::FunnelItemsQueryService`).
- **Aging visual**: heat levels 24h/72h (sem atividade) e 5d/10d (tempo no stage) em `composables/useStageColor.js`; **decorativo, sem alertas/ações**.
- **WIP limits soft**: apenas `localStorage` (`kanban:wip`), não persistidos no banco.
- **Bulk move** + Move modal + Preview modal + Reassign no card (otimista) já existem.
- **Scheduled Messages**: feature completa e isolada (`ScheduledMessage`, drawer, composer) — **não integrada às automações de stage**.
- **Filtros**: query, stageIds, labelIds, assigneeId, status — **não há views salvas/persistidas**.
- **Dedupe inteligente** por telefone BR normalizado e policies Pundit team-aware (`funnel_policy.rb` etc.).
- **Lacunas-chave**: sem campos custom, sem rule engine declarativo, sem dashboards/relatórios in-board, sem real-time broadcast (ActionCable pronto mas não usado), sem WorkForms, sem IA, sem `settings` JSON em Funnel/FunnelStage.

---

## 3. Catálogo de ferramentas-alvo (monday → Chat SPX)

> Esforço: **P** (pequeno, dias) · **M** (médio, 1–2 semanas) · **G** (grande, 3+ semanas / fundação nova). Inovação conforme catálogo de pesquisa.

### Views

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Views salvas (filtros+sort+group persistidos) | Recortes nomeados e fixados do board | "Minhas urgentes", "SLA estourando", "Sem resposta 24h" por agente; nova model `kanban_view` reusando JSON de filtro existente | média | M |
| Filtros avançados (AND/OR) | Multi-condição combinável | "canal=WhatsApp E prioridade=alta E (sem agente OU aguardando)" sobre `viewFilters` em `KanbanFilterSelect.vue` | média | M |
| Groups (agrupamento horizontal) | Seções colapsáveis dentro do board | Segunda dimensão: agrupar cards por dia de entrada / campanha / faixa de SLA mantendo as colunas de stage | média | M |
| Main Table View | Grade densa estilo planilha com sumários | Triagem em massa, edição rápida de vários campos, export — evolução do `ListView.vue` com sort/group | média | M |
| Cards View (galeria rica) | Cards grandes não-por-status | Modo galeria de conversas (avatar, última msg, valor) para telas amplas; toggle no `KanbanIndex.vue` | média | P |
| Kanban View (coração) | Cards em colunas por status, drag muda status | **Já existe** — base do produto (`KanbanBoard.vue`) | média | — |
| Calendar View | Itens com data num calendário | Follow-ups/retornos prometidos num calendário (evolui `CalendarView.vue` p/ datas de card, não só agendadas) | alta | M |
| Chart View (dashboards in-board) | Gráficos a partir das colunas | Conversas por estágio/agente/motivo, conversão do funil, tempo médio por etapa | alta | G |
| File Gallery View | Galeria única de todos os anexos | Mural de comprovantes/prints/PDFs do funil — **casa com a galeria/download em massa já existente** | alta | M |
| WIP Limits / Deadline Mode | Teto por coluna + destaque de atrasados | **WIP já existe em soft/localStorage**; persistir no banco + destaque de SLA furado | alta | P |
| Timeline / Gantt View | Barras início→fim por item | Visão secundária p/ negociações longas (abertura→previsão de fechamento) | baixa | G |
| Conditional coloring | Linhas/células coloridas por regra | Card muda de cor sozinho por aging/SLA (verde/amarelo/vermelho) — **estende `useStageColor.js`** | alta | P |
| Item Card / peek panel customizável | Painel sobreposto com campos escolhidos | **Já existe** `ConversationPreviewModal.vue`; tornar campos exibidos configuráveis | média | P |

### Colunas / Campos customizáveis

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Status/Label/Priority Column | Rótulos coloridos = colunas do Kanban | **Já é** o motor: cada `FunnelStage` é um label | média | — |
| People / Person Column | Atribui membro com avatar | **Avatar do agente já no card**; permitir atribuir arrastando + filtrar "minhas" | alta | P |
| Numbers Column | Campo numérico com soma/média no rodapé | Valor potencial da venda / score; agregar R$ por coluna do funil | alta | M |
| Text / Long Text Column | Texto curto / notas longas | Apelido, nº pedido, tag livre / resumo interno da conversa no card | baixa/média | P |
| Dropdown / Tags Column | Multi-seleção / tags transversais | Motivo do contato, produto, departamento; **tags reusam labels do Chatwoot** | média/alta | M |
| Date / Hour Column | Data/hora por item | Prazo de retorno prometido, melhor horário p/ contato | média | P |
| Formula Column | Calcula de outras colunas sem gravar | Tempo de espera (agora − última resposta), score de prioridade, classe SLA | alta | M |
| Progress / Battery Column | Barra de % concluído | Avanço no checklist de atendimento (qualificação→proposta→fechamento) | alta | M |
| Rating Column | Estrelas 1–5 agregáveis | CSAT / nota de qualidade do supervisor no card | média | P |
| Phone / Email / Link Column | Telefone, e-mail, URL clicáveis | **Telefone com 1-clique WhatsApp/ligar**; link do pedido/proposta no card | alta/média | P |
| Files Column | Anexa arquivos ao item | Comprovantes vinculados ao card → alimenta a File Gallery | média | M |
| Checkbox / Check Column | Booleano feito/não-feito | Checklist obrigatório: "consentimento LGPD", "contato confirmado" | baixa | P |
| Time Tracking Column | Cronômetro start/stop por pessoa | Handling time (AHT) por agente/conversa, base de produtividade | alta | M |
| Last Updated / Creation Log | Quem/quando alterou ou criou | **Aging já usa isso**; expor "parado há X" e marca de abertura/SLA 1ª resposta | alta/média | P |
| Button Column | Botão dispara ação/automação | "Encerrar", "Escalar", "Agendar follow-up" direto no card | alta | M |
| Combo Columns (Date+Status etc.) | Funde 2 infos numa célula | Prazo+status ou duração+valor compacto no card | média | M |
| Location Column | Endereço com mapa | Região do cliente p/ roteamento (sem Map View completo) | média | M |

### Automação

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Recipes When/Then (trigger-condição-ação) | Builder visual de regras | **Fundação nova**: rule engine sobre `funnel_stages.settings` / `funnel_automations`; "quando entra na coluna X e prioridade=alta, notificar" | alta | G |
| Status-change automation | Mudança de status move/ação | **Já existe** open/resolved; generalizar p/ qualquer transição | alta | M |
| Move item to group/board | Avança/roteia item | Avançar stage automaticamente ou rotear p/ outro funil/team | média | M |
| Date-based / deadline (motor SLA) | Trigger por data/prazo | "X h após 1ª resposta sem resolução → escalar"; alerta antes de estourar SLA | alta | M |
| Recurring / scheduled | Varredura periódica do board | A cada hora, conversa parada >2h em "Em atendimento" → notificar supervisor (Sidekiq) | média | M |
| Action chaining | Um trigger, várias ações | Ao resolver: mover + taguear + notificar + disparar CSAT num evento só | média | M |
| Notify person / owner | Notifica pessoa/owner/time | Avisar agente quando card muda de stage; avisar time em conversa nova sem dono | alta | P |
| Alerts & reminders | Lembretes agendados | Lembrete p/ retomar "Aguardando cliente" parado; follow-up pendente | média | P |
| Escalation (prioridade+prazo) | Move p/ "Urgente" + notifica gestor | SLA de alta prioridade perto de estourar → coluna "Urgente" + avisa supervisor | alta | M |
| Assign owner / round-robin | Atribuição automática | Distribuir conversas novas em rodízio entre agentes; por estágio/tag | alta | M |
| Button-triggered | Botão na linha dispara recipe | "Assumir"/"Escalar"/"Reabrir" com efeito automatizado | média | M |
| Batch / Bulk actions | Ação em vários itens | **`bulk_move` já existe**; somar bulk_reassign/bulk_tag/bulk_archive | média | P |
| SLA Column / Monitor | Alvo por prioridade, status Dentro/Violado | SLA de 1ª resposta e resolução por stage; vermelho em risco; % cumprimento | alta | M |
| Time in Status | Tempo em cada coluna | **Aging já começou**; expor como métrica de gargalo | alta | P |

### IA

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| AI Summarize / resumo de thread | Condensa histórico | Resumo da conversa no card p/ assumir sem ler tudo; handoff de turno | alta | M |
| AI Categorize / Classify | Classifica tipo/urgência | Auto-classificar conversa nova → coluna/funil certo | alta | M |
| AI Detect Sentiment | Tom emocional | Pintar card por sentimento; cliente irritado → priorizar/escalar | alta | M |
| AI Writing Assistant | Gera rascunho de resposta | Sugerir resposta/rascunho no card; msg-padrão por estágio | alta | M |
| AI Extract Info | Estrutura dados não-estruturados | Extrair CPF/pedido/CNPJ do texto/anexo → preencher campos custom | alta | M |
| AI Translate | Traduz no board | Traduzir conversa de cliente estrangeiro p/ o agente | média | M |
| AI-powered columns | Coluna que se auto-preenche | "Sentimento"/"Categoria"/"Resumo" por conversa, filtrável no Kanban | alta | G |
| AI-powered automations | Trigger + bloco IA | Toda conversa nova: resumida + classificada + sentimento na entrada | alta | G |
| AI Service Agent / auto-reply | Responde dúvidas comuns, escala difíceis | Triagem autônoma de conversas repetitivas com nível de confiança | alta | G |

### Dashboards / Relatórios

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Numbers Widget | Número-chave com variação vs período | Cartões: abertas, resolvidas hoje, novas, tempo médio de resposta | média | M |
| Chart Widget | Gráficos configuráveis | Volume por estágio/agente/canal/dia; tendência de resolução | média | G |
| Battery Widget | Barra de proporção por status | Saúde do funil: % resolvido vs atendimento vs aguardando | alta | M |
| Workload Widget / View | Carga × capacidade por pessoa | Quem tem conversas demais vs livre; rebalancear em tempo real | alta | G |
| Time in Status / Aging report | Tempo por coluna, gargalos | Relatório de aging do funil — **estende dados já calculados** | alta | M |
| Goals / Objectives Widget | Metas vinculadas a KPI | "X resolvidas/dia", NPS alvo, tempo de 1ª resposta com progresso | alta | M |
| Baselines | Snapshot de referência vs real | Comparar volume/tempos atuais vs média histórica (benchmark) | alta | G |
| Capacity / Workload Planning | Capacidade semanal por pessoa | Dimensionar turnos por carga prevista; antecipar picos | alta | G |
| Activity Log / Tracker | Timeline auditável de ações | Quem assumiu/transferiu/resolveu/reabriu cada conversa | média | M |
| Pivot Table / Advanced Reporting | Tabela dinâmica multi-dimensão | Conversas por agente × canal × motivo | alta | G |
| Live Dashboards | Widgets ao vivo | Painel reflete a fila em tempo real — **casa com real-time já no Kanban** | média | M |
| Portfolio / Multi-board Roll-up | Consolida vários boards | Roll-up de inboxes/filiais p/ gestor regional | alta | G |
| Mobile Dashboards | Métricas no celular | Supervisor acompanha fila/SLA fora do escritório | média | M |

### Colaboração

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Updates (feed no item) | Discussão em contexto no item | Notas internas no card sem poluir o chat com o cliente — memória da conversa | média | M |
| @menções a pessoas/equipes | Puxa pessoa via @, notifica | "@joao caso de retenção" sem transferir o ticket | média | M |
| Reações em updates | 👍 sem escrever resposta | Supervisor confirma que viu a nota com 👍 | baixa | P |
| Inbox / sino de notificações | Central do que exige atenção | **Chatwoot já tem sino**; alimentar com eventos de Kanban | baixa/média | P |
| Checklists em updates | Sub-passos marcáveis | Protocolo de atendimento dentro do card | baixa | P |
| Board permissions granulares | Editar próprios vs ver colegas | **Casa com o isolamento de msg por agente já existente**; permissão por stage | alta | M |
| Shareable boards & guests | Convidados externos só num board | Parceiro/terceirizado vê e comenta só um funil | média | M |
| Real-time (broadcast de moves) | Outro user move → atualiza ao vivo | **ActionCable pronto**; `kanban_channel` + broadcast em `MoveService` | média | M |

### Forms

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| WorkForms (form público → item) | Submissão vira item no board | Form público de intake → cria **conversa+card** na 1ª coluna já preenchido | alta | G |
| Form View | Form embutido do board | Captura/pré-atendimento que cria card "Novo" com triagem | alta | M |
| Template Center | Funis prontos por caso de uso | Templates: suporte/retenção/cobrança/pós-venda em 1 clique | média | M |

### Integração

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Webhooks (saída/entrada) | Evento → sistema externo e vice-versa | Cada move de card notifica sistemas SPX — **reusa Webhook model** | alta | P |
| Twilio / WhatsApp / SMS | Notifica cliente por evento | Cliente recebe WhatsApp/SMS em mudança de estágio | alta | M |
| Slack integration | Posta no Slack em eventos | Avisar plantão de conversa urgente/escalada | média | M |
| Gmail / e-mail | E-mail por evento; e-mail→item | "Seu chamado foi resolvido" ao mudar stage | média | M |
| Connect Boards (enxuto) | Liga itens de boards diferentes | Vincular conversa ↔ registro de cliente/pedido (sem motor de dependências) | alta | M |
| Zapier / Make / n8n | 9.000+ apps no-code | Funil → ERP/planilha/BI por evento | média | M |
| Embed widget / iframe | Embute qualquer coisa na view | CRM do cliente ao lado do funil sem trocar de aba | média | M |

### UX / Mobile

| Ferramenta | O que faz no monday | Como fica no Chat SPX | Inovação | Esforço |
|---|---|---|---|---|
| Drag-and-drop avançado | Arrasta cards, colunas e grupos | **Cards já arrastam**; reordenar/renomear colunas livremente | média | P |
| Multi-select drag | Seleciona e move vários | Shift/Cmd-click + mover lote (state em store kanban) | média | M |
| Atalhos de teclado | Shift+? / navegação rápida | Power-user navega o funil sem mouse | média | M |
| Dark mode | Tema escuro | Conforto em turnos longos/noturnos | baixa | M |
| Busca avançada / quick search | Varre itens/updates/arquivos | Achar conversa por nome/telefone/assunto entre milhares de cards | média | M |
| Cards View mobile | Galeria no app móvel | Supervisor acompanha funil pelo celular | média | M |

---

## 4. Roadmap faseado

Ordenado por **valor × esforço**: quick-wins primeiro, fundações ambiciosas depois. Cada fase entra atrás de feature flag e é validada em `nicolas.chatspx.app` antes da frota.

### Fase 1 — Quick-wins visuais e de organização (flag `kanban_v2_basics`)
**Objetivo:** ganhos imediatos de produtividade sem schema pesado nem fundação nova.
**Features:** WIP persistido + Deadline Mode; Conditional coloring por SLA/aging; People-column (atribuir arrastando + filtro "minhas"); Cards View (galeria); peek panel com campos configuráveis; drag de colunas (reordenar/renomear); reações 👍 em notas.
**Backend:**
- Migration `add_settings_to_funnel_stages` (jsonb `settings` default `{}`) para guardar `wip_limit`, cores condicionais e flags por stage.
- `app/models/funnel_stage.rb`: `store_accessor :settings, :wip_limit, ...`.
- `app/views/api/v1/models/_funnel_stage.json.jbuilder`: expor `settings`.
- `app/controllers/api/v1/accounts/funnel_stages_controller.rb`: permitir `settings` no strong params.
**Front:**
- `composables/useStageColor.js`: estender heat → cor condicional por SLA.
- `KanbanColumn.vue`: WIP do banco + destaque "Deadline Mode"; drag de coluna.
- `KanbanCard.vue`: atribuir arrastando, badge de "parado há X".
- `KanbanIndex.vue`: toggle Cards View.
- `ConversationPreviewModal.vue`: campos exibidos configuráveis.
**Riscos:** baixo; principal é não regredir o WIP em localStorage (migrar suave). 
**Pronto quando:** WIP persiste no banco, cores reagem a SLA/aging, atribuição por drag funciona, e Cards View carrega com a mesma paginação cursor.

### Fase 2 — Campos customizados por card (flag `kanban_custom_fields`)
**Objetivo:** dar ao card a flexibilidade de colunas do monday sem inchar a tabela de conversas.
**Features:** Text/Long Text, Numbers (com agregação por coluna), Date/Hour, Dropdown/Tags, Checkbox, Rating, Phone/Email/Link, Files, Progress/Battery; Combo columns; render configurável no card.
**Backend:**
- Migration `create_funnel_custom_fields` (definição por funil: `funnel_id`, `key`, `label`, `field_type`, `options jsonb`, `position`, `show_on_card`).
- Valores em `conversations.custom_attributes` (campo já existente) namespaced por funil — **sem nova tabela de valores** no MVP.
- `app/views/api/v1/models/_funnel_item.json.jbuilder`: renderizar `custom_attributes` filtrados pelas defs do funil.
- Novo controller `api/v1/accounts/funnels/custom_fields_controller.rb` (CRUD de definições) + rota aninhada em `funnels`.
- Agregação numérica em `Kanban::FunnelItemsQueryService` (soma/média por stage no rodapé).
**Front:**
- `FunnelForm.vue`: editor de campos custom do funil.
- `KanbanCard.vue`: render dos campos `show_on_card`.
- `ConversationPreviewModal.vue`: edição inline dos valores.
- Novo `KanbanCustomFieldEditor.vue`.
**Riscos:** médio — schema de `custom_attributes` é livre; validar tipos no backend e evitar N+1 na agregação (já há padrão de bulk fetch).
**Pronto quando:** gestor define campos por funil, agente preenche no preview, card mostra os marcados, e rodapé da coluna soma os numéricos.

### Fase 3 — Views salvas, filtros avançados e bulk actions (flag `kanban_saved_views`)
**Objetivo:** cada agente abre seu recorte sem reconfigurar; supervisor opera em massa.
**Features:** Views salvas; filtros AND/OR; Groups (2ª dimensão); Main Table View com sort/group/export; bulk reassign/tag/archive; busca avançada.
**Backend:**
- Migration `create_kanban_views` (`account_id`, `user_id` opcional, `name`, `filters jsonb`, `is_shared`).
- Controller `api/v1/accounts/kanban_views_controller.rb` (CRUD) + rotas.
- `app/controllers/api/v1/accounts/funnel_items_controller.rb`: estender com `bulk_reassign`, `bulk_tag`, `bulk_archive` (irmãos do `bulk_move` existente).
- Service `app/services/funnel_items/bulk_update_service.rb`.
- `Kanban::FunnelItemsQueryService`: suportar agrupamento e filtro composto.
**Front:**
- `KanbanIndex.vue`: dropdown de views + "Salvar como view".
- `KanbanFilterSelect.vue`: builder AND/OR.
- `ListView.vue` → Table View com sort/group/export CSV.
- `KanbanBoard.vue`: seleção múltipla + menu de ações em massa.
- store `kanban/mutations.js`/`actions.js`: estado de seleção e views.
**Riscos:** médio — bulk em milhares de cards; paginar a operação e respeitar policies por item.
**Pronto quando:** views persistem por usuário, filtro composto funciona, e ações em massa respeitam Pundit.

### Fase 4 — Real-time, colaboração e notificações (flag `kanban_realtime`)
**Objetivo:** board vivo e colaborativo, sem refresh.
**Features:** broadcast de moves (ActionCable); Updates/notas internas no card; @menções; sino alimentado por Kanban; Activity Log por card; checklists em update; permissão por stage.
**Backend:**
- `app/channels/kanban_channel.rb` (broadcast `funnel:<id>`).
- Broadcast em `FunnelItems::MoveService#perform` após `save!`.
- Reusar `notes`/`messages` privadas existentes para Updates ou nova `funnel_item_notes`.
- Listener `app/listeners/kanban_listener.rb` → eventos de notificação + Activity Log.
- `funnel_item_policy.rb` / `funnel_stage_policy.rb`: regra "só admin move p/ stage X".
**Front:**
- `KanbanBoard.vue`: hook de subscribe + consumo de broadcast com conflict resolution (mesmo card movido por 2 users).
- `KanbanCard.vue`/`ConversationPreviewModal.vue`: feed de notas, @menção, reações, checklist.
**Riscos:** alto — resolução de conflito de move concorrente; idempotência do broadcast.
**Pronto quando:** mover um card num cliente atualiza nos demais em <2s, e notas/@menções notificam pelo sino.

### Fase 5 — Automações declarativas (flag `kanban_automations`) — **FUNDAÇÃO**
**Objetivo:** rule engine "quando→condição→então" sobre o funil; fim do hardcode open/resolved.
**Features:** Recipes When/Then; status-change generalizado; date-based/SLA; recurring; action chaining; round-robin; escalation; notify owner; alerts; Button column; SLA Column/Monitor; Time in Status como métrica.
**Backend:**
- Migration `create_funnel_automations` (`funnel_id`, `stage_id` opcional, `trigger jsonb`, `conditions jsonb`, `actions jsonb`, `active`).
- Service `app/services/kanban/automation_engine_service.rb` (parser + executor de ações: move, assign, notify, tag, webhook, schedule).
- Generalizar `FunnelItems::MoveService#update_conversation_status` para delegar ao engine (preservando open/resolved como recipes default).
- Jobs `app/jobs/kanban/run_scheduled_automations_job.rb` e `app/jobs/kanban/sla_monitor_job.rb` (Sidekiq schedule).
- Reusar Webhook model para ação de webhook outbound.
**Front:**
- Novo `KanbanAutomationBuilder.vue` (builder visual When/Then) + biblioteca de templates.
- `StageForm.vue`: link p/ regras do stage.
- `KanbanCard.vue`: Button column + badge de SLA (Dentro/Risco/Violado).
**Riscos:** alto — loops de automação, ordem de execução, performance da varredura. Mitigar com guarda de reentrância e dry-run.
**Pronto quando:** gestor cria "quando entra em Aguardando, iniciar SLA 24h; se estourar, escalar+notificar" sem código, e o open/resolved legado vira recipe.

### Fase 6 — Dashboards & relatórios in-board (flag `kanban_dashboards`)
**Objetivo:** gestor sente o pulso da operação sem exportar.
**Features:** Numbers/Battery/Chart/Workload/Goals widgets; Aging/Time-in-Status report; Activity Log consolidado; Live Dashboards; Pivot/Advanced; Portfolio roll-up; Mobile.
**Backend:**
- Service `app/services/kanban/funnel_report_service.rb` (queries de throughput, cycle time, aging via `FunnelItem` + `moved_at`).
- Action `stats` em `funnels_controller.rb`.
- Snapshots p/ Baselines (job diário → tabela `funnel_metric_snapshots`).
**Front:**
- Novo `FunnelStats.vue` + widgets (Chart.js já no projeto).
- Aba "Dashboard" em `KanbanIndex.vue`; live via canal da Fase 4.
**Riscos:** médio — custo das queries agregadas; usar índices existentes (`moved_at`, `funnel_stage_id`) e materializar snapshots.
**Pronto quando:** painel mostra abertas/resolvidas/aging/carga ao vivo e exporta.

### Fase 7 — IA de atendimento (flag `kanban_ai`)
**Objetivo:** triagem e assistência instantâneas.
**Features:** AI Summarize no card; Categorize; Sentiment (pinta card); Writing Assistant; Extract Info → campos custom; Translate; AI-powered columns; AI-powered automations (resumir+classificar+sentimento na entrada); AI Service Agent.
**Backend:**
- Service `app/services/kanban/ai/*` reusando a integração de IA existente do Chatwoot.
- Bloco IA como ação no `automation_engine_service` (Fase 5).
- Colunas IA = campos custom (Fase 2) auto-preenchidos por job.
**Front:** `ConversationPreviewModal.vue` (resumo/rascunho/tradução) + chips de sentimento/categoria no `KanbanCard.vue`.
**Riscos:** alto — custo de tokens, latência, qualidade; nível de confiança configurável e fallback humano.
**Pronto quando:** conversa nova entra resumida+classificada+com sentimento, e agente gera rascunho de resposta no card.

### Fase 8 — WorkForms, templates e integrações (flag `kanban_forms_integrations`)
**Objetivo:** entrada estruturada e cola com o ecossistema.
**Features:** WorkForms público → conversa+card; Form View intake; Template Center de funis; Webhooks de move; Twilio/WhatsApp/Slack/Gmail por evento; Connect Boards enxuto; Zapier/Make/n8n; embed iframe.
**Backend:**
- Model `funnel_template` + service `kanban/create_funnel_from_template_service.rb` + seed `db/seeds/funnel_templates.rb`.
- Endpoint público de form → cria conversa via Channel::Api + `FunnelItems::MoveService` p/ 1ª coluna.
- Ação webhook já viabilizada na Fase 5.
**Front:** "From Template" em `FunnelForm.vue`; builder de form; widget de embed.
**Riscos:** médio — segurança do endpoint público (anti-spam/rate-limit, validação).
**Pronto quando:** envio de form público cria card "Novo" preenchido e move de stage dispara webhook/Slack.

---

## 5. Modelo de dados proposto

Estratégia: **estender, não reescrever.** Preservar `funnels` / `funnel_stages` / `funnel_items` / `scheduled_messages` e os índices/cursores existentes.

### 5.1 `settings` JSON em stages e funnels (Fase 1)
```ruby
# db/migrate/XXXX_add_settings_to_funnel_stages.rb
add_column :funnel_stages, :settings, :jsonb, null: false, default: {}
# db/migrate/XXXX_add_settings_to_funnels.rb
add_column :funnels, :settings, :jsonb, null: false, default: {}
```
```ruby
# app/models/funnel_stage.rb
store_accessor :settings, :wip_limit, :sla_hours, :color_rules, :stage_permissions
```
Guarda WIP persistido, regras de cor condicional, SLA por stage e permissões — sem novas tabelas.

### 5.2 Campos customizados por card (Fase 2)
```ruby
# db/migrate/XXXX_create_funnel_custom_fields.rb
create_table :funnel_custom_fields do |t|
  t.references :funnel, null: false, foreign_key: true
  t.string  :key, null: false        # namespaced em conversations.custom_attributes
  t.string  :label, null: false
  t.string  :field_type, null: false # text|long_text|number|date|hour|dropdown|tags|checkbox|rating|phone|email|link|files|progress
  t.jsonb   :options, null: false, default: {}
  t.integer :position, default: 0
  t.boolean :show_on_card, default: false
  t.timestamps
end
add_index :funnel_custom_fields, [:funnel_id, :key], unique: true
```
**Valores** reaproveitam `conversations.custom_attributes` (já existe), com chave `funnel_<id>_<key>`. MVP sem tabela de valores; histórico/auditoria fica para o Activity Log da Fase 4.

### 5.3 Automações declarativas (Fase 5)
```ruby
# db/migrate/XXXX_create_funnel_automations.rb
create_table :funnel_automations do |t|
  t.references :funnel, null: false, foreign_key: true
  t.references :funnel_stage, foreign_key: true  # opcional: regra por coluna
  t.string  :name
  t.jsonb   :trigger, null: false, default: {}    # {event: 'item_moved'|'status_changed'|'time_in_stage'|'date_reached'|'created'}
  t.jsonb   :conditions, null: false, default: [] # [{field:'priority', op:'eq', value:'high'}, ...]
  t.jsonb   :actions, null: false, default: []     # [{type:'move', stage_id:..}, {type:'notify', user_id:..}, {type:'webhook',...}]
  t.boolean :active, default: true
  t.timestamps
end
```
O `Kanban::AutomationEngineService` interpreta `trigger/conditions/actions`. As automações `open`/`resolved` de hoje viram **recipes default** seedadas, mantendo `FunnelItems::MoveService` retrocompatível.

### 5.4 Snapshots de métricas (Fase 6, p/ Baselines)
```ruby
# db/migrate/XXXX_create_funnel_metric_snapshots.rb
create_table :funnel_metric_snapshots do |t|
  t.references :funnel, null: false, foreign_key: true
  t.date    :captured_on, null: false
  t.jsonb   :metrics, null: false, default: {}  # {stage_id => {count, avg_age_seconds, throughput}}
  t.timestamps
end
add_index :funnel_metric_snapshots, [:funnel_id, :captured_on], unique: true
```

### 5.5 Views salvas (Fase 3) e templates (Fase 8)
- `kanban_views` (`account_id`, `user_id?`, `name`, `filters jsonb`, `is_shared`).
- `funnel_templates` (`name`, `description`, `definition jsonb` com stages + campos + automações).

**Compatibilidade:** todas as novas colunas são `jsonb default {}` ou tabelas novas → **zero impacto** nos serializers e cursores atuais até a flag da fase ligar.

---

## 6. Diferenciais inovadores (além do monday — porque somos atendimento)

1. **Responder WhatsApp inline no card.** O preview já existe; transformar em composer real (texto/áudio/mídia + interativos botões/listas via WAHA) — mover o card **e** responder o cliente sem abrir a conversa. O monday nunca terá isso: os "itens" dele não falam.
2. **Automação por sentimento via IA.** "Quando sentimento = negativo E valor > R$X → mover p/ Urgente + notificar supervisor + sugerir rascunho de retenção." Une IA + rule engine + SLA num gatilho único de atendimento.
3. **SLA por estágio com alerta vivo e pausa fora do horário.** Cada coluna tem alvo de 1ª resposta/resolução; card pinta verde/amarelo/vermelho e o `sla_monitor_job` escala antes de estourar — métrica de compliance nativa, sem exportar.
4. **Mover por evento de conversa.** Não só status: "cliente respondeu" → volta de "Aguardando cliente"; "anexo recebido" → marca checklist "comprovante"; "áudio recebido" → taguear. O funil reage ao que acontece **na conversa real**.
5. **Formulário público que vira conversa+card.** WorkForm de intake cria uma conversa de verdade (Channel::Api) **e** o card na 1ª coluna já preenchido — o lead entra falando, não como linha morta de planilha.
6. **Handoff de turno com resumo por IA + nota interna.** Ao passar o plantão, IA resume a tratativa + histórico e fixa como Update no card; quem assume lê 1 parágrafo. Mata o "preciso reler tudo".
7. **Round-robin com respeito a WIP e carga real.** Atribuição automática que considera o WIP persistido e a Workload View — não distribui p/ quem já está no limite. Distribuição justa ancorada na fila de conversas, não em tarefas genéricas.
8. **Galeria/download em massa por funil.** A feature de galeria+zip já existente do Chat SPX vira a File Gallery View do board — revisar todos os comprovantes de um funil e baixar em lote. Diferencial pronto e barato de plugar.

---

## 7. Riscos, flags e validação

- **Feature flags por fase** (atrás de flag, padrão off no código): `kanban_v2_basics`, `kanban_custom_fields`, `kanban_saved_views`, `kanban_realtime`, `kanban_automations`, `kanban_dashboards`, `kanban_ai`, `kanban_forms_integrations`. **Atenção ao teto de 63 bits do bitmask** (`feature_flags` é bigint) — já estamos perto do limite; reaproveitar slots deprecados como feito com `ai_assistant_v2` (bit 39), e considerar migrar Kanban v2 para um esquema de flags não-bitmask se a frente consumir muitos bits.
- **Validação sempre em `nicolas.chatspx.app` antes da frota.** Build vite + `assets:precompile` (zero-downtime) + `sudo /bin/systemctl restart chatwoot.target`. "Meu chat" = staging para testar tudo; "chat oficial" = produção, **nunca** testar lá.
- **Migrations com cautela** (diretriz do usuário): toda migration nova é aditiva (`jsonb default {}` / tabela nova), reversível, e aplicada primeiro no staging. Não aplicar na frota sem aprovação.
- **Performance:** o cursor loading e o bulk fetch de last_message (`DISTINCT ON`) já dão a base; novas agregações usam os índices existentes (`moved_at`, `funnel_stage_id`, unique `conversation_id+funnel_id`). Dashboards pesados → snapshots materializados (5.4), não query ao vivo na fila inteira.
- **Real-time (Fase 4):** risco de conflito de move concorrente — resolver por `moved_at`/last-write-wins com reconciliação no broadcast.
- **Automações (Fase 5):** risco de loop/reentrância — guarda de profundidade, dry-run e log de execução obrigatórios.
- **IA (Fase 7):** custo/latência/qualidade — nível de confiança configurável, fallback humano, e nunca auto-responder cliente sem opt-in explícito por inbox.
- **Working tree:** nunca `git checkout/restore/reset` amplo; árvore tem muito trabalho não-commitado. Commits atômicos por fase.

---

## 8. Sugestão de priorização — top 5 para pedir primeiro

1. **WIP persistido + Conditional coloring por SLA/aging (Fase 1, P).** Maior valor percebido por menor esforço: o board passa a "gritar" o que está atrasado sozinho, e o WIP deixa de se perder no localStorage. Reaproveita `useStageColor.js` e o aging que já existe. Começa a construir a cultura de SLA.
2. **Campos customizados por card (Fase 2, M).** Destrava quase tudo depois: valor da venda, motivo, score, prazo, telefone clicável. Usa `conversations.custom_attributes` (já existe) → sem tabela de valores. É a base para Formula, Battery, agregações e colunas de IA.
3. **Views salvas + filtros AND/OR + bulk actions (Fase 3, M).** Ganho operacional diário imediato para agentes e supervisores; `bulk_move` já existe, então bulk reassign/tag/archive é incremento barato. "Minhas urgentes" / "SLA estourando" muda a rotina.
4. **Real-time broadcast de moves (Fase 4, M).** ActionCable já está pronto e ocioso; com pouco plumbing o board fica vivo entre agentes — pré-requisito para dashboards ao vivo e para a credibilidade de um Kanban colaborativo.
5. **Automações declarativas — MVP (Fase 5, G, mas core).** O divisor de águas: SLA por estágio, escalonamento e notificações sem código. Mesmo um MVP (3–4 triggers, 4–5 ações) já entrega o "padrão monday" de verdade e absorve a automação open/resolved atual como recipe. É o item de maior teto de valor — vale começar o design dele em paralelo às fases 1–3.

**Sequência recomendada de pedido:** 1 → 2 → 3 (entregas rápidas e visíveis) com o **design da Fase 5** rodando em paralelo, depois 4 e 5. Dashboards (6) e IA (7) vêm quando os dados (campos custom + automações + snapshots) já existirem para alimentá-los.
