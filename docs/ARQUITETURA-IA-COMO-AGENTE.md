# Plano — IA como Agente Atribuível (decidido 2026-06-11 · EM EXECUÇÃO no mesmo dia)

> **STATUS (11/06 noite):** Fase A ✅ (loop autônomo da .41, aceite com 331 specs, commit `2bee0f724`) ·
> B1 instructions ✅ · B3 tools por config ✅ · C4 action `assign_ai_agent` ✅ · C6 tool
> `transferir_para_agente` ✅ (frente Claude local) · **orquestração E2E provada** (triagem
> automática → Clara → transferência → Bruna) na conta 3/inbox 44 do chatspx.app ·
> Fase C (UI) em andamento pelo loop · Pendentes: B2 formal (subprompts concatenados —
> interim coberto), C1-C3 (UI), C5 (handoff team_id), Fase D (políticas/#53 — a triagem
> via `assign_ai_agent` já substitui o conceito).

> **Decisão do Paulo (11/06):** acabar com "uma Clara com cenários". Cada IA = um agente
> independente, atribuível a conversa como um atendente, com time. **A IA só responde
> conversas atribuídas a ela** — sem router de whitelist/etiqueta/flag.
>
> **Status: PLANEJADO, não iniciado.** Executar na `homologacao`, validar na sandbox
> SimplexIA (número Cloud API), e só então virar a Tozi. Esforço total: **~2 semanas dev**.
> Análise de viabilidade: 6 agentes sobre o código em 11/06 (~316 leituras, citações
> arquivo:linha abaixo). Veredito: **possível, ~70% do trilho já existe no core**.

---

## 1. Decisões fechadas (11/06)

| # | Decisão | Resolução |
|---|---|---|
| D-A1 | Trilho da atribuição | **(A) AgentBot-espelho por Captain::Assistant** (novo `bot_type: :captain` + ref ao assistant). Paulo delegou; cravado pelo Claude: zero migration em conversations, callback de exclusividade (`conversation.rb:318-322`), endpoint e FunnelAutomationListener funcionam de graça |
| D-A2 | Humano × conversa da IA | **Composer BLOQUEADO com "Assumir conversa"**: conversa atribuída à IA não aceita resposta pública de humano; o atendente clica "Assumir conversa" (self-assign → callback limpa a IA → composer libera). Nota privada continua sempre liberada. Guard também no backend (não só UI) |
| D-A3 | Cenários | **Mantidos SÓ como comportamento (subprompts)**: a tabela `captain_scenarios` e a aba viram editor de subprompts concatenados no prompt do agente; deixam de ser roteamento |
| D-A4 | Gate de resposta | A IA só responde conversa atribuída a ela. RouterService (whitelist/skip_labels/skip_after_human_response/trava `atendimento_humano`) é aposentado; sobram guards técnicos (activity, conteúdo vazio, grupos) |
| D-A5 | Time da IA (MVP) | Sem schema novo: automação atribui `assign_team` + `assign_ai_agent` em par. Membership polimórfica em Team fica pra depois (G) |
| D-A6 | Regra #53 | **Morre na virada** (obrigatório: zeraria a atribuição da IA a cada reabertura) — substituída por triagem que ATRIBUI |

## 2. O modelo-alvo em uma narrativa

Lead manda mensagem → conversa SEM dono → **triagem** (automação ou agente triador) atribui
time + agente IA do nicho → a IA responde como atendente (nome/avatar dela no card e nas
bolhas — `assistant.rb:20,35,90-99` já suporta) → lead esquenta → IA faz handoff: atribui o
corretor (com `team_id`) → **o callback limpa a atribuição da IA → ela cala** → atendente vê
a conversa normal. Se um humano quiser intervir antes: clica "Assumir conversa". Se quiser
devolver pra IA: atribui o agente IA de volta (seletor ou macro). Transferência IA→IA = tool
que troca a atribuição. Piloto/teste = atribuir a IA só às conversas de teste. **Sem flags.**

O que morre de graça: whitelist `only_contact_phones`, label `atendimento`, trava
`atendimento_humano`, `skip_after_human_response`, pending limbo, e o hop duplo do 1º turno
(orquestrador→cenário — latência e tokens ×2 hoje).

