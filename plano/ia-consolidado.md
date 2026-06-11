# Plano Consolidado — Agentes IA como Atendentes + Gate Universal de Resposta

> **Status: PLANEJADO, não iniciado** (consolidado em 2026-06-11).
> Funde o `plano/ia.md` (decisões do Paulo 11/06, trilho AgentBot-espelho) com os
> requisitos do Walisson (11/06): IA visível na parte de usuários, fix do reload de
> atribuição, gate universal de resposta com dialog "quer atribuir a você?", IA fora
> da atribuição manual comum, e tab "IA" nas listas de conversas.
>
> Trilho backend verificado no código em 11/06 (AssignmentService, callback de
> exclusividade, endpoint — citações arquivo:linha abaixo). Executar na `homologacao`,
> validar na sandbox SimplexIA, só então virar a Tozi.
> **Working tree only — nenhum commit até TUDO pronto e validado.**

---

## 1. Decisões fechadas (todas em 11/06)

| # | Decisão | Resolução |
|---|---|---|
| D-1 | Trilho da atribuição | **AgentBot-espelho** por `Captain::Assistant` (novo `bot_type: :captain` + ref ao assistant). Zero migration em `conversations`; callback de exclusividade e endpoint funcionam de graça. (= D-A1 do plano Paulo, verificado) |
| D-2 | IA na parte de usuários | **Seção separada "Agentes IA"** dentro da página de usuários/agentes (Configurações), com nome/avatar da IA e badge. Read-only ali (sem editar role/deletar). Sem User real — IA não é login |
| D-3 | Atribuição manual da IA | **Seletor "Agente IA" no sidebar — visível SÓ para admin.** Agente comum não vê e o backend rejeita (403) se tentar. Caminho normal de atribuição da IA = triagem/automação/macro |
| D-4 | Gate universal de resposta | **Só o assignee responde.** Ser do time NÃO libera resposta — dá direito de **assumir com 1 clique**. Quem não é do time (admin ou agente) escolhe um dos times DELE no próprio dialog e assume. Vale para conversa de IA, de colega, ou sem dono. Notas privadas sempre liberadas. Guard no backend (não só UI), atrás de feature flag por conta |
| D-5 | Tab "IA" nas listas | Tab **"IA" SUBSTITUI "Não atribuídas"** na barra: **Minhas / IA / Todas**, em **todas** as listas (conversas, time, label, custom view) + contador. Mostra conversas com `assignee_agent_bot_id` presente. **"Não atribuídas" vira tab condicional de alerta**: só renderiza quando count > 0 (estilo warning) — rede de segurança pra falha de triagem/órfãs. Com a flag desligada, tabs atuais intactas |
| D-6 | Gate da IA | A IA só responde conversa **atribuída a ela** (triagem atribui time + IA em par). RouterService aposentado; sobram guards técnicos (activity, vazio, grupos). (= D-A4/A5 Paulo) |
| D-7 | Cenários | Viram **subprompts** concatenados no prompt do agente; deixam de ser roteamento. (= D-A3 Paulo) |
| D-8 | Regra #53 | **Morre na virada** (zeraria a atribuição da IA a cada reopen) — substituída por triagem que ATRIBUI. (= D-A6 Paulo) |
| D-9 | Roubo de conversa | Colega do time pode assumir conversa de outro humano via dialog; **anterior é notificado**. Fora do time → fluxo D-4 |
| D-10 | Fix reload | Remover os `router.push` pós-atribuição — usuário permanece na conversa, store atualiza in-place |
| D-11 | Opção "None" na atribuição | **Removida da UI** de atribuição manual de agente (sidebar, context menu, bulk). Ninguém "solta" conversa pro limbo: devolver = atribuir IA (admin/macro) ou resolver (reopen → re-triagem). Backend/automação/API mantêm a capacidade técnica (triagem e callback dependem dela) |
| D-12 | Vigia de órfãs | Conversa aberta sem dono por mais de X min (config) → **re-triagem automática + notificação a admin**. Cobre: triagem sem match, inbox sem IA, usuário deletado, automação desligada |
| D-13 | Toggle por conta | **Configuração da conta (admin): "Modo de atendimento"** — `Clássico` × `Atribuição obrigatória`. Clássico = tudo como hoje (tabs Minhas/Não atribuídas/Todas, "None" existe, sem gate, sem dialog). Atribuição obrigatória = gate + dialog + tabs novas + sem None + vigia. O toggle É a feature flag `reply_assignment_gate`, exposta como setting visível com UI bonita (não flag interna). Default: Clássico (rollout seguro). **Independe de ter IA**: conta sem IA pode usar atribuição obrigatória (gate + tab condicional funcionam sozinhos); a tab "IA" só renderiza se a conta tem ao menos 1 assistant |

## 2. O modelo-alvo em uma narrativa

