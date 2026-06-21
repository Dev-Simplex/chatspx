# Plano — Fila por time + handoff "pull" da IA (modo Atribuição obrigatória)

> **Status: PLANEJADO, não iniciado** (2026-06-12). Estudo de viabilidade feito sobre o código
> (citações arquivo:linha abaixo). **Working tree only — nada commitado até validar.**
> Vale **só no modo com a tab IA ligada** (`reply_assignment_gate` ON). Modo Clássico = intacto.

---

## 1. A ideia em uma frase

Quando a IA **termina** um atendimento, ela **solta a conversa numa fila do time** (não empurra
pra um agente específico). Essa fila é a aba **"Aguardando atendimento"**, **escopada por time**
(cada um vê a fila do seu time), e a conversa só aparece nela **quando há agente online no time**.
Um humano **puxa** da fila (assume e responde). Se o time inteiro está offline, um **vigia** evita
que o lead fique invisível.

## 2. Decisões fechadas

| # | Decisão | Resolução |
|---|---|---|
| F-1 | Modelo de handoff | **Pull**: a IA termina → **solta o espelho** (`assignee_agent_bot_id = nil`) + mantém `team_id` → conversa fica "open, sem dono, com time" = aguardando |
| F-2 | Anti re-captura (CRÍTICO) | Desligar a **re-captura automática da IA** (`orphan_captain_reentry?`) no modo fila — senão a próxima mensagem do cliente faz a IA pegar de volta e a fila nunca existe |
| F-3 | Escopo da aba | **Por time**: agente não-admin vê só a fila dos times dele; **admin vê tudo** |
| F-4 | "Atendimento livre" | **Online** (presença) — a conversa aparece na fila do time quando há **≥1 agente online** no time. NÃO usa capacidade (enterprise) |
| F-5 | Time offline (lead invisível) | **Vigia sempre escala** — mesmo com o time todo offline. Time com agente online: conversa fica na fila; se ficar > 10 min sem ninguém puxar → escala. Time SEM ninguém online (no handoff ou durante a espera) → escala já (não fica invisível). **Escala = notifica os admins da conta** + conversa permanece visível/sinalizada. (10 min configurável) |
| F-6 | Escopo geral | Tudo só com `reply_assignment_gate` ON. Modo Clássico inalterado |

## 3. Viabilidade (estudo 2026-06-12) — ALTA, baixa-média complexidade

A maior parte da fundação já existe. O risco real **não** é o escopo nem a presença — é o **F-2** (re-captura).

## 4. Base que já existe (arquivo:linha)

| Peça | Onde | Situação |
|---|---|---|
| Handoff atual ("suave", IA mantém a conversa) | `enterprise/lib/captain/tools/handoff_tool.rb` (`trigger_handoff`, suporte a `team_id` da tarefa C6) | Mudar p/ soltar o espelho |
| Release de espelho já existe (cota zerada) | `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb` (`perform_handoff` ~190-201) | Padrão a reusar |
| **Re-captura automática (o gotcha)** | `hook_execution_service.rb` (`orphan_captain_reentry?` ~151-161, `reattach_sector_assistant`) | **Gatear no modo fila (F-2)** |
| Round-robin / auto-assign já NÃO roubam conversa | `app/services/auto_assignment/agent_assignment_service.rb` (checa `assignee_agent_bot_id.present?`), `app/models/concerns/auto_assignment_handler.rb` | ✅ protegido |
| Finder: filtro `unassigned` / sem espelho | `app/finders/conversation_finder.rb` `filter_by_assignee_type` (~170-182, `unassigned.without_captain_assignee`) | ✅ já mostra a fila |
| Finder: escopo por time | `conversation_finder.rb` `set_team` (~130-143), `filter_by_team` (~220-224) | Forçar p/ a aba aguardando |
| Finder: contadores | `conversation_finder.rb` `compute_all_counts` (~253-288, `unassigned_count`) | Herdam o filtro de time |
| Flag/modo | `app/models/account.rb` `reply_assignment_gate_enabled?`; finder `ai_tabs_enabled?` (~184-186) | ✅ pronta |
| Presença online | `lib/online_status_tracker.rb` (`get_available_users`), `app/models/concerns/inbox_agent_availability.rb` (`available_agents`, `fetch_online_agent_ids`) | Reusar p/ F-4 |
| Times do usuário | `user.teams` (`team_members`), `team.members` | Reusar |
| Aba "Aguardando atendimento" (label) | `ChatList.vue` (já condicional ao modo — feito) | ✅ pronto |
| Notificação de assunção / dono anterior | NotificationService `conversation_assignment` | Reusar p/ vigia/assunção |

## 5. Fases e tarefas

