# Chat Interno v2 — Repaginada (dinâmica + visual + features)

> Evolução do Chat Interno entre agentes (Módulo B, B1+B2 já entregues). O usuário pediu melhoria em **todas as frentes**: básico de mensageria, integração com atendimento, notificações & presença, gestão de canais & acabamento — **+ dinâmica e visual**. Base técnica intacta: `InternalChannel`/`Member`/`Message`, real-time via `RoomChannel` + `ActionCableBroadcastJob` (eventos `internal.message.created` / `internal.mention.created`), store `internalChat`, `InternalChatIndex.vue`. Flag `internal_chat` (bit 30), ligada na conta #1.
>
> Princípios: reaproveitar a casa (presença/notificações/soft-delete do Chatwoot já existem), atrás da flag, commit + deploy + validação por fase no staging.

---

## Fase 1 — Visual & dinâmica (revamp da UI) — **FUNDAÇÃO** ✅ FEITA (2026-06-26)
> Reescrita do `InternalChatIndex.vue`: avatares reais (componente `Avatar`, iniciais coloridas quando sem foto) na lista/header/mensagens; agrupamento por dia (Hoje/Ontem/data) + por autor consecutivo (<5min); bolhas refinadas (própria à direita verde, colega à esquerda, nome só no 1º do bloco, horário no hover); preview inline de imagem nos anexos + chip de arquivo; links clicáveis (linkify seguro, sem v-html); composer com textarea auto-resize, foco ao abrir canal, botão enviar com ícone; scroll suave + botão "descer" quando rolado pra cima (auto-scroll só se perto do fim); estados vazios/carregando. i18n (TODAY/YESTERDAY/DIRECT/MEMBERS_COUNT/LOADING). Build+lint verdes. **Deferido p/ Fase 2:** last_message do canal não atualiza em tempo real (só no refetch).

### Itens originais da Fase 1
Redesenho do `InternalChatIndex.vue` para parecer um chat de verdade (referência: a própria tela de conversa do Chatwoot, polida).
- **Avatares reais** (Thumbnail/avatar do user) na lista e nas mensagens, em vez do ícone genérico.
- **Agrupamento de mensagens** por autor consecutivo + **divisor de dia** ("Hoje", "Ontem", data) + horário discreto.
- **Bolhas refinadas**: própria à direita (verde brand), colega à esquerda; nome só no 1º de um bloco; cantos/spacing consistentes.
- **Preview inline de imagem** nos anexos (thumbnail clicável) em vez de só link; ícone+nome para outros arquivos.
- **Links clicáveis** + markdown leve (negrito/itálico/código) e quebra de linha.
- **Estados** caprichados: vazio (sem canais / sem mensagens), carregando (skeleton), erro.
- **Header do canal** mais rico: avatar/ícone + nome + subtítulo (membros do grupo / "online" no DM).
- **Composer** mais polido: textarea auto-resize, dica de envio, botões alinhados, foco automático ao abrir canal.
- **Dinâmica**: auto-scroll suave ao chegar/enviar, "▼ novas mensagens" quando rolado pra cima, transição de entrada das bolhas.

## Fase 2 — Básico de mensageria — ✅ COMPLETA (2A+2B+2C)
> **2C FEITA (2026-06-26):** responder/citar (coluna `reply_to_id`, migration `20260626130000`; preview da citação clicável que rola até a original; barra de reply no composer; só cita msg do mesmo canal) e **paginação** do histórico (index retorna `{messages, has_more}` página de 30 newest com `reorder(id: :desc)`; `before` carrega antigas ao rolar pro topo, preservando posição do scroll). 54 specs verdes; build/lint OK.
> **2B FEITA (2026-06-26):** "digitando…" (endpoint typing + broadcast `internal.typing` aos outros membros; composer com throttle 2.5s/stop 3.5s; linha "Fulano está digitando…") e recibo de leitura "Visto/Visto por N" (`InternalChannels::MarkReadService` faz broadcast `internal.read`; membros no jbuilder ganham `last_read_at`; computa visto a partir do last_read_at vs created_at da minha última msg). Sem migration. 51 specs verdes; build/lint OK. **Pendente 2C:** responder/citar + paginação do histórico.
>
> **2A FEITA (2026-06-26):** editar (autor; label "editada"), apagar (autor/admin; soft-delete → "mensagem apagada") e reações com emoji (jsonb `reactions` no internal_messages; toggle; chips com contagem; picker rápido). Migration `20260626120000` (edited_at/deleted_at/reactions). Endpoints update/destroy/react + broadcast `internal.message.updated` (novo `BroadcastService` reusado pelo create). UI: toolbar de hover (reagir/editar/apagar), edição inline, confirm de apagar inline (sem prompt nativo), label "editada". 48 specs verdes; build/lint OK. **Pendentes 2B/2C:** digitando…, recibo de leitura, responder/citar, paginação do histórico.