Lead manda mensagem → conversa sem dono → **triagem** (automação) atribui time + agente IA
do nicho → IA responde como atendente (nome/avatar dela no card e nas bolhas) → a conversa
aparece na **tab "IA"** de todas as listas → lead esquenta → IA faz handoff: atribui o
corretor com `team_id` → **callback limpa a IA → ela cala** → corretor atende normal.

Humano quer intervir antes? Digita e clica enviar → **dialog animado**: "Essa conversa está
sendo atendida pela {IA}. Assumir e enviar?" → 1 clique → atribuição troca, IA cala,
mensagem sai. Mesma mecânica para conversa de colega ("Assumir de {nome} e enviar?", colega
notificado) e conversa sem dono ("Atribuir a mim e enviar?"). Se a pessoa não é do time da
conversa (admin ou agente de outro time), o mesmo dialog mostra **os times dela** para
escolher junto. A mensagem digitada **nunca se perde** — envia automático após atribuir.

Admin pode atribuir IA manualmente pelo seletor (admin-only) — piloto, teste, devolver pra
IA. Agente comum devolve pra IA via macro/automação. Transferência IA→IA = tool que troca a
atribuição. **Sem flags, sem whitelist, sem label de roteamento.**

A barra de listas vira **Minhas / IA / Todas** — "Não atribuídas" deixa de ser tab fixa
(no regime normal nunca há órfã: a triagem atribui na entrada e o gate exige dono pra
responder) e só se **materializa como tab de alerta** quando alguma conversa cai no limbo;
o vigia (D-12) re-triagem automaticamente. A opção **"None" some da atribuição manual**:
conversa nunca volta pro limbo pela mão de alguém.

O que morre de graça: whitelist `only_contact_phones`, label `atendimento`, trava
`atendimento_humano`, `skip_after_human_response`, pending limbo, hop duplo do 1º turno.

## 3. A base que JÁ existe (verificada no código em 11/06)

| Peça | Onde | Status |
|---|---|---|
| Coluna `conversations.assignee_agent_bot_id` + índice parcial | `schema.rb:726,736` | ✅ verificado |
| `AssignmentService` com `assignee_type='AgentBot'` (bot×humano mutuamente exclusivos) | `app/services/conversations/assignment_service.rb:1-42` | ✅ verificado |
| `POST /assignments` aceita `assignee_type` + renderiza `agent_bot_slim` | `assignments_controller.rb:15-50` | ✅ verificado |
| Atribuir humano LIMPA o bot (= "transferiu → IA cala") | `reset_agent_bot_when_assignee_present`, `conversation.rb:318-322` | ✅ verificado |
| `agent_bots.bot_type` enum (hoje só `webhook: 0`) + `bot_config` JSONB | `agent_bot.rb:37`, schema | ✅ verificado |
| Banner self-assign + TeamSelectionModal (esqueleto da UX do gate) | `ReplyBoxBanner.vue`, `TeamSelectionModal.vue` | ✅ verificado |
| Causa do reload: `router.push` pós-atribuição (3 pontos + ChatList) | `ConversationAction.vue:100-102,197-199,223-225`, `ChatList.vue:869` | ✅ verificado |
| Dialog components-next (native `<dialog>`, open/close, confirm) | `components-next/dialog/Dialog.vue` | ✅ verificado |
| Pipeline recebe assistant como argumento (selector é o único ponto inbox-keyed) | `hook_execution_service.rb:110-117` | conferir na Fase A |
| Precedente "bot da conversa vence bot da inbox" | `agent_bot_listener.rb:47-53` | conferir na Fase A |
| Store front `captainAssistants` registrado | `store/index.js:53` | conferir na Fase C |
| Receita de automation action nova (copiar do `add_sla`) | `enterprise/automation_rule.rb:6-8`, `constants.js:717-721` | conferir na Fase C |
| Molde de tool que atribui (copilot `assign_conversation`) | `assign_conversation_service.rb:11-29` | conferir na Fase C |
| HandoffTool com TODO de team_id já desenhado | `handoff_tool.rb:74-84` | conferir na Fase C |
| Notificação de atribuição existente (avisa novo assignee) | NotificationService / `conversation_assignment` | conferir na Fase D |

---

## 4. Fases e tarefas

### Fase 0 — Fix do reload na atribuição (P, ~½ dia) — independente, primeiro entregável

| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| 0.1 | Remover `router.push` do setter `assignedTeam`, `assignAgentDirect` e `onConfirmTransferTeam` — permanecer na conversa; toast confirma; store já atualiza in-place | `ConversationAction.vue:88-104,189-203,205-231` | P |
| 0.2 | Alinhar context menu da lista: remover o `router.push` do `onAssignTeam` | `ChatList.vue:857-873` | P |
| 0.3 | Conferir que nada dependia da navegação (estado limpo via `beforeRouteLeave` do ConversationView, websocket sync) | `ConversationView.vue:67-80` | P |