### Fase 1 — Handoff "pull" + anti re-captura (backend) — 🔴 núcleo
| ID | Tarefa | Onde |
|---|---|---|
| 1.1 | No handoff, **soltar o espelho** antes do `bot_handoff!` (`assignee_agent_bot_id = nil`), mantendo `team_id` | `handoff_tool.rb#trigger_handoff` |
| 1.2 | **Gatear `orphan_captain_reentry?`**: no modo fila (flag ON), NÃO reanexar a IA do setor quando chega mensagem em conversa solta | `hook_execution_service.rb` ~151-161 |
| 1.3 | Garantir estado estável "open + team + sem dono + sem espelho" (callbacks de exclusividade não revertem) | `app/models/conversation.rb`, enterprise overlays |
| 1.4 | Conferir que `orphan_retriage`/triagem não re-atribui IA quebrando a fila | `app/jobs/conversations/orphan_retriage_job.rb` (`still_orphan?`) |

### Fase 2 — Fila escopada por time + presença (backend) — médio
| ID | Tarefa | Onde |
|---|---|---|
| 2.1 | Forçar **escopo por time** na aba aguardando quando flag ON + não-admin (sempre `@team_ids = user.teams`) | `conversation_finder.rb#set_team` |
| 2.2 | **Gate de presença**: a fila/contador da aba aguardando só conta conversas de times **com ≥1 agente online** (reusa `OnlineStatusTracker`) | `conversation_finder.rb` `filter_by_assignee_type` + `compute_all_counts` |
| 2.3 | Contadores aplicam os mesmos filtros (time + presença) | `compute_all_counts` |

### Fase 3 — Vigia (lead não fica invisível) — pequeno
| ID | Tarefa | Onde |
|---|---|---|
| 3.1 | Job/automação: conversa aguardando há > X min (config) sem ninguém → notifica admin / escala | job novo ou automação |

### Fase 4 — UI (ajustes) — pequeno
| ID | Tarefa | Onde |
|---|---|---|
| 4.1 | Frontend já passa `teamId` e já renomeia a aba — conferir e, se preciso, estado "fila vazia / ninguém online" | `ChatList.vue` |

## 6. Plano de testes (obrigatório antes do aceite)

### Specs (Rails + Vitest)
- Handoff solta o espelho + mantém time (1.1); mensagem do cliente em conversa solta **NÃO** reanexa IA no modo fila (1.2) e **reanexa** no modo antigo (não regredir); estado estável (1.3); triagem não rouba (1.4).
- Finder: aba aguardando escopada por time (não-admin vê só seus times; admin vê tudo); presença (time sem online → conversa não conta/aparece; com online → aparece); contadores idem; modo Clássico inalterado.

### Playwright (OBRIGATÓRIO, light + dark, conta 3, usuário de teste dedicado — nunca senha real)
| # | Cenário | Esperado |
|---|---|---|
| Q1 | IA faz handoff | conversa some da tab IA e entra em "Aguardando atendimento" do time, sem dono |
| Q2 | Cliente manda nova msg na conversa solta | IA **não** recaptura (fica aguardando) |
| Q3 | Agente do time (online) abre a aba | vê a conversa na fila do time dele |
| Q4 | Agente de OUTRO time | **não** vê essa conversa |
| Q5 | Admin | vê a conversa (account-wide) |
| Q6 | Time sem ninguém online | conversa não aparece na fila do time; vigia notifica admin |
| Q7 | Agente puxa (assume) | sai da fila, vira dele, ele responde |
| Q8 | Modo Clássico (flag off) | nada muda (sem fila por time, sem gate de presença) |
| Q9 | DOM walker | sem i18n vazada, ícones ok, contraste, 0 console errors, 2 temas |

### E2E (sandbox conta 3)
- Fluxo completo: lead → IA atende → handoff → fila do time → agente online puxa → responde → resolve.
- Time offline: handoff → não aparece → vigia escala/notifica.

## 7. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| 🔴 IA recaptura a conversa solta (fila não existe) | **F-2 / 1.2** — gatear `orphan_captain_reentry?` no modo fila (ponto #1) |
| Lead invisível com time offline | **F-5 / Fase 3** — vigia notifica/escala |
| Callbacks de exclusividade reverterem a liberação | 1.3 + specs do estado estável |
| Triagem/orphan_retriage re-atribuir IA | 1.4 |
| Presença "online" quase sempre true pra quem está olhando | aceitável: o gate de presença age sobretudo no contador/visibilidade quando o time está ausente; o vigia cobre o resto |
| Capacidade (enterprise) fora do escopo | decisão F-4 (só online); pode evoluir depois |

## 8. Decisões (fechadas)
1. **Vigia: 10 min** (configurável) até escalar quando há time online mas ninguém puxa.
2. **Escala sempre, mesmo sem time online** → **notifica os admins da conta** + conversa fica visível/sinalizada (nunca some). Sem time online no handoff = escala imediata.

## 9. Encaixe
Extensão da Fase D (gate universal) do `ia-consolidado.md`. Reusa flag, finder, presença e
notificação. Implementar no modo econômico (Opus + xhigh, sem ultracode), working tree only,
Playwright light+dark antes do aceite.