### Itens originais da Fase 2
- **Digitando…** em tempo real (broadcast `internal.typing` por pubsub_token; debounce).
- **Editar / apagar** mensagem (soft-delete: badge "editada"/"apagada"); broadcast de update.
- **Reações** com emoji (👍❤️✅) — nova tabela `internal_message_reactions` ou jsonb; toggle + contagem.
- **Responder/citar** uma mensagem (quote inline + scroll-to-original).
- **Recibo de leitura** ("visto") — exibir a partir do `last_read_at` dos membros.
- **Paginação do histórico** (cursor por created_at; carregar antigas ao rolar pro topo).

## Fase 3 — Integração com o atendimento (o diferencial) — ✅ FEITA (2026-06-26)
> Compartilhar conversa de cliente no chat interno como **card rico** + menção **#123** como link. Backend: coluna `shared_conversation_id` (migration `20260626140000`, FK conversations nullify); CreateService resolve por `display_id` na conta; `shared_conversation_preview` (display_id, status, contact_name, inbox_name) na serialização (jbuilder + BroadcastService). Frontend: ação **"Compartilhar no chat interno"** no `MoreActions` da conversa (gated pela flag) → modal `ShareToInternalChat` (escolhe canal OU colega p/ DM = "pedir ajuda" + nota) → `shareConversation` no store; card clicável na bolha que abre `/conversations/:display_id`; `#123` no texto vira link (rota `inbox_conversation`). 56 specs verdes; build/lint OK. "Pedir ajuda" coberto pelo mesmo modal (compartilhar p/ um colega).

### Itens originais da Fase 3
- **Compartilhar conversa de cliente** no chat: action "encaminhar conversa #N" → mensagem com card clicável que abre `/conversations/N`.
- **"Pedir ajuda"** a partir da conversa do cliente: botão que abre/cria DM (ou posta em canal) com o link da conversa anexado.
- **Menção `#123`** vira link para a conversa; (opcional) menção a contato.

## Fase 4 — Notificações & presença — ✅ FEITA (2026-06-26)
> Sem backend/migration. **Notificações:** helper `internalChatNotify` (som `/audio/dashboard/ping.mp3` + Notification API desktop best-effort, pede permissão se 'default') disparado em @menção (Sidebar, junto do toast) e em nova DM de outro quando `document.hidden` (store applyIncomingMessage, via rootGetters.getCurrentUserID + channel_type direct). **Presença:** `presenceOf(userId)` lê `agents/getAgentById().availability_status`; passado como `:status` ao Avatar (badge online/busy/offline) na lista de canais, header e seletor de DM; `agents/get` no mount. Build/lint OK.
- **Som + notificação desktop** para @menção e nova DM (reusar Notification API / AudioAlerts do dashboard) — sem tocar no sino global.
- **Presença online/offline** (bolinha) — reusar `OnlinePresenceTracker`/presença do Chatwoot.
- **Badges** refinados: por canal na lista + total na sidebar (total já existe).

## Fase 5 — Gestão de canais & permissões — ✅ FEITA (2026-06-26) → CHAT INTERNO v2 COMPLETO
> Sem migration. Backend: endpoints `update` (renomear, só group_chat), `add_member`/`remove_member` (group_chat), `leave` (não-DM) no InternalChannelsController; criação de **canal de equipe agora admin-only**; policy (update?/add_member?/remove_member?/leave? = membro); broadcast `internal.channel.updated` aos membros → refetch. 62 specs verdes. Frontend: `ManageChannelDialog` (renomear + lista de membros c/ remover + adicionar agentes + sair), aberto por engrenagem no header dos grupos; store (renameChannel/addMember/removeMember/leaveChannel + REMOVE_CHANNEL + applyChannelUpdated); handler actionCable. i18n MANAGE.*. **Canal "Geral"/Anúncios: deferido (opcional).** Build/lint OK.
- **Gerenciar grupo** após criado: renomear, adicionar/remover membros, sair, arquivar.
- **Permissões**: quem pode criar grupos / canais de equipe (admin vs agente).
- **Canal "Geral"/Anúncios** por conta (opcional).

---

## Ordem & DoD
Fase 1 primeiro (fundação visual em que tudo se encaixa), depois 2 → 3 → 4 → 5.
Cada fase: specs (back) / lint+build (front) verdes → commit atômico → deploy no staging (assets + restart) → validação visual do usuário.

## Riscos / notas
- Real-time já provado (RoomChannel). Novos eventos (`typing`, `reaction`, `message.updated`) seguem o mesmo padrão de broadcast aos pubsub_tokens dos membros.
- Avatares/presença: reusar componentes existentes (Avatar, presença) para consistência.
- Markdown: usar o renderer já existente no projeto se houver (evitar dep nova).
- Paginação: o index hoje carrega tudo; migrar para cursor sem quebrar o real-time (append continua funcionando).