**Aceite Fase 0:** trocar agente e time pelo sidebar e pelo context menu mantém a conversa
aberta, valores atualizam na hora, sem navegação. Playwright light+dark passa (§6).

### Fase A — Backend: trilho AgentBot + gate da IA (M, ~2-3 dias)

| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| A1 | `bot_type :captain` no AgentBot + ref ao assistant (`bot_config['assistant_id']` ou coluna ref) + criação/sync automática do espelho (nome/avatar) ao criar/editar/excluir assistant | `agent_bot.rb:37`, migration leve, hook no `assistant.rb` | P |
| A2 | Gate novo: `should_process_captain_response?` checa "conversa atribuída a um assistant" (via espelho); assistant resolvido pela CONVERSA, não pela inbox | `hook_execution_service.rb:7-9,32-44,109-140,164-166` | M |
| A3 | Re-checar atribuição DENTRO dos jobs (job em voo cala se trocou o dono) | `response_builder_job.rb:299-302`, `debounced_response_job.rb:4-21`, `followup_job.rb:38` | P |
| A4 | Migrar call-sites de `inbox.captain_assistant` (listener, resolução pending, copilot_trigger, endpoint) | `captain_listener.rb:6-8`, `inbox_pending_conversations_resolution_job.rb` | P |
| A5 | `CaptainInbox` vira ELEGIBILIDADE (quais IAs podem atuar na inbox): remover uniqueness de `inbox_id`, has_one→has_many | `captain_inbox.rb:21`, `enterprise/concerns/inbox.rb:5-8` | P |
| A6 | Aposentar RouterService mantendo guards técnicos (activity/vazio/grupos) | `router_service.rb` | P |
| A7 | Guard backend de atribuição manual da IA: `AssignmentService`/policy rejeita `assignee_type='AgentBot'` de bot captain se `Current.user` não-admin (403); automação/macro/tool passam | `assignment_service.rb`, `assignments_controller.rb` | P |
| A8 | Cota zerada: handoff explícito em PT (hoje EN hardcoded), re-keyado pra conversa | `hook_execution_service.rb:142-154` | P |
| A9 | Decidir destino de `active_bot?`/`pending_status_enabled`/auto-resolve no modelo novo (pending-de-bot morre estruturalmente) | `enterprise/inbox.rb:10-22`, `conversation.rb:340-351`, `message.rb:468-478` | P |

**Aceite Fase A:** numa inbox de teste com 2 assistants elegíveis: conversa sem atribuição →
IA muda; atribuir IA-1 (como admin) → responde; atribuir IA-2 → IA-2 responde e IA-1 cala;
atribuir humano → IA cala (callback); debounce em voo após troca de dono → descartado;
agente comum tentando atribuir IA via API → 403.

### Fase B — Agentes independentes + subprompts (P-M, ~1-2 dias)

| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| B1 | Prompt de ATENDENTE no v2: `config['instructions']` passa a valer (hoje runner v2 IGNORA — armadilha conhecida) + template sem identidade de orquestrador | `assistant.liquid:5,64-71`, `assistant.rb:131-146`, `agentable.rb:15-29` | P |
| B2 | Subprompts: concatenar `resolved_instructions` dos cenários habilitados; runner para de mapear cenários como agentes | `agent_runner_service.rb:167-175`, `assistant.liquid` | P |
| B3 | Tools de negócio armadas no assistant: `config['tools']` validado contra `available_agent_tools` (assistant sem cenário nasce SEM buscar_imovel!) | `assistant.rb:118-129`, `scenario.rb:117-127` | P |
| B4 | Histórico legado: `agent_name='scenario_X'` cai no default da gem silenciosamente — validar em homolog; limpar persistência | `response_builder_job.rb:76,247-258` | P |
| B5 | Script rake de criação dos agentes por nicho + duplicação de knowledge (Playbook + Q&A; embeddings re-geram via after_commit) | precedente: `aws_create_faq.rb` | P |
| B6 | Opcional: modelo LLM por assistant (`config['model']` com fallback pra conta) | `agentable.rb:45-48` | P |
| B7 | ScenariosTab re-rotulada "Comportamentos/Subprompts" (CRUD intacto) | `ScenariosTab.vue` | P |

**Aceite Fase B:** agente standalone responde com prompt rico + usa buscar_imovel; subprompt
muda comportamento sem segundo agente LLM; 1º turno em 1 chamada (sem hop).

### Fase C — UI: identidade da IA + atribuição + tab "IA" (M, ~3-4 dias)

| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| C1 | **Seção "Agentes IA"** na página de usuários/agentes (Configurações): lista os assistants com avatar/nome/badge, inboxes elegíveis, status; read-only (gestão continua na área de Agentes IA). Fonte: store `captainAssistants` | página settings agents + i18n pt_BR/en | M |
| C2 | **Seletor "Agente IA" no sidebar** da conversa — renderizado SÓ para admin (`isAdmin`); dropdown próprio abaixo do de agente; dispatch com `assignee_type: 'AgentBot'` | `ConversationAction.vue:301-391`, `api/inbox/conversation.js:94-98` | M |
| C3 | Conversa da IA NÃO aparece como "Não atribuída": serializar assignee-IA + scopes/finder/contadores + **badge "IA" no card** | `_conversation.json.jbuilder:37-60`, `conversation.rb:82-84`, `conversation_finder.rb:168-173`, ConversationCard | M |
| C4 | **Tab "IA" no lugar de "Não atribuídas"** (Minhas/IA/Todas): novo `assignee_type='ai'` no finder (scope `assignee_agent_bot_id IS NOT NULL` de bot captain) + contador `ai_count`; **tab "Não atribuídas" condicional** (renderiza só com `unassigned_count > 0`, estilo alerta); tab "IA" só renderiza se a conta tem ≥1 assistant; modo Clássico (D-13) mantém layout atual. Em conversas, time, label e custom views | `conversation_finder.rb`, meta/counts jbuilder, `ChatTypeTabs.vue`, `wootConstants.ASSIGNEE_TYPE`, store conversations + i18n | M |
| C5 | Automation action `assign_ai_agent` (receita do `add_sla`) — macros herdam de graça | `enterprise/automation_rule.rb`, `enterprise/action_service.rb`, `constants.js`, `automationHelper.js` | P |
| C6 | HandoffTool: `team_id` no handoff + manter dono quando a conversa já tem corretor | `handoff_tool.rb:26-84` | P |
| C7 | Tool `transferir_para_agente` (IA→IA): troca atribuição + enfileira ResponseBuilder do novo | novo arquivo, molde `assign_conversation_service.rb` | P |
| C8 | Filtro defensivo: espelhos captain NUNCA aparecem em assignable_agents/round-robin/relatórios (estruturalmente já não aparecem por serem AgentBot — adicionar spec que trava isso) | spec | P |
| C9 | **Remover opção "None"** dos pontos de atribuição manual de agente (dropdown do sidebar, context menu, bulk actions) quando a flag estiver ligada; API/automação seguem aceitando `assignee_id: nil` | `ConversationAction.vue` (agentsList), context menu, bulk + i18n | P |
| C10 | **Vigia de órfãs** (D-12): job/automação — conversa open sem `assignee_id` e sem `assignee_agent_bot_id` por > X min → re-triagem + notificação admin; X configurável | job novo ou automação + doc | P |

**Aceite Fase C:** admin atribui IA pela UI e agente comum nem vê o seletor; card mostra a IA
como dona com badge; barra mostra Minhas/IA/Todas e a tab "IA" lista/conta certo em todas as
views; criar uma órfã de propósito faz a tab "Não atribuídas" condicional aparecer e o vigia
re-triagem; dropdowns de atribuição sem opção "None"; automação
label→`assign_team`+`assign_ai_agent` funciona; handoff IA→corretor mantém time e notifica;
seção "Agentes IA" aparece na página de usuários nos dois temas.

### Fase D — Gate universal de resposta (M, ~2-3 dias)

| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| D1 | **Guard backend**: criação de message outgoing não-privada por User exige `user.id == conversation.assignee_id`. Erro 422 com código `assignment_required` (+ metadados: dono atual, time da conversa). Bypass: notas privadas, automações/campanhas (Current.user nil), jobs da IA, external echo. Atrás de feature flag por conta (`reply_assignment_gate`) | `messages_controller.rb:44-55` / `message_builder.rb:23-34` | M |
| D2 | **Dialog "Quer atribuir a você?"** (components-next Dialog, animação slide-up/spring a partir do reply box), interceptando o envio. 4 variantes: (a) sem dono + do time/sem time → "Atribuir a mim e enviar"; (b) dono humano + do time → "Assumir de {nome} e enviar"; (c) dona IA → "Assumir da {IA} e enviar"; (d) fora do time (admin ou agente) → escolher um dos times DO USUÁRIO + "Atribuir e enviar". Após confirmar: assignTeam (se d) → assignAgent (self) → **mensagem digitada envia automática** | novo `AssignToReplyDialog.vue` (evolui `ReplyBoxBanner` + `TeamSelectionModal`), interceptar em `ReplyBox.vue` (`onSendReply`) | M |
| D3 | Banner proativo enquanto digita (já existe) atualizado para o novo texto/regra; CTA abre o mesmo dialog | `ReplyBoxBanner.vue` | P |
| D4 | Notificar o assignee anterior quando colega assume (reusar notificação `conversation_assignment`) | NotificationService | P |
| D5 | i18n completo pt_BR + en das novas strings (zero hardcode; spec de paridade) | `locale/pt_BR/*`, `locale/en/*` | P |
| D6 | Tratar 422 `assignment_required` no frontend como fallback (se dois agentes tentarem assumir ao mesmo tempo, o segundo recebe o dialog de novo com o dono atualizado) | store conversations / ReplyBox | P |
| D7 | **Toggle "Modo de atendimento"** em Configurações da conta (admin): card com os dois modos, descrição do que muda, confirmação ao trocar; persiste na feature flag `reply_assignment_gate`; todas as superfícies (gate, tabs, None, vigia, dialog) leem dela | settings da conta (frontend + backend) + i18n | M |
| D8 | **Stack de efeitos visuais** (§10): instalar `motion-v` (LazyMotion), `@number-flow/vue`, `@formkit/auto-animate`, `canvas-confetti` (lazy), plugin `tailwindcss-animated`; copiar componentes Inspira UI adaptados aos tokens (doc v1/Tailwind 3.4); `MotionConfig reducedMotion="user"` global | package.json, tailwind.config.js, components-next | P-M |

