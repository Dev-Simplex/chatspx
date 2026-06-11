# Progresso — Plano IA Consolidado (execução autônoma /loop ultracode)

> Estado vivo da execução do `plano/ia-consolidado.md`. Atualizado a cada tarefa.
> Iniciado em 2026-06-11. Branch: detached HEAD @ 428e97b24 (homologação). Working tree only — NUNCA commit/push/deploy.

## Legenda
- `[ ]` pendente · `[~]` em andamento · `[x]` concluída com aceite comprovado · `[!]` bloqueada

## Estado do ambiente (verificado 2026-06-11)
- Repo: `/home/chatwoot/chatwoot`, detached HEAD @ 428e97b24, working tree com `M public/version.json` (pré-existente, não tocar)
- Serviço: `chatwoot.target` ativo, HTTP 200 em `localhost:3000`
- Restart permitido: `sudo systemctl restart chatwoot.target`
- Evidências: `plano/evidencias/`

---

## Fase 0 — Fix do reload na atribuição (P) — ✅ CONCLUÍDA (2026-06-11)
- [x] 0.1 `router.push` substituído por navegação CONDICIONAL (ver AD-2) em `assignedTeam` setter, `assignAgentDirect`, `onConfirmTransferTeam` (`ConversationAction.vue`)
- [x] 0.2 Idem no `onAssignTeam` (`ChatList.vue`) — só navega se a conversa afetada é a aberta E acesso perdido
- [x] 0.3 Conferido por agente explorador: store atualiza in-place (ASSIGN_AGENT/ASSIGN_TEAM mutations + ActionCable reconcilia); `beforeRouteLeave` é guarda genérica sem dependência de atribuição; nenhum consumidor depende da navegação
- [x] **Aceite F0 COMPROVADO**: Playwright P1+P2 light+dark 4/4 PASS, zero console errors, zero navegação; vitest 11/11. Evidências: `plano/evidencias/f0-validacao.md` + 8 screenshots + `f0-vitest-output.txt`. Exceção documentada (AD-2): navegação residual APENAS em perda real de acesso (não-admin, time alheio, não-assignee), com toast explicativo i18n.

**Artefatos F0**: `app/javascript/dashboard/helper/conversationAccessHelper.js` (novo) + spec (11/11 verde); edits em `ConversationAction.vue`, `ChatList.vue`, i18n `pt_BR/conversation.json` + `en/conversation.json`. ESLint limpo (2 warnings pré-existentes de chave i18n dinâmica, fora do escopo).

**Ciclo de revisão adversarial F0 (4 lentes)** — achados e fixes aplicados:
1. ~~BLOCKER (regression)~~ guard do ChatList era dead-code em 6 rotas (`:conversationId` camelCase vs `:conversation_id`) → fix: lê ambos os params.
2. ~~BLOCKER (ux)~~ assignee stale em troca de time: backend `ensure_assignee_is_from_team` limpa/realoca assignee não-membro do novo time → fix: sites de troca de time passam `assigneeId: null` (acesso pós-troca = admin ∥ membro do novo time).
3. ~~MAJOR (ux)~~ ejeção silenciosa → fix: toast novo `CONVERSATION.ASSIGNMENT_ACCESS_LOST` (pt_BR+en) antes da navegação; pt_BR de `CHANGE_TEAM` estava mistraduzido ("Status da conversa mudou") → corrigido p/ "Time da conversa alterado"; `CHANGE_TEAM_FAILED` criado (pt_BR+en).
4. ~~MAJOR (tests)~~ mutante sobrevivente no guard de identidade → specs de identidade degenerada (undefined/null/0) + coerção simétrica `Number()` p/ assignee + `!Number(teamId)` (string '0').
5. ~~MINOR~~ setter `assignedTeam` sem rethrow/catch → fix: `rethrow: true` + rollback do update otimista + toast de falha (supera AD-3 parcialmente). `ChatList.onAssignTeam` ganhou `rethrow: true`.
6. ~~MINOR~~ falha parcial em `onConfirmTransferTeam` (time commitado, agente falhou) pulava o guard → fix: flag `teamApplied`, guard roda no catch com `assigneeId: null`.
7. ~~MINOR~~ `getMyTeams` vazio pré-fetch → fail-open: guard early-return se store de teams vazio.
8. Registrados como pendência (fora do escopo F0, pré-existentes): fluxos sem guard (hotkeys/command bar, `useResolveValidation`, bulk actions, ReplyBoxBanner), drift de membership em sessão, `validate_team_param_access` não modelado (documentado no docstring do helper).