## 3. A base que JÁ existe (por que é ~70% pronto)

| Peça | Onde |
|---|---|
| Coluna `conversations.assignee_agent_bot_id` + índice parcial | migration `20251022162159`, `schema.rb:726,736` |
| AssignmentService com `assignee_type='AgentBot'` (bot e humano mutuamente exclusivos) | `assignment_service.rb:8-42` |
| `POST /assignments` aceita `assignee_type` | `assignments_controller.rb:15-23,42-44` |
| Atribuir humano LIMPA o bot (= "transferiu → IA cala") | `reset_agent_bot_when_assignee_present`, `conversation.rb:318-322` |
| Precedente "bot da conversa vence bot da inbox" | `agent_bot_listener.rb:47-53` |
| Pipeline de resposta recebe o assistant como argumento (selector é o único ponto inbox-keyed) | `hook_execution_service.rb:110-117` |
| Assistant com zero cenários já roda (spec coberta) | `agent_runner_service.rb:171`, spec `:178-191` |
| Subprompt pronto: `Scenario#resolved_instructions/resolved_tools` | `scenario.rb:62-71,104-115` |
| Store front `captainAssistants` registrado | `store/index.js:53` |
| Receita de automation action nova (copiar do `add_sla`) | `enterprise/automation_rule.rb:6-8`, `constants.js:717-721` |
| Molde de tool que atribui (copilot `assign_conversation`) | `assign_conversation_service.rb:11-29` |
| HandoffTool com TODO de team_id já desenhado | `handoff_tool.rb:74-84` |

## 4. Fases e tarefas

### Fase A — Backend: trilho + gate (M, ~2-3 dias)
| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| A1 | `bot_type :captain` no AgentBot + ref ao assistant + criação/sync automática do espelho (nome/avatar) ao criar/editar assistant | `agent_bot.rb:37`, migration leve (ref), hook no assistant | P |
| A2 | Gate novo: `should_process_captain_response?` checa "conversa atribuída a um assistant"; assistant resolvido pela CONVERSA | `hook_execution_service.rb:7-9,32-44,109-140,164-166` | M |
| A3 | Re-checar atribuição DENTRO dos jobs (job em voo cala se trocou o dono) | `response_builder_job.rb:299-302`, `debounced_response_job.rb:4-21`, `followup_job.rb:38` | P |
| A4 | Migrar call-sites de `inbox.captain_assistant` | `captain_listener.rb:6-8`, `inbox_pending_conversations_resolution_job.rb` (re-keyar ou aposentar), copilot_trigger, endpoint `inbox_assistant` | P |
| A5 | `CaptainInbox` vira ELEGIBILIDADE (quais IAs atuam na inbox): remover `validates :inbox_id, uniqueness` + has_one→has_many | `captain_inbox.rb:21`, `enterprise/concerns/inbox.rb:5-8` | P |
| A6 | Aposentar RouterService mantendo guards técnicos (activity/vazio/grupos) | `router_service.rb` | P |
| A7 | Guard backend do D-A2: outgoing público de User em conversa com IA atribuída → 422 "Assuma a conversa" (nota privada passa) | `Messages::MessageBuilder` / message validation | P |
| A8 | Cota zerada: handoff explícito em PT (hoje EN hardcoded) re-keyado pra conversa | `hook_execution_service.rb:142-154` | P |
| A9 | Decidir destino de `active_bot?`/`pending_status_enabled`/auto-resolve no modelo novo (pending-de-bot morre estruturalmente) | `enterprise/inbox.rb:10-22`, `conversation.rb:340-351`, `message.rb:468-478` | P |

**Aceite Fase A:** numa inbox de teste com 2 assistants elegíveis: conversa sem atribuição →
IA muda; atribuir IA-1 → responde; atribuir IA-2 → IA-2 responde e IA-1 cala; atribuir
humano → IA cala (callback); debounce em voo após troca de dono → descartado.