**Aceite Fase D:** com a flag ligada — agente não-dono clica enviar → dialog certo para cada
variante, mensagem sai após confirmar e nunca se perde; nota privada passa sem dialog; API
direta sem atribuição → 422; corrida entre dois agentes → segundo vê dialog atualizado; com
a flag desligada → comportamento atual intacto.

### Fase E — Políticas e limpeza (P, ~1 dia)

| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| E1 | Matar/substituir regra #53: regra nova só re-triagem órfãs REAIS (reopen sem dono ativo) | automação em prod + doc | P |
| E2 | Varredura de `update_columns` nos scripts de operação (pulam o callback de exclusividade); padronizar `AssignmentService` | `scripts/spx/tozi/*` | P |
| E3 | Specs dos caminhos críticos (gate por atribuição IA, gate universal, guard admin-only, exclusividade, tab IA finder/counts) | spec/ + spec/enterprise | M |
| E4 | Telemetria: AssistantLog ganha eventos de atribuição/assunção (auditoria da virada) | `assistant_log` | P |
| E5 | Nota no vault: `Padrao - IA como atendente via AgentBot-espelho` + lições descobertas na implementação | `vault/01-Permanentes/` | P |

---

## 5. Plano de testes (inegociável antes de declarar qualquer fase "done")

### 5.1 Specs Rails (por fase)
- **A:** gate da IA por atribuição (responde/cala), exclusividade, re-check em job em voo, guard 403 não-admin, sync do espelho (create/rename/destroy do assistant). **[rev2 pós-crítica — cenários novos, ver `fase-a-design.md`]:** rajada de chunks do humanizer (re-check POR chunk: dono troca após o 2º chunk → 3-4 não saem); triagem assíncrona (incoming sem dono → automação atribui espelho → gatilho pós-atribuição A2d responde no 1º turno; idem IA→IA); exclusividade no team-change (triagem seta team + espelho → nenhum humano auto-atribuído, nunca `assignee_id` E `assignee_agent_bot_id` juntos — 4 caminhos de auto-assignment, A2b-expandida); humano responde SEM se atribuir → espelho desatribuído, IA cala (A2c); resolve limpa o dono-espelho → reopen nasce sem dono, notes/FAQ via fallback "participante" (A2e).
- **B:** prompt standalone, subprompt concatenado, tools armadas, agent_name legado.
- **C:** finder/counts do `assignee_type='ai'`, serializer do assignee-IA, action `assign_ai_agent`, espelho fora de assignable_agents (C8).
- **D:** guard `assignment_required` (todas as variantes + bypasses + flag off), notificação ao anterior, paridade i18n en↔pt_BR.