## Fase A — Backend: trilho AgentBot + gate da IA (M) — ✅ CONCLUÍDA (backend; falta E2E LLM de go-live)
- [x] @architect: revisão do desenho contra o código real (workflow `fase-a-architect`, 4 exploradores + síntese) → **`plano/fase-a-design.md`** (812 linhas, drift verificado, ZERO openQuestions de produto). Tarefa nova obrigatória descoberta: **A2b** (auto-assignment round-robin não pode roubar conversa da IA — scope `:unassigned` ignora `assignee_agent_bot_id`). Ordem: A1 → (A2+A6+A8 núcleo ∥ A3, A7, A2b) → A4 → A5+A9 → fechamento
- [x] A1 `bot_type :captain` + ref assistant + sync espelho — **implementado e NO AR** (migration `captain_assistant_id` aplicada em homolog+test, `AssistantMirrorService`, hooks, guard webhook no listener, CRUD protegido com 422+i18n, rake backfill → 12 espelhos; **148 specs/0 falhas**, RuboCop limpo; restart feito, app 200)
- [~] A2 Gate por atribuição da CONVERSA — **implementado** (hook_execution_service: assigned_assistant, 5 pontos re-keyados, supressão por elegibilidade, trava atendimento_humano removida); specs do hook reescritos verdes. Aguarda suíte integrada + review
- [~] A3 Re-check nos jobs — **implementado** (response_builder pré-LLM + pré-envio + **por chunk** no humanizer; debounced early-return por dono; followup re-keyado + reordenado). 43 specs/0 falhas
- [x] A4 Migrar call-sites de `inbox.captain_assistant` — **implementado** (reply_suggestion, captain_listener por dono/participante, endpoint, resolution_job com `assistant_for` + Current.executed_by no loop, scheduler dedupe por inbox). Grep do singular = 0 → A5 liberado. 49 specs (2 falhas pré-existentes de activity_reason lifecycle). ⚠️ usa fallback `inbox.captain_assistants.first` que SÓ funciona após A5 landar (mesmo change-set)
- [x] A5 CaptainInbox vira elegibilidade — **implementado** (uniqueness composta `{scope: :captain_assistant_id}`, has_many `captain_inboxes`/`captain_assistants through`; zero migration). Destravou o fallback do A4. 26 specs A5/A9 verdes
- [~] A6 RouterService enxuto in-place — **implementado** (sobram activity/vazio/skip_groups; morreram whitelist/skip_labels/skip_after_human_response/bug agent_bot_id)
- [~] A7 Guard 403 admin-only — **implementado** (controller set_agent, render :forbidden explícito, i18n `conversations.captain.assignment_forbidden` pt_BR+en). 15 specs/0 falhas
- [~] A8 Handoff de cota PT re-keyado + desatribui espelho — **implementado** (I18n.with_locale da conta, sender=assistant)
- [~] A2c (nova) outgoing público de User desatribui espelho — **implementado** (Enterprise::Message, human_response?)
- [~] A2b-expandida (4 caminhos auto-assignment) + invariante de exclusividade — **implementado** (legado/bulk/team-change/V2; specs de invariante nos 4 fluxos)
- [~] A2e (nova) resolve limpa dono-espelho — **implementado** (before_save captain-only; snooze não limpa; webhook preservado)
- [x] A2d (nova) gatilho pós-atribuição cutuca pipeline — **implementado** (`AssignmentKickJob` + callback; re-usa o entry do hook; 9 specs/0)
- [x] A9 `active_bot?`/`pending_status_enabled`/auto-resolve — **implementado** (`captain_active?` re-keyado pra elegibilidade; A9.2-A9.4 = zero-edição: pending-de-bot já é gateado por `pending_status_enabled` default false → morre operacionalmente, preserva D-13; auto-resolve mantido como rede de segurança legada)
- [x] **Aceite FA backend COMPROVADO**: 13 tarefas implementadas; boot OK; suíte integrada 331/3 (3 pré-existentes); review adversarial 5 lentes (4 ✓ + 1 blocker corrigido); conjunto de aceite mapeado bullet-a-bullet 143/1 (só SLA/avatar pré-existente). Evidências: `plano/evidencias/fase-a-aceite.md` + `fase-a-suite-integrada.txt`. **Falta (go-live, não-autônomo)**: E2E §5.3 com LLM real na sandbox SimplexIA (precisa API keys) + decisão de produto AD-10 (gate sem flag em modo Clássico).