### Fase B — Agentes independentes + subprompts (P-M, ~1-2 dias)
| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| B1 | Prompt de ATENDENTE no v2: `config['instructions']` passa a valer (hoje o runner v2 IGNORA — armadilha conhecida) + template variante sem identidade de orquestrador | `assistant.liquid:5,64-71`, `assistant.rb:131-146`, `agentable.rb:15-29` | P |
| B2 | Subprompts: concatenar `resolved_instructions` dos cenários habilitados no prompt do agente; runner para de mapear cenários como agentes (1 linha) | `agent_runner_service.rb:167-175`, `assistant.liquid` | P |
| B3 | Tools de negócio armadas no assistant: `config['tools']` validado contra `available_agent_tools` (hoje assistant sem cenário nasce SEM buscar_imovel!) | `assistant.rb:118-129`, reusar `resolve_tool_instance` (`scenario.rb:117-127`) | P |
| B4 | Histórico legado: mensagens com `agent_name='scenario_X...'` caem no default da gem silenciosamente — validar em homolog; limpar persistência do agent_name | `response_builder_job.rb:76,247-258` | P |
| B5 | Script de criação dos agentes por nicho + duplicação de knowledge (Playbook + 40 Q&A por assistant; chunks/embeddings re-geram via after_commit) | script rake (precedente: `aws_create_faq.rb`) | P |
| B6 | Opcional: modelo LLM por assistant (`config['model']` com fallback pra conta) | `agentable.rb:45-48` | P |
| B7 | ScenariosTab re-rotulada "Comportamentos/Subprompts" (CRUD sobrevive intacto) | `ScenariosTab.vue` | P |

**Aceite Fase B:** agente standalone (sem cenários) responde com o prompt rico + usa
buscar_imovel; subprompt habilitado muda o comportamento sem criar segundo agente LLM;
1º turno sem hop (1 chamada).

### Fase C — UI + automação (M, ~2-3 dias)
| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| C1 | Seletor "Agente IA" no sidebar da conversa (dropdown próprio, abaixo do de agente; fonte: store `captainAssistants`) + dispatch com `assignee_type` | `ConversationAction.vue:301-391`, `api/inbox/conversation.js:94-98` | M |
| C2 | D-A2 visual: composer bloqueado em conversa da IA — banner "Atendida por {IA}" + botão **"Assumir conversa"** (self-assign → libera); aba de nota privada segue ativa | `ReplyBox.vue` + i18n en/pt_BR | M |
| C3 | Conversa da IA NÃO aparece como "Não atribuída": serializar assignee-IA + scopes/finder/contadores + badge no card | `_conversation.json.jbuilder:37-60`, `conversation.rb:82-84`, `conversation_finder.rb:168-173`, ConversationCard | M |
| C4 | Automation action `assign_ai_agent` (receita do add_sla) — macros herdam de graça | `enterprise/automation_rule.rb`, `enterprise/action_service.rb`, `constants.js`, `automationHelper.js` | P |
| C5 | HandoffTool: `team_id` + manter dono quando a conversa já tem corretor (decisão 2.2 do DECISOES) | `handoff_tool.rb:26-84` | P |
| C6 | Tool `transferir_para_agente` (IA→IA): troca atribuição + enfileira ResponseBuilder do novo | novo arquivo, molde `assign_conversation_service.rb` | P |

**Aceite Fase C:** atendente atribui IA pela UI; card mostra a IA como dona; humano não
consegue responder sem "Assumir"; automação de label→`assign_team`+`assign_ai_agent`
funciona; handoff IA→corretor mantém time certo e notifica (T5 já ligado).

### Fase D — Políticas e limpeza (P, ~1 dia)
| ID | Tarefa | Onde | Esf. |
|---|---|---|---|
| D1 | Matar/substituir a regra #53: regra nova só re-triagem órfãs REAIS (reopen sem dono ativo) | automation em prod + doc | P |
| D2 | Varredura de `update_columns` nos scripts de operação (pulam o callback de exclusividade — mesma classe do bug 403); padronizar `AssignmentService` nos scripts | `scripts/spx/tozi/*` | P |
| D3 | Specs dos caminhos críticos novos (gate por atribuição, guard do composer, exclusividade) | spec/enterprise | M |
| D4 | Telemetria: AssistantLog ganha eventos de atribuição/assunção (auditoria da virada) | `assistant_log` | P |

## 5. Migração da Tozi (quando for executar)