### 5.2 Playwright (OBRIGATÓRIO, light + dark, user de teste dedicado — NUNCA resetar senha de conta real)
| # | Cenário | Valida |
|---|---|---|
| P1 | Trocar agente e time pelo sidebar | permanece na conversa, sem reload, valores atualizam (Fase 0) |
| P2 | Trocar time pelo context menu da lista | idem (Fase 0) |
| P3 | Página de usuários | seção "Agentes IA" com badge, avatar, nos 2 temas, sem i18n leak |
| P4 | Sidebar como admin vs como agente | seletor "Agente IA" só aparece pra admin |
| P5 | Barra de tabs em conversas/time/label | Minhas/IA/Todas; tab IA conta/filtra certo, contador atualiza ao vivo; "Não atribuídas" AUSENTE quando count=0 |
| P5b | Criar conversa órfã de propósito | tab "Não atribuídas" condicional APARECE com estilo de alerta; some quando órfã é atribuída |
| P5c | Dropdowns de atribuição (sidebar, context menu, bulk) | opção "None" não existe |
| P6 | Card de conversa da IA | badge IA, aparece na tab "IA" |
| P7 | Gate variante (a): conversa sem dono, agente do time digita e envia | dialog "Atribuir a mim e enviar" → mensagem aparece na thread |
| P8 | Gate variante (b): conversa do colega | dialog "Assumir de {nome}" → assume e envia |
| P9 | Gate variante (c): conversa da IA | dialog "Assumir da {IA}" → IA limpa, mensagem sai |
| P10 | Gate variante (d): admin/agente fora do time | dialog com seleção dos times do usuário → atribui time+self e envia |
| P11 | Nota privada em conversa não-atribuída | passa SEM dialog |
| P12 | DOM walker pós-mudanças | sem i18n keys vazadas, ícones renderizados (width/height>0), sem console errors, contraste ok nos 2 temas |
| P13 | Toggle "Modo de atendimento" nas configurações | troca Clássico↔Atribuição obrigatória reflete na hora: tabs, None, gate e dialog ligam/desligam sem deploy; conta SEM IA em modo obrigatório → sem tab "IA", gate e tab condicional funcionam |