**Ciclo de review adversarial Fase A (5 lentes)** — `correctness-gate` ✓, `regression-pipeline` ✓, `security-403-sync` ✓, `product-i18n-deploy` ✓ (i18n/migration/rake APROVADOS), `invariant-exclusivity` ✗→corrigido:
- ~~BLOCKER~~ **guard A2b quebrava o handoff IA→humano**: `HandoffTool` usa o mesmo `AgentAssignmentService#perform` que o guard A2b bloqueia, mas `bot_handoff!` não limpava o espelho → corretor não era atribuído e a IA continuava respondendo (violava D-6 e E2E #8). **FIX**: `HandoffTool#trigger_handoff` agora solta o espelho (`update!(assignee_agent_bot_id: nil) if ...captain?`) antes de atribuir — mesmo padrão do handoff de cota. +2 specs (solta espelho / atribui corretor) verdes; guards A2b sem regressão (28/0). O `handoff_tool_spec` antes não tinha NENHa assertion de assignee — por isso a regressão passou silenciosa.
- Achados menores adiados (documentados p/ relatório final, fora do escopo de aceite da Fase A): cota consumida se rajada do humanizer for interrompida no 1º chunk (sent:0 — LLM já rodou, defensável); invariante A2b pode quebrar com `assign_team`+`assign_ai_agent` em saves SEPARADOS (só ativa na Fase C, quando a action existir — registrar exigência de ordem ou limpeza no mesmo save); admin pode atribuir espelho de assistant não-elegível à inbox (gate por ownership ignora CaptainInbox — endurecer na Fase C/C8); A2c trata external_echo como resposta humana; sync do espelho engole StandardError (logado, sem sinal ativo); reopen pending pós-resolve volta a pending escondida sem triagem na Fase A.

## Fase B — Agentes independentes + subprompts (P-M) — ✅ VALIDADA (escopo AD-11: auditar, não implementar)
- [x] **VALIDAÇÃO CONCLUÍDA** (AD-11) — relatório completo em `plano/evidencias/fase-b-validacao.md`:
  - B1 **parcial**: `config['instructions']` JÁ VALE (commit `7e8353fa8` do outro dev — armadilha do plano desatualizada); falta remover identidade de orquestrador do template
  - Tools de negócio **existem e funcionam via cenários** (`buscar_imovel`, `enviar_fotos_imovel`, `programar_followup`, `salvar_info_lead`...) — caminho DIFERENTE do plano (cenários continuam sub-agentes; divergência com D-7 aceita via AD-11)
  - B5 coberto em espírito: `rake captain:export/import` (`captain_sync.rake`) sincroniza assistant entre ambientes com embeddings
  - B2/B3/B4/B6/B7: **não implementados** — gaps documentados, NÃO serão implementados (instrução do usuário); B4 (agent_name legado silencioso) e B3 (assistant sem cenário = sem tools) viram considerações de desenho da Fase C (C7)
- [x] **Aceite FB**: substituído pela validação (AD-11). Funcional comprovado pela equipe de 6 agentes na sandbox (commit `428e97b24`)

## Fase C — UI: identidade da IA + atribuição + tab "IA" (M)
- [ ] C1 Seção "Agentes IA" na página de usuários/agentes (read-only)
- [ ] C2 Seletor "Agente IA" no sidebar (admin-only)
- [ ] C3 Assignee-IA serializado + scopes/finder/contadores + badge "IA" no card
- [ ] C4 Tab "IA" no lugar de "Não atribuídas" (Minhas/IA/Todas) + tab condicional de alerta
- [ ] C5 Automation action `assign_ai_agent`
- [ ] C6 HandoffTool com `team_id` + manter dono
- [ ] C7 Tool `transferir_para_agente` (IA→IA)
- [ ] C8 Spec: espelhos captain fora de assignable_agents/round-robin/relatórios
- [ ] C9 Remover opção "None" da atribuição manual (flag ligada)
- [ ] C10 Vigia de órfãs (job/automação + notificação admin)
- [ ] **Aceite FC**: roteiro §4 Fase C + Playwright P3-P6 light+dark + specs 5.1-C

## Fase D — Gate universal de resposta (M)
- [ ] D1 Guard backend `assignment_required` (422) atrás da flag `reply_assignment_gate`
- [ ] D2 Dialog "Quer atribuir a você?" — 4 variantes, mensagem nunca se perde
- [ ] D3 Banner proativo atualizado (CTA abre o dialog)
- [ ] D4 Notificar assignee anterior quando colega assume
- [ ] D5 i18n completo pt_BR + en (spec de paridade)
- [ ] D6 Tratamento do 422 no frontend (corrida → dialog atualizado)
- [ ] D7 Toggle "Modo de atendimento" nas configurações da conta
- [ ] D8 Stack de efeitos visuais (§9-10: motion-v, number-flow, auto-animate, confetti, tailwindcss-animated)
- [ ] **Aceite FD**: roteiro §4 Fase D + Playwright P7-P13 light+dark + specs 5.1-D

## Fase E — Políticas e limpeza (P)
- [ ] E1 Matar/substituir regra #53 (doc — execução em prod é da virada)
- [ ] E2 Varredura `update_columns` nos scripts spx/tozi → AssignmentService
- [ ] E3 Specs dos caminhos críticos
- [ ] E4 Telemetria: AssistantLog eventos de atribuição/assunção
- [ ] E5 Nota no vault: `Padrao - IA como atendente via AgentBot-espelho` + lições
- [ ] **Aceite FE**: specs verdes + notas no vault

## Encerramento
- [ ] `plano/ia-relatorio-final.md`
- [ ] Lições registradas no vault
- [ ] Loop encerrado

---

## Decisões tomadas em autonomia
| # | Data | Decisão | Justificativa |
|---|------|---------|---------------|
| AD-1 | 2026-06-11 | Manter repo em detached HEAD @ 428e97b24, sem criar branch | Working tree only por regra; criar branch não é necessário para editar e seria mudança de estado git desnecessária |
| AD-2 | 2026-06-11 | Fase 0: remoção dos `router.push` NÃO foi seca — virou navegação condicional via helper `losesConversationAccess` que espelha `authorize_team_access` (conversations_controller.rb:231-245, custom do fork) | Exploração descobriu que o push mascarava um 403: não-admin que transfere conversa para time do qual não participa (sem ser assignee) perde acesso à conversa aberta — `update_last_seen` automático passaria a falhar em loop. D-10 preservado em todos os cenários comuns (admin, self-assign, membro do time); navegação residual SÓ quando o acesso é comprovadamente perdido (mesmo destino do push antigo). Cenário não contradiz D-1..D-13 |
| AD-3 | 2026-06-11 | ~~Não corrigir~~ ausência de `.catch` no setter `assignedTeam` → SUPERADA: rethrow+rollback+toast implementados no ciclo de revisão F0 | Revisores apontaram que o guard de acesso exigia estado real do backend |
| AD-4 | 2026-06-11 | Fase A/A1: coluna `agent_bots.captain_assistant_id` (FK `on_delete: :nullify` + índice único parcial) em vez de `bot_config['assistant_id']` | bot_config não tem consumidor backend, índice nem integridade referencial; detalhes em `fase-a-design.md` §A1 |
| AD-5 | 2026-06-11 | Fase A/A7: guard 403 SÓ no controller de assignments (não no AssignmentService/policy como o plano sugeria) | `Macros::ExecutionService` seta `Current.user` = agente executor — guard no service bloquearia macro de agente comum, contradizendo D-3; Pundit renderiza 401 (não 403) — `render :forbidden` explícito |
| AD-6 | 2026-06-11 | Fase A/A5: zero migration — índice DB já é único no par; validação vira uniqueness composta; flip has_one→has_many só após grep do singular zerar | Índice `(captain_assistant_id, inbox_id)` já existe; remover validação errada quebraria menos do que parece, mas o guard `respond_to?` no hook desligaria o captain silenciosamente |
| AD-7 | 2026-06-11 | Fase A/A2: supressão de greeting/OOO mantida por ELEGIBILIDADE (CaptainInbox.exists?), não por atribuição | Por atribuição pura, conversa nova receberia greeting automático na janela criação→triagem (regressão visível ao lead) |
| AD-8 | 2026-06-11 | Fase A/A8: handoff de cota re-keyado pra atribuição + DESATRIBUI o espelho; mensagem via chave i18n existente `conversations.captain.handoff` no locale da conta | Sem o re-key vira no-op silencioso; sem desatribuir vira spam a cada incoming |
| AD-9 | 2026-06-11 | Crítico refutou 5 pontos do núcleo → design em rev2 com tarefas novas: **A2b-expandida** (4 caminhos de auto-assignment + invariante de exclusividade no team-change da triagem), **A2c** (outgoing público de User desatribui espelho — sucessor transitório do `skip_after_human_response`, revisar na Fase D), **A2d** (gatilho pós-atribuição cutuca pipeline — corrida triagem assíncrona × 1º turno), **A2e** (resolve limpa dono-espelho — narrativa §2/teste 11), re-check por CHUNK no humanizer (A3), critérios do backfill expandidos | Achados verificados contra o código pelo crítico; nenhum contradiz D-1..D-13 — são correções técnicas do desenho |
| AD-10 | 2026-06-11 | **NOTA DE PRODUTO (go-live/Fase D, não bloqueia homolog)**: conta em modo Clássico (D-13) com CaptainInbox e sem triagem ficaria com canal silencioso (gate sem atribuição + greeting suprimido por elegibilidade). Supressão por elegibilidade = comportamento atual (sem regressão); a combinação só ocorre em configuração que o rollout §6 evita | Crítico apontou; decisão de condicionar gate/supressão ao modo da conta fica para quando o toggle D7 existir — registrar no relatório final p/ Walisson |
| AD-11 | 2026-06-11 | **Fase B: escopo alterado pelo usuário** — B1-B7 já foram implementados por outro dev; minha tarefa passa a ser VALIDAR o código existente contra os requisitos B1-B7 e o aceite da fase (auditoria + specs), registrando o que está feito/faltante, e seguir para a Fase C | Instrução direta do usuário (Walisson) em 11/06 ~21:50 UTC: "pode pular essa fase, isso meu amigo já fez, se você validar o código para ver o que ele fez" |

## Pendências / bloqueios
- **Follow-ups F0 (pré-existentes, fora do escopo 0.1/0.2 — candidatos à Fase D, que redesenha esses fluxos):** command bar/hotkeys (`useConversationHotKeys.js` onChangeTeam/onChangeAssigneeWithTeam — sem guard, catch silencioso), context menu/bulk de AGENTE (`useBulkActions.onAssignAgent` → BulkActionsJob assíncrono, sem guard), `useResolveValidation` (assignTeam ao resolver), `ReplyBoxBanner`. Todos fail-open (usuário fica na conversa; pode tomar 403 em ação subsequente — mesmo comportamento de antes da F0)
- Rollback do setter `assignedTeam` em trocas consecutivas rápidas pode sobrescrever valor commitado até o websocket ressincronizar (janela improvável; mitigação documentada no achado)
- Novas chaves i18n só em en+pt_BR (padrão do fork; demais locales caem no fallback en)
- **Drift de schema pré-existente (descoberto no A1)**: tabelas `funnels`/`funnel_stages`/`funnel_items` existem no `schema.rb` commitado mas NENHUMA migration as cria; o banco de PRODUÇÃO homolog também não as tem — `create_default_funnel` falha (rescued) em toda criação de account. Test DB corrigido via DDL manual; sugerir migration formal ao Walisson. Lição no vault: `Licao - Schema drift funnels no fork Chatwoot`
- Espelho captain cria AccessToken (herdado do AgentBot) — superfície de credencial nunca exposta na UI; follow-up opcional documentado no design
- Specs e2e copilot (`spec/e2e/`) exigem `@playwright/test` não instalado; validação Playwright da F0 será via script ad-hoc `require('playwright')` (browsers chromium-1217 já baixados e headless verificado)

## Infos de validação (recon 2026-06-11)
- Usuário de teste Playwright: `playwright-test@simplex.local` / `Pl4ywR1ght!Test` (user 52, admin nas accounts 1-SimplexIA e 3) — login verificado. NUNCA tocar contas reais (35 users reais no banco)
- Dark mode: localStorage `color_scheme` (light|dark|auto), classe `dark` em `document.body` (themeHelper.js), Tailwind `darkMode: 'class'`
- Specs frontend: Vitest 3.0.5 — `TZ=UTC pnpm exec vitest run --no-coverage <path>`
- App em RAILS_ENV=production: mudança de frontend exige `assets:precompile` + restart antes do Playwright

## Log de iterações
- **2026-06-11 it.1**: progresso criado; vault consultado (ROUTER - Engineering, CLAUDE.md do vault); ambiente verificado (serviço ativo, arquivos Fase 0 existem). Workflow `fase0-explore` (4 agentes): drift mínimo de linhas; achado crítico do 403 mascarado (→AD-2). Implementação F0 concluída (helper+spec+4 sites). ESLint ok, vitest 8/8. Workflow `fase0-review` (4 lentes adversariais) em andamento.
- **2026-06-11 it.2**: review adversarial retornou 2 blockers + majors → todos corrigidos (ver "Ciclo de revisão"). Workflow `fase0-verify-fixes` (2 verificadores): **ready ✓ / ready ✓** — sobraram minors/nits; 2 corrigidos na hora (toast errado na falha do passo de time em `onConfirmTransferTeam`; race de navegação — guard agora confere `conversationId` da ação vs conversa aberta), resto em pendências. Vitest 11/11, ESLint limpo. Precompile v1 OK + restart OK (app 200). Precompile v2 (fixes finais) em andamento → próximo: restart + Playwright P1/P2 light+dark.
- **2026-06-11 it.3**: precompile v2 + restart OK. Validação Playwright F0: **4/4 PASS** (P1/P2 light+dark, zero console errors, zero navegação) → **Fase 0 ACEITA** com evidências. Workflow `fase-a-architect` concluído → `plano/fase-a-design.md` (zero openQuestions; AD-4..AD-8 registradas; tarefa nova A2b). Workflow `fase-a-impl-1` lançado: @dev implementa A1 (espelho AgentBot + migration + specs) ∥ crítico adversarial do núcleo A2/A6/A8/A2b.
- **2026-06-11 it.4**: A1 **done** (148 specs/0 falhas, 12 espelhos, RuboCop ok) + restart → A1 no ar. Crítico do núcleo: **ready=false, 5 majors** (auto-assignment legado/bulk/team-change roubando conversa da IA; humano-sem-se-atribuir não cala IA; rajada do humanizer fora do re-check; corrida triagem assíncrona × 1º turno; critérios do backfill) + nota de produto D-13 (→AD-10). Workflow `fase-a-design-rev2` lançado: arquiteto incorpora os fixes no design (A2b-expandida, A2c, A2d, A2e).
- **2026-06-11 it.5**: design **rev2** pronto (adendo pós-crítica, divergências 13-21, mapa de aceite +5, riscos +7). Workflow `fase-a-impl-2` lançado: 4 implementadores paralelos — núcleo atômico (A2+A6+A8+A2c), A3 (re-check por chunk + followup), A7 (guard 403), A2b-expandida+A2e — specs serializados via flock.
- **2026-06-11 it.6**: `fase-a-impl-2` concluído — **4/4 done**. Núcleo: 70+108 specs/0 falhas. A3: 43/0. A7: 15/0. A2b/A2e: 13 examples novos verdes (falhas remanescentes = drift pré-existente do fork, ex. AvatarFromUrlJob aridade, SLA — não relacionadas). 49 arquivos de código tocados no total. Vault ganhou 4 lições (git stash em working tree compartilhada; spec pending exige pending_status_enabled; specs upstream stale ActivityMessageJob por id; schema drift funnels). **PENDENTES da Fase A**: A4 (call-sites restantes), A5 (has_many), A2d (kick pós-atribuição), A9.
- **2026-06-11 it.7**: **suíte integrada Fase A = 241 examples, 1 falha** — a única é `conversation_spec.rb:17` (SLA activity), provada PRÉ-EXISTENTE do HEAD: `AvatarFromFaviconJob:9` chama `AvatarFromUrlJob.perform_now` com 2 args (espera 3); arquivos avatar idênticos ao HEAD (working tree limpo neles). Lote impl-2 compõe limpo. Portão do A5 conferido: faltam migrar `inbox.captain_assistant` em reply_suggestion/captain_listener/endpoint/resolution_job (os `mirror.captain_assistant` são API nova no AgentBot, sobrevivem). Workflow `fase-a-impl-3` lançado: A4 ∥ A2d.
- **2026-06-11 it.8**: `fase-a-impl-3` concluído — A4+A2d **done**. A4 zerou o grep do `inbox.captain_assistant` singular (libera A5); resolution_job re-keyado com `assistant_for` (dono→participante→inbox.captain_assistants.first); A2d adicionou `AssignmentKickJob` + callback `kick_captain_pipeline_after_mirror_assignment` (9 specs/0). Falhas remanescentes: 2 pré-existentes no resolution_job (lifecycle de `captain_activity_reason`) + SLA avatar. ⚠️ fallback do A4 depende do flip A5. Workflow `fase-a-impl-4` lançado: A5+A9 (destrava o fallback do A4).
- **2026-06-11 it.9**: `fase-a-impl-4` concluído — A5+A9 **done** (todas as 13 tarefas da Fase A implementadas). **Boot OK** + restart + app 200. **Suíte integrada completa Fase A = 331 examples, 3 falhas — TODAS provadas pré-existentes** (mecanismo de activity reason e jobs avatar idênticos ao HEAD; evidência em `plano/evidencias/fase-a-suite-integrada.txt`). Diffs gerados (`/tmp/fase-a-impl.diff` 1171 linhas, `/tmp/fase-a-specs.diff` 2429). Workflow `fase-a-review` (5 lentes adversariais) em andamento.
- **2026-06-11 it.10**: review adversarial retornou 4 ready ✓ + 1 BLOCKER (guard A2b quebrava handoff IA→humano). **Blocker corrigido**: `HandoffTool#trigger_handoff` solta o espelho antes de atribuir o corretor (padrão do handoff de cota) — +2 specs verdes, guards A2b 28/0. De carona, consertei 4 falhas pré-existentes de test-hygiene no `handoff_tool_spec` (stub `Conversation.where` estreito + spec stale do note sem reason) → arquivo 21/0, RuboCop limpo. **Conjunto de aceite Fase A: 143 examples, 1 falha (SLA/avatar pré-existente)**, mapeado bullet-a-bullet em `plano/evidencias/fase-a-aceite.md`. **Fase A backend ACEITA.** Próximo: Fase B.
- **2026-06-11 it.11**: `fase-b-explore` (1ª tentativa) falhou — 3 subagentes bateram no **limite de sessão** (reset 21:40 UTC). Pausa prevista no §8; às 21:46 UTC (pós-reset) o workflow foi relançado via resume do mesmo script. Modelo da sessão voltou a Fable 5 (usuário alternou para Opus durante a janela de limite).
- **2026-06-11 it.12**: usuário alterou o escopo da Fase B (AD-11: outro dev já fez; validar em vez de implementar). `fase-b-explore` concluído (3 clusters) + auditoria git (branch `paulao`): **Fase B VALIDADA** — relatório em `evidencias/fase-b-validacao.md` (B1 parcial ✓; tools via cenários ✓; captain:export/import cobre B5 em espírito; B2/B3/B4/B6/B7 são gaps documentados e aceitos). Divergência com D-7 aceita por instrução direta do usuário. Iniciando Fase C (exploração).
- **2026-06-11 it.13**: usuário liberou paralelismo máximo (sem dó de token). **Pipeline C∥D∥E**: `fase-c-explore` (4 agentes) + `fase-d-e-explore` (5 agentes: guard/422, replybox/dialog, notificação/toggle, efeitos visuais §9-10, fase E completa) rodando simultaneamente. Sequência prevista: explorações → designs (C e D em paralelo) → implementação em lotes de arquivos disjuntos (D7/flag cedo, pois C9/C10 condicionam nela) → reviews adversariais → Playwright P3-P13 light+dark.
- **2026-06-11 it.14**: `fase-c-explore` concluído (4 clusters, dossiê em `/tmp/fase-c-exploracao.json`). Achados-chave: (1) **bigint de feature_flags da conta CHEIO** (66/63) → flag `reply_assignment_gate` nasce em `account.settings` jsonb já na Fase C; (2) dropdown C2 precisa do **id do espelho AgentBot** (assignment_service resolve por AgentBot; mandar assistant.id falha silencioso) — payload do assistant sem avatar_url/agent_bot_id (gap a fechar); (3) serializer precisa de discriminador de tipo p/ assignee-IA (colisão id User×Bot); (4) None tem **4 pontos** de injeção (sidebar/command-bar/context-menu/bulk); (5) drift: finder é `app/finders/` (não services); unassigned_count hoje INCLUI conversas da IA. Workflow `fase-c-design` (@architect) lançado com decisões pré-tomadas. `fase-d-e-explore` segue rodando.
