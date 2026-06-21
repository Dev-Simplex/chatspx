# Relatório Final — IA como Atendente + Gate Universal de Resposta

> Execução autônoma do `plano/ia-consolidado.md` (Fases 0→A→B→C→D→E).
> Período: 2026-06-11 a 2026-06-12. Ambiente: VM homologação, branch `homologacao`.
> **Working tree only — nada foi commitado/pushado/deployado por mim.** Fases 0+A foram
> commitadas por humanos (`2bee0f724`); o restante está no working tree aguardando revisão.

---

## 1. Resumo executivo

| Fase | Escopo | Status |
|---|---|---|
| **0** | Fix do reload pós-atribuição | ✅ **ACEITA** — Playwright P1/P2 light+dark 4/4, vitest 11/11 |
| **A** | Trilho AgentBot-espelho + gate da IA por atribuição | ✅ **ACEITA (backend)** — 331 specs (3 falhas pré-existentes); review 5 lentes; falta E2E LLM real (go-live) |
| **B** | Agentes independentes + subprompts | ✅ **VALIDADA** (escopo alterado pelo usuário: outro dev já fez; auditei — ver §3 AD-11) |
| **C** | UI: identidade da IA + atribuição + tab "IA" | ✅ **IMPLEMENTADA + VALIDADA** — Playwright light+dark conta 3; suítes verdes |
| **D** | Gate universal de resposta + dialog + efeitos | ✅ **IMPLEMENTADA + VALIDADA** — dialog ao vivo capturado; guard/notif/dialog unit-testados |
| **E** | Políticas e limpeza | ✅ **IMPLEMENTADA + VERIFICADA** — 17 specs; runbook de virada |

**Pronto para revisão humana e merge.** Pendências de go-live em §5.

---

## 2. O que foi feito, por fase

### Fase 0 — Reload na atribuição
Os 4 `router.push` pós-atribuição (3 em `ConversationAction.vue`, 1 em `ChatList.vue`) viravam
navegação ao dashboard. Substituídos por navegação CONDICIONAL via novo helper
`conversationAccessHelper.js` que espelha o `authorize_team_access` do backend: só navega quando
o usuário REALMENTE perde acesso (não-admin, time alheio, não-assignee), com toast explicativo.
O review pegou 2 blockers (param de rota camelCase; assignee stale na troca de time) — corrigidos.

### Fase A — Trilho AgentBot-espelho + gate da IA (backend)
Cada `Captain::Assistant` ganha um **AgentBot-espelho** (`bot_type: :captain`, coluna FK
`captain_assistant_id`) sincronizado (nome/avatar) por `AssistantMirrorService` + hooks. A IA
vira atendente atribuível via `conversations.assignee_agent_bot_id`. O gate de resposta passou de
**inbox-keyed** para **"conversa atribuída ao espelho do assistant"** (resolvido pela CONVERSA).
13 tarefas (A1-A9 + A2b/A2c/A2d/A2e descobertas no review):
- A2b: 4 caminhos de auto-assignment deixam de roubar conversa da IA (preserva a invariante bot×humano).
- A2c: outgoing público de humano solta o espelho (sucessor do `skip_after_human_response`).
- A2d: gatilho pós-atribuição (`AssignmentKickJob`) cutuca o pipeline — resolve 1º turno da triagem assíncrona e IA→IA.
- A2e: resolve limpa o dono-espelho.
- Handoff (C6): `team_id` validado na conta, solta espelho + seta time no mesmo save.
- Guard 403 admin-only para atribuição manual de IA.

### Fase B — Agentes independentes (VALIDAÇÃO, não implementação)
Por instrução do usuário (AD-11), auditei o que outro dev (Paulo) já fez:
`config['instructions']` no prompt v2 (commit `7e8353fa8`); `config['tools']` armando tools de
negócio (commit `c69979876`); `rake captain:export/import` (sync entre ambientes). Gaps do plano
original (cenários→subprompts, B4/B6/B7) documentados em `evidencias/fase-b-validacao.md` — não
implementados por decisão do usuário.

### Fase C — UI (8 lotes)
- **Seção "Agentes IA"** na página de Agentes (read-only, badge + inboxes elegíveis).
- **Seletor "Agente IA"** no sidebar (admin-only; usa o id do espelho).
- **Serializer** do assignee-IA + **scopes/finder/contadores** + **badge "IA"** no card.
- **Tab "IA"** (Minhas/IA/Todas) + "Não atribuídas" condicional (só com órfãs, estilo alerta).
- **Automation action** `assign_ai_agent` + macro.
- **Tool** `transferir_para_agente` (IA→IA).
- **Remoção do "None"** nos 4 pontos de atribuição (atrás da flag).
- **Vigia de órfãs** (`OrphanConversationsWatchJob` cron */5 + re-triagem + notificação admin).