### 5.3 E2E na sandbox SimplexIA (roteiro adaptado do plano Paulo, 16 testes)
| # | Teste | Esperado |
|---|---|---|
| 1 | Conversa nova sem atribuição | IA MUDA (nada de resposta) |
| 2 | Admin atribui agente Vendas pela UI | responde no tom Vendas, card com badge IA, entra na tab "IA" |
| 3 | "quero alugar 3 quartos até 2.500" | buscar_imovel → opções reais (tools armadas, B3) |
| 4 | Áudio + foto | transcreve/entende |
| 5 | FAQ ("aceitam pet?") | responde da knowledge DUPLICADA do agente certo |
| 6 | Subprompt on/off | comportamento muda sem segundo agente LLM |
| 7 | Silêncio 2-3 min | follow-up vem do MESMO agente (A3/A4) |
| 8 | "quero falar com corretor" | handoff: corretor com team atribuído, IA cala, push chega, conversa SAI da tab "IA" |
| 9 | Humano digita em conversa da IA | dialog "Assumir da {IA}" → assume → IA cala |
| 10 | Transferir IA→IA (tool) | agente novo assume com a knowledge dele, tab "IA" segue correta |
| 11 | Resolver + lead volta | reabre SEM dono → triagem re-atribui (sem #53, sem pending) |
| 12 | "blz" | [IGNORAR] (comportamento preservado) |
| 13 | Debounce em voo + humano assume no meio | job descartado, IA não fala por cima |
| 14 | Reatribuição em massa via script | usa AssignmentService, exclusividade preservada (E2) |
| 15 | Agente comum tenta atribuir IA (API direta) | 403 |
| 16 | Corrida: dois agentes assumem a mesma conversa | segundo recebe dialog atualizado com o novo dono |
| 17 | Triagem desligada de propósito + conversa nova | órfã → tab "Não atribuídas" condicional aparece → vigia re-triagem em X min + notificação admin |

---

## 6. Migração da Tozi (quando for executar a virada)

1. **NUNCA deletar a Clara** antes de copiar — destroy cascateia documents/Q&A/chunks.
   Criar agentes novos AO LADO (Júlia/Vendas, Locação, Letícia/Financeiro), duplicar
   knowledge via script (B5), configurar behavior baseline documentado (debounce/
   humanizer/business_hours) pra evitar drift entre agentes.
2. Validar tudo na **sandbox SimplexIA** primeiro (roteiro §5.3).
3. Virada na inbox 91: registrar elegibilidade (CaptainInbox), criar automação de triagem
   (intenção → team + agente IA), desativar #53, ligar `reply_assignment_gate` na conta.
   O "switch" = a triagem começa a atribuir. **Rollback = desativar a automação de triagem
   + desligar a flag do gate** (conversas já atribuídas a humanos não mudam).
4. Aposentadoria da Clara #7: desconectar elegibilidade, manter registro como arquivo morto.

## 7. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| `update_columns` em massa pula o callback de exclusividade | E2 (padronizar AssignmentService nos scripts) |
| Jobs serializados com assistant antigo durante deploy da virada | A3 (re-check no job) + janela calma |
| Gate universal travar operação se mal calibrado | Feature flag por conta (D1) — desligar reverte na hora, sem deploy |
| Corrida de assunção entre dois agentes | D6 (422 `assignment_required` re-renderiza dialog com dono atual) |
| Knowledge duplicada ×N → drift de conteúdo | aceito no tamanho atual; editar = ação ×N documentada |
| `AssistantResponse.search` não escopa sozinho | regra: SEMPRE via association `assistant.responses` |
| `agent_name` legado cai no agente default | B4 (validar em homolog + limpar persistência) |
| Cota captain por conta: N agentes no mesmo pote | monitorar; mensagem em PT (A8) |
| #53 ativa zera atribuição da IA | E1 obrigatório na virada |
| Espelho AgentBot órfão (assistant deletado) | sync no destroy (A1) + spec |
| Tab "IA" em views com cache de contadores | conferir counts em todas as views na P5 |
| Substituir "Não atribuídas" esconde órfãs (lead invisível) | tab condicional só-quando-count>0 + vigia de órfãs (C10/D-12); contas com flag desligada mantêm tabs antigas |
| Sem "None" na UI, conversa de agente deletado/afastado fica presa | deleção de user nullifica assignee → vira órfã → vigia re-triagem; bulk reassign continua disponível |

## 8. Sequência de execução e governança

- **Ordem:** Fase 0 → A → B → C → D → E (0 pode sair na frente como entregável isolado;
  B pode correr em paralelo com C após A pronta).
- **Esforço total estimado:** ~2,5-3 semanas dev.
- **Ambiente:** desenvolvimento e testes nesta VM (`homologacao`, 192.168.8.232 — VM
  inteira é homolog). Restart: `sudo systemctl restart chatwoot.target`.
- **Execução via AIOX (SDC):** @sm draft → @po valida → @dev implementa → @qa gate por
  fase; @architect revisa a Fase A antes de codar (mexe no coração do pipeline Captain).
- **MODO ULTRACODE OBRIGATÓRIO (orquestração multi-agente via Workflow):** toda sessão de
  implementação deve ativar ultracode (`/effort` → ultracode, ou incluir a palavra
  "ultracode" no prompt — sessão nova NÃO herda o modo). Padrão por fase:
  1. **Explorar** — agentes paralelos releem os arquivos-alvo da fase ANTES de editar
     (citações arquivo:linha deste plano podem ter drift — verificar sempre);
  2. **Implementar** — dividir tarefas independentes da fase entre agentes (worktree
     isolation se editarem arquivos em paralelo);
  3. **Revisar adversarialmente** — fan-out de revisores sobre o diff (correctness,
     regressão, i18n pt_BR/en, dark mode, segurança do gate) tentando REFUTAR que está
     pronto; só passa o que sobreviver;
  4. **Validar** — Playwright light+dark dos cenários da fase (§5.2) + specs, com
     evidências (screenshots), antes de declarar o aceite.
- **Modelo:** sessão e subagentes rodam em **Fable** (sem override de modelo nos
  workflows — herdar o modelo da sessão). Se a cota bater no limite, o loop pausa e
  retoma quando renovar — o estado está em `plano/ia-progresso.md`, nada se perde.
- **Git:** working tree only; commit único (ou por fase, a decidir com Walisson) somente
  após TUDO validado; push apenas via @devops.
- **Execução autônoma (/loop):** o estado vive em `plano/ia-progresso.md` — checklist de
  todas as fases/tarefas (criar na 1ª iteração a partir deste plano), status de cada uma,
  decisões técnicas tomadas em autonomia (com justificativa) e pendências. Evidências de
  aceite (screenshots Playwright light+dark, saída de specs) em `plano/evidencias/`.
  Cada iteração: lê plano + progresso → executa a próxima pendência → valida → atualiza
  o progresso. Fase só é marcada concluída com o aceite comprovado. Divergência plano ×
  código → resolver com a melhor decisão técnica e REGISTRAR; só parar para perguntar se
  contradizer uma decisão de produto (D-1..D-13). Commit/push/deploy NUNCA em autonomia —
  revisão final e commit são com o Walisson. Ao concluir tudo: relatório em
  `plano/ia-relatorio-final.md` + lições no vault + encerrar o loop.
- **i18n:** pt_BR primeiro, paridade com en (regra do fork).
- **Padrões de UI:** components-next, Tailwind only, tokens `bg-n-*`/`rgb(var(--solid-2))`
  (NUNCA `var(--n-*)`), validação Playwright light+dark obrigatória.

## 9. Stack de efeitos visuais ("efeitos lendários") — pesquisada e verificada em 11/06/2026

Pesquisa em GitHub/npm (4 agentes, estrelas/licenças/releases/bundle verificados). Critérios:
Vue 3 + Tailwind 3.4 do fork, dark mode por tokens, MIT-friendly, bundle enxuto, mantida em 2026.

### Bibliotecas adotadas

| Lib | Papel | Licença | Peso (gzip) | Status jun/2026 |
|---|---|---|---|---|
| **motion-v** (Motion for Vue, oficial motion.dev) | Engine de animação: dialog spring + exit (AnimatePresence), checkmark pathLength, shake, whilePress | MIT | ~7,5KB sync via LazyMotion (+24KB lazy) | v2.3.0 de 08/06/2026, 424k dl/sem — peer deps já satisfeitas (`@vueuse/core ^12` existe no fork) |
| **Inspira UI** (unovue) | Fonte primária de componentes prontos copy-paste (port Vue do Aceternity/Magic UI): Border Beam, Glow/Neon Border, Confetti, Number Ticker, Animated List/Tabs | MIT puro | só o que copiar (Border Beam = CSS puro, 0 deps) | 4.6k ⭐, push 19/05/2026; usar **doc v1** (v1.inspira-ui.pages.dev) = Tailwind v3 |
| **@number-flow/vue** (NumberFlow) | Contador odômetro (dígitos rolando) dos badges das tabs | MIT | 6,2KB, zero deps | 7.4k ⭐, release 02/2026; herda cor/fonte → dark mode grátis |
| **@formkit/auto-animate** | `v-auto-animate` na lista de conversas e no container de tabs (entrada/saída/reorder automáticos) | MIT | 3,2KB, zero deps | 13.8k ⭐, estável |
| **canvas-confetti** | Celebração sutil ao assumir conversa (lazy `import()` no handler) | ISC | 4,3KB (fora do bundle inicial) | 12.6k ⭐, padrão da categoria |
| **tailwindcss-animated** (plugin) | Utilitárias `animate-shake`/`animate-jump-in`/`animate-fade-up` (CSS-only, JIT) pra tab de alerta | MIT | ~0 (JIT) | push 16/05/2026 |

**Descartadas com motivo:** `@vueuse/motion` (dormente 15 meses, sem exit/layout animations);
`vue3-lottie`/`lottie-web` (77KB gzip por um checkmark — anti-pattern; SVG stroke resolve com 0KB);
GSAP (grátis comercial desde 2025 incl. Flip — fica como **upgrade opcional** se quisermos transições
de tab nível máximo; licença proprietária no-charge, registrar se adotar); Vue Bits (ótimo catálogo,
**fonte secundária** — MIT+Commons Clause e GSAP/three.js em vários; minerar ClickSpark/StarBorder
pontualmente); Spark UI/Animata/MagicPattern (inspiração apenas).

### Mapa efeito → caso de uso

| Caso | Efeito | Peça |
|---|---|---|
| Dialog de atribuição (D2) | Entrada slide-up com spring físico + exit suave + stagger do conteúdo; `whilePress` no confirm | motion-v `AnimatePresence` + `:transition="{ type: 'spring', visualDuration: 0.35, bounce: 0.25 }"` sobre o Dialog **existente** (mantém semântica/a11y; Animated Modal do Inspira só como referência visual) |
| Sucesso ao assumir | Checkmark SVG animado (stroke-dashoffset, 0 deps, `currentColor` = dark mode grátis) + confete sutil (`particleCount: 30, scalar: 0.8, disableForReducedMotion`) na 1ª da sessão | receita CSS própria + canvas-confetti lazy |
| Tab "IA" | Contador odômetro + dot com `animate-ping` duplo ou glow-pulse de box-shadow com token | NumberFlow + CSS puro |
| Tab condicional "Não atribuídas" | Aparece com `animate-jump-in`, headShake 1x ao chegar nova órfã, glow border de alerta | tailwindcss-animated + keyframes headShake + Glow Border (Inspira) |
| Badge "Agente IA" (cards + página usuários) | **Border Beam** (feixe percorrendo a borda — CSS puro com `@property` + conic-gradient, Baseline 2024, fallback = borda estática) ou shimmer text | Inspira UI adaptado aos tokens `rgb(var(--token))` |
| Listas mudando de tab | FLIP automático | `<TransitionGroup>` nativo + auto-animate |

**Regras:** todo efeito respeita `prefers-reduced-motion` (`MotionConfig reducedMotion="user"` global,
`disableForReducedMotion` no confetti, `@media` nos keyframes); cores SEMPRE via tokens
(`rgb(var(--token))`, nunca hex hardcoded — componentes copiados do Inspira/uiverse precisam adaptação);
orçamento de bundle da stack: **~14KB gzip** + motion-v (7,5KB sync na estratégia LazyMotion).
Receitas CSS completas (border beam, shimmer, glow-pulse, headShake, checkmark) salvas na pesquisa —
portar para `components-next/` na implementação.

## 10. Relação com o plano anterior

Este plano **substitui** `plano/ia.md` como referência de execução, preservando dele:
trilho D-A1, fases A/B quase integrais, migração Tozi e riscos. Diferenças: D-A2 (composer
bloqueado só em conversa de IA) foi **absorvido e generalizado** pelo gate universal (D-4);
C1 (seletor de IA) ficou **admin-only** (D-3); novos itens sem equivalente lá: Fase 0
(reload), seção "Agentes IA" na página de usuários (D-2), tab "IA" (D-5), gate universal
com dialog em 4 variantes (Fase D).