1. **NUNCA deletar a Clara** antes de copiar — `destroy` cascateia documents/Q&A/chunks
   (`assistant.rb:27-39`). Criar os agentes novos AO LADO (Júlia/Vendas, Locação,
   Letícia/Financeiro), duplicar knowledge via script (B5), configurar behavior baseline
   (debounce/humanizer/business_hours documentado — senão drift silencioso entre agentes).
2. Validar tudo na **sandbox SimplexIA** primeiro (roteiro §6).
3. Virada na inbox 91: registrar elegibilidade dos agentes (CaptainInbox), criar a automação
   de triagem (intenção → team + agente IA), desativar a #53, e o "switch" vira: **a triagem
   começa a atribuir os agentes**. Rollback = desativar a automação de triagem (as conversas
   já atribuídas a humanos não mudam).
4. Aposentadoria da Clara #7: desconectar elegibilidade, manter o registro como arquivo
   morto (knowledge preservada como fonte).

## 6. Roteiro E2E adaptado (substitui os 13 testes do plano antigo)

| # | Teste | Esperado |
|---|---|---|
| 1 | Conversa nova sem atribuição | IA MUDA (nada de resposta) |
| 2 | Atribuir agente Vendas pela UI | responde no tom Vendas, card mostra a IA como dona |
| 3 | "quero alugar 3 quartos até 2.500" | buscar_imovel → opções reais (tools armadas no assistant, B3) |
| 4 | Áudio + foto | transcreve/entende (gates de áudio já abertos em prod) |
| 5 | FAQ ("aceitam pet?") | responde da knowledge DUPLICADA do agente certo |
| 6 | Subprompt habilitado vs desabilitado | comportamento muda, sem segundo agente LLM |
| 7 | Silêncio 2-3 min | follow-up vem do MESMO agente (FollowupJob re-keyado, A3/A4) |
| 8 | "quero falar com corretor" | handoff: corretor atribuído com team, IA cala (callback), push chega |
| 9 | Humano tenta digitar em conversa da IA | composer bloqueado; "Assumir conversa" libera e IA cala |
| 10 | Transferir IA→IA (tool) | agente novo assume com a knowledge dele |
| 11 | Resolver + lead volta | reabre open SEM dono → triagem re-atribui (sem #53, sem pending) |
| 12 | "blz" | [IGNORAR] (comportamento preservado) |
| 13 | Debounce em voo + assumir humano no meio | job descartado, IA não fala por cima (A3) |
| 14 | Reatribuição em massa via script | usa AssignmentService, exclusividade preservada (D2) |

## 7. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| `update_columns` em massa pula o callback de exclusividade | D2 (padronizar AssignmentService nos scripts) |
| Jobs serializados com assistant antigo durante o deploy da virada | A3 (re-check dentro do job) + janela de deploy calma |
| Knowledge duplicada ×N → drift de conteúdo entre agentes | aceito pro tamanho atual (1 doc + 40 Q&A); editar = ação ×N documentada; compartilhamento real é projeto G futuro |
| `AssistantResponse.search` não escopa sozinho (vaza Q&A entre agentes/contas) | regra de código: SEMPRE via association `assistant.responses` |
| `agent_name` legado no histórico cai no agente default silenciosamente | B4 (validar em homolog + limpar persistência) |
| Cota captain por conta: N agentes queimam o mesmo pote | monitorar; mensagem de cota em PT (A8) |
| #53 ativa zera atribuição da IA | D1 obrigatório na virada |

## 8. Encaixe na sequência macro

**Pré-requisitos:** sandbox SimplexIA montada (Etapa 2 do plano macro) · decisões Grupos 2-8
do DECISOES-CLARA que sobrevivem (várias morrem com este modelo: 2.4 whitelist, 2.6
router_skip, parte da 3.x — a triagem por intenção do 3.5 passa a ATRIBUIR agente em vez de
depender de etiqueta pro router).

**Posição:** este plano SUBSTITUI parte da Onda 2 ("Mãos") do roadmap com um modelo melhor —
e o go-live da Clara (T7/T9/T10/T12 pendentes) deve acontecer JÁ neste modelo (religar no
modelo velho = pagar a gambiarra duas vezes). As Ondas 1 (percepção), 3 (memória) e 4.1
(vigia SLA) não conflitam e podem correr em paralelo.