### Fase D — Gate universal + dialog + efeitos
- **Guard 422** `assignment_required` no `messages_controller` (controller-level, atrás da flag;
  bypasses: nota privada, bot-token, echo WAHA via `source_id`, incoming).
- **Dialog "quer assumir?"** (`AssignToReplyDialog`) com 4 variantes; intercepta o envio
  preservando o draft; trata o 422 (D6).
- **Notificação** ao assignee anterior quando colega assume (tipo novo `conversation_unassignment`;
  ator capturado no dispatch sync).
- **Toggle "Modo de atendimento"** nas Configurações da conta (a flag `reply_assignment_gate`).
- **Stack de efeitos** (D8): motion-v, NumberFlow (odômetro nas tabs), auto-animate, canvas-confetti,
  tailwindcss-animated — instaladas; NumberFlow + jump-in aplicados (auto-animate na lista pulado:
  conflito com virtualização, AD-17).

### Fase E — Políticas e limpeza
- E2: `update_columns`/`update!` de atribuição padronizados via `AssignmentService`.
- E4: telemetria `AssistantLog` (mirror_assigned/released/human_takeover) via watcher.
- E1: `runbook-e2e-validacao.md` (desativar regra #29 na janela E2E; verificar #53 em PROD na virada).
- **AD-16 (pedido do usuário)**: atividade de atribuição feita pela IA mostra o NOME da IA
  ("Atribuído a locação por Júlia") em vez de "Sistema de Automação".

---

## 3. Decisões tomadas em autonomia (AD-1..AD-17)

Registro completo em `plano/ia-progresso.md` (tabela). Destaques que merecem atenção do Walisson:
- **AD-10 (PRODUTO — go-live)**: o gate da IA por atribuição é INCONDICIONAL (sem flag). Conta em
  modo Clássico (D-13) com CaptainInbox e SEM triagem ficaria com canal silencioso. Não é regressão
  (a supressão de greeting já é como hoje), e o rollout §6 evita a configuração — mas decidir antes
  do go-live se condiciona o gate/supressão ao modo da conta.
- **AD-11**: Fase B virou validação (outro dev já fez) — divergência com D-7 aceita pelo usuário.
- **AD-14**: removidos os 6 assistants duplicados da conta 1 (sandbox), mantidos os 6 da conta 3
  (com backup em `/home/chatwoot/backup-assistants-conta1/`).
- **AD-16**: nome da IA nas atividades (pedido do usuário).
- **AD-17**: `auto-animate` NÃO aplicado na lista de conversas (virtualizada — daria glitch).

---

## 4. Como testar

### Specs (Rails + Vitest)
```bash
# Backend (use um clone do test DB p/ paralelismo, ex.: chatwoot_test_2..7)
POSTGRES_DATABASE=chatwoot_test_2 RAILS_ENV=test bundle exec rspec \
  spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb \
  spec/listeners/notification_listener_spec.rb \
  spec/enterprise/models/enterprise/activity_message_handler_spec.rb \
  spec/finders/conversation_finder_spec.rb \
  spec/enterprise/services/enterprise/message_templates/hook_execution_service_spec.rb
# Frontend
TZ=UTC pnpm exec vitest run --no-coverage \
  app/javascript/dashboard/components-next/Conversation/specs/AssignToReplyDialog.spec.js \
  app/javascript/dashboard/store/modules/conversations/specs/getters.spec.js
```
Falhas pré-existentes do fork conhecidas (NÃO são regressão): `perform_meta_only` (código morto),
`pending_status_allowed_by_inbox`, `AvatarFromUrlJob` aridade, `getAllAttachments` (spec stale).

### Visual (Playwright) — já executado
Evidências em `plano/evidencias/`: `fase-c-playwright.md` + 12 screenshots (tabs IA, seção Agentes
IA, badge, dialog ao vivo) light+dark na conta 3. Para rodar de novo:
`NODE_PATH=/home/chatwoot/chatwoot/node_modules node /tmp/pw-fase-c.js`.

### Manual na conta 3 (flag já LIGADA)
1. Configurações → Agentes → role até "Agentes IA" (Rafa/Marina/Letícia/Bruna com badge).
2. Conversas → tabs Minhas/**IA**/Todas; abra a conversa da tab IA → badge "IA" + "Clara".
3. Como admin não-membro do time da conversa, digite e clique enviar → **dialog de assunção**.
4. Configurações da conta → "Modo de atendimento" → alternar Clássico ↔ Atribuição obrigatória.

---

## 5. O que falta para o go-live (revisão humana + ações)

1. **Revisão humana do diff e commit** (não fiz commit — working tree only). ~90 arquivos de código.
2. **E2E com LLM real** na sandbox (roteiro §5.3, 16 testes) — exige API keys; valida a geração de
   resposta da IA ponta a ponta. Os specs cobrem as DECISÕES do gate, não o texto do LLM.
3. **Decisão de produto AD-10** (gate sem flag no modo Clássico) — ver §3.
4. **Vetor de segurança do guard D1**: bypass via `source_id` (um agente autenticado pode adicioná-lo
   para furar o gate — é o discriminador do echo WAHA, OQ-D3 sancionada). Avaliar endurecimento.
   Detalhes em `evidencias/d1-guard-revisao-seguranca.md`.
5. **Ícone da IA na atividade** (pedido do usuário): o NOME já aparece (AD-16); o avatar/ícone exige
   guardar a referência do ator na mensagem de atividade + render no front — pendente de confirmação.
6. **Virada (§6 do plano)**: registrar elegibilidade, criar automação de triagem, desativar regra
   #29 (sandbox) / verificar #53 (PROD), ligar a flag. Rollback = desligar triagem + flag.

---

## 6. Estado do código
- Branch `homologacao`. Working tree com ~90 arquivos modificados/novos (Fases C/D/E + AD-16) +
  os de Fases 0/A já commitados pelos humanos.
- Migration da Fase A (`captain_assistant_id`) aplicada em homolog e no test DB. A flag
  `reply_assignment_gate` vive em `account.settings` (jsonb) — sem migration.
- Libs novas (D8): `motion-v`, `@number-flow/vue`, `@formkit/auto-animate`, `canvas-confetti`,
  `tailwindcss-animated` (~14KB gzip + motion-v 7,5KB).

---

## 7. Fase F — Identidade visual da IA (2026-06-12, a pedido do usuário)

Camada de identidade visual sobre as Fases C/D, espelhando o design de quem já consolidou IA
(Intercom Fin, Notion AI, Google Gemini). Tudo com tokens light+dark e `prefers-reduced-motion`.

- **Ícone universal de IA — sparkle ✨** (AD-20): `i-lucide-bot` → `i-lucide-sparkles` em todas as
  superfícies (card, seção Agentes IA, dropdown, atividade, barra de IA, diálogo, tab IA). Pesquisa
  (a pedido do usuário) confirmou o sparkle como símbolo universal de IA — padronizado pelo Google
  em 2023 (Gemini), adotado por ChatGPT/Notion/Zoom/Spotify.
- **Cor própria por IA** (F6): `dashboard/helper/aiAccent.js` — paleta roxa/violet/magenta/índigo
  determinística por id do assistant (índice = id % 6), com variantes light/dark. Aplicada no chip do
  card, no badge e avatar da seção Agentes IA, e na barra de IA. (Ex.: Clara = magenta.)
- **Barra de IA "está atendendo"** (redesign do banner antigo, considerado "feio"): no
  `ReplyBoxBanner`, barra roxa persistente estilo Intercom Fin — sparkle na cor da IA +
  "{IA} está atendendo esta conversa" + subtexto + botão **"Assumir conversa"** (reusa
  `onClickSelfAssign` + `TeamSelectionModal`). Brilho que varre + ícone que pulsa. O `<Banner>`
  genérico de self-assign é suprimido quando a IA é dona (sem duplicação), e o banner-texto F5 do
  MessagesView foi removido (mantido só o esmaecido do composer).
- **Animação "motion de qualidade"** (F7): `BorderBeam` (feixe de luz) no badge "Agente IA" da
  config — cores forçadas para `--violet` (o default do componente usa `--iris`, que neste fork é
  VERDE, AD-18).
- **Atribuição feita pela IA mostra o nome da IA** (AD-16/AD-19): atividade "Atribuído a vendas por
  Clara" em roxo + sparkle (override edition-safe em `Enterprise::ActivityMessageHandler`).
- **Ícone customizável por IA — NÃO implementado** (AD-21, follow-up de go-live): o assistant já tem
  `avatar_url` (personalização por imagem) + cor própria + sparkle padrão. Um picker dedicado tocaria
  `captain/assistant.rb` (área quente) com risco para "zero erros"; valor marginal baixo.

**Aceite Fase F**: build (heap 8GB — o default OOM neste bundle) + restart + app 200; sparkle no CSS
compilado. Playwright light+dark confirmou todas as superfícies (evidências `plano/evidencias/ff-*.png`).
Specs: front 54/54 (componentes tocados) + back enterprise 15/15; ESLint 0 erros. Único 404 do console
= `enterprise/api/v1/accounts/3/limits`, endpoint pré-existente do ambiente (não relacionado).

> Atualização do §5 (follow-ups): o item "Ícone da IA na atividade" está RESOLVIDO (sparkle + nome +
> roxo). Novo follow-up aberto: picker de ícone por IA (AD-21), opcional.
